import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

/// Small string key-value table: settings JSON, chosen directories, theme and
/// shell state. This is the `kv` row of the schema in
/// `docs/v3-rewrite-plan.md`, section 4.3.
@DataClassName('KvEntry')
class Kv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// The app's SQLite database.
///
/// Schema version 1 holds only [Kv]. The mod index tables (`mods`,
/// `mod_assets`, `existing_files`, `backups`) arrive in Phase 1 as schema
/// version 2; see the TODO in [migration].
@DriftDatabase(tables: [Kv])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens (creating it if needed) the on-disk database at [file]. All SQL
  /// runs on drift's background isolate so the UI thread never blocks on IO.
  factory AppDatabase.open(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));

  static const int latestSchemaVersion = 1;

  @override
  int get schemaVersion => latestSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // TODO(phase-1): schema version 2 adds `mods`, `mod_assets` (with the
      // `file_key` and `asset_type` indexes), `existing_files` and `backups`.
      // Migrate step-wise (`for (var v = from; v < to; v++)`) and keep every
      // step forever; never edit a shipped step.
    },
    beforeOpen: (details) async {
      // Needed for ON DELETE CASCADE on `mod_assets` from Phase 1 on. SQLite
      // disables foreign keys per connection by default.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
