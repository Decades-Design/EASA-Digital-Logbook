import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/countersignature.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/flight_times.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/projection/derived_quantity.dart';
import 'package:easa_digital_log/domain/projection/projection.dart';
import 'package:easa_digital_log/domain/projection/projection_result.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:easa_digital_log/domain/totals/totals_summary.dart';
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

const _testAircraft = Aircraft(
  registration: 'G-TEST',
  manufacturer: 'Cessna',
  model: '152',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

Flight _flight({
  required CalendarDate date,
  Duration blockDuration = const Duration(hours: 1),
  PilotCapacity capacity = _picCapacity,
  CircuitCounts? takeoffs,
  CircuitCounts? landings,
  List<Approach> approaches = const [],
  List<String> route = const ['EGXX'],
}) {
  final offBlocks = UtcInstant.utc(date.year, date.month, date.day, 10);
  return Flight(
    aircraftRegistration: 'G-TEST',
    route: route,
    prePlannedNavigation: false,
    offBlocks: offBlocks,
    onBlocks: offBlocks.add(blockDuration),
    capacity: capacity,
    carryingPassengers: false,
    takeoffs: takeoffs ?? const CircuitCounts(dayFullStop: 1),
    landings: landings ?? const CircuitCounts(dayFullStop: 1),
    ifrFlightPlanFiled: false,
    actualInstrumentTime: FlightDuration.zero,
    simulatedInstrumentTime: FlightDuration.zero,
    approaches: approaches,
    holdingProceduresCount: 0,
    trackingPerformed: false,
    remarks: '',
  );
}

FlightRecord _record(
  String id,
  Flight flight, {
  Aircraft aircraft = _testAircraft,
}) => FlightRecord(id: id, flight: flight, aircraft: aircraft);

/// Returns `crossCountry` equal to block time for a flight, so
/// [crossCountryOfWhichPic] tests can assert exact totals without a real
/// jurisdiction profile.
class _FakeProjection implements Projection {
  const _FakeProjection();

  @override
  ProjectionResult project(Flight flight, Aircraft aircraft) =>
      ProjectionResult(
        jurisdictionId: 'test',
        quantities: {
          'crossCountry': DerivedQuantity.creditable(flight.blockTime, 'test'),
        },
      );

  @override
  ProjectionResult projectAggregate(Iterable<(Flight, Aircraft)> flights) =>
      throw UnimplementedError();
}

void main() {
  group('bucketTotals', () {
    const asOf = CalendarDate(2026, 8, 21);

    test('year: sums each flight into its calendar year, current flagged', () {
      final flights = [
        _record('1', _flight(date: const CalendarDate(2026, 3, 1))),
        _record('2', _flight(date: const CalendarDate(2026, 6, 1))),
        _record('3', _flight(date: const CalendarDate(2025, 1, 1))),
        _record(
          '4',
          _flight(date: const CalendarDate(2019, 1, 1)),
        ), // the oldest of 8 years
        _record(
          '5',
          _flight(date: const CalendarDate(2018, 1, 1)),
        ), // outside the 8-year window
      ];

      final buckets = bucketTotals(flights, Granularity.year, asOf);

      expect(buckets, hasLength(8));
      expect(buckets.last.label, '2026');
      expect(buckets.last.value, const FlightDuration(120));
      expect(buckets.last.isCurrent, isTrue);
      expect(buckets[buckets.length - 2].label, '2025');
      expect(buckets[buckets.length - 2].value, const FlightDuration(60));
      // 2026 back through 2019 is exactly 8 years -- 2019 is the oldest
      // bucket shown; 2018 (one year further) never appears at all.
      expect(buckets.first.label, '2019');
      expect(buckets.first.value, const FlightDuration(60));
    });

    test('month: crosses a year boundary correctly', () {
      final flights = [
        _record(
          '1',
          _flight(date: const CalendarDate(2026, 8, 15)),
        ), // current month
        _record(
          '2',
          _flight(date: const CalendarDate(2026, 1, 15)),
        ), // 7 months back
        _record(
          '3',
          _flight(date: const CalendarDate(2025, 12, 15)),
        ), // 8 months back -> excluded
      ];

      final buckets = bucketTotals(flights, Granularity.month, asOf, count: 8);

      expect(buckets.last.label, 'Aug');
      expect(buckets.last.value, const FlightDuration(60));
      expect(buckets.first.label, 'Jan');
      expect(buckets.first.value, const FlightDuration(60));
    });

    test('day: a flight exactly 7 days back lands in the oldest bucket', () {
      final flights = [
        _record('1', _flight(date: asOf)),
        _record('2', _flight(date: asOf.addDays(-7))),
        _record(
          '3',
          _flight(date: asOf.addDays(-8)),
        ), // outside the 8-day window
      ];

      final buckets = bucketTotals(flights, Granularity.day, asOf, count: 8);

      expect(buckets.last.value, const FlightDuration(60));
      expect(buckets.last.isCurrent, isTrue);
      expect(buckets.first.value, const FlightDuration(60));
    });

    test('week: an 8th rolling week is 7*7=49 to 55 days back', () {
      final flights = [
        _record(
          '1',
          _flight(date: asOf.addDays(-49)),
        ), // first day of the oldest window
        _record('2', _flight(date: asOf.addDays(-56))), // one day outside it
      ];

      final buckets = bucketTotals(flights, Granularity.week, asOf, count: 8);

      expect(buckets.first.value, const FlightDuration(60));
    });

    test('an empty flight set produces all-zero buckets', () {
      final buckets = bucketTotals(const [], Granularity.year, asOf);
      expect(buckets.every((b) => b.value == FlightDuration.zero), isTrue);
    });
  });

  group('sumBlockTimeInRange', () {
    test('includes both range endpoints', () {
      final flights = [
        _record('1', _flight(date: const CalendarDate(2026, 1, 1))),
        _record('2', _flight(date: const CalendarDate(2026, 6, 15))),
        _record('3', _flight(date: const CalendarDate(2026, 12, 31))),
        _record('4', _flight(date: const CalendarDate(2027, 1, 1))),
      ];

      final total = sumBlockTimeInRange(
        flights,
        const CalendarDate(2026, 1, 1),
        const CalendarDate(2026, 12, 31),
      );

      expect(total, const FlightDuration(180));
    });
  });

  group('aircraftClassLabel', () {
    test('single-engine piston aeroplane is SEP', () {
      expect(aircraftClassLabel(_testAircraft), 'SEP (land)');
    });

    test('twin-engine piston aeroplane is MEP', () {
      const twin = Aircraft(
        registration: 'G-TWIN',
        manufacturer: 'Piper',
        model: 'PA-34',
        category: AircraftCategory.aeroplane,
        engineType: EngineType.piston,
        engineCount: 2,
        operatingSurface: OperatingSurface.land,
        requiresMultiCrew: false,
      );
      expect(aircraftClassLabel(twin), 'MEP (land)');
    });

    test('a touring motor glider is TMG regardless of engine count', () {
      const tmg = Aircraft(
        registration: 'G-TMG',
        manufacturer: 'Diamond',
        model: 'HK36',
        category: AircraftCategory.touringMotorGlider,
        engineType: EngineType.piston,
        engineCount: 1,
        operatingSurface: OperatingSurface.land,
        requiresMultiCrew: false,
      );
      expect(aircraftClassLabel(tmg), 'TMG');
    });

    test('a turbofan jet falls back to its own type label', () {
      const jet = Aircraft(
        registration: 'G-JET',
        manufacturer: 'Cessna',
        model: 'Citation CJ2',
        icaoTypeDesignator: 'C25A',
        category: AircraftCategory.aeroplane,
        engineType: EngineType.turbofan,
        engineCount: 2,
        operatingSurface: OperatingSurface.land,
        requiresMultiCrew: true,
      );
      expect(aircraftClassLabel(jet), 'C25A');
      expect(aircraftClassLabel(jet), aircraftTypeLabel(jet));
    });
  });

  group('groupByAircraft', () {
    const jet = Aircraft(
      registration: 'G-JET',
      manufacturer: 'Cessna',
      model: 'Citation CJ2',
      icaoTypeDesignator: 'C25A',
      category: AircraftCategory.aeroplane,
      engineType: EngineType.turbofan,
      engineCount: 2,
      operatingSurface: OperatingSurface.land,
      requiresMultiCrew: true,
    );
    const twin = Aircraft(
      registration: 'G-TWIN',
      manufacturer: 'Piper',
      model: 'PA-34',
      category: AircraftCategory.aeroplane,
      engineType: EngineType.piston,
      engineCount: 2,
      operatingSurface: OperatingSurface.land,
      requiresMultiCrew: false,
    );

    test(
      'groups single-pilot before multi-pilot, with class and type subtotals',
      () {
        final flights = [
          _record(
            '1',
            _flight(
              date: const CalendarDate(2026, 1, 1),
              blockDuration: const Duration(hours: 2),
            ),
          ), // single-pilot SEP, G-TEST
          _record(
            '2',
            _flight(
              date: const CalendarDate(2026, 1, 2),
              blockDuration: const Duration(hours: 1),
              capacity: _picCapacity.copyWith(multiPilotOperation: false),
            ),
            aircraft: twin,
          ), // single-pilot MEP
          _record(
            '3',
            _flight(
              date: const CalendarDate(2026, 1, 3),
              blockDuration: const Duration(hours: 3),
              capacity: _picCapacity.copyWith(multiPilotOperation: true),
            ),
            aircraft: jet,
          ), // multi-pilot jet
        ];

        final groups = groupByAircraft(flights);

        expect(groups, hasLength(2));
        expect(groups[0].multiPilot, isFalse);
        expect(groups[0].total, const FlightDuration(180));
        // SEP (2h) sorts before MEP (1h).
        expect(groups[0].classes[0].classLabel, 'SEP (land)');
        expect(groups[0].classes[1].classLabel, 'MEP (land)');

        expect(groups[1].multiPilot, isTrue);
        expect(groups[1].total, const FlightDuration(180));
        expect(groups[1].classes.single.isSingleType, isTrue);
      },
    );

    test('an empty flight set produces no groups', () {
      expect(groupByAircraft(const []), isEmpty);
    });
  });

  test('distinctAircraftFlown counts unique registrations', () {
    final flights = [
      _record('1', _flight(date: const CalendarDate(2026, 1, 1))),
      _record('2', _flight(date: const CalendarDate(2026, 1, 2))),
    ];
    expect(distinctAircraftFlown(flights), 1);
  });

  test('soloTime sums only sole-occupant flights', () {
    final flights = [
      _record(
        '1',
        _flight(date: const CalendarDate(2026, 1, 1), capacity: _picCapacity),
      ),
      _record(
        '2',
        _flight(
          date: const CalendarDate(2026, 1, 2),
          capacity: _picCapacity.copyWith(soleOccupant: false),
        ),
      ),
    ];
    expect(soloTime(flights), const FlightDuration(60));
  });

  group('awaitingCountersignatureTime', () {
    test('sums only flights with a pending countersignature', () {
      final flights = [
        _record(
          '1',
          _flight(
            date: const CalendarDate(2026, 1, 1),
            capacity: _picCapacity.copyWith(
              countersignature: const Countersignature(
                status: CountersignatureStatus.pending,
              ),
            ),
          ),
        ),
        _record(
          '2',
          _flight(
            date: const CalendarDate(2026, 1, 2),
            capacity: _picCapacity.copyWith(
              countersignature: const Countersignature(
                status: CountersignatureStatus.signed,
              ),
            ),
          ),
        ),
        _record(
          '3',
          _flight(
            date: const CalendarDate(2026, 1, 3),
            capacity: _picCapacity.copyWith(
              countersignature: const Countersignature(
                status: CountersignatureStatus.refused,
              ),
            ),
          ),
        ),
        _record('4', _flight(date: const CalendarDate(2026, 1, 4))), // null
      ];

      expect(awaitingCountersignatureTime(flights), const FlightDuration(60));
    });
  });

  test(
    'crossCountryOfWhichPic sums only flights flown with command authority',
    () {
      final flights = [
        _record(
          '1',
          _flight(
            date: const CalendarDate(2026, 1, 1),
            blockDuration: const Duration(hours: 2),
            capacity: _picCapacity,
          ),
        ),
        _record(
          '2',
          _flight(
            date: const CalendarDate(2026, 1, 2),
            blockDuration: const Duration(hours: 1),
            capacity: _picCapacity.copyWith(commandAuthority: false),
          ),
        ),
      ];

      expect(
        crossCountryOfWhichPic(flights, const _FakeProjection()),
        const FlightDuration(120),
      );
    },
  );

  group('longestFlight', () {
    test('returns the longest block time', () {
      final flights = [
        _record(
          '1',
          _flight(
            date: const CalendarDate(2026, 1, 1),
            blockDuration: const Duration(hours: 1),
          ),
        ),
        _record(
          '2',
          _flight(
            date: const CalendarDate(2026, 1, 2),
            blockDuration: const Duration(hours: 4),
          ),
        ),
      ];
      expect(longestFlight(flights), const FlightDuration(240));
    });

    test('is zero for an empty flight set', () {
      expect(longestFlight(const []), FlightDuration.zero);
    });
  });

  test('opsCounts sums takeoffs, landings and approaches across flights', () {
    final flights = [
      _record(
        '1',
        _flight(
          date: const CalendarDate(2026, 1, 1),
          takeoffs: const CircuitCounts(dayFullStop: 2, nightTouchAndGo: 1),
          landings: const CircuitCounts(dayFullStop: 2, nightTouchAndGo: 1),
          approaches: const [
            Approach(
              type: ApproachType.ils,
              aerodromeIcao: 'EGXX',
              runway: '09',
              count: 2,
            ),
          ],
        ),
      ),
      _record(
        '2',
        _flight(
          date: const CalendarDate(2026, 1, 2),
          takeoffs: const CircuitCounts(dayFullStop: 1),
          landings: const CircuitCounts(dayFullStop: 1),
        ),
      ),
    ];

    final counts = opsCounts(flights);

    expect(counts.dayFullStopTakeoffs, 3);
    expect(counts.dayFullStopLandings, 3);
    expect(counts.nightTouchAndGoTakeoffs, 1);
    expect(counts.nightTouchAndGoLandings, 1);
    expect(counts.instrumentApproaches, 2);
  });

  group('aerodromesVisited', () {
    test(
      'counts unique ICAO codes, resolving countries where the directory knows them',
      () {
        final directory = AerodromeDirectory([
          Aerodrome(
            icaoCode: 'EGKA',
            name: 'Shoreham',
            position: GeoCoordinate(latitude: 50.8, longitude: -0.3),
            isoCountry: 'GB',
          ),
          Aerodrome(
            icaoCode: 'LFAT',
            name: 'Le Touquet',
            position: GeoCoordinate(latitude: 50.5, longitude: 1.6),
            isoCountry: 'FR',
          ),
        ]);
        final flights = [
          _record(
            '1',
            _flight(
              date: const CalendarDate(2026, 1, 1),
              route: const ['EGKA', 'LFAT', 'EGKA'],
            ),
          ),
          _record(
            '2',
            _flight(
              date: const CalendarDate(2026, 1, 2),
              route: const ['EGKA', 'PRIVATE-STRIP'],
            ),
          ),
        ];

        final result = aerodromesVisited(flights, directory);

        expect(result.aerodromes, 3); // EGKA, LFAT, PRIVATE-STRIP
        expect(
          result.countries,
          2,
        ); // GB, FR -- the private strip resolves to neither
      },
    );

    test('an empty flight set visits nothing', () {
      final result = aerodromesVisited(const [], AerodromeDirectory(const []));
      expect(result.aerodromes, 0);
      expect(result.countries, 0);
    });
  });
}
