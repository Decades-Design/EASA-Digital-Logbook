import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:easa_digital_log/ui/entry/duplicate_flight_action.dart';
import 'package:easa_digital_log/ui/providers/database_provider.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _picCapacity = PilotCapacity(
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
  registration: 'G-ABCD',
  manufacturer: 'Cessna',
  model: '152',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

FlightRecord _record(List<String> route) {
  final offBlocks = UtcInstant.utc(2026, 1, 1, 9);
  return FlightRecord(
    id: 'f1',
    aircraft: _aircraft,
    flight: Flight(
      aircraftRegistration: _aircraft.registration,
      route: route,
      prePlannedNavigation: false,
      offBlocks: offBlocks,
      onBlocks: offBlocks.add(const Duration(hours: 1)),
      capacity: _picCapacity,
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
    ),
  );
}

void main() {
  Future<void> pumpWithButton(WidgetTester tester, FlightRecord record) async {
    // The default 800x600 test surface is too short for NewFlightScreen's
    // full-length column once navigated to — see new_flight_screen_test
    // .dart's own pumpScreen for the same fix.
    tester.view.physicalSize = const Size(390, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // #58's qualification-gap banner (rendered inside the NewFlightScreen
    // this pushes) reads real repository providers, which need a working
    // `databaseProvider` override — same fix as new_flight_screen_test
    // .dart's own pumpScreen.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDuplicateFlightMenu(context, record),
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'a round trip shaped [A, B, A] opens duplicate directly — reversing it '
    'would be a no-op',
    (tester) async {
      await pumpWithButton(tester, _record(['EGKA', 'EGTB', 'EGKA']));

      await tester.tap(find.text('trigger'));
      // Past the push transition, short of pumpAndSettle: NewFlightScreen's
      // own async jurisdiction load and full-form layout aren't what this
      // test is about — only that no chooser sheet interposed itself and
      // navigation actually happened.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Duplicate return leg'), findsNothing);
      expect(find.text('New flight'), findsOneWidget);
    },
  );

  testWidgets('a single-aerodrome route opens duplicate directly', (
    tester,
  ) async {
    await pumpWithButton(tester, _record(['EGKA', 'EGKA']));

    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Duplicate return leg'), findsNothing);
    expect(find.text('New flight'), findsOneWidget);
  });

  testWidgets('a genuine one-way route offers a same-route/return-leg choice', (
    tester,
  ) async {
    await pumpWithButton(tester, _record(['EGKA', 'EGTB']));

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Duplicate return leg'), findsOneWidget);
    expect(find.text('EGTB → EGKA'), findsOneWidget);

    await tester.tap(find.text('Duplicate return leg'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('New flight'), findsOneWidget);
  });
}
