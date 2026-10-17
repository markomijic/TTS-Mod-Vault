import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:tts_mod_vault/data/db/converters.dart';
import 'package:tts_mod_vault/data/db/daos/backups_dao.dart';
import 'package:tts_mod_vault/data/db/daos/existing_files_dao.dart';
import 'package:tts_mod_vault/data/db/daos/library_queries.dart';
import 'package:tts_mod_vault/data/db/daos/mods_dao.dart';
import 'package:tts_mod_vault/data/db/tables.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/audio_visibility.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';

part 'app_database.g.dart';

/// The app's SQLite database (schema in `docs/v3-rewrite-plan.md`, 4.3).
///
/// Schema version 1 holds every table: `kv`, `mods`, `mod_assets` (with the
/// `file_key` and `asset_type` indexes), `existing_files` and `backups`.
/// The app has not shipped yet, so there are no upgrade steps; once it has,
/// migrate step-wise (`for (var v = from; v < to; v++)`) and never edit a
/// shipped step.
@DriftDatabase(
  tables: [Kv, Mods, ModAssets, ExistingFiles, Backups],
  daos: [ModsDao, ExistingFilesDao, BackupsDao, LibraryQueries],
)
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
    beforeOpen: (details) async {
      // SQLite disables foreign keys per connection by default; needed for
      // ON DELETE CASCADE on `mod_assets`.
      await customStatement('PRAGMA foreign_keys = ON');
      // WAL lets reads proceed while the refresh pipeline writes, and NORMAL
      // sync is durable enough for a rebuildable index. Both are no-ops on
      // an in-memory database.
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = NORMAL');
    },
  );
}
