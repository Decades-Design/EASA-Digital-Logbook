import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens an in-memory database with all eight tables', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.allTables, hasLength(8));
  });
}
