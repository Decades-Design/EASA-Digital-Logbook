import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/pilot_profile_repository.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/pilot_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PilotProfileRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = PilotProfileRepository(db);
  });

  tearDown(() => db.close());

  test('find returns null before anything has been saved', () async {
    expect(await repository.find(), isNull);
  });

  test('round-trips through save and find', () async {
    const profile = PilotProfile(dateOfBirth: CalendarDate(1990, 6, 15));

    await repository.save(profile);

    expect(await repository.find(), profile);
  });

  test(
    'saving again replaces the single row rather than adding a second one',
    () async {
      await repository.save(
        const PilotProfile(dateOfBirth: CalendarDate(1990, 6, 15)),
      );
      await repository.save(
        const PilotProfile(dateOfBirth: CalendarDate(1985, 1, 1)),
      );

      expect(
        await repository.find(),
        const PilotProfile(dateOfBirth: CalendarDate(1985, 1, 1)),
      );
    },
  );
}
