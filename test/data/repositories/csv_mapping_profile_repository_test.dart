import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/csv_mapping_profile_repository.dart';
import 'package:easa_digital_log/io/generic_csv/generic_csv_field.dart';
import 'package:easa_digital_log/io/generic_csv/generic_csv_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

const _mapping = GenericCsvMapping(
  name: 'My spreadsheet',
  columnByField: {
    GenericCsvField.date: 'Date',
    GenericCsvField.offBlocksTime: 'Off',
    GenericCsvField.onBlocksTime: 'On',
    GenericCsvField.aircraftRegistration: 'Reg',
    GenericCsvField.departure: 'From',
    GenericCsvField.destination: 'To',
  },
  dateFormat: CsvDateFormat.dmy,
  durationFormat: CsvDurationFormat.hoursMinutes,
);

void main() {
  late AppDatabase db;
  late CsvMappingProfileRepository profiles;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    profiles = CsvMappingProfileRepository(db);
  });

  tearDown(() => db.close());

  test('round-trips a mapping through upsert and find', () async {
    final id = await profiles.upsert(_mapping);

    final found = await profiles.find(id);

    expect(found?.name, 'My spreadsheet');
    expect(found?.columnByField, _mapping.columnByField);
    expect(found?.dateFormat, CsvDateFormat.dmy);
    expect(found?.durationFormat, CsvDurationFormat.hoursMinutes);
  });

  test('find returns null for an unknown id', () async {
    expect(await profiles.find('nonexistent'), isNull);
  });

  test('upsert with an existing id replaces the row rather than adding a '
      'second one', () async {
    final id = await profiles.upsert(_mapping);

    await profiles.upsert(
      const GenericCsvMapping(
        name: 'Renamed',
        columnByField: {GenericCsvField.date: 'Flight Date'},
        dateFormat: CsvDateFormat.isoYmd,
        durationFormat: CsvDurationFormat.decimalHours,
      ),
      id: id,
    );

    final all = await profiles.listAll();
    expect(all, hasLength(1));
    expect(all.single.mapping.name, 'Renamed');
  });

  test('listAll returns every saved mapping', () async {
    await profiles.upsert(_mapping);
    await profiles.upsert(
      const GenericCsvMapping(
        name: 'A second spreadsheet',
        columnByField: {},
        dateFormat: CsvDateFormat.isoYmd,
        durationFormat: CsvDurationFormat.decimalHours,
      ),
    );

    final all = await profiles.listAll();
    expect(
      all.map((r) => r.mapping.name),
      containsAll(['My spreadsheet', 'A second spreadsheet']),
    );
  });

  test('delete removes the mapping', () async {
    final id = await profiles.upsert(_mapping);

    await profiles.delete(id);

    expect(await profiles.find(id), isNull);
  });
}
