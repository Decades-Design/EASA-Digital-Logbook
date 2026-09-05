import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/ui/preferences/app_preferences.dart';
import 'package:easa_digital_log/ui/providers/database_provider.dart';
import 'package:easa_digital_log/ui/settings/settings_screen.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #56: the first widget test for this screen — proves provider overrides
/// (database, shared preferences) actually work end to end.
void main() {
  Future<SharedPreferences> pumpScreen(WidgetTester tester) async {
    // See aircraft_list_screen_test.dart's own note on why this flag is
    // needed: without it, drift's query-stream debounce timer never fires
    // under a widget test's fake clock.
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    PackageInfo.setMockInitialValues(
      appName: 'EASA Digital Logbook',
      packageName: 'com.example.easa_digital_log',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('renders every section without crashing', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Aircraft'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Time display'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the theme choice is genuinely persisted via shared_preferences, not '
    'just held in provider state',
    (tester) async {
      final prefs = await pumpScreen(tester);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      // A fresh `ProviderContainer` over the same (mocked) `prefs` instance
      // simulates the app being fully restarted — proving the choice
      // outlives the provider that wrote it, not just this widget's state.
      final restarted = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(restarted.dispose);
      expect(restarted.read(themeModeProvider), ThemeMode.dark);
      expect(tester.takeException(), isNull);
    },
  );
}
