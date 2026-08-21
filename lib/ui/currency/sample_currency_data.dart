import '../../domain/currency/currency_dashboard.dart';
import '../../domain/currency/evaluation_subject.dart';
import '../../domain/currency/held_record.dart';
import '../../domain/model/aircraft.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/flight.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/pilot_capacity.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/pilot_record/held_qualification_records.dart';
import '../../domain/pilot_record/held_rating.dart';
import '../../domain/pilot_record/medical_certificate.dart';
import '../../domain/pilot_record/medical_certificate_validity.dart';
import '../../domain/pilot_record/pilot_profile.dart';
import '../../domain/repository/flight_read_repository.dart';

/// Sample data for the Currency screen, standing in for real repository
/// wiring — the same convention `sample_logbook_data.dart` and
/// `sample_fleet_data.dart` already established, pending #56's live data
/// wiring. Every date below is computed relative to [CalendarDate today]
/// rather than hard-coded, so the deliberately-crafted spread of currency
/// states (satisfied, due soon, expired, in grace) stays correct no matter
/// when the app happens to run.
///
/// **Which rules apply to which licence is fixture-picked, not resolved
/// from held ratings.** No domain concept of "which currency rules apply to
/// what a pilot holds" exists yet (a pilot without a tailwheel endorsement,
/// for instance, should never see tailwheel currency at all) — this hand
/// picks a subset consistent with the sample pilot's own held ratings,
/// standing in for a real resolver that's Settings-phase work.
const samplePilotProfile = PilotProfile(
  dateOfBirth: CalendarDate(1985, 6, 15),
  primaryJurisdictionId: 'eu.easa.part-fcl',
);

