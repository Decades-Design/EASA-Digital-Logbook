import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/aircraft_repository.dart';
import '../../domain/model/aircraft.dart';
import '../entry/widgets/entry_card.dart';
import '../entry/widgets/entry_section_label.dart';
import '../entry/widgets/entry_top_bar.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'aircraft_qualification_display.dart';

/// #61: add or edit one aircraft record. [existing] null means add;
/// non-null pre-fills every field and offers Archive/Unarchive — there is
/// no draft/committed split here (`Aircraft` is a current reference record,
/// not a historical one, per its own class dartdoc), so unlike the flight
/// entry form there is exactly one save action.
class AircraftEditScreen extends ConsumerStatefulWidget {
  const AircraftEditScreen({super.key, this.existing});

  final AircraftRecord? existing;

  @override
  ConsumerState<AircraftEditScreen> createState() => _AircraftEditScreenState();
}

class _AircraftEditScreenState extends ConsumerState<AircraftEditScreen> {
  late final TextEditingController _registrationController;
  late final TextEditingController _manufacturerController;
  late final TextEditingController _modelController;
  late final TextEditingController _icaoTypeController;
  late final TextEditingController _typeRatingController;

  late AircraftCategory _category;
  late EngineType _engineType;
  late int _engineCount;
  late OperatingSurface _operatingSurface;
  late bool _requiresMultiCrew;
  late Map<String, Set<AircraftQualification>> _requiredQualifications;
  late bool _archived;

  String? _error;

  @override
  void initState() {
    super.initState();
    final aircraft = widget.existing?.aircraft;
    _registrationController = TextEditingController(
      text: aircraft?.registration ?? '',
    );
    _manufacturerController = TextEditingController(
      text: aircraft?.manufacturer ?? '',
    );
    _modelController = TextEditingController(text: aircraft?.model ?? '');
    _icaoTypeController = TextEditingController(
      text: aircraft?.icaoTypeDesignator ?? '',
    );
    _typeRatingController = TextEditingController(
      text: aircraft?.typeRatingDesignator ?? '',
    );
    _category = aircraft?.category ?? AircraftCategory.aeroplane;
    _engineType = aircraft?.engineType ?? EngineType.piston;
    _engineCount = aircraft?.engineCount ?? 1;
    _operatingSurface = aircraft?.operatingSurface ?? OperatingSurface.land;
    _requiresMultiCrew = aircraft?.requiresMultiCrew ?? false;
    _requiredQualifications = {
      for (final entry
          in (aircraft?.requiredQualifications ?? const {}).entries)
        entry.key: Set.of(entry.value),
    };
    _archived = aircraft?.archived ?? false;
  }

