import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/pilot_record/pilot_profile.dart';
import '../../domain/repository/export_record_repository.dart';
import '../../export/amc1_fcl050_export_plan.dart';
import '../../export/amc1_fcl050_layout.dart';
import '../providers/easa_export_providers.dart';
import '../providers/pilot_profile_providers.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';

const _amc1Fcl050ExportFormatLabel = 'AMC1 FCL.050';

/// #83: exports and seals the AMC1 FCL.050 PDF logbook. A date range (same
/// pattern as `ExportScreen`'s ForeFlight CSV flow), an inline
/// holder-identity editor (nothing else in the app can set this yet — see
/// the #83 design spec's "Section 1"), and two actions: Preview (no state
/// change, watermarked) and Export & Seal (commits every still-draft
/// flight in range, atomically, after a confirmation naming how many).
class Amc1Fcl050ExportScreen extends ConsumerStatefulWidget {
  const Amc1Fcl050ExportScreen({super.key});

  @override
  ConsumerState<Amc1Fcl050ExportScreen> createState() =>
      _Amc1Fcl050ExportScreenState();
}

class _Amc1Fcl050ExportScreenState
    extends ConsumerState<Amc1Fcl050ExportScreen> {
  CalendarDate? _from;
  CalendarDate? _to;
  Future<List<ExportRecord>>? _overlapCheck;
  bool _busy = false;
  final _holderNameController = TextEditingController();
  final _licenceNumberController = TextEditingController();
  bool _holderFieldsLoaded = false;

  @override
  void dispose() {
    _holderNameController.dispose();
    _licenceNumberController.dispose();
    super.dispose();
  }

  void _prefillHolderFieldsOnce(PilotProfile? profile) {
    if (_holderFieldsLoaded || profile == null) return;
    _holderFieldsLoaded = true;
    _holderNameController.text = profile.holderName ?? '';
    _licenceNumberController.text = profile.primaryLicenceNumber ?? '';
  }

  /// No-ops when [currentProfile] is null: a fresh install with no
  /// `PilotProfile` row yet has no `dateOfBirth`/`primaryJurisdictionId` for
  /// this screen to know — both feed real logic elsewhere (medical-validity
  /// banding, which jurisdiction totals/currency key off), so fabricating a
  /// placeholder profile just to attach the holder-identity edit onto would
  /// be exactly the "never guess a missing discriminator" CLAUDE.md rules
  /// out, and would contradict `PilotProfile.holderName`'s own doc comment
  /// ("an export screen with nothing set here must ask, not guess"). The
  /// PDF itself reads straight from the text controllers regardless, so
  /// skipping persistence here doesn't affect this export's own output —
  /// only whether the fields are pre-filled next time, until a real profile
  /// exists via whatever path already creates one.
  Future<void> _saveHolderFieldsIfChanged(PilotProfile? currentProfile) async {
    if (currentProfile == null) return;
    final name = _holderNameController.text.trim();
    final licenceNumber = _licenceNumberController.text.trim();
    if (currentProfile.holderName == name &&
        currentProfile.primaryLicenceNumber == licenceNumber) {
      return;
    }
    await ref
        .read(pilotProfileRepositoryProvider)
        .save(
          currentProfile.copyWith(
            holderName: name.isEmpty ? null : name,
            primaryLicenceNumber: licenceNumber.isEmpty ? null : licenceNumber,
          ),
        );
    ref.invalidate(pilotProfileProvider);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = (isFrom ? _from : _to) ?? _todayAsCalendarDate();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final date = CalendarDate(picked.year, picked.month, picked.day);
      if (isFrom) {
        _from = date;
      } else {
        _to = date;
      }
      _overlapCheck = null;
      final from = _from;
      final to = _to;
      if (from != null && to != null && from <= to) {
        _overlapCheck = ref
            .read(exportRecordRepositoryProvider)
            .findOverlapping(
              format: _amc1Fcl050ExportFormatLabel,
              from: from,
              to: to,
            );
      }
    });
  }

  CalendarDate _todayAsCalendarDate() {
    final now = DateTime.now();
    return CalendarDate(now.year, now.month, now.day);
  }

  Future<Amc1Fcl050ExportPlan> _buildPlan(
    CalendarDate from,
    CalendarDate to,
  ) async {
    final easaProjection = await ref.read(easaProjectionProvider.future);
    return buildAmc1Fcl050ExportPlan(
      flightReadRepository: ref.read(flightReadRepositoryProvider),
      easaProjection: easaProjection,
      from: from,
      to: to,
    );
  }

  Future<void> _preview() async {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return;

    setState(() => _busy = true);
    try {
      final plan = await _buildPlan(from, to);
      final document = await buildAmc1Fcl050Logbook(
        holderName: _holderNameController.text.trim(),
        holderLicenceNumber: _licenceNumberController.text.trim(),
        rows: plan.contentRows,
        openingBalance: plan.openingBalance,
        isDraftPreview: true,
      );
      final bytes = await document.save();

      final fileName = 'amc1_fcl050_preview_${from}_to_$to.pdf';
      final savedUri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/pdf',
        dialogTitle: 'Save preview PDF',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (savedUri == null) return; // pilot cancelled the save dialog.
      _showMessage('Preview saved to $fileName. Nothing was sealed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportAndSeal() async {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return;

    setState(() => _busy = true);
    try {
      final plan = await _buildPlan(from, to);

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export & Seal'),
          content: Text(
            plan.draftCount == 0
                ? 'No new drafts in this range. This will still generate '
                      'a PDF and record a new export entry, sealing '
                      'nothing further.'
                : 'This will seal ${plan.draftCount} draft flight(s) as '
                      'committed and immutable. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Export & Seal'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final document = await buildAmc1Fcl050Logbook(
        holderName: _holderNameController.text.trim(),
        holderLicenceNumber: _licenceNumberController.text.trim(),
        rows: plan.contentRows,
        openingBalance: plan.openingBalance,
      );
      final bytes = await document.save();
      final fileName = 'amc1_fcl050_${from}_to_$to.pdf';

      final savedUri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/pdf',
        dialogTitle: 'Save $_amc1Fcl050ExportFormatLabel export',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (savedUri == null) return; // pilot cancelled -- nothing sealed.

      final currentProfile = await ref.read(pilotProfileProvider.future);
      await _saveHolderFieldsIfChanged(currentProfile);

      final exportRecordId = await ref
          .read(exportRecordRepositoryProvider)
          .recordExport(
            format: _amc1Fcl050ExportFormatLabel,
            from: from,
            to: to,
          );
      await ref
          .read(flightRepositoryProvider)
          .sealForExport(
            flightIds: plan.draftFlightIds,
            exportRecordId: exportRecordId,
          );

      _showMessage(
        '${plan.contentRows.length} flight(s) exported to $fileName; '
        '${plan.draftCount} sealed.',
      );
    } catch (e) {
      // The PDF may already be saved to disk by this point (recordExport
      // or sealForExport threw after the file-save succeeded) -- nothing
      // was sealed (see recordExport/sealForExport's own transactional
      // guarantees), but a silent failure here would leave the pilot
      // looking at a PDF that appears to be a completed, sealed export
      // when it isn't. Design spec §Architecture piece 3 promises the
      // pilot sees an error and can retry with a fresh file.
      _showMessage(
        'Export failed while sealing: $e. Nothing was sealed; the saved '
        'PDF is not a sealed export.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final semantic = context.semanticColors;
    final from = _from;
    final to = _to;
    final rangeValid = from != null && to != null && from <= to;
    final profileAsync = ref.watch(pilotProfileProvider);
    profileAsync.whenData(_prefillHolderFieldsOnce);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Export to $_amc1Fcl050ExportFormatLabel',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                children: [
                  TextField(
                    controller: _holderNameController,
                    decoration: const InputDecoration(
                      labelText: "Holder's name",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _licenceNumberController,
                    decoration: const InputDecoration(
                      labelText: "Holder's licence number",
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Choose a date range to export.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('From'),
                    subtitle: Text(from?.toString() ?? 'Not set'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _pickDate(isFrom: true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('To'),
                    subtitle: Text(to?.toString() ?? 'Not set'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _pickDate(isFrom: false),
                  ),
                  if (from != null && to != null && from > to)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'The "From" date must be on or before "To".',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  if (_overlapCheck != null)
                    FutureBuilder<List<ExportRecord>>(
                      future: _overlapCheck,
                      builder: (context, snapshot) {
                        final overlapping = snapshot.data ?? const [];
                        if (overlapping.isEmpty) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: semantic.currencyWarningSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'This range overlaps ${overlapping.length} '
                            'previous export(s).',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: semantic.currencyWarning,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (rangeValid && !_busy) ? _preview : null,
                  child: const Text('Preview'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (rangeValid && !_busy) ? _exportAndSeal : null,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Export & Seal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
