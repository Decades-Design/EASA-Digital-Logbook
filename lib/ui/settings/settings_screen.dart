import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../domain/currency/currency_dashboard.dart';
import '../../domain/currency/currency_rule_loader.dart';
import '../../domain/currency/rule_set_summary.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/totals/totals_summary.dart';
import '../currency/rule_asset_paths.dart';
import '../currency/sample_currency_data.dart';
import '../preferences/app_preferences.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../totals/sample_totals_data.dart';

const _jurisdictionLabels = {
  'eu.easa.part-fcl': 'EASA Part-FCL',
  'us.faa.part61': 'FAA Part 61',
};

/// A plain UI-only sample string — `PilotProfile` has no name field, and
/// adding one wasn't part of this phase's approved scope (see the redesign
/// plan). Purely decorative header text, not backed by any persisted or
/// domain-derived value.
const _pilotDisplayName = 'A. Whitmore';

/// Settings screen (#62/Phase 4 of the redesign) — replaces the M0
/// placeholder. The one screen in this redesign that touches real app-wide
/// state: Theme and Time-display are genuinely persisted via
/// `shared_preferences` (see `app_preferences.dart`) rather than sample data,
/// since a preference is itself the thing being modelled, not a stand-in for
/// a future repository. Licences, aircraft/aerodrome counts and the rule-set
/// summary still run against the shared sample fixtures every other screen
/// in this redesign uses, pending #56.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  RuleSetSummary? _ruleSetSummary;
  PackageInfo? _packageInfo;
  int? _aircraftCount;
  int? _aerodromeCount;
  late final CalendarDate _today;

  @override
  void initState() {
    super.initState();
    _today = CalendarDate.fromUtcInstant(
      UtcInstant.fromDateTime(DateTime.now().toUtc()),
    );
    _load();
  }

  Future<void> _load() async {
    // `cache: false` — see `NewFlightScreen._loadJurisdictions`'s own note.
    final results = await Future.wait([
      for (final path in ruleAssetPaths)
        rootBundle.loadString(path, cache: false),
    ]);
    final loader = CurrencyRuleLoader.fromYaml(results);
    final ruleSetSummary = summarizeRuleSet(loader.allInForce(_today));
    final packageInfo = await PackageInfo.fromPlatform();
    final flights = sampleTotalsFlights(_today);
    final aircraftCount = distinctAircraftFlown(flights);
    // A bare unique-ICAO count, not `totals_summary.aerodromesVisited` --
    // that also resolves country via the full ~85,000-row OurAirports CSV,
    // which this row's plain count doesn't need to load just for a number.
    final aerodromeCount = <String>{
      for (final record in flights) ...record.flight.route,
    }.length;
    if (!mounted) return;
    setState(() {
      _ruleSetSummary = ruleSetSummary;
      _packageInfo = packageInfo;
      _aircraftCount = aircraftCount;
      _aerodromeCount = aerodromeCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ruleSetSummary = _ruleSetSummary;
    final packageInfo = _packageInfo;
    final aircraftCount = _aircraftCount;
    final aerodromeCount = _aerodromeCount;
    if (ruleSetSummary == null ||
        packageInfo == null ||
        aircraftCount == null ||
        aerodromeCount == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(child: _Header()),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const _SectionHeader('LICENCES & AUTHORITIES'),
                for (final licence in sampleCurrencyLicences) ...[
                  const _Divider(),
                  _LicenceRow(licence: licence),
                ],
                const _Divider(),
                const _AddLicenceRow(),
                const _SectionHeader('DISPLAY'),
                const _Divider(),
                const _ThemeRow(),
                const _Divider(),
                const _TimeDisplayRow(),
                const _Divider(),
                const _DateFormatRow(),
                const _SectionHeader('DATA'),
                const _Divider(),
                _InertRow(
                  title: 'Aircraft & aerodromes',
                  subtitle:
                      '$aircraftCount aircraft · $aerodromeCount aerodromes',
                ),
                const _Divider(),
                const _InertRow(
                  title: 'Import',
                  subtitle:
                      'ForeFlight or Garmin CSV · preview before applying',
                ),
                const _Divider(),
                // `exportDatabaseBackup`/`isBackupOverdue`
                // (lib/data/database_backup.dart) are real and tested, but
                // no screen has ever opened a live `AppDatabase` (#56) --
                // every screen in the app, this one included, runs on
                // sample data. Wiring "Back up now" today would either back
                // up an empty database or require building the app's first
                // live DB connection as a side effect of a Settings screen;
                // both are out of scope here.
                const _InertRow(
                  title: 'Backup & encryption',
                  subtitle: 'Available once live data exists (#56)',
                ),
                const _Divider(),
                // `flight_history.dart`'s replay logic exists; no query
                // layer or viewer UI has been built to call it from yet.
                const _InertRow(
                  title: 'Revision history',
                  subtitle: 'No viewer yet',
                ),
                const _SectionHeader('ABOUT'),
                const _Divider(),
                _InertRow(
                  title: 'Rule set in use',
                  subtitle:
                      '${ruleSetSummary.total} rules · '
                      'EASA ${ruleSetSummary.byJurisdiction['eu.easa.part-fcl'] ?? 0} · '
                      'FAA ${ruleSetSummary.byJurisdiction['us.faa.part61'] ?? 0} · '
                      'medicals ${ruleSetSummary.medicalCount}',
                ),
                const _Divider(),
                _InertRow(
                  title: 'Version',
                  subtitle:
                      '${packageInfo.version} (${packageInfo.buildNumber})',
                ),
                const _Divider(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: theme.textTheme.displaySmall?.copyWith(fontSize: 27),
          ),
          const SizedBox(height: 4),
          Text(
            _pilotDisplayName,
            style: theme.textTheme.bodySmall?.copyWith(color: ink.muted),
          ),
        ],
      ),
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

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant);
}

