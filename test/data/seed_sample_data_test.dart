import 'dart:io';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/flight_read_repository_drift.dart';
import 'package:easa_digital_log/data/repositories/held_rating_repository.dart';
import 'package:easa_digital_log/data/repositories/pilot_profile_repository.dart';
import 'package:easa_digital_log/data/seed_sample_data.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/primitives/default_primitives.dart';
import 'package:easa_digital_log/domain/projection/jurisdiction_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seeds a pilot profile, held ratings, aircraft and committed flights '
      'into an empty database', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await seedSampleDataIfEmpty(db);

    final profile = await PilotProfileRepository(db).find();
    expect(profile, isNotNull);
    expect(profile!.primaryJurisdictionId, 'eu.easa.part-fcl');

    final heldRatings = await HeldRatingRepository(db).findAll();
    expect(heldRatings.map((r) => r.jurisdictionId).toSet(), {
      'eu.easa.part-fcl',
      'us.faa.part61',
    });

    const registrations = {'G-ARRW', 'N456BD', 'G-MULTI', 'N123CJ'};

    // This test only cares that seeded flights are readable as committed,
    // not what their derived values are -- but `watchFlights` projects
    // eagerly, so a real, registered jurisdiction is still required.
    final yaml = File(
      'assets/jurisdictions/eu.easa.part-fcl.yaml',
    ).readAsStringSync();
    final projection = JurisdictionProjection(
      registry: JurisdictionRegistry([parseJurisdictionProfileYaml(yaml)]),
      primitives: defaultPrimitives,
      aerodromes: AerodromeDirectory.fromOurAirportsCsv(
        'id,ident,type,name,latitude_deg,longitude_deg,elevation_ft,'
        'continent,iso_country,iso_region,municipality,scheduled_service,'
        'gps_code,icao_code,iata_code,local_code\n',
      ),
      jurisdictionId: 'eu.easa.part-fcl',
    );

    final committed = await DriftFlightReadRepository(
      db,
    ).watchFlights(projection: projection).first;
    expect(committed, hasLength(361)); // 360 generated + 1 hand-authored
    expect(
      committed.map((p) => p.record.aircraft.registration).toSet(),
      registrations,
    );

    // Seeding is a one-time thing -- calling it again once a profile exists
    // must not duplicate anything.
    await seedSampleDataIfEmpty(db);
    final committedAgain = await DriftFlightReadRepository(
      db,
    ).watchFlights(projection: projection).first;
    expect(committedAgain, hasLength(361));
  });
}