  @override
  void dispose() {
    _registrationController.dispose();
    _manufacturerController.dispose();
    _modelController.dispose();
    _icaoTypeController.dispose();
    _typeRatingController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final registration = _registrationController.text.trim().toUpperCase();
    if (registration.isEmpty) {
      setState(() => _error = 'Registration is required.');
      return;
    }
    if (_manufacturerController.text.trim().isEmpty ||
        _modelController.text.trim().isEmpty) {
      setState(() => _error = 'Manufacturer and model are required.');
      return;
    }

    final repository = ref.read(aircraftRepositoryProvider);
    final existingId = widget.existing?.id;
    final duplicateId = await repository.findIdByRegistration(registration);
    if (duplicateId != null && duplicateId != existingId) {
      setState(
        () => _error =
            '$registration is already registered to another '
            'aircraft in this logbook.',
      );
      return;
    }

    if (existingId != null) {
      final qualificationsChanged = !_mapEquals(
        _requiredQualifications,
        widget.existing!.aircraft.requiredQualifications,
      );
      if (qualificationsChanged) {
        final confirmed = await _confirmQualificationChange();
        if (confirmed != true) return;
      }
    }

    final aircraft = Aircraft(
      registration: registration,
      manufacturer: _manufacturerController.text.trim(),
      model: _modelController.text.trim(),
      icaoTypeDesignator: _icaoTypeController.text.trim().isEmpty
          ? null
          : _icaoTypeController.text.trim(),
      category: _category,
      engineType: _engineType,
      engineCount: _engineCount,
      operatingSurface: _operatingSurface,
      requiresMultiCrew: _requiresMultiCrew,
      typeRatingDesignator: _typeRatingController.text.trim().isEmpty
          ? null
          : _typeRatingController.text.trim(),
      requiredQualifications: _requiredQualifications,
      archived: _archived,
    );

    await repository.upsert(aircraft, id: existingId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool?> _confirmQualificationChange() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update required qualifications?'),
        content: const Text(
          'This aircraft carries no history of its own, so the change '
          'applies retroactively: past flights on this registration will be '
          're-checked against the new list next time a qualification gap is '
          'shown (#105).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleArchived() async {
    final id = widget.existing?.id;
    if (id == null) return;
    await ref.read(aircraftRepositoryProvider).setArchived(id, !_archived);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            EntryTopBar(
              title: isEditing ? 'Edit aircraft' : 'New aircraft',
              onSaveDraft: _save,
              saveLabel: 'Save',
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.semanticColors.currencyWarningSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.semanticColors.currencyWarning,
                          ),
                        ),
                      ),
                    ),
                  if (isEditing && _archived)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.semanticColors.currencyWarningSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Archived — hidden from the entry-form picker. '
                          'Past flights against $_registrationText still '
                          'resolve it.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.semanticColors.currencyWarning,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EntrySectionLabel('Identity'),
                        const SizedBox(height: 8),
                        EntryCard(
                          child: Column(
                            children: [
                              _TextRow(
                                label: 'Registration',
                                controller: _registrationController,
                                hint: 'G-ABCD',
                                textCapitalization:
                                    TextCapitalization.characters,
                              ),
                              const EntryCardDivider(),
                              _TextRow(
                                label: 'Manufacturer',
                                controller: _manufacturerController,
                                hint: 'Cessna',
                              ),
                              const EntryCardDivider(),
                              _TextRow(
                                label: 'Model',
                                controller: _modelController,
                                hint: '152',
                              ),
                              const EntryCardDivider(),
                              _TextRow(
                                label: 'ICAO type',
                                controller: _icaoTypeController,
                                hint: 'C152 (optional)',
                                textCapitalization:
                                    TextCapitalization.characters,
                              ),
                              const EntryCardDivider(),
                              _TextRow(
                                label: 'Type rating',
                                controller: _typeRatingController,
                                hint: 'A320 (optional)',
                                textCapitalization:
                                    TextCapitalization.characters,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EntrySectionLabel('Logging facts'),
                        const SizedBox(height: 8),
                        EntryCard(
                          child: Column(
                            children: [
                              EntryCardRow(
                                label: 'Category',
                                child: DropdownButton<AircraftCategory>(
                                  value: _category,
                                  underline: const SizedBox.shrink(),
                                  items: [
                                    for (final c in AircraftCategory.values)
                                      DropdownMenuItem(
                                        value: c,
                                        child: Text(_categoryLabel(c)),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _category = v!),
                                ),
                              ),
                              const EntryCardDivider(),
                              EntryCardRow(
                                label: 'Engine type',
                                child: DropdownButton<EngineType>(
                                  value: _engineType,
                                  underline: const SizedBox.shrink(),
                                  items: [
                                    for (final e in EngineType.values)
                                      DropdownMenuItem(
                                        value: e,
                                        child: Text(_engineTypeLabel(e)),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _engineType = v!),
                                ),
                              ),
                              const EntryCardDivider(),
                              EntryCardRow(
                                label: 'Engine count',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 18),
                                      tooltip: 'Decrease engine count',
                                      onPressed: _engineCount > 1
                                          ? () => setState(() => _engineCount--)
                                          : null,
                                    ),
                                    Text(
                                      '$_engineCount',
                                      style: AppMonoText.value(
                                        theme.colorScheme.onSurface,
                                        size: 14,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 18),
                                      tooltip: 'Increase engine count',
                                      onPressed: () =>
                                          setState(() => _engineCount++),
                                    ),
                                  ],
                                ),
                              ),
                              const EntryCardDivider(),
                              EntryCardRow(
                                label: 'Operating surface',
                                child: DropdownButton<OperatingSurface>(
                                  value: _operatingSurface,
                                  underline: const SizedBox.shrink(),
                                  items: [
                                    for (final s in OperatingSurface.values)
                                      DropdownMenuItem(
                                        value: s,
                                        child: Text(_surfaceLabel(s)),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _operatingSurface = v!),
                                ),
                              ),
                              const EntryCardDivider(),
                              EntryCardRow(
                                label: 'Multi-pilot certification',
                                child: Switch(
                                  value: _requiresMultiCrew,
                                  onChanged: (v) =>
                                      setState(() => _requiresMultiCrew = v),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final jurisdictionId
                      in qualificationsByJurisdiction.keys)
                    _QualificationSection(
                      jurisdictionId: jurisdictionId,
                      configured: _requiredQualifications.containsKey(
                        jurisdictionId,
                      ),
                      held: _requiredQualifications[jurisdictionId] ?? const {},
                      onToggleConfigured: (configured) => setState(() {
                        if (configured) {
                          _requiredQualifications[jurisdictionId] = {};
                        } else {
                          _requiredQualifications.remove(jurisdictionId);
                        }
                      }),
                      onToggleQualification: (qualification, held) =>
                          setState(() {
                            final set =
                                _requiredQualifications[jurisdictionId] ?? {};
                            if (held) {
                              set.add(qualification);
                            } else {
                              set.remove(qualification);
                            }
                            _requiredQualifications[jurisdictionId] = set;
                          }),
                    ),
                  if (isEditing) ...[
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: OutlinedButton(
                        onPressed: _toggleArchived,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _archived
                              ? theme.colorScheme.primary
                              : context.semanticColors.currencyWarning,
                        ),
                        child: Text(_archived ? 'Unarchive' : 'Archive'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _registrationText => _registrationController.text.trim();

  bool _mapEquals(
    Map<String, Set<AircraftQualification>> a,
    Map<String, Set<AircraftQualification>> b,
  ) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!setEquals(a[key]!, b[key]!)) return false;
    }
    return true;
  }

  bool setEquals(Set<AircraftQualification> a, Set<AircraftQualification> b) {
    return a.length == b.length && a.containsAll(b);
  }
}

String _categoryLabel(AircraftCategory category) => switch (category) {
  AircraftCategory.aeroplane => 'Aeroplane',
  AircraftCategory.helicopter => 'Helicopter',
  AircraftCategory.poweredLift => 'Powered lift',
  AircraftCategory.glider => 'Glider',
  AircraftCategory.touringMotorGlider => 'Touring motor glider',
  AircraftCategory.airship => 'Airship',
  AircraftCategory.balloon => 'Balloon',
  AircraftCategory.poweredParachute => 'Powered parachute',
};

String _engineTypeLabel(EngineType type) => switch (type) {
  EngineType.none => 'None',
  EngineType.piston => 'Piston',
  EngineType.turboprop => 'Turboprop',
  EngineType.turbojet => 'Turbojet',
  EngineType.turbofan => 'Turbofan',
  EngineType.electric => 'Electric',
};

String _surfaceLabel(OperatingSurface surface) => switch (surface) {
  OperatingSurface.land => 'Land',
  OperatingSurface.sea => 'Sea',
  OperatingSurface.amphibian => 'Amphibian',
};

class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: ink.medium),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: textCapitalization,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: hint,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QualificationSection extends StatelessWidget {
  const _QualificationSection({
    required this.jurisdictionId,
    required this.configured,
    required this.held,
    required this.onToggleConfigured,
    required this.onToggleQualification,
  });

  final String jurisdictionId;
  final bool configured;
  final Set<AircraftQualification> held;
  final ValueChanged<bool> onToggleConfigured;
  final void Function(AircraftQualification qualification, bool held)
  onToggleQualification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final label =
        qualificationJurisdictionLabels[jurisdictionId] ?? jurisdictionId;
    final qualifications = qualificationsByJurisdiction[jurisdictionId]!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntrySectionLabel('$label qualifications'),
          const SizedBox(height: 8),
          EntryCard(
            child: Column(
              children: [
                EntryCardRow(
                  label: 'Configured for $label',
                  child: Switch(
                    value: configured,
                    onChanged: onToggleConfigured,
                  ),
                ),
                if (!configured)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Not set up yet — distinct from "set up, nothing '
                      'required". A qualification gap is never checked '
                      'against $label until this is turned on.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ink.faint,
                      ),
                    ),
                  ),
                if (configured)
                  for (final qualification in qualifications) ...[
                    const EntryCardDivider(),
                    _QualificationRow(
                      qualification: qualification,
                      held: held.contains(qualification),
                      onChanged: (v) => onToggleQualification(qualification, v),
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QualificationRow extends StatelessWidget {
  const _QualificationRow({
    required this.qualification,
    required this.held,
    required this.onChanged,
  });

  final AircraftQualification qualification;
  final bool held;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final info = qualificationInfo[qualification]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // #66: merges the label + explanation into the Switch's own
      // semantics node, so a screen reader announces what's being toggled
      // rather than just "on/off, switch".
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.label, style: theme.textTheme.bodyMedium),
                  Text(
                    info.explanation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ink.faint,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: held, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