const sampleAircraft = Aircraft(
  registration: 'G-ABCD',
  manufacturer: 'Cessna',
  model: '172S',
  icaoTypeDesignator: 'C172',
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

/// EASA and FAA licence descriptors — see this file's own dartdoc for why
/// [CurrencyLicenceSpec.privilegeSummary] and `ruleIds` are hand-written
/// rather than derived.
const sampleCurrencyLicences = [
  CurrencyLicenceSpec(
    jurisdictionId: 'eu.easa.part-fcl',
    label: 'EASA',
    isPrimary: true,
    privilegeSummary: 'PPL(A) · SEP (land)',
    ruleIds: [
      'easa.fcl060.b1_passenger_recency',
      'eu.easa.fcl740a.sep_land_revalidation',
      'eu.easa.med_a045.class2_validity',
    ],
  ),
  CurrencyLicenceSpec(
    jurisdictionId: 'us.faa.part61',
    label: 'FAA',
    isPrimary: false,
    privilegeSummary: 'PPL ASEL',
    ruleIds: [
      'us.faa.61_57_a.takeoff_landing_currency',
      'us.faa.61_57_c.instrument_currency',
      'us.faa.61_57_c.instrument_currency_grace_period',
      'us.faa.61_56.flight_review',
      'us.faa.61_23.third_class_medical_validity',
    ],
  ),
];

Flight _sampleFlight({
  required CalendarDate date,
  CircuitCounts? landings,
  CircuitCounts? takeoffs,
  List<Approach> approaches = const [],
  int holdingProceduresCount = 0,
  bool trackingPerformed = false,
  Set<AlternativeComplianceEvent> alternativeComplianceEvents = const {},
}) {
  final offBlocks = UtcInstant.utc(date.year, date.month, date.day, 10);
  return Flight(
    aircraftRegistration: sampleAircraft.registration,
    route: const ['EGKA', 'EGKA'],
    prePlannedNavigation: false,
    offBlocks: offBlocks,
    onBlocks: offBlocks.add(const Duration(hours: 1)),
    capacity: _picCapacity,
    carryingPassengers: false,
    takeoffs: takeoffs ?? const CircuitCounts(),
    landings: landings ?? const CircuitCounts(),
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

/// This pilot's flights, deliberately chosen to exercise a spread of
/// currency states rather than an all-green dashboard:
/// - 10 days ago: 12 landings + 4 takeoffs, deliberately overshooting both
///   rules that read it, at two different margins: EASA passenger recency
///   (landings only, needs 3) shows the big "12 / 3" overshoot; FAA
///   take-off/landing currency (an `allOf` of both counts, represented by
///   whichever leaf has the *tighter* ratio) is instead capped by its
///   takeoffs leaf at "4 / 3" — the mockup's own "4 of 3" example — since
///   4/3 (1.33×) is a tighter margin than landings' 12/3 (4×). One flight,
///   two different overshoot magnitudes, each genuinely computed rather
///   than hand-set per row.
/// - 60 days ago: an EASA class-rating proficiency check — satisfies SEP
///   (land) revalidation via `FCL.740.A(b)(1)(ii)`'s alternative branch,
///   comfortably (`RuleWindow.expiryFrom` projects a fresh ~12-month
///   currency window forward from *this occurrence's own date*, not from
///   the rating's stated expiry — see [sampleHeldRatings]'s own note).
/// - ~8 months ago: 6 approaches, a holding procedure and course tracking —
///   inside FAA instrument currency's 12-month grace window but outside its
///   ordinary 6-month one, so the two rows land in different states.
/// - exactly 730 days ago (the earliest date the rule's own 24-month
///   window still counts): an FAA flight review — lands its `expiryFrom`
///   projection inside the hero row's 30-day window, the screen's "DUE
///   SOON" example (see the flight's own comment below for the exact
///   mechanics).
List<FlightRecord> sampleCurrencyFlights(CalendarDate today) => [
  FlightRecord(
    id: 'sample-currency-1',
    flight: _sampleFlight(
      date: today.addDays(-10),
      takeoffs: const CircuitCounts(dayFullStop: 4),
      landings: const CircuitCounts(dayFullStop: 12),
    ),
    aircraft: sampleAircraft,
  ),
  FlightRecord(
    id: 'sample-currency-2',
    flight: _sampleFlight(
      date: today.addDays(-60),
      alternativeComplianceEvents: const {
        AlternativeComplianceEvent.easaClassRatingProficiencyCheck,
      },
    ),
    aircraft: sampleAircraft,
  ),
  FlightRecord(
    id: 'sample-currency-3',
    flight: _sampleFlight(
      date: today.addDays(-240),
      approaches: const [
        Approach(
          type: ApproachType.ils,
          aerodromeIcao: 'EGKA',
          runway: '02',
          count: 6,
        ),
      ],
      holdingProceduresCount: 1,
      trackingPerformed: true,
    ),
    aircraft: sampleAircraft,
  ),
  FlightRecord(
    id: 'sample-currency-4',
    // `RuleWindow.expiryFrom` projects forward from the *occurrence's own*
    // date by the window's month count (24), not from today — a flight
    // review flown exactly 730 days ago (the earliest date that still
    // counts inside the rule's own 24-calendar-month window) keeps this
    // rule current only through the last day of the same calendar month
    // two years on, which lands inside the hero row's 30-day window
    // relative to `today`. This is the screen's "DUE SOON" example, next
    // to instrument currency's "EXPIRED" one.
    flight: _sampleFlight(
      date: today.addDays(-730),
      alternativeComplianceEvents: const {
        AlternativeComplianceEvent.faaFlightReview,
      },
    ),
    aircraft: sampleAircraft,
  ),
];

/// The SEP(land) class rating — stated to expire 25 days from [today],
/// though the revalidation rule itself doesn't land near that date; see the
/// proficiency-check flight's own comment above for why.
List<HeldRating> sampleHeldRatings(CalendarDate today) => [
  HeldRating(
    kind: HeldRatingKind.classRating,
    designator: 'SEP(land)',
    jurisdictionId: 'eu.easa.part-fcl',
    issueDate: today.addDays(-700),
    expiryDate: today.addDays(25),
  ),
];

List<MedicalCertificate> sampleMedicalCertificates(CalendarDate today) => [
  MedicalCertificate(
    certificateClass: MedicalCertificateClass.easaClass2,
    jurisdictionId: 'eu.easa.part-fcl',
    issueDate: today.addDays(-300),
  ),
  MedicalCertificate(
    certificateClass: MedicalCertificateClass.faaThirdClass,
    jurisdictionId: 'us.faa.part61',
    issueDate: today.addDays(-200),
  ),
];

/// One [EvaluationSubject], shared by both licences: a flight's raw facts
/// don't change depending on which jurisdiction is asking about them, and
/// [sampleAircraft] is the one aircraft both licences' rules reference —
/// see `currency_dashboard.dart`'s own note on why a dashboard-wide view
/// evaluates against a single representative aircraft rather than one per
/// rule.
EvaluationSubject sampleEvaluationSubject(CalendarDate today) {
  final heldRecords = <HeldRecord>[
    for (final rating in sampleHeldRatings(today)) heldRatingHeldRecord(rating),
    for (final certificate in sampleMedicalCertificates(today))
      medicalCertificateHeldRecord(certificate, samplePilotProfile.dateOfBirth),
  ];
  return EvaluationSubject(
    flights: sampleCurrencyFlights(today),
    referenceAircraft: sampleAircraft,
    heldRecords: heldRecords,
  );
}
