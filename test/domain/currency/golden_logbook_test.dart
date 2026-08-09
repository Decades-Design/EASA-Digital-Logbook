import 'dart:io';

import 'package:easa_digital_log/domain/currency/currency_rule_evaluator.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_loader.dart';
import 'package:easa_digital_log/domain/currency/evaluation_subject.dart';
import 'package:easa_digital_log/domain/currency/held_record.dart';
import 'package:easa_digital_log/domain/currency/rule_result.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/pilot_record/held_qualification_records.dart';
import 'package:easa_digital_log/domain/pilot_record/held_rating.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// #53 -- a golden logbook exercising every implemented currency rule against
// hand-verified expected outcomes, in both satisfied and unsatisfied states.
//
// **Methodology, per #53's own instruction not to derive expectations from
// the implementation.** The logbook is built from a small number of
// documented, constant-cadence phases (a pattern flight every N days,
// stated below) rather than a few hundred individually hand-typed flights.
// Every expectation in this file is checked by window arithmetic against
// the regulation text -- "the last qualifying flight was 104 days before
// the evaluation date, which is more than the 90-day window" -- never by
// running the evaluator and copying its answer down. The cadence is what
// makes that arithmetic tractable at this volume: knowing flights occur
// every 4 days makes "is there one in the last 90 days" a one-line
// computation instead of a scan.
//
// Phases (all flights G-CSEP, a Cessna 172, single-engine piston landplane,
// no type rating -- so `aircraft_match` conditions always pass trivially
// against [_referenceAircraft], the same aircraft):
//   A  2023-01-01 .. 2023-06-29, every 4 days, day full-stop landings.
//   gap 2023-06-30 .. 2023-10-20, no flying -- 113 days, well past every
//      90-day window this app has.
//   C  2023-10-21 .. 2024-08-31, every 4 days, day full-stop landings.
//   D  2024-09-01 .. 2024-12-10, every 4 days, day TOUCH-AND-GO landings --
//      deliberately not full-stop, to separate FAA Sec.61.57(a) (any
//      landing type) from Sec.61.57(a)(2) (full-stop only) at the same
//      evaluation date.
//   E  2024-12-11 .. 2024-12-29, every 4 days, day full-stop landings.
// Plus three landmark flights: a night circuit (2023-02-01), an instrument
// flight (2023-01-10), and a dual training flight with an instructor
// aboard (2024-06-01) -- see their own comments below.
void main() {
  final loader = _loadAllRules();
  const evaluator = CurrencyRuleEvaluator();

  final subject = EvaluationSubject(
    flights: _flightRecords,
    referenceAircraft: _referenceAircraft,
    heldRecords: _heldRecords,
  );

  RuleResult evaluate(String ruleId, CalendarDate asOf) {
    final rule = loader.resolve(ruleId, asOf);
    return evaluator.evaluateRequirement(rule.requirement, subject, asOf);
  }

  group('every rule file loads and resolves', () {
    test('all 14 currency rule files are present', () {
      expect(_ruleIds, hasLength(14));
      for (final id in _ruleIds) {
        expect(
          () => loader.resolve(id, CalendarDate(2024, 1, 1)),
          returnsNormally,
          reason: 'rule "$id" failed to resolve',
        );
      }
    });
  });

  group('FAA Sec.61.57(a) takeoff/landing currency', () {
    const ruleId = 'us.faa.61_57_a.takeoff_landing_currency';

    test('satisfied during active flying (phase A)', () {
      final result = evaluate(ruleId, CalendarDate(2023, 2, 20));
      expect(result.satisfied, isTrue);
    });

    test('unsatisfied 108 days after the last flight before the gap', () {
      // Last phase-A flight: 2023-06-29. 2023-10-15 is 108 days later.
      final result = evaluate(ruleId, CalendarDate(2023, 10, 15));
      expect(result.satisfied, isFalse);
      expect(result.components[0].explanation, contains('0 of 3'));
    });

    test('touch-and-goes count too (phase D)', () {
      // Phase D (2024-09-01..2024-12-10) is touch-and-go only; this rule
      // does not filter by landing type, unlike Sec.61.57(a)(2).
      final result = evaluate(ruleId, CalendarDate(2024, 12, 5));
      expect(result.satisfied, isTrue);
    });
  });

  group('FAA Sec.61.57(a)(2) tailwheel (full-stop only) currency', () {
    const ruleId = 'us.faa.61_57_a2.tailwheel_takeoff_landing_currency';

    test('satisfied when the recent landings are full-stop (phase A)', () {
      final result = evaluate(ruleId, CalendarDate(2023, 2, 20));
      expect(result.satisfied, isTrue);
    });

    test(
      'unsatisfied when the preceding 90 days are touch-and-go only (phase D)',
      () {
        final result = evaluate(ruleId, CalendarDate(2024, 12, 5));
        expect(result.satisfied, isFalse);
        expect(result.explanation, contains('0 of 2 requirements met'));
      },
    );
  });

  group('FAA Sec.61.57(b) night takeoff/landing currency', () {
    const ruleId = 'us.faa.61_57_b.night_takeoff_landing_currency';

    test('satisfied 19 days after the night circuit (2023-02-01)', () {
      final result = evaluate(ruleId, CalendarDate(2023, 2, 20));
      expect(result.satisfied, isTrue);
    });

    test(
      'unsatisfied 104 days after the night circuit, though day currency holds',
      () {
        final night = evaluate(ruleId, CalendarDate(2023, 5, 15));
        final day = evaluate(
          'us.faa.61_57_a.takeoff_landing_currency',
          CalendarDate(2023, 5, 15),
        );
        expect(night.satisfied, isFalse);
        expect(day.satisfied, isTrue);
      },
    );
  });

  group(
    'FAA Sec.61.57(c) instrument currency (6-month) and grace (12-month)',
    () {
      const currentId = 'us.faa.61_57_c.instrument_currency';
      const graceId = 'us.faa.61_57_c.instrument_currency_grace_period';

      test(
        'both satisfied shortly after the instrument flight (2023-01-10)',
        () {
          expect(
            evaluate(currentId, CalendarDate(2023, 3, 1)).satisfied,
            isTrue,
          );
          expect(evaluate(graceId, CalendarDate(2023, 3, 1)).satisfied, isTrue);
        },
      );

      test('6-month lapsed but 12-month grace still holds at 203 days out', () {
        // 2023-01-10 -> 2023-08-01 is 203 days: outside 6 calendar months
        // (window start 2023-02-01) but inside 12 (window start 2022-08-01).
        expect(
          evaluate(currentId, CalendarDate(2023, 8, 1)).satisfied,
          isFalse,
        );
        expect(evaluate(graceId, CalendarDate(2023, 8, 1)).satisfied, isTrue);
      });

      test(
        'both lapsed a year past the instrument flight: an IPC is required',
        () {
          // 12-month window at 2024-02-01 starts 2023-02-01, after the
          // instrument flight (2023-01-10) -- excluded from both windows.
          expect(
            evaluate(currentId, CalendarDate(2024, 2, 1)).satisfied,
            isFalse,
          );
          expect(
            evaluate(graceId, CalendarDate(2024, 2, 1)).satisfied,
            isFalse,
          );
        },
      );
    },
  );

  group('FAA Sec.61.56 flight review', () {
    const ruleId = 'us.faa.61_56.flight_review';

    test('satisfied within 24 months of the review (2023-01-05)', () {
      final result = evaluate(ruleId, CalendarDate(2023, 6, 1));
      expect(result.satisfied, isTrue);
    });

    test('unsatisfied more than 24 calendar months later', () {
      final result = evaluate(ruleId, CalendarDate(2025, 6, 1));
      expect(result.satisfied, isFalse);
    });
  });

  group('FAA Sec.61.23(d) medical validity, all three classes', () {
    for (final entry in [
      (
        'us.faa.61_23.first_class_medical_validity',
        CalendarDate(2023, 6, 1),
        CalendarDate(2024, 6, 1),
      ),
      (
        'us.faa.61_23.second_class_medical_validity',
        CalendarDate(2023, 6, 1),
        CalendarDate(2024, 6, 1),
      ),
      (
        'us.faa.61_23.third_class_medical_validity',
        CalendarDate(2023, 1, 1),
        CalendarDate(2025, 2, 1),
      ),
    ]) {
      final (ruleId, satisfiedAsOf, unsatisfiedAsOf) = entry;
      test('$ruleId: satisfied within validity, unsatisfied after', () {
        expect(evaluate(ruleId, satisfiedAsOf).satisfied, isTrue);
        expect(evaluate(ruleId, unsatisfiedAsOf).satisfied, isFalse);
      });
    }
  });

  group('EASA FCL.060(b)(1) passenger recency', () {
    const ruleId = 'easa.fcl060.b1_passenger_recency';

    test('satisfied during active flying (phase A)', () {
      expect(evaluate(ruleId, CalendarDate(2023, 2, 20)).satisfied, isTrue);
    });

    test('unsatisfied 108 days after the last flight before the gap', () {
      final result = evaluate(ruleId, CalendarDate(2023, 10, 15));
      expect(result.satisfied, isFalse);
      expect(result.explanation, contains('0 of 3'));
    });
  });

  group('EASA FCL.060(b)(3) night passenger recency', () {
    const ruleId = 'eu.easa.fcl060.b3_night_passenger_recency';

    test('satisfied 19 days after the night circuit', () {
      expect(evaluate(ruleId, CalendarDate(2023, 2, 20)).satisfied, isTrue);
    });

    test(
      'unsatisfied 104 days after the night circuit even though day '
      'passenger recency (FCL.060(b)(1)) still holds -- no IR held either',
      () {
        final result = evaluate(ruleId, CalendarDate(2023, 5, 15));
        expect(result.satisfied, isFalse);
        // b(1)'s own 3-landing leg still passes; only the night-or-IR leg
        // fails -- CLAUDE.md rule 5's "never render a jurisdiction-dependent
        // number without its qualifier" shows up here as two components,
        // not one flat boolean.
        expect(result.components, hasLength(2));
        expect(result.components[0].satisfied, isTrue);
        expect(result.components[1].satisfied, isFalse);
      },
    );
  });

  group('EASA FCL.740.A(b)(1) SEP(land) revalidation', () {
    const ruleId = 'eu.easa.fcl740a.sep_land_revalidation';

    test('satisfied: a year of ordinary flying plus the June dual flight '
        'covers all five FCL.740.A(b)(1)(i) legs before the rating expires '
        '2025-01-01', () {
      final rule = loader.resolve(ruleId, CalendarDate(2024, 12, 15));
      final result = evaluator.evaluateRequirement(
        rule.requirement,
        EvaluationSubject(
          flights: _flightRecords,
          referenceAircraft: _referenceAircraft,
          heldRecords: [_currentSepRatingHeldRecord],
        ),
        CalendarDate(2024, 12, 15),
      );
      expect(result.satisfied, isTrue);
    });

    test('unsatisfied: a rating that expired 2022-12-31, before this '
        'logbook has any flights in its preceding-12-months window', () {
      final rule = loader.resolve(ruleId, CalendarDate(2023, 1, 1));
      final result = evaluator.evaluateRequirement(
        rule.requirement,
        EvaluationSubject(
          flights: _flightRecords,
          referenceAircraft: _referenceAircraft,
          heldRecords: [_oldSepRatingHeldRecord],
        ),
        CalendarDate(2023, 1, 1),
      );
      expect(result.satisfied, isFalse);
      expect(result.explanation, contains('None of 2 alternatives'));
    });
  });

  group('EASA MED.A.045 medical validity, both classes', () {
    for (final entry in [
      (
        'eu.easa.med_a045.class1_validity',
        CalendarDate(2023, 4, 1),
        CalendarDate(2023, 8, 1),
      ),
      (
        'eu.easa.med_a045.class2_validity',
        CalendarDate(2024, 1, 1),
        CalendarDate(2025, 2, 1),
      ),
    ]) {
      final (ruleId, satisfiedAsOf, unsatisfiedAsOf) = entry;
      test('$ruleId: satisfied within validity, unsatisfied after', () {
        expect(evaluate(ruleId, satisfiedAsOf).satisfied, isTrue);
        expect(evaluate(ruleId, unsatisfiedAsOf).satisfied, isFalse);
      });
    }
  });
}

