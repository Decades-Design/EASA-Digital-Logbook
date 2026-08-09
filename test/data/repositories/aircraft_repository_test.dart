import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AircraftRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = AircraftRepository(db);
  });

  tearDown(() => db.close());

  const c152 = Aircraft(
    registration: 'G-ABCD',
    manufacturer: 'Cessna',
    model: '152',
    category: AircraftCategory.aeroplane,
    engineType: EngineType.piston,
    engineCount: 1,
    operatingSurface: OperatingSurface.land,
    requiresMultiCrew: false,
    requiredQualifications: {
      'eu.easa.part-fcl': {},
      'us.faa.part61': {AircraftQualification.faaHighPerformance},
    },
  );

  test('round-trips through upsert and find, including the absent-vs-empty '
      'jurisdiction distinction', () async {
    final id = await repository.upsert(c152);
    final found = await repository.find(id);

    expect(found, c152);
    expect(
      found!.requiredQualifications.containsKey('eu.easa.part-fcl'),
      isTrue,
      reason: 'present-but-empty must survive the round trip',
    );
    expect(found.requiredQualifications['eu.easa.part-fcl'], isEmpty);
    expect(
      found.requiredQualifications.containsKey('uk.caa.part-fcl'),
      isFalse,
      reason: 'never-configured must stay absent, not an empty set',
    );
  });

  test(
    'upsert with an existing id replaces the row and its qualifications',
    () async {
      final id = await repository.upsert(c152);
      final updated = c152.copyWith(
        requiredQualifications: {
          'eu.easa.part-fcl': {AircraftQualification.easaTailwheel},
        },
      );

      await repository.upsert(updated, id: id);
      final found = await repository.find(id);

      expect(found!.requiredQualifications, updated.requiredQualifications);
    },
  );

  test('delete removes the aircraft and its qualification rows', () async {
    final id = await repository.upsert(c152);
    await repository.delete(id);

    expect(await repository.find(id), isNull);
  });
}
