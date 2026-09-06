import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/csv_mapping_profile_repository.dart';
import '../../io/generic_csv/generic_csv_adapter.dart';
import '../../io/generic_csv/generic_csv_field.dart';
import '../../io/generic_csv/generic_csv_mapping.dart';
import '../../io/import_adapter.dart';
import '../providers/csv_mapping_profile_providers.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';
import 'import_preview_screen.dart';

const Map<GenericCsvField, String> _fieldLabels = {
  GenericCsvField.date: 'Date',
  GenericCsvField.offBlocksTime: 'Off-blocks time',
  GenericCsvField.onBlocksTime: 'On-blocks time',
  GenericCsvField.aircraftRegistration: 'Aircraft registration',
  GenericCsvField.aircraftType: 'Aircraft type (optional)',
  GenericCsvField.departure: 'Departure',
  GenericCsvField.destination: 'Destination',
  GenericCsvField.picDuration: 'PIC duration',
  GenericCsvField.sicDuration: 'SIC duration',
  GenericCsvField.dualReceivedDuration: 'Dual received duration',
  GenericCsvField.soloDuration: 'Solo duration',
  GenericCsvField.dayLandings: 'Day landings',
  GenericCsvField.nightLandings: 'Night landings',
  GenericCsvField.remarks: 'Remarks',
};

const Map<CsvDateFormat, String> _dateFormatLabels = {
  CsvDateFormat.isoYmd: 'YYYY-MM-DD',
  CsvDateFormat.usMdy: 'MM/DD/YYYY',
  CsvDateFormat.dmy: 'DD/MM/YYYY',
};

const Map<CsvDurationFormat, String> _durationFormatLabels = {
  CsvDurationFormat.decimalHours: 'Decimal hours (1.5)',
  CsvDurationFormat.hoursMinutes: 'Hours:minutes (1:30)',
};

/// #72's column-mapping step: detects [csv]'s own header row and lets the
/// pilot assign each to a canonical field, choose the date/duration
/// formats explicitly (never guessed), optionally load or save a named
/// mapping profile, then hands the resulting `ImportParseResult` to
/// [ImportPreviewScreen] — the same preview every other format's importer
/// uses.
class GenericCsvMappingScreen extends ConsumerStatefulWidget {
  const GenericCsvMappingScreen({super.key, required this.csv});

  final String csv;

  @override
  ConsumerState<GenericCsvMappingScreen> createState() =>
      _GenericCsvMappingScreenState();
}

class _GenericCsvMappingScreenState
    extends ConsumerState<GenericCsvMappingScreen> {
  late final List<String> _headers = detectCsvHeaders(widget.csv);
  final Map<GenericCsvField, String?> _selection = {
    for (final field in GenericCsvField.values) field: null,
  };
  CsvDateFormat _dateFormat = CsvDateFormat.isoYmd;
  CsvDurationFormat _durationFormat = CsvDurationFormat.hoursMinutes;
  final _nameController = TextEditingController();
  bool _saveForReuse = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _loadProfile(GenericCsvMapping mapping) {
    setState(() {
      for (final field in GenericCsvField.values) {
        _selection[field] = mapping.columnByField[field];
      }
      _dateFormat = mapping.dateFormat;
      _durationFormat = mapping.durationFormat;
      _nameController.text = mapping.name;
    });
  }

  Future<void> _continue() async {
    final missing = [
      for (final field in requiredGenericCsvFields)
        if (_selection[field] == null) _fieldLabels[field]!,
    ];
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Still needs: ${missing.join(', ')}')),
      );
      return;
    }

    final mapping = GenericCsvMapping(
      name: _nameController.text.trim().isEmpty
          ? 'Untitled mapping'
          : _nameController.text.trim(),
      columnByField: {
        for (final entry in _selection.entries)
          if (entry.value != null) entry.key: entry.value!,
      },
      dateFormat: _dateFormat,
      durationFormat: _durationFormat,
    );

    ImportParseResult parsed;
    try {
      parsed = GenericCsvAdapter(
        mapping,
      ).parse({GenericCsvAdapter.csvKey: widget.csv});
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    if (_saveForReuse) {
      await ref.read(csvMappingProfileRepositoryProvider).upsert(mapping);
      ref.invalidate(savedCsvMappingProfilesProvider);
    }

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImportPreviewScreen(
          parseResult: parsed,
          sourceLabel: 'Generic CSV (${mapping.name})',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final savedProfilesAsync = ref.watch(savedCsvMappingProfilesProvider);

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
                      'Map columns',
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
                  savedProfilesAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (error, stackTrace) => const SizedBox.shrink(),
                    data: (profiles) => profiles.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child:
                                DropdownButtonFormField<
                                  CsvMappingProfileRecord
                                >(
                                  decoration: const InputDecoration(
                                    labelText: 'Load a saved mapping',
                                  ),
                                  items: [
                                    for (final record in profiles)
                                      DropdownMenuItem(
                                        value: record,
                                        child: Text(record.mapping.name),
                                      ),
                                  ],
                                  onChanged: (record) {
                                    if (record != null) {
                                      _loadProfile(record.mapping);
                                    }
                                  },
                                ),
                          ),
                  ),
                  Text(
                    'COLUMNS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final field in GenericCsvField.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DropdownButtonFormField<String?>(
                        initialValue: _selection[field],
                        decoration: InputDecoration(
                          labelText:
                              '${_fieldLabels[field]}'
                              '${requiredGenericCsvFields.contains(field) ? ' *' : ''}',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            child: Text('— not mapped —'),
                          ),
                          for (final header in _headers)
                            DropdownMenuItem(
                              value: header,
                              child: Text(header),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selection[field] = value),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'FORMATS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<CsvDateFormat>(
                    initialValue: _dateFormat,
                    decoration: const InputDecoration(labelText: 'Date format'),
                    items: [
                      for (final format in CsvDateFormat.values)
                        DropdownMenuItem(
                          value: format,
                          child: Text(_dateFormatLabels[format]!),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _dateFormat = value ?? _dateFormat),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<CsvDurationFormat>(
                    initialValue: _durationFormat,
                    decoration: const InputDecoration(
                      labelText: 'Duration format',
                    ),
                    items: [
                      for (final format in CsvDurationFormat.values)
                        DropdownMenuItem(
                          value: format,
                          child: Text(_durationFormatLabels[format]!),
                        ),
                    ],
                    onChanged: (value) => setState(
                      () => _durationFormat = value ?? _durationFormat,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _saveForReuse,
                    onChanged: (value) =>
                        setState(() => _saveForReuse = value ?? false),
                    title: const Text('Save this mapping for reuse'),
                  ),
                  if (_saveForReuse)
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Mapping name',
                      ),
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
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _continue,
              child: const Text('Preview import'),
            ),
          ),
        ),
      ),
    );
  }
}
