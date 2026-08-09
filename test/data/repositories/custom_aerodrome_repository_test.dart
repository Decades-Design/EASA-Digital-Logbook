import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/custom_aerodrome_repository.dart';
import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CustomAerodromeRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = CustomAerodromeRepository(db);
  });

  tearDown(() => db.close());

  final strip = Aerodrome(
    name: "Wicker's Field",
    position: GeoCoordinate(latitude: 51.2, longitude: -0.9),
    elevationFt: 210,
  );

  test('round-trips through upsert and find', () async {
    final id = await repository.upsert(strip);
    expect(await repository.find(id), strip);
  });

  test('find returns null for an unknown id', () async {
    expect(await repository.find('nonexistent'), isNull);
  });

  test('delete removes the row', () async {
    final id = await repository.upsert(strip);
    await repository.delete(id);
    expect(await repository.find(id), isNull);
  });
}
