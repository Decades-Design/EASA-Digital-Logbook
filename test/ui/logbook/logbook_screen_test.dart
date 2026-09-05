import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/seed_sample_data.dart';
import 'package:easa_digital_log/ui/logbook/logbook_screen.dart';
import 'package:easa_digital_log/ui/providers/database_provider.dart';
import 'package:easa_digital_log/ui/providers/jurisdiction_projection_providers.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// #56: the first widget test for this screen — proves the provider-
/// override capability actually works against a real database, jurisdiction
/// registry and aerodrome directory, not just architecturally.
void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<void> Function(AppDatabase db)? seed,
  }) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // See aircraft_list_screen_test.dart's own note on `closeStreamsSynchronously`
    // — needed for `draftFlightRecordsProvider`/`committedFlightRecordsProvider`
    // (both drift `.watch()` streams) to behave under a widget test's fake clock.
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    if (seed != null) await seed(db);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    // `jurisdictionProjectionsProvider` reads the ~13MB bundled OurAirports
    // CSV via `rootBundle.loadString` — real file I/O, resolved via a real
    // `Timer`/event-loop turn that a widget test's fake clock never
    // advances on its own (`pumpAndSettle` only keeps pumping while new
    // *frames* get scheduled, and nothing schedules one while this is
    // still in flight, so it settles immediately without ever finishing).
    // `runAsync` gives it real wall-clock time to actually complete,
    // reading through the same container the widget below reuses.
    await tester.runAsync(
      () => container.read(jurisdictionProjectionsProvider.future),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LogbookScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows the no-licence empty state for a fresh install with no pilot '
    'profile',
    (tester) async {
      await pumpScreen(tester);

      expect(find.text('No licence on file yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'renders a chronological list of real, repository-backed flights once '
    'seeded',
    (tester) async {
      await pumpScreen(tester, seed: seedSampleDataIfEmpty);

      expect(find.text('No licence on file yet'), findsNothing);
      expect(find.text('No flights logged yet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
