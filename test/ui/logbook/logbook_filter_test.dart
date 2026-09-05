import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:easa_digital_log/ui/logbook/logbook_filter.dart';
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

FlightRecord _record({
  String id = 'f1',
  CalendarDate date = const CalendarDate(2026, 6, 1),
  List<String> route = const ['EGKA', 'EGKB'],
  List<Approach> approaches = const [],
  PilotCapacity capacity = _picCapacity,
  bool ifrFlightPlanFiled = false,
  int nightLandings = 0,
  String remarks = '',
  String? otherPilotName,
  Aircraft aircraft = _aircraft,
}) {
  final offBlocks = UtcInstant.utc(date.year, date.month, date.day, 10);
  return FlightRecord(
    id: id,
    aircraft: aircraft,
    flight: Flight(
      aircraftRegistration: aircraft.registration,
      route: route,
      prePlannedNavigation: false,
      offBlocks: offBlocks,
      onBlocks: offBlocks.add(const Duration(hours: 1)),
      capacity: capacity,
      otherPilotName: otherPilotName,
      carryingPassengers: false,
      takeoffs: const CircuitCounts(dayFullStop: 1),
      landings: CircuitCounts(
        dayFullStop: nightLandings == 0 ? 1 : 0,
        nightFullStop: nightLandings,
      ),
      ifrFlightPlanFiled: ifrFlightPlanFiled,
      actualInstrumentTime: FlightDuration.zero,
      simulatedInstrumentTime: FlightDuration.zero,
      approaches: approaches,
      holdingProceduresCount: 0,
      trackingPerformed: false,
      remarks: remarks,
    ),
  );
}