const List<String> _ruleIds = [
  'us.faa.61_57_a.takeoff_landing_currency',
  'us.faa.61_57_a2.tailwheel_takeoff_landing_currency',
  'us.faa.61_57_b.night_takeoff_landing_currency',
  'us.faa.61_57_c.instrument_currency',
  'us.faa.61_57_c.instrument_currency_grace_period',
  'us.faa.61_56.flight_review',
  'us.faa.61_23.first_class_medical_validity',
  'us.faa.61_23.second_class_medical_validity',
  'us.faa.61_23.third_class_medical_validity',
  'easa.fcl060.b1_passenger_recency',
  'eu.easa.fcl060.b3_night_passenger_recency',
  'eu.easa.fcl740a.sep_land_revalidation',
  'eu.easa.med_a045.class1_validity',
  'eu.easa.med_a045.class2_validity',
];

CurrencyRuleLoader _loadAllRules() {
  final ruleFiles =
      Directory('assets/rules')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return CurrencyRuleLoader.fromYaml([
    for (final file in ruleFiles) file.readAsStringSync(),
  ]);
}

const _referenceAircraft = Aircraft(
  registration: 'G-CSEP',
  manufacturer: 'Cessna',
  model: '172',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

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

const _dualWithInstructorCapacity = PilotCapacity(
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
    influencedFlight: false,
    name: 'A. Instructor',
  ),
);

