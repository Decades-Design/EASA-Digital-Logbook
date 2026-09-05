import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/aerodrome.dart';
import '../../domain/model/geo_coordinate.dart';
import '../entry/widgets/entry_card.dart';
import '../entry/widgets/entry_section_label.dart';
import '../entry/widgets/entry_top_bar.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';

/// #63: "User-defined aerodromes for strips absent from the dataset, with
/// manual coordinates." Only [name] and a position are required — an ICAO
/// code is exactly what a private strip or unlicensed field usually
/// doesn't have (see [Aerodrome]'s own dartdoc).
class AddCustomAerodromeScreen extends ConsumerStatefulWidget {
  const AddCustomAerodromeScreen({super.key, this.prefillName});

  /// Carries over whatever the pilot already typed in the picker's search
  /// box — most of the time that's the strip's name, so retyping it here
  /// would be pure busywork.
  final String? prefillName;

  @override
  ConsumerState<AddCustomAerodromeScreen> createState() =>
      _AddCustomAerodromeScreenState();
}

class _AddCustomAerodromeScreenState
    extends ConsumerState<AddCustomAerodromeScreen> {
  late final TextEditingController _nameController;
  final _icaoController = TextEditingController();
  final _iataController = TextEditingController();
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  final _elevationController = TextEditingController();
  final _countryController = TextEditingController();

  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.prefillName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _icaoController.dispose();
    _iataController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _elevationController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    final lat = double.tryParse(_latController.text.trim());
    final lon = double.tryParse(_lonController.text.trim());
    if (lat == null || lon == null) {
      setState(() => _error = 'Latitude and longitude are required.');
      return;
    }

    final GeoCoordinate position;
    try {
      position = GeoCoordinate(latitude: lat, longitude: lon);
    } on ArgumentError catch (e) {
      setState(() => _error = e.message.toString());
      return;
    }

    final aerodrome = Aerodrome(
      icaoCode: _icaoController.text.trim().isEmpty
          ? null
          : _icaoController.text.trim().toUpperCase(),
      iataCode: _iataController.text.trim().isEmpty
          ? null
          : _iataController.text.trim().toUpperCase(),
      name: name,
      position: position,
      elevationFt: int.tryParse(_elevationController.text.trim()),
      isoCountry: _countryController.text.trim().isEmpty
          ? null
          : _countryController.text.trim().toUpperCase(),
    );

    await ref.read(customAerodromeRepositoryProvider).upsert(aerodrome);
    if (mounted) Navigator.of(context).pop(aerodrome);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            EntryTopBar(
              title: 'New aerodrome',
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
                                label: 'Name',
                                controller: _nameController,
                                hint: "Wicker's Field",
                              ),
                              const EntryCardDivider(),
                              _TextRow(
                                label: 'ICAO code',
                                controller: _icaoController,
                                hint: 'optional',
                                textCapitalization: TextCapitalization.characters,
                              ),
                              const EntryCardDivider(),
                              _TextRow(
                                label: 'IATA code',
                                controller: _iataController,
                                hint: 'optional',
                                textCapitalization: TextCapitalization.characters,
                              ),
                              const EntryCardDivider(),
                              _TextRow(
                                label: 'Country',
                                controller: _countryController,
                                hint: 'GB (optional)',
                                textCapitalization: TextCapitalization.characters,
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
                        const EntrySectionLabel('Position'),
                        const SizedBox(height: 8),
                        EntryCard(
                          child: Column(
                            children: [
                              _TextRow(
                                label: 'Latitude',
                                controller: _latController,
                                hint: '51.4706',
                                keyboardType: const TextInputType.numberWithOptions(
                                  signed: true,
                                  decimal: true,
                                ),
                              ),
                              const EntryCardDivider(),
                              _TextRow(
                                label: 'Longitude',
                                controller: _lonController,
                                hint: '-0.461941',
                                keyboardType: const TextInputType.numberWithOptions(
                                  signed: true,
                                  decimal: true,
                                ),
                              ),
                              const EntryCardDivider(),
                              _TextRow(
                                label: 'Elevation (ft)',
                                controller: _elevationController,
                                hint: 'optional',
                                keyboardType: const TextInputType.numberWithOptions(
                                  signed: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.textCapitalization = TextCapitalization.none,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: ink.medium),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: textCapitalization,
              keyboardType: keyboardType,
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
