import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/export/amc1_fcl050_row.dart';
import 'package:easa_digital_log/export/amc1_fcl050_totals.dart';
import 'package:flutter_test/flutter_test.dart';

/// #77's arithmetic checked directly against plain Dart values, without
/// needing to parse rendered PDF content back out — the same testing
/// philosophy `amc1_fcl050_layout_test.dart` already uses for per-flight
/// cell values.
void main() {
  Amc1Fcl050Row row({
    FlightDuration singlePilotSingleEngine = FlightDuration.zero,
    FlightDuration singlePilotMultiEngine = FlightDuration.zero,
    FlightDuration multiPilotTime = FlightDuration.zero,
    FlightDuration totalTimeOfFlight = FlightDuration.zero,
    int landingsDay = 0,
    int landingsNight = 0,
    FlightDuration operationalNight = FlightDuration.zero,
    FlightDuration operationalIfr = FlightDuration.zero,
    FlightDuration pilotFunctionPic = FlightDuration.zero,
    FlightDuration pilotFunctionCoPilot = FlightDuration.zero,
    FlightDuration pilotFunctionDual = FlightDuration.zero,
    FlightDuration pilotFunctionInstructor = FlightDuration.zero,
  }) => Amc1Fcl050Row(
    date: '01/06/26',
    departurePlace: 'EGKA',
    departureTime: '09:00',
    arrivalPlace: 'EGKA',
    arrivalTime: '10:00',
    aircraftMakeModelVariant: 'Cessna 152',
    aircraftRegistration: 'G-ABCD',
    singlePilotSingleEngine: singlePilotSingleEngine,
    singlePilotMultiEngine: singlePilotMultiEngine,
    multiPilotTime: multiPilotTime,
    totalTimeOfFlight: totalTimeOfFlight,
    namesPic: 'SELF',
    landingsDay: landingsDay,
    landingsNight: landingsNight,
    operationalNight: operationalNight,
    operationalIfr: operationalIfr,
    pilotFunctionPic: pilotFunctionPic,
    pilotFunctionCoPilot: pilotFunctionCoPilot,
    pilotFunctionDual: pilotFunctionDual,
    pilotFunctionInstructor: pilotFunctionInstructor,
    remarks: '',
  );

  final rowA = row(
    singlePilotSingleEngine: const FlightDuration(60),
    totalTimeOfFlight: const FlightDuration(60),
    landingsDay: 2,
    landingsNight: 1,
    operationalNight: const FlightDuration(15),
    pilotFunctionPic: const FlightDuration(60),
  );

  final rowB = row(
    singlePilotMultiEngine: const FlightDuration(90),
    multiPilotTime: const FlightDuration(30),
    totalTimeOfFlight: const FlightDuration(120),
    landingsDay: 1,
    landingsNight: 3,
    operationalNight: const FlightDuration(45),
    operationalIfr: const FlightDuration(20),
    pilotFunctionCoPilot: const FlightDuration(120),
  );

  test('zero has every duration and count at zero', () {
    const totals = Amc1Fcl050Totals.zero;
    expect(totals.singlePilotSingleEngine, FlightDuration.zero);
    expect(totals.singlePilotMultiEngine, FlightDuration.zero);
    expect(totals.multiPilotTime, FlightDuration.zero);
    expect(totals.totalTimeOfFlight, FlightDuration.zero);
    expect(totals.landingsDay, 0);
    expect(totals.landingsNight, 0);
    expect(totals.operationalNight, FlightDuration.zero);
    expect(totals.operationalIfr, FlightDuration.zero);
    expect(totals.pilotFunctionPic, FlightDuration.zero);
    expect(totals.pilotFunctionCoPilot, FlightDuration.zero);
    expect(totals.pilotFunctionDual, FlightDuration.zero);
    expect(totals.pilotFunctionInstructor, FlightDuration.zero);
  });

  test('fromRows of an empty list is zero', () {
    final totals = Amc1Fcl050Totals.fromRows(const []);
    expect(totals.totalTimeOfFlight, FlightDuration.zero);
    expect(totals.landingsDay, 0);
  });

  test('fromRows sums each field across every row using integer minutes', () {
    final totals = Amc1Fcl050Totals.fromRows([rowA, rowB]);

    expect(totals.singlePilotSingleEngine, const FlightDuration(60));
    expect(totals.singlePilotMultiEngine, const FlightDuration(90));
    expect(totals.multiPilotTime, const FlightDuration(30));
    expect(totals.totalTimeOfFlight, const FlightDuration(180));
    expect(totals.landingsDay, 3);
    expect(totals.landingsNight, 4);
    expect(totals.operationalNight, const FlightDuration(60));
    expect(totals.operationalIfr, const FlightDuration(20));
    expect(totals.pilotFunctionPic, const FlightDuration(60));
    expect(totals.pilotFunctionCoPilot, const FlightDuration(120));
    expect(totals.pilotFunctionDual, FlightDuration.zero);
    expect(totals.pilotFunctionInstructor, FlightDuration.zero);
  });

  test('operator + combines two totals field by field', () {
    final a = Amc1Fcl050Totals.fromRows([rowA]);
    final b = Amc1Fcl050Totals.fromRows([rowB]);
    final combined = a + b;
    final direct = Amc1Fcl050Totals.fromRows([rowA, rowB]);

    expect(combined.totalTimeOfFlight, direct.totalTimeOfFlight);
    expect(combined.landingsDay, direct.landingsDay);
    expect(combined.landingsNight, direct.landingsNight);
    expect(combined.pilotFunctionCoPilot, direct.pilotFunctionCoPilot);
  });

  test('page one totals values print a summed HH:MM/count per column, never '
      'blank on zero, and blank for every non-summable column', () {
    final totals = Amc1Fcl050Totals.fromRows([rowA, rowB]);

    expect(amc1Fcl050PageOneTotalsValues(totals), [
      '', // date
      '', '', // departure place/time
      '', '', // arrival place/time
      '', '', // aircraft make/model, registration
      '01:00', // SE
      '01:30', // ME
      '00', '30', // MULTI-PILOT TIME hh/mm
      '03', '00', // TOTAL TIME OF FLIGHT hh/mm
      '', // names PIC
      '3', // landings day
      '4', // landings night
    ]);
  });

  test(
    'page one totals values show 00:00/0 for an all-zero total, not blank',
    () {
      final totals = Amc1Fcl050Totals.zero;

      expect(amc1Fcl050PageOneTotalsValues(totals), [
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '00:00',
        '00:00',
        '00',
        '00',
        '00',
        '00',
        '',
        '0',
        '0',
      ]);
    },
  );

  test('page two totals values print a summed HH:MM per column, blank for '
      'FSTD (no data model yet) and no remarks column', () {
    final totals = Amc1Fcl050Totals.fromRows([rowA, rowB]);

    expect(amc1Fcl050PageTwoTotalsValues(totals), [
      '01', '00', // OPERATIONAL CONDITION TIME NIGHT hh/mm
      '00', '20', // IFR hh/mm
      '01', '00', // PILOT FUNCTION TIME PIC hh/mm
      '02', '00', // CO-PILOT hh/mm
      '00', '00', // DUAL hh/mm
      '00', '00', // INSTRUCTOR hh/mm
      '', '', // FSTD date, type
      '', '', // FSTD total time hh/mm
    ]);
  });
}
