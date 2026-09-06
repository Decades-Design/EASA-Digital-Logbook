import '../domain/model/aircraft.dart';
import '../domain/model/flight.dart';
import '../domain/model/flight_duration.dart';
import '../domain/model/flight_times.dart';
import '../domain/model/utc_instant.dart';
import '../domain/projection/projection.dart';
import '../domain/projection/projection_result.dart';
import 'amc1_fcl050_row.dart';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// `dd/mm/yy` per the sheet's own group 1 sub-heading — not this app's
/// usual ISO formatting, since that is a display convention the printed
/// template itself specifies.
String _formatDate(UtcInstant instant) {
  final utc = instant.asUtcDateTime;
  return '${_twoDigits(utc.day)}/${_twoDigits(utc.month)}/'
      '${_twoDigits(utc.year % 100)}';
}

String _formatTime(UtcInstant instant) {
  final utc = instant.asUtcDateTime;
  return '${_twoDigits(utc.hour)}:${_twoDigits(utc.minute)}';
}

FlightDuration _quantity(ProjectionResult result, String name) =>
    result[name]?.value ?? FlightDuration.zero;

/// Group 7: `'SELF'` when this pilot held command authority, by the same
/// convention every paper EASA logbook uses; otherwise whoever else did —
/// the instructor's name when dual instruction was received and influenced
/// the flight (the instructor normally holds command on that flight), or
/// [Flight.otherPilotName] for every other arrangement (SIC, safety pilot,
/// examiner). Blank, never guessed, when none of these names anyone.
String _namesPic(Flight flight) {
  if (flight.capacity.commandAuthority) return 'SELF';
  final instructor = flight.capacity.instructor;
  if (instructor != null && instructor.influencedFlight) {
    return instructor.name ?? '';
  }
  return flight.otherPilotName ?? '';
}

/// Maps one [flight] flown in [aircraft] to a printed `AMC1 FCL.050` row,
/// deriving every jurisdiction-dependent figure (group 5's single/multi-
/// pilot split, group 9's night/IFR time, group 10's pilot function time)
/// via [easaProjection] — the same division `foreflight_flight_exporter
/// .dart` uses for FAA's own export, applied to EASA's sheet instead.
///
/// Everything else is a raw [Flight]/[Aircraft] fact read directly: dates,
/// places, times, aircraft identity and landings counts already have a
/// single, jurisdiction-independent meaning, so there is nothing to
/// project for them.
Amc1Fcl050Row buildAmc1Fcl050Row({
  required Flight flight,
  required Aircraft aircraft,
  required Projection easaProjection,
}) {
  final blockTime = flight.blockTime;
  final result = easaProjection.project(flight, aircraft);
  final route = flight.route;

  final pic =
      _quantity(result, 'pic') +
      _quantity(result, 'spic') +
      _quantity(result, 'picus');

  return Amc1Fcl050Row(
    date: _formatDate(flight.offBlocks),
    departurePlace: route.isNotEmpty ? route.first : '',
    departureTime: _formatTime(flight.offBlocks),
    arrivalPlace: route.length > 1 ? route.last : '',
    arrivalTime: _formatTime(flight.onBlocks),
    aircraftMakeModelVariant: [
      aircraft.manufacturer,
      aircraft.model,
    ].where((s) => s.isNotEmpty).join(' '),
    aircraftRegistration: aircraft.registration,
    singlePilotSingleEngine: _quantity(result, 'singlePilotSingleEngine'),
    singlePilotMultiEngine: _quantity(result, 'singlePilotMultiEngine'),
    multiPilotTime: _quantity(result, 'multiPilot'),
    totalTimeOfFlight: blockTime,
    namesPic: _namesPic(flight),
    landingsDay: flight.landings.dayFullStop + flight.landings.dayTouchAndGo,
    landingsNight:
        flight.landings.nightFullStop + flight.landings.nightTouchAndGo,
    operationalNight: _quantity(result, 'night'),
    operationalIfr: _quantity(result, 'ifr'),
    pilotFunctionPic: pic,
    pilotFunctionCoPilot: _quantity(result, 'copilot'),
    pilotFunctionDual: _quantity(result, 'dual'),
    pilotFunctionInstructor: _quantity(result, 'instructor'),
    remarks: flight.remarks,
  );
}