Flight _patternFlight(
  CalendarDate date, {
  required CircuitCounts counts,
  Duration blockTime = const Duration(minutes: 30),
  PilotCapacity capacity = _picCapacity,
  List<Approach> approaches = const [],
  int holdingProceduresCount = 0,
  bool trackingPerformed = false,
  Set<AlternativeComplianceEvent> alternativeComplianceEvents = const {},
}) {
  final offBlocks = UtcInstant.utc(date.year, date.month, date.day, 10);
  return Flight(
    aircraftRegistration: _referenceAircraft.registration,
    route: const ['EGXX'],
    prePlannedNavigation: false,
    offBlocks: offBlocks,
    onBlocks: offBlocks.add(blockTime),
    capacity: capacity,
    carryingPassengers: false,
    takeoffs: counts,
    landings: counts,
    ifrFlightPlanFiled: false,
    actualInstrumentTime: FlightDuration.zero,
    simulatedInstrumentTime: FlightDuration.zero,
    approaches: approaches,
    holdingProceduresCount: holdingProceduresCount,
    trackingPerformed: trackingPerformed,
    alternativeComplianceEvents: alternativeComplianceEvents,
    remarks: '',
  );
}

/// A run of pattern flights every [stepDays] days from [start] to [end]
/// inclusive, all with [counts]. The regular cadence is what makes "is
/// there a qualifying flight in the last N days" a one-line arithmetic
/// check rather than a per-flight lookup -- see the file dartdoc.
List<Flight> _cadence({
  required CalendarDate start,
  required CalendarDate end,
  required CircuitCounts counts,
  int stepDays = 4,
}) {
  final flights = <Flight>[];
  var date = start;
  while (date <= end) {
    flights.add(_patternFlight(date, counts: counts));
    date = date.addDays(stepDays);
  }
  return flights;
}

