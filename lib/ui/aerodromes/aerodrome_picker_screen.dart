import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/aerodrome.dart';
import '../../domain/model/aerodrome_directory.dart';
import '../providers/aerodrome_providers.dart';
import '../providers/aerodrome_search_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'add_custom_aerodrome_screen.dart';

/// #63: search the bundled OurAirports dataset (by ICAO, IATA or name) plus
/// the pilot's own user-defined strips, with recent and frequent aerodromes
/// surfaced first when there's nothing typed yet. Entirely offline — the
/// dataset is a bundled asset (`aerodromeDirectoryProvider`), never a
/// network call.
///
/// Returns the picked aerodrome's identifier (ICAO, falling back to IATA,
/// falling back to its bare name) via `Navigator.pop`, or `null` if
/// cancelled — a plain `String` rather than a full [Aerodrome], because a
/// "recent" or "frequent" entry derived from [Flight.route] may name an
/// ICAO code this app has no [Aerodrome] record for at all (a private strip
/// flown to before #63 ever recorded its coordinates); there is no way to
/// hand back a full record for a code like that, but the bare identifier is
/// still exactly what a route-leg field wants. See
/// `date_route_section.dart`'s use of this screen.
class AerodromePickerScreen extends ConsumerStatefulWidget {
  const AerodromePickerScreen({super.key});

  @override
  ConsumerState<AerodromePickerScreen> createState() =>
      _AerodromePickerScreenState();
}

class _AerodromePickerScreenState extends ConsumerState<AerodromePickerScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addCustom() async {
    final created = await Navigator.of(context).push<Aerodrome>(
      MaterialPageRoute(
        builder: (_) => AddCustomAerodromeScreen(prefillName: _query.trim()),
      ),
    );
    if (created != null && mounted) {
      Navigator.of(
        context,
      ).pop(created.icaoCode ?? created.iataCode ?? created.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final directoryAsync = ref.watch(aerodromeDirectoryProvider);
    final customAsync = ref.watch(customAerodromesProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'ICAO, IATA or name',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                tooltip: 'Clear search',
                                onPressed: _searchController.clear,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: directoryAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('The aerodrome dataset could not be loaded.'),
                ),
                data: (directory) => customAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Custom aerodromes could not be loaded.'),
                  ),
                  data: (custom) => _query.trim().isEmpty
                      ? _BrowseList(directory: directory)
                      : _SearchResults(
                          directory: directory,
                          custom: custom,
                          query: _query,
                          onAddCustom: _addCustom,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseList extends ConsumerWidget {
  const _BrowseList({required this.directory});

  final AerodromeDirectory directory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentAerodromeCodesProvider);
    final frequentAsync = ref.watch(frequentAerodromeCodesProvider);

    return recentAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (recent) => frequentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const SizedBox.shrink(),
        data: (frequent) {
          final frequentOnly = frequent
              .where((icao) => !recent.contains(icao))
              .toList();

          if (recent.isEmpty && frequentOnly.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Search by ICAO, IATA or name to find an aerodrome.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.inkTiers.muted),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (recent.isNotEmpty) ...[
                const _SectionHeader('RECENT'),
                for (final icao in recent)
                  _AerodromeRow(icao: icao, aerodrome: directory.byIcao(icao)),
              ],
              if (frequentOnly.isNotEmpty) ...[
                const _SectionHeader('FREQUENT'),
                for (final icao in frequentOnly)
                  _AerodromeRow(icao: icao, aerodrome: directory.byIcao(icao)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.directory,
    required this.custom,
    required this.query,
    required this.onAddCustom,
  });

  final AerodromeDirectory directory;
  final List<Aerodrome> custom;
  final String query;
  final VoidCallback onAddCustom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final results = directory.search(query, extra: custom);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              'No aerodrome matches "$query".',
              style: theme.textTheme.bodyMedium?.copyWith(color: ink.muted),
            ),
          ),
        for (final aerodrome in results)
          _AerodromeRow(
            icao: aerodrome.icaoCode ?? aerodrome.iataCode ?? aerodrome.name,
            aerodrome: aerodrome,
          ),
        InkWell(
          onTap: onAddCustom,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Add "$query" as a new aerodrome',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final ink = context.inkTiers;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Text(
        label,
        style: AppMonoText.tag(ink.muted).copyWith(letterSpacing: 1.1),
      ),
    );
  }
}

class _AerodromeRow extends StatelessWidget {
  const _AerodromeRow({required this.icao, required this.aerodrome});

  final String icao;
  final Aerodrome? aerodrome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return InkWell(
      onTap: () => Navigator.of(context).pop(
        aerodrome == null
            ? icao
            : (aerodrome!.icaoCode ?? aerodrome!.iataCode ?? aerodrome!.name),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                icao,
                style: AppMonoText.value(
                  theme.colorScheme.onSurface,
                  size: 14,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                aerodrome?.name ?? 'Unknown aerodrome',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: aerodrome == null ? ink.faint : ink.medium,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (aerodrome?.isoCountry != null)
              Text(
                aerodrome!.isoCountry!,
                style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
              ),
          ],
        ),
      ),
    );
  }
}