/// A plain label/subtitle row with no interaction — for status information
/// that has nowhere to navigate to yet (Import, Backup, Revision history,
/// Rule set, Version). Deliberately not wrapped in an `InkWell`: a tappable
/// row implies a destination, and showing one where nothing happens is a
/// worse signal than a plain info row.
class _InertRow extends StatelessWidget {
  const _InertRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    // `SizedBox(width: double.infinity)` -- a bare `Column` has no width
    // opinion of its own and shrink-wraps to its widest child, so without
    // this the whole row centres in its parent `Column` instead of sitting
    // flush left (regression: every _InertRow rendered centred on-device).
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _LicenceRow extends StatelessWidget {
  const _LicenceRow({required this.licence});

  final CurrencyLicenceSpec licence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final scheme = theme.colorScheme;
    final label =
        _jurisdictionLabels[licence.jurisdictionId] ?? licence.jurisdictionId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  licence.privilegeSummary,
                  style: theme.textTheme.labelSmall?.copyWith(color: ink.muted),
                ),
              ],
            ),
          ),
          if (licence.isPrimary)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'PRIMARY',
                style: AppMonoText.tag(
                  context.semanticColors.overriddenText,
                ).copyWith(letterSpacing: 0.7),
              ),
            ),
        ],
      ),
    );
  }
}

/// A real multi-licence model (issuing authority, primary flag, an add-flow)
/// is a separate, larger feature than this screen — deferred rather than
/// shoehorned in. Same no-op convention as Currency's "Edit" pending a
/// licence editor.
class _AddLicenceRow extends StatelessWidget {
  const _AddLicenceRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Icon(Icons.add, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              'Add a licence',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pill switch generic over any small enum-like value — the same visual
/// pattern as Totals' `_GranularitySwitch`/Aerodromes' `_AeroTabSwitch`,
/// generalised here since this screen uses it twice (Theme, Time display).
class _PillSwitch<T> extends StatelessWidget {
  const _PillSwitch({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in options.entries)
            InkWell(
              onTap: () => onChanged(entry.key),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: entry.key == value ? scheme.surface : null,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: entry.key == value
                      ? [
                          BoxShadow(
                            color: scheme.onSurface.withValues(alpha: 0.14),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  entry.value,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeRow extends ConsumerWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final mode = ref.watch(themeModeProvider);
    final note = switch (mode) {
      ThemeMode.system =>
        'Following the device — twilight palette after sunset if it uses one.',
      ThemeMode.dark => 'Always dark, whatever the device is set to.',
      ThemeMode.light => 'Always light, whatever the device is set to.',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Theme', style: theme.textTheme.titleSmall),
              _PillSwitch<ThemeMode>(
                value: mode,
                options: const {
                  ThemeMode.light: 'Light',
                  ThemeMode.dark: 'Dark',
                  ThemeMode.system: 'System',
                },
                onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
          ),
        ],
      ),
    );
  }
}

class _TimeDisplayRow extends ConsumerWidget {
  const _TimeDisplayRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final preference = ref.watch(timeDisplayProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Time display', style: theme.textTheme.titleSmall),
              _PillSwitch<TimeDisplayPreference>(
                value: preference,
                options: const {
                  TimeDisplayPreference.localWithUtc: 'Local, UTC echo',
                  TimeDisplayPreference.utcOnly: 'UTC only',
                },
                onChanged: (p) => ref.read(timeDisplayProvider.notifier).set(p),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'stored in UTC either way',
            style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
          ),
          const SizedBox(height: 4),
          Text(
            _clockSample(preference),
            style: AppMonoText.value(theme.colorScheme.onSurface, size: 13),
          ),
        ],
      ),
    );
  }

  /// Previews the *device's own current* offset via plain `DateTime`
  /// (`.timeZoneName`/`.timeZoneOffset` need no timezone database for "right
  /// now") — never a stored flight instant resolved against a named zone,
  /// which is the historical-lookup case CLAUDE.md reserves for M4.
  String _clockSample(TimeDisplayPreference preference) {
    final now = DateTime.now();
    final utc = now.toUtc();
    final utcLabel =
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}Z';
    if (preference == TimeDisplayPreference.utcOnly) {
      return utcLabel;
    }
    final localLabel =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')} ${now.timeZoneName}';
    return '$localLabel · $utcLabel';
  }
}

/// Not a switchable preference — the app only ever renders one date
/// convention anywhere (`docs/entry-form.md`'s date field:
/// `'${date.day} ${month} ${date.year}'`, e.g. "17 Aug 2026"). A picker with
/// a single non-greyed option would be fabricated UI, not a real
/// preference, so this is real, current, informational text instead.
class _DateFormatRow extends StatelessWidget {
  const _DateFormatRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Date format', style: theme.textTheme.titleSmall),
          Text(
            'D MMM YYYY',
            style: AppMonoText.value(theme.colorScheme.onSurface, size: 13),
          ),
        ],
      ),
    );
  }
}
