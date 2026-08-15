import 'package:flutter/material.dart';

import '../currency/currency_screen.dart';
import '../entry/new_flight_screen.dart';
import '../logbook/logbook_screen.dart';
import '../settings/settings_screen.dart';
import '../theme/app_colors.dart';
import '../totals/totals_screen.dart';

/// The four tab destinations plus the "New flight" action live here (#55).
///
/// "New flight" is deliberately not a fifth tab: the mockups and
/// docs/entry-form.md both treat entry as a full-screen flow you're pushed
/// into, not a place you sit. Design 1e settled this precisely — of the
/// three nav shapes explored there, "A — labelled, FAB raised" is the pick:
/// labels stay because a logbook has occasional users, not daily ones (a
/// bare ring icon isn't guessable as "Currency"), and the FAB owns the
/// centre slot so a fifth tab (Import/Export, per 1e-C) can be added later
/// without ever displacing it.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _tabs = [
    _NavTab(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: 'Logbook',
    ),
    _NavTab(
      icon: Icons.verified_outlined,
      selectedIcon: Icons.verified,
      label: 'Currency',
    ),
    _NavTab(
      icon: Icons.query_stats_outlined,
      selectedIcon: Icons.query_stats,
      label: 'Totals',
    ),
    _NavTab(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  static const _screens = [
    LogbookScreen(),
    CurrencyScreen(),
    TotalsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const NewFlightScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) ...[
              Expanded(
                child: _NavTabButton(
                  tab: _tabs[i],
                  selected: i == _index,
                  onTap: () => setState(() => _index = i),
                ),
              ),
              // The FAB's reserved slot — the third of five columns, per 1e-A.
              if (i == 1) const SizedBox(width: 64),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavTab {
  const _NavTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _NavTabButton extends StatelessWidget {
  const _NavTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = context.inkTiers;
    final color = selected ? scheme.primary : ink.muted;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? tab.selectedIcon : tab.icon,
              size: 23,
              color: color,
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                fontFamily: 'Instrument Sans',
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