const _fullStop3 = CircuitCounts(dayFullStop: 3);
const _touchAndGo3 = CircuitCounts(dayTouchAndGo: 3);

final List<Flight> _allFlights = [
  // Phase A: 2023-01-01 .. 2023-06-29, day full-stop, every 4 days.
  ..._cadence(
    start: CalendarDate(2023, 1, 1),
    end: CalendarDate(2023, 6, 29),
    counts: _fullStop3,
  ),
  // gap: 2023-06-30 .. 2023-10-20, no flying (113 days).
  // Phase C: 2023-10-21 .. 2024-08-31, day full-stop, every 4 days.
  ..._cadence(
    start: CalendarDate(2023, 10, 21),
    end: CalendarDate(2024, 8, 31),
    counts: _fullStop3,
  ),
  // Phase D: 2024-09-01 .. 2024-12-10, day TOUCH-AND-GO, every 4 days --
  // separates Sec.61.57(a) from Sec.61.57(a)(2).
  ..._cadence(
    start: CalendarDate(2024, 9, 1),
    end: CalendarDate(2024, 12, 10),
    counts: _touchAndGo3,
  ),
  // Phase E: 2024-12-11 .. 2024-12-29, day full-stop, every 4 days.
  ..._cadence(
    start: CalendarDate(2024, 12, 11),
    end: CalendarDate(2024, 12, 29),
    counts: _fullStop3,
  ),

  // Landmark: a night circuit, the sole source of night landings in this
  // logbook -- FAA Sec.61.57(b) and EASA FCL.060(b)(3) both key off it.
  _patternFlight(
    CalendarDate(2023, 2, 1),
    counts: const CircuitCounts(nightFullStop: 3),
  ),

  // Landmark: an instrument flight -- six ILS approaches to one procedure,
  // one holding pattern, tracking performed. The sole source of instrument
  // currency in this logbook -- Sec.61.57(c) and its grace-period sibling
  // key off it.
  _patternFlight(
    CalendarDate(2023, 1, 10),
    counts: const CircuitCounts(),
    approaches: const [
      Approach(
        type: ApproachType.ils,
        aerodromeIcao: 'EGXX',
        runway: '27',
        count: 6,
      ),
    ],
    holdingProceduresCount: 1,
    trackingPerformed: true,
  ),

  // Landmark: a training flight with an instructor aboard, satisfying
  // FCL.740.A(b)(1)(i)'s "1 hour with an instructor" leg. Also carries the
  // faaFlightReview event on the *cadence* flight of 2023-01-05, below.
  _patternFlight(
    CalendarDate(2024, 6, 1),
    counts: const CircuitCounts(dayFullStop: 1),
    blockTime: const Duration(hours: 1, minutes: 12),
    capacity: _dualWithInstructorCapacity,
  ),

  // Landmark: the FAA Sec.61.56 flight review, recorded on its own date
  // rather than folded into a cadence flight so it reads clearly here.
  _patternFlight(
    CalendarDate(2023, 1, 5),
    counts: _fullStop3,
    alternativeComplianceEvents: const {
      AlternativeComplianceEvent.faaFlightReview,
    },
  ),
];

