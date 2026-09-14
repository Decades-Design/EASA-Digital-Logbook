import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/export/amc1_fcl050_row.dart';

/// Fixed inputs for the AMC1 FCL.050 determinism suite (#79) — shared by
/// `amc1_fcl050_determinism_test.dart` (which compares against the
/// committed golden PDF) and `amc1_fcl050_golden_writer.dart` (which
/// regenerates it), so the two can never silently drift apart. Values are
/// arbitrary but fixed: what matters is that every run of either file
/// builds the exact same document.
const amc1Fcl050GoldenHolderName = 'Jane Pilot';
const amc1Fcl050GoldenHolderLicenceNumber = 'UK.FCL.123456';

List<Amc1Fcl050Row> amc1Fcl050GoldenRows() => [
  const Amc1Fcl050Row(
    date: '28/12/24',
    departurePlace: 'LIAP',
    departureTime: '12:30',
    arrivalPlace: 'LIAP',
    arrivalTime: '13:15',
    aircraftMakeModelVariant: 'BEECH V35B TN',
    aircraftRegistration: 'N346AP',
    singlePilotSingleEngine: FlightDuration(45),
    singlePilotMultiEngine: FlightDuration.zero,
    multiPilotTime: FlightDuration.zero,
    totalTimeOfFlight: FlightDuration(45),
    namesPic: 'Self',
    landingsDay: 3,
    landingsNight: 2,
    operationalNight: FlightDuration.zero,
    operationalIfr: FlightDuration.zero,
    pilotFunctionPic: FlightDuration(45),
    pilotFunctionCoPilot: FlightDuration.zero,
    pilotFunctionDual: FlightDuration.zero,
    pilotFunctionInstructor: FlightDuration.zero,
    remarks: 'Local flight.',
  ),
  const Amc1Fcl050Row(
    date: '02/01/25',
    departurePlace: 'EGKA',
    departureTime: '09:00',
    arrivalPlace: 'EGHI',
    arrivalTime: '10:05',
    aircraftMakeModelVariant: 'Cessna 152',
    aircraftRegistration: 'G-ABCD',
    singlePilotSingleEngine: FlightDuration.zero,
    singlePilotMultiEngine: FlightDuration.zero,
    multiPilotTime: FlightDuration(65),
    totalTimeOfFlight: FlightDuration(65),
    namesPic: '',
    landingsDay: 1,
    landingsNight: 0,
    operationalNight: FlightDuration.zero,
    operationalIfr: FlightDuration(20),
    pilotFunctionPic: FlightDuration.zero,
    pilotFunctionCoPilot: FlightDuration.zero,
    pilotFunctionDual: FlightDuration.zero,
    pilotFunctionInstructor: FlightDuration.zero,
    remarks: 'PICUS sector, multi-crew.',
    countersignature: 'Countersigned by K. Almqvist (SWE.ATPL.90233)',
  ),
];
