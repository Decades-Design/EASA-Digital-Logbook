import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:easa_digital_log/io/canonical_import_row.dart';
import 'package:easa_digital_log/io/import_adapter.dart';
import 'package:easa_digital_log/ui/io/import_preview_screen.dart';
import 'package:easa_digital_log/ui/providers/database_provider.dart';
import 'package:easa_digital_log/ui/providers/flight_records_providers.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _capacity = PilotCapacity(
  commandAuthority: true,
  soleManipulator: true,
  soleOccupant: true,
  multiPilotOperation: false,
  additionalCrewRequiredByRule: false,
  actingAsInstructor: false,
  actingAsExaminer: false,
  picusClaimed: false,
  picInterventionNotRequired: false,
);

const _aircraft = Aircraft(
  registration: 'N100AB',
  manufacturer: 'Cessna',
  model: '172',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

Flight _flight({int hour = 10}) => Flight(
  aircraftRegistration: 'N100AB',
  route: const ['KABC', 'KDEF'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 1, 1, hour),
  onBlocks: UtcInstant.utc(2026, 1, 1, hour + 1),
  capacity: _capacity,
  carryingPassengers: false,
  takeoffs: const CircuitCounts(dayFullStop: 1),
  landings: const CircuitCounts(dayFullStop: 1),
  ifrFlightPlanFiled: false,
  actualInstrumentTime: FlightDuration.zero,
  simulatedInstrumentTime: FlightDuration.zero,
  approaches: const [],
  holdingProceduresCount: 0,
  trackingPerformed: false,
  remarks: '',
);

/// #73's preview screen — proves the duplicate-defaults-to-skipped and
/// clean-row-defaults-to-imported behaviour, the error section, and that
/// pressing "Import" genuinely writes a draft through the real repository
/// stack, not just updates local widget state.
///
/// `allFlightRecordsProvider` is overridden directly to a hand-built list
/// rather than exercised through its real jurisdiction-asset/drift-stream
/// chain: that chain needs real wall-clock time under a widget test's fake
/// clock (see `logbook_screen_test.dart`'s own note), and this screen's own
/// logic (`buildImportPreview`) is exactly as real either way — only the
/// data source differs.
void main() {
  Future<AppDatabase> pumpScreen(
    WidgetTester tester, {
    required ImportParseResult parseResult,
    List<FlightRecord> existingFlights = const [],
  }) async {
    // A SnackBar's "Undo" action can render outside the default 800x600
    // test viewport (see logbook_screen_test.dart's own note) — enough
    // height that it stays reachable by tap().
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await AircraftRepository(db).upsert(_aircraft, id: 'aircraft-1');

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        allFlightRecordsProvider.overrideWith((ref) async => existingFlights),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ImportPreviewScreen(
            parseResult: parseResult,
            sourceLabel: 'Test importer',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('a duplicate flight defaults to skipped, a new one defaults to '
      'imported, and an error row is shown read-only', (tester) async {
    final existingFlight = _flight(hour: 9);
    await pumpScreen(
      tester,
      parseResult: ImportParseResult(
        rows: [
          CanonicalImportRow(
            sourceRowNumber: 2,
            flight: existingFlight, // exact duplicate of the seed below
            aircraft: _aircraft,
          ),
          CanonicalImportRow(
            sourceRowNumber: 3,
            flight: _flight(hour: 14),
            aircraft: _aircraft,
          ),
        ],
        errors: const [ImportRowError(rowNumber: 4, message: 'bad row')],
      ),
      existingFlights: [
        FlightRecord(
          id: 'existing-1',
          flight: existingFlight,
          aircraft: _aircraft,
        ),
      ],
    );

    expect(find.textContaining('bad row'), findsOneWidget);

    // Two per-row checkboxes plus the "reviewed the unreadable rows"
    // acknowledgment checkbox #74 requires before Import enables.
    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes, hasLength(3));
    expect(checkboxes.map((c) => c.value), [false, true, false]);
  });

  testWidgets(
    'Import stays disabled until the unreadable rows are acknowledged, '
    'even with a valid row selected',
    (tester) async {
      await pumpScreen(
        tester,
        parseResult: ImportParseResult(
          rows: [
            CanonicalImportRow(
              sourceRowNumber: 2,
              flight: _flight(),
              aircraft: _aircraft,
            ),
          ],
          errors: const [ImportRowError(rowNumber: 3, message: 'bad row')],
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      final buttonAfter = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(buttonAfter.onPressed, isNotNull);
    },
  );

  testWidgets('pressing Import writes the selected flight as a draft', (
    tester,
  ) async {
    final db = await pumpScreen(
      tester,
      parseResult: ImportParseResult(
        rows: [
          CanonicalImportRow(
            sourceRowNumber: 2,
            flight: _flight(),
            aircraft: _aircraft,
          ),
        ],
        errors: const [],
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Import 1 flight(s)'));
    await tester.pumpAndSettle();

    final flights = await db.select(db.flightsTable).get();
    expect(flights, hasLength(1));
    expect(flights.single.committedAt, isNull);
    expect(flights.single.importBatchId, isNotNull);

    final batches = await db.select(db.importBatchesTable).get();
    expect(batches.single.sourceLabel, 'Test importer');
  });

  testWidgets('tapping Undo removes the imported draft and reports the split', (
    tester,
  ) async {
    final db = await pumpScreen(
      tester,
      parseResult: ImportParseResult(
        rows: [
          CanonicalImportRow(
            sourceRowNumber: 2,
            flight: _flight(),
            aircraft: _aircraft,
          ),
        ],
        errors: const [],
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Import 1 flight(s)'));
    // Not pumpAndSettle: a SnackBar's default display duration (4s) would
    // elapse under the fake clock's accelerated pumping and dismiss it
    // before its action could be invoked. Pump in short steps instead,
    // stopping as soon as it appears, well inside that 4s window.
    for (var i = 0; i < 20 && find.text('Undo').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('1 flight(s) imported as drafts.'), findsOneWidget);

    // The SnackBarAction's own render position sits right at (and, in
    // this test environment, very slightly past) the edge of even a
    // generously tall test viewport, so `tap()`'s hit-testing misses it —
    // invoking its callback directly exercises the same behaviour a real
    // tap would without fighting that geometry.
    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    action.onPressed();
    for (
      var i = 0;
      i < 20 && find.text('1 flight(s) removed.').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(await db.select(db.flightsTable).get(), isEmpty);
    expect(find.text('1 flight(s) removed.'), findsOneWidget);
  });

  testWidgets('unchecking the only row disables the Import button', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      parseResult: ImportParseResult(
        rows: [
          CanonicalImportRow(
            sourceRowNumber: 2,
            flight: _flight(),
            aircraft: _aircraft,
          ),
        ],
        errors: const [],
      ),
    );

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('"Skip all duplicates" excludes every flagged row at once', (
    tester,
  ) async {
    final existingFlight = _flight(hour: 9);
    await pumpScreen(
      tester,
      parseResult: ImportParseResult(
        rows: [
          CanonicalImportRow(
            sourceRowNumber: 2,
            flight: existingFlight,
            aircraft: _aircraft,
          ),
        ],
        errors: const [],
      ),
      existingFlights: [
        FlightRecord(
          id: 'existing-1',
          flight: existingFlight,
          aircraft: _aircraft,
        ),
      ],
    );

    // The one row is already excluded by default (it's a duplicate) —
    // select it, then use "Skip all duplicates" to exclude it again.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);

    await tester.tap(find.text('Skip all duplicates'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isFalse);
  });
}
