import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/held_rating_repository.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/held_rating.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late HeldRatingRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = HeldRatingRepository(db);
  });

  tearDown(() => db.close());

  const sep = HeldRating(
    kind: HeldRatingKind.classRating,
    designator: 'SEP(land)',
    jurisdictionId: 'eu.easa.part-fcl',
    issueDate: CalendarDate(2024, 1, 1),
    expiryDate: CalendarDate(2026, 1, 1),
  );

  test(
    'round-trips through upsert and find, including a null expiryDate',
    () async {
      const faaType = HeldRating(
        kind: HeldRatingKind.typeRating,
        designator: 'A320',
        jurisdictionId: 'us.faa.part61',
        issueDate: CalendarDate(2024, 1, 1),
      );

      final sepId = await repository.upsert(sep);
      final faaTypeId = await repository.upsert(faaType);

      expect(await repository.find(sepId), sep);
      expect(await repository.find(faaTypeId), faaType);
    },
  );

  test('round-trips a language proficiency level', () async {
    const english = HeldRating(
      kind: HeldRatingKind.languageProficiency,
      designator: 'english',
      jurisdictionId: 'eu.easa.part-fcl',
      issueDate: CalendarDate(2024, 1, 1),
      languageProficiencyLevel: 6,
    );

    final id = await repository.upsert(english);

    expect(await repository.find(id), english);
  });

  test('upsert with an existing id replaces the row', () async {
    final id = await repository.upsert(sep);
    final revalidated = sep.copyWith(
      issueDate: const CalendarDate(2026, 1, 1),
      expiryDate: const CalendarDate(2028, 1, 1),
    );

    await repository.upsert(revalidated, id: id);

    expect(await repository.find(id), revalidated);
  });

  test('findAll returns every held rating', () async {
    const faaType = HeldRating(
      kind: HeldRatingKind.typeRating,
      designator: 'A320',
      jurisdictionId: 'us.faa.part61',
      issueDate: CalendarDate(2024, 1, 1),
    );
    await repository.upsert(sep);
    await repository.upsert(faaType);

    expect(await repository.findAll(), unorderedEquals([sep, faaType]));
  });

  test('delete removes the rating', () async {
    final id = await repository.upsert(sep);
    await repository.delete(id);

    expect(await repository.find(id), isNull);
  });
}
