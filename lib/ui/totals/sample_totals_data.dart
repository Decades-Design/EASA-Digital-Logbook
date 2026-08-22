import '../../domain/model/aircraft.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/countersignature.dart';
import '../../domain/model/flight.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/instructor_presence.dart';
import '../../domain/model/pilot_capacity.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/repository/flight_read_repository.dart';

export '../currency/sample_currency_data.dart' show samplePilotProfile;

/// Sample data for the Totals screen — the same "real engine over a
/// documented fixture, pending #56" convention as
/// `sample_currency_data.dart`/`sample_logbook_data.dart`. That fixture's 4
/// flights are deliberately narrow (each hand-tuned for one currency state);
/// a meaningful multi-year chart needs real breadth instead, so this is a
/// separate, larger fixture rather than reusing Currency's.
///
/// [sampleTotalsFlights] is **generated, not hand-authored, and
/// deliberately not `Random()`-seeded** — every flight's date, aircraft,
/// capacity and route come from `i`'s own remainder against a few small
/// numbers, so the exact same 360 flights render on every run. This keeps
/// the screen reviewable (the generator is the whole story) and the tests
/// that exercise `totals_summary.dart` against it reproducible.
const _sepWarrior = Aircraft(
  registration: 'G-ARRW',
  manufacturer: 'Piper',
  model: 'PA-28-161 Warrior',
  icaoTypeDesignator: 'P28A',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

const _sepSkyhawk = Aircraft(
  registration: 'N456BD',
  manufacturer: 'Cessna',
  model: '172S Skyhawk',
  icaoTypeDesignator: 'C172',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

const _mepSeneca = Aircraft(
  registration: 'G-MULTI',
  manufacturer: 'Piper',
  model: 'PA-34-200T Seneca',
  icaoTypeDesignator: 'PA34',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 2,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

const _citationJet = Aircraft(
  registration: 'N123CJ',
  manufacturer: 'Cessna',
  model: 'Citation CJ2',
  icaoTypeDesignator: 'C25A',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.turbofan,
  engineCount: 2,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: true,
);

/// 70% Warrior/Skyhawk (single-pilot SEP), 20% Seneca (single-pilot MEP),
/// 10% the jet (multi-pilot) — roughly the mockup's own SEP-heavy fleet mix.
Aircraft _aircraftFor(int i) => switch (i % 10) {
  0 || 1 || 2 || 3 => _sepWarrior,
  4 || 5 || 6 => _sepSkyhawk,
  7 || 8 => _mepSeneca,
  _ => _citationJet,
};

/// A small pool of real GA aerodromes, the same flavour
/// `sample_logbook_data.dart` already uses — `_homeBase` is where most
/// flights start and end; the others give `aerodromesVisited` and the
/// cross-country primitives something real to resolve.
const _homeBase = 'EGKA';
const _destinations = ['EGHH', 'EGTB', 'LFAT', 'EGLF', 'EGBJ'];

const _picSolo = PilotCapacity(
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

const _picWithPax = PilotCapacity(
  commandAuthority: true,
  soleManipulator: true,
  soleOccupant: false,
  multiPilotOperation: false,
  additionalCrewRequiredByRule: false,
  actingAsInstructor: false,
  actingAsExaminer: false,
  picusClaimed: false,
  picInterventionNotRequired: false,
);

const _dualReceived = PilotCapacity(
  commandAuthority: false,
  soleManipulator: true,
  soleOccupant: false,
  multiPilotOperation: false,
  additionalCrewRequiredByRule: false,
  actingAsInstructor: false,
  actingAsExaminer: false,
  picusClaimed: false,
  picInterventionNotRequired: false,
  instructor: InstructorPresence(
    capacity: InstructorCapacity.flightInstructor,
    influencedFlight: true,
    name: 'J. Reilly',
  ),
);

const _actingAsInstructor = PilotCapacity(
  commandAuthority: true,
  soleManipulator: false,
  soleOccupant: false,
  multiPilotOperation: false,
  additionalCrewRequiredByRule: false,
  actingAsInstructor: true,
  actingAsExaminer: false,
  picusClaimed: false,
  picInterventionNotRequired: false,
);

const _multiPilotCopilot = PilotCapacity(
  commandAuthority: false,
  soleManipulator: false,
  soleOccupant: false,
  multiPilotOperation: true,
  additionalCrewRequiredByRule: true,
  actingAsInstructor: false,
  actingAsExaminer: false,
  picusClaimed: false,
  picInterventionNotRequired: false,
  otherPilotRole: OtherPilotRole.requiredCrew,
);

const _multiPilotPic = PilotCapacity(
  commandAuthority: true,
  soleManipulator: false,
  soleOccupant: false,
  multiPilotOperation: true,
  additionalCrewRequiredByRule: true,
  actingAsInstructor: false,
  actingAsExaminer: false,
  picusClaimed: false,
  picInterventionNotRequired: false,
  otherPilotRole: OtherPilotRole.requiredCrew,
);

PilotCapacity _capacityFor(int i, Aircraft aircraft) {
  if (aircraft == _citationJet) {
    return i.isEven ? _multiPilotPic : _multiPilotCopilot;
  }
  return switch (i % 7) {
    0 || 1 || 2 => _picSolo,
    3 => _picWithPax,
    4 => _dualReceived,
    5 => _actingAsInstructor,
    _ => _picSolo,
  };
}

const Duration _localFlightDuration = Duration(minutes: 45);
const Duration _crossCountryFlightDuration = Duration(hours: 2, minutes: 15);

/// Generated flight count, oldest to newest, before the one hand-authored
/// pending-countersignature flight [sampleTotalsFlights] appends.
const _generatedFlightCount = 360;

List<FlightRecord> sampleTotalsFlights(CalendarDate today) => [
  for (var i = 0; i < _generatedFlightCount; i++) _generatedFlight(i, today),
  _pendingCountersignatureFlight(today),
];

FlightRecord _generatedFlight(int i, CalendarDate today) {
  // Roughly every 3 days, oldest first — ~3 years of history.
  final date = today.addDays(-(_generatedFlightCount - 1 - i) * 3);
  final aircraft = _aircraftFor(i);
  final capacity = _capacityFor(i, aircraft);
  final isCrossCountry = i % 5 == 0;
  final isNight = i % 13 == 0;
  final isIfr = i % 17 == 0;
  final duration = isCrossCountry
      ? _crossCountryFlightDuration
      : _localFlightDuration;

  // 22:00 UTC is past civil dusk at EGKA's latitude year-round (even at
  // midsummer BST), so a night-flagged flight actually falls at night rather
  // than merely carrying a night circuit count while the derived Night time
  // stays zero.
  final offBlocks = UtcInstant.utc(
    date.year,
    date.month,
    date.day,
    isNight ? 22 : 10,
  );
  final flight = Flight(
    aircraftRegistration: aircraft.registration,
    // `i ~/ 5` rather than `i` -- `isCrossCountry` is itself `i % 5 == 0`, so
    // indexing the destination pool by `i` would always land on index 0 and
    // every cross-country flight would visit the same single aerodrome.
    route: isCrossCountry
        ? [_homeBase, _destinations[(i ~/ 5) % _destinations.length], _homeBase]
        : const [_homeBase, _homeBase],
    prePlannedNavigation: isCrossCountry,
    offBlocks: offBlocks,
    onBlocks: offBlocks.add(duration),
    capacity: capacity,
    carryingPassengers: capacity == _picWithPax,
    takeoffs: CircuitCounts(
      dayFullStop: isNight ? 0 : 1,
      nightFullStop: isNight ? 1 : 0,
    ),
    landings: CircuitCounts(
      dayFullStop: isNight ? 0 : 1,
      nightFullStop: isNight ? 1 : 0,
    ),
    ifrFlightPlanFiled: isIfr,
    actualInstrumentTime: isIfr
        ? const FlightDuration(20)
        : FlightDuration.zero,
    simulatedInstrumentTime: FlightDuration.zero,
    approaches: isIfr
        ? const [
            Approach(
              type: ApproachType.ils,
              aerodromeIcao: _homeBase,
              runway: '02',
            ),
          ]
        : const [],
    holdingProceduresCount: 0,
    trackingPerformed: false,
    remarks: '',
  );
  return FlightRecord(
    id: 'sample-totals-$i',
    flight: flight,
    aircraft: aircraft,
  );
}

/// The one flight the plan calls out explicitly: a PICUS claim still
/// awaiting its countersignature, exercising
/// `totals_summary.awaitingCountersignatureTime`.
FlightRecord _pendingCountersignatureFlight(CalendarDate today) {
  final date = today.addDays(-14);
  final offBlocks = UtcInstant.utc(date.year, date.month, date.day, 9);
  return FlightRecord(
    id: 'sample-totals-picus-pending',
    flight: Flight(
      aircraftRegistration: _mepSeneca.registration,
      route: const [_homeBase, _homeBase],
      prePlannedNavigation: false,
      offBlocks: offBlocks,
      onBlocks: offBlocks.add(const Duration(hours: 1, minutes: 40)),
      capacity: const PilotCapacity(
        commandAuthority: false,
        soleManipulator: false,
        soleOccupant: false,
        multiPilotOperation: false,
        additionalCrewRequiredByRule: false,
        actingAsInstructor: false,
        actingAsExaminer: false,
        picusClaimed: true,
        picInterventionNotRequired: true,
        otherPilotRole: OtherPilotRole.notRequiredCrew,
        countersignature: Countersignature(
          status: CountersignatureStatus.pending,
        ),
      ),
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
    aircraft: _mepSeneca,
  );
}
