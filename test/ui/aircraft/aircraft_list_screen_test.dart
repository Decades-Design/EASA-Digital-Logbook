import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/ui/aircraft/aircraft_list_screen.dart';
import 'package:easa_digital_log/ui/providers/database_provider.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// #56: the first widget test for this screen — proves the provider-
/// override capability #56 itself calls for actually works, against a real
/// (in-memory) database and repository, not just architecturally possible.
void main() {
  Future<AppDatabase> pumpScreen(
    WidgetTester tester, {
    Future<void> Function(AppDatabase db)? seed,
  }) async {
    // `closeStreamsSynchronously: true` — without it, drift keeps a query
    // stream's cache alive for one event-loop iteration after its last
    // subscriber cancels (in case something resubscribes right away), via
    // a real `Timer`. A widget test's fake clock never advances that timer
    // on its own, and drift's own source comment calls this out by name:
    // "If you're sent here because your Flutter tests fail, [use this]."
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    if (seed != null) await seed(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AircraftListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('shows the empty state for a fresh install', (tester) async {
    await pumpScreen(tester);

    expect(find.text('No aircraft yet. Tap + to add one.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lists active aircraft and separates archived ones under their own '
    'header',
    (tester) async {
      await pumpScreen(
        tester,
        seed: (db) async {
          final repo = AircraftRepository(db);
          await repo.upsert(
            const Aircraft(
              registration: 'G-ARRW',
              manufacturer: 'Piper',
              model: 'PA-28-161 Warrior',
              category: AircraftCategory.aeroplane,
              engineType: EngineType.piston,
              engineCount: 1,
              operatingSurface: OperatingSurface.land,
              requiresMultiCrew: false,
            ),
          );
          final archivedId = await repo.upsert(
            const Aircraft(
              registration: 'G-OLDIE',
              manufacturer: 'Cessna',
              model: '152',
              category: AircraftCategory.aeroplane,
              engineType: EngineType.piston,
              engineCount: 1,
              operatingSurface: OperatingSurface.land,
              requiresMultiCrew: false,
            ),
          );
          await repo.setArchived(archivedId, true);
        },
      );

      expect(find.text('G-ARRW'), findsOneWidget);
      expect(find.text('Piper PA-28-161 Warrior'), findsOneWidget);
      expect(find.text('ARCHIVED'), findsOneWidget);
      expect(find.text('G-OLDIE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
