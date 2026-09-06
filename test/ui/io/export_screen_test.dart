import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/export_record_repository_drift.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/primitives/default_primitives.dart';
import 'package:easa_digital_log/domain/projection/jurisdiction_projection.dart';
import 'package:easa_digital_log/domain/projection/projection.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:easa_digital_log/ui/io/export_screen.dart';
import 'package:easa_digital_log/ui/providers/database_provider.dart';
import 'package:easa_digital_log/ui/providers/foreflight_export_providers.dart';
import 'package:easa_digital_log/ui/providers/repository_providers.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal fake — `ExportScreen` only ever calls `watchFlights`, so
/// everything else is unreachable and just throws if that ever changes
/// without this fake being noticed.
class _FakeFlightReadRepository implements FlightReadRepository {
  _FakeFlightReadRepository(this.projectedFlights);

  final List<ProjectedFlight> projectedFlights;

  @override
  Stream<List<ProjectedFlight>> watchFlights({
    required Projection projection,
    FlightQuery query = const FlightQuery(),
  }) => Stream.value(projectedFlights);

  @override
  Future<ProjectedFlight?> find(
    String flightId, {
    required Projection projection,
  }) => throw UnimplementedError();

  @override
  Stream<List<FlightRecord>> watchDrafts() => throw UnimplementedError();

  @override
  Future<FlightRecord?> findDraft(String flightId) =>
      throw UnimplementedError();

  @override
  Future<FlightHistory?> revisionHistory(String flightId) =>
      throw UnimplementedError();
}

/// A render/flow test — actually driving `file_picker`'s native save dialog
/// isn't exercised here (a platform channel with no fake to hand a path
/// back through in a widget test, the same limitation `import_screen_test.dart`
/// documents), so these tests stop short of tapping Export once a range
/// with real flights is selected. The "no flights in range" path is
/// exercised fully, since it returns before ever reaching the save dialog.
///
/// `faaProjectionProvider`/`flightReadRepositoryProvider` are overridden
/// directly rather than exercising `jurisdictionProjectionsProvider`'s real
/// asset-loading chain — this screen's own logic doesn't care where the
/// data came from, only what it does with it.
void main() {
  final fakeFaaProjection = JurisdictionProjection(
    registry: JurisdictionRegistry(const []),
    primitives: defaultPrimitives,
    aerodromes: AerodromeDirectory(const []),
    jurisdictionId: 'us.faa.part61',
  );

  Future<AppDatabase> pumpScreen(
    WidgetTester tester, {
    List<ProjectedFlight> projectedFlights = const [],
  }) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        faaProjectionProvider.overrideWith((ref) async => fakeFaaProjection),
        flightReadRepositoryProvider.overrideWithValue(
          _FakeFlightReadRepository(projectedFlights),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const ExportScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  Future<void> pickDate(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ListTile, label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('the Export button is disabled until a valid range is picked', (
    tester,
  ) async {
    await pumpScreen(tester);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await pickDate(tester, 'From');
    await pickDate(tester, 'To');

    final buttonAfter = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(buttonAfter.onPressed, isNotNull);
  });

  testWidgets(
    'exporting a range with no committed flights reports that rather than '
    'opening a save dialog',
    (tester) async {
      await pumpScreen(tester);

      await pickDate(tester, 'From');
      await pickDate(tester, 'To');

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No committed flights'), findsOneWidget);
    },
  );

  testWidgets(
    'a range overlapping a previously recorded export shows a warning',
    (tester) async {
      final db = await pumpScreen(tester);
      final today = DateTime.now();
      await DriftExportRecordRepository(db).recordExport(
        format: 'ForeFlight',
        from: CalendarDate(today.year, today.month, 1),
        to: CalendarDate(today.year, today.month, today.day),
      );

      await pickDate(tester, 'From');
      await pickDate(tester, 'To');
      await tester.pumpAndSettle();

      expect(find.textContaining('overlaps'), findsOneWidget);
    },
  );
}