void main() {
  group('LogbookFilter.isEmpty', () {
    test('true for the default filter', () {
      expect(const LogbookFilter().isEmpty, isTrue);
    });

    test('false once any field is set', () {
      expect(const LogbookFilter(searchText: 'x').isEmpty, isFalse);
      expect(const LogbookFilter(ifrFlightPlanFiled: true).isEmpty, isFalse);
    });
  });

  group('LogbookFilter.matches — date range', () {
    test('excludes a flight before "from"', () {
      const filter = LogbookFilter(from: CalendarDate(2026, 6, 15));
      expect(
        filter.matches(_record(date: const CalendarDate(2026, 6, 1))),
        isFalse,
      );
    });

    test('excludes a flight after "to"', () {
      const filter = LogbookFilter(to: CalendarDate(2026, 6, 15));
      expect(
        filter.matches(_record(date: const CalendarDate(2026, 7, 1))),
        isFalse,
      );
    });

    test('includes a flight within the range, inclusive of both ends', () {
      const filter = LogbookFilter(
        from: CalendarDate(2026, 6, 1),
        to: CalendarDate(2026, 6, 30),
      );
      expect(
        filter.matches(_record(date: const CalendarDate(2026, 6, 1))),
        isTrue,
      );
      expect(
        filter.matches(_record(date: const CalendarDate(2026, 6, 30))),
        isTrue,
      );
    });
  });

  group('LogbookFilter.matches — aircraft', () {
    test('matches by registration, not by any id', () {
      const filter = LogbookFilter(aircraftLabel: 'G-ABCD');
      expect(filter.matches(_record()), isTrue);
      expect(
        filter.matches(
          _record(aircraft: _aircraft.copyWith(registration: 'G-WXYZ')),
        ),
        isFalse,
      );
    });
  });

  group('LogbookFilter.matches — aerodrome', () {
    test('matches a route leg, case-insensitively', () {
      const filter = LogbookFilter(aerodromeIdentifier: 'egkb');
      expect(filter.matches(_record(route: const ['EGKA', 'EGKB'])), isTrue);
    });

    test('matches an approach aerodrome not on the route itself', () {
      const filter = LogbookFilter(aerodromeIdentifier: 'EGLL');
      expect(
        filter.matches(
          _record(
            route: const ['EGKA', 'EGKA'],
            approaches: const [
              Approach(
                type: ApproachType.ils,
                aerodromeIcao: 'EGLL',
                runway: '27L',
                count: 1,
              ),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('excludes a flight that touched neither', () {
      const filter = LogbookFilter(aerodromeIdentifier: 'EGLL');
      expect(filter.matches(_record(route: const ['EGKA', 'EGKB'])), isFalse);
    });
  });

  group('LogbookFilter.matches — capacity', () {
    test('matches a single capacity dimension', () {
      const filter = LogbookFilter(
        capacity: CapacityFilter(actingAsInstructor: true),
      );
      expect(
        filter.matches(
          _record(
            capacity: _picCapacity.copyWith(
              actingAsInstructor: true,
              instructor: const InstructorPresence(
                capacity: InstructorCapacity.flightInstructor,
                influencedFlight: true,
              ),
            ),
          ),
        ),
        isTrue,
      );
      expect(filter.matches(_record()), isFalse);
    });

    test('every set dimension must match (ANDed)', () {
      const filter = LogbookFilter(
        capacity: CapacityFilter(commandAuthority: true, picusClaimed: true),
      );
      // commandAuthority true, picusClaimed false (default) — fails the AND.
      expect(filter.matches(_record()), isFalse);
    });
  });

  group('LogbookFilter.matches — IFR', () {
    test('matches on ifrFlightPlanFiled', () {
      const filter = LogbookFilter(ifrFlightPlanFiled: true);
      expect(filter.matches(_record(ifrFlightPlanFiled: true)), isTrue);
      expect(filter.matches(_record(ifrFlightPlanFiled: false)), isFalse);
    });
  });

  group('LogbookFilter.matches — night', () {
    test('hasNightFlying: true requires at least one night landing', () {
      const filter = LogbookFilter(hasNightFlying: true);
      expect(filter.matches(_record(nightLandings: 1)), isTrue);
      expect(filter.matches(_record(nightLandings: 0)), isFalse);
    });

    test('hasNightFlying: false requires zero night landings', () {
      const filter = LogbookFilter(hasNightFlying: false);
      expect(filter.matches(_record(nightLandings: 0)), isTrue);
      expect(filter.matches(_record(nightLandings: 1)), isFalse);
    });
  });

  group('LogbookFilter.matches — free text', () {
    test('matches registration', () {
      const filter = LogbookFilter(searchText: 'abcd');
      expect(filter.matches(_record()), isTrue);
    });

    test('matches remarks', () {
      const filter = LogbookFilter(searchText: 'diverted');
      expect(filter.matches(_record(remarks: 'Diverted for weather')), isTrue);
      expect(filter.matches(_record(remarks: 'Uneventful')), isFalse);
    });

    test('matches a crew name (other pilot)', () {
      const filter = LogbookFilter(searchText: 'smith');
      expect(filter.matches(_record(otherPilotName: 'J. Smith')), isTrue);
    });

    test('matches an instructor name', () {
      const filter = LogbookFilter(searchText: 'jones');
      expect(
        filter.matches(
          _record(
            capacity: _picCapacity.copyWith(
              actingAsInstructor: false,
              instructor: const InstructorPresence(
                capacity: InstructorCapacity.flightInstructor,
                influencedFlight: true,
                name: 'A. Jones',
              ),
            ),
          ),
        ),
        isTrue,
      );
    });

    test('matches a route/approach aerodrome code', () {
      const filter = LogbookFilter(searchText: 'egkb');
      expect(filter.matches(_record(route: const ['EGKA', 'EGKB'])), isTrue);
    });

    test('is case-insensitive and does not match unrelated text', () {
      const filter = LogbookFilter(searchText: 'ZZZZ');
      expect(filter.matches(_record()), isFalse);
    });

    test('a blank search text matches everything', () {
      const filter = LogbookFilter(searchText: '   ');
      expect(filter.matches(_record()), isTrue);
    });
  });

  group('LogbookFilter.matches — combined filters are ANDed', () {
    test('a flight matching every dimension but one is excluded', () {
      const filter = LogbookFilter(
        aircraftLabel: 'G-ABCD',
        ifrFlightPlanFiled: true,
        searchText: 'abcd',
      );
      // Matches aircraft and search text, but not IFR.
      expect(filter.matches(_record(ifrFlightPlanFiled: false)), isFalse);
    });
  });

  group('LogbookFilter.toFlightQuery', () {
    test('carries over the SQL-capable fields only', () {
      const filter = LogbookFilter(
        from: CalendarDate(2026, 1, 1),
        to: CalendarDate(2026, 12, 31),
        aircraftId: 'aircraft-1',
        aerodromeIdentifier: 'EGKA',
        capacity: CapacityFilter(commandAuthority: true),
        ifrFlightPlanFiled: true,
        searchText: 'x',
      );
      final query = filter.toFlightQuery();
      expect(query.from, const CalendarDate(2026, 1, 1));
      expect(query.to, const CalendarDate(2026, 12, 31));
      expect(query.aircraftId, 'aircraft-1');
      expect(query.aerodromeIdentifier, 'EGKA');
      expect(query.capacity?.commandAuthority, isTrue);
    });
  });

  group('LogbookFilter.copyWith', () {
    test('clearFrom/clearTo/etc. actually clear rather than no-op', () {
      const filter = LogbookFilter(
        from: CalendarDate(2026, 1, 1),
        aircraftId: 'a1',
        aircraftLabel: 'G-ABCD',
      );
      final cleared = filter.copyWith(clearFrom: true, clearAircraft: true);
      expect(cleared.from, isNull);
      expect(cleared.aircraftId, isNull);
      expect(cleared.aircraftLabel, isNull);
    });

    test('updates one field and leaves the rest untouched', () {
      const filter = LogbookFilter(searchText: 'abc');
      final updated = filter.copyWith(ifrFlightPlanFiled: true);
      expect(updated.searchText, 'abc');
      expect(updated.ifrFlightPlanFiled, isTrue);
    });
  });
}