final List<FlightRecord> _flightRecords = [
  for (var i = 0; i < _allFlights.length; i++)
    FlightRecord(
      id: 'golden-$i',
      flight: _allFlights[i],
      aircraft: _referenceAircraft,
    ),
];

final HeldRecord _currentSepRatingHeldRecord = heldRatingHeldRecord(
  HeldRating(
    kind: HeldRatingKind.classRating,
    designator: 'SEP(land)',
    jurisdictionId: 'eu.easa.part-fcl',
    issueDate: CalendarDate(2023, 1, 1),
    expiryDate: CalendarDate(2025, 1, 1),
  ),
);

final HeldRecord _oldSepRatingHeldRecord = heldRatingHeldRecord(
  HeldRating(
    kind: HeldRatingKind.classRating,
    designator: 'SEP(land)',
    jurisdictionId: 'eu.easa.part-fcl',
    issueDate: CalendarDate(2021, 1, 1),
    expiryDate: CalendarDate(2022, 12, 31),
  ),
);

// Medical held records are constructed directly with an explicit validity
// window rather than run through medicalCertificateHeldRecord's age-band
// logic -- that logic already has its own dedicated tests
// (medical_certificate_validity_test.dart). This fixture only needs *some*
// valid/invalid window to exercise the currency rule that consumes it.
final List<HeldRecord> _heldRecords = [
  _currentSepRatingHeldRecord,
  const HeldRecord(
    kind: 'medical_certificate.easaClass1',
    validFrom: CalendarDate(2023, 1, 1),
    validUntil: CalendarDate(2023, 7, 1),
  ),
  const HeldRecord(
    kind: 'medical_certificate.easaClass2',
    validFrom: CalendarDate(2023, 1, 1),
    validUntil: CalendarDate(2025, 1, 1),
  ),
  const HeldRecord(
    kind: 'medical_certificate.faaFirstClass',
    validFrom: CalendarDate(2023, 1, 1),
    validUntil: CalendarDate(2024, 1, 1),
  ),
  const HeldRecord(
    kind: 'medical_certificate.faaSecondClass',
    validFrom: CalendarDate(2023, 1, 1),
    validUntil: CalendarDate(2024, 1, 1),
  ),
  const HeldRecord(
    kind: 'medical_certificate.faaThirdClass',
    validFrom: CalendarDate(2020, 1, 1),
    validUntil: CalendarDate(2025, 1, 1),
  ),
];
