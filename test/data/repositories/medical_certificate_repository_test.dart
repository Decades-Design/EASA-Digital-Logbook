import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/medical_certificate_repository.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/medical_certificate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late MedicalCertificateRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = MedicalCertificateRepository(db);
  });

  tearDown(() => db.close());

  const class2 = MedicalCertificate(
    certificateClass: MedicalCertificateClass.easaClass2,
    jurisdictionId: 'eu.easa.part-fcl',
    issueDate: CalendarDate(2024, 1, 15),
  );

  test('round-trips through upsert and find', () async {
    final id = await repository.upsert(class2);

    expect(await repository.find(id), class2);
  });

  test('upsert with an existing id replaces the row', () async {
    final id = await repository.upsert(class2);
    final renewed = class2.copyWith(issueDate: const CalendarDate(2029, 1, 20));

    await repository.upsert(renewed, id: id);

    expect(await repository.find(id), renewed);
  });

  test(
    'findAll returns every held certificate, e.g. an EASA and an FAA one held together',
    () async {
      const faaThird = MedicalCertificate(
        certificateClass: MedicalCertificateClass.faaThirdClass,
        jurisdictionId: 'us.faa.part61',
        issueDate: CalendarDate(2024, 3, 1),
      );
      await repository.upsert(class2);
      await repository.upsert(faaThird);

      final all = await repository.findAll();

      expect(all, unorderedEquals([class2, faaThird]));
    },
  );

  test('delete removes the certificate', () async {
    final id = await repository.upsert(class2);
    await repository.delete(id);

    expect(await repository.find(id), isNull);
  });
}
