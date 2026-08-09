import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/held_aircraft_qualification_repository.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/held_aircraft_qualification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late HeldAircraftQualificationRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = HeldAircraftQualificationRepository(db);
  });

  tearDown(() => db.close());

  const heldVp = HeldAircraftQualification(
    qualification: AircraftQualification.easaVariablePitchPropeller,
    jurisdictionId: 'eu.easa.part-fcl',
    dateGranted: CalendarDate(2020, 1, 1),
    signatoryName: 'A. Instructor',
    signatoryCredentialNumber: 'FI-123',
  );

  test('round-trips through upsert and find', () async {
    final id = await repository.upsert(heldVp);

    expect(await repository.find(id), heldVp);
  });

  test('findAll returns every held qualification', () async {
    const heldTailwheel = HeldAircraftQualification(
      qualification: AircraftQualification.faaTailwheel,
      jurisdictionId: 'us.faa.part61',
      dateGranted: CalendarDate(2021, 6, 1),
    );
    await repository.upsert(heldVp);
    await repository.upsert(heldTailwheel);

    expect(
      await repository.findAll(),
      unorderedEquals([heldVp, heldTailwheel]),
    );
  });

  test('delete removes the qualification', () async {
    final id = await repository.upsert(heldVp);
    await repository.delete(id);

    expect(await repository.find(id), isNull);
  });
}
