import 'package:drift/drift.dart';

part 'fixture_database.g.dart';

@DataClassName('FixtureItemRow')
class FixtureItemsTable extends Table {
  @override
  String get tableName => 'fixture_items';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [FixtureItemsTable])
class FixtureDatabase extends _$FixtureDatabase {
  FixtureDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (Migrator m, int from, int to) async {
      if (from == 1 && to == 2) {
        await m.addColumn(fixtureItemsTable, fixtureItemsTable.notes);
      }
    },
  );
}
