import '../domain/model/calendar_date.dart';
import '../domain/model/utc_instant.dart';
import '../domain/pilot_record/held_rating.dart';
import '../ui/currency/sample_currency_data.dart' show samplePilotProfile;
import '../ui/totals/sample_totals_data.dart' show sampleTotalsFlights;
import 'database.dart';
import 'repositories/aircraft_repository.dart';
import 'repositories/flight_repository_drift.dart';
import 'repositories/held_rating_repository.dart';
import 'repositories/pilot_profile_repository.dart';

/// First-run seeding (#56) — a fresh on-device database has no pilot
/// profile, no aircraft, no flights, which is the *correct* end state (a
/// real install shouldn't carry someone else's flights), but leaves every
/// screen looking broken rather than empty until real data-entry screens
/// (#59 edit, #61 aircraft management) exist to put anything there. Until
/// then, seeding [samplePilotProfile] and [sampleTotalsFlights] — the same
/// fixtures the screens rendered before this file existed — keeps today's
/// appearance while everything underneath becomes real and persistent.
/// Delete this file (and its call in `main()`) once there's a real way to
/// enter a pilot profile, licences and flights by hand.
///
/// Runs at most once: [seedSampleDataIfEmpty] is a no-op the moment a pilot
/// profile has ever been saved, so a real profile the pilot enters later
/// permanently turns seeding off rather than fighting their data.
///
/// **Seeded flights are committed, not left as drafts.** They represent
/// three years of backfilled history, not something mid-entry — treating
/// them as already-committed lets them flow through
/// `FlightReadRepository.watchFlights`'s committed-only aggregate path the
/// same way real historical flights eventually will, rather than leaving
/// Totals/Currency looking empty until a real export happens. A pilot's own
/// future entries still follow the ordinary draft-until-exported rule
/// (CLAUDE.md rule 4) untouched.
Future<void> seedSampleDataIfEmpty(AppDatabase db) async {
  final pilotProfileRepository = PilotProfileRepository(db);
  if (await pilotProfileRepository.find() != null) {
    return;
  }

  await pilotProfileRepository.save(samplePilotProfile);

  final heldRatingRepository = HeldRatingRepository(db);
  final issueDate = CalendarDate(
    samplePilotProfile.dateOfBirth.year + 18,
    samplePilotProfile.dateOfBirth.month,
    samplePilotProfile.dateOfBirth.day,
  );
  for (final rating in [
    HeldRating(
      kind: HeldRatingKind.classRating,
      designator: 'SEP(land)',
      jurisdictionId: 'eu.easa.part-fcl',
      issueDate: issueDate,
    ),
    HeldRating(
      kind: HeldRatingKind.classRating,
      designator: 'ASEL',
      jurisdictionId: 'us.faa.part61',
      issueDate: issueDate,
    ),
  ]) {
    await heldRatingRepository.upsert(rating);
  }

  final aircraftRepository = AircraftRepository(db);
  final flightRepository = DriftFlightRepository(db);
  final today = CalendarDate.fromUtcInstant(
    UtcInstant.fromDateTime(DateTime.now().toUtc()),
  );

  final aircraftIds = <String, String>{};
  for (final record in sampleTotalsFlights(today)) {
    final registration = record.aircraft.registration;
    aircraftIds[registration] ??= await aircraftRepository.upsert(
      record.aircraft,
    );

    final flightId = await flightRepository.createDraft(
      record.flight,
      aircraftId: aircraftIds[registration]!,
    );
    await flightRepository.commit(flightId);
  }
}
