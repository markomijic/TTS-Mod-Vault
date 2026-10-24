import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/tables.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/audio_visibility.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/models/asset.dart';
import 'package:tts_mod_vault/domain/models/asset_summary.dart';
import 'package:tts_mod_vault/domain/models/mod.dart';
import 'package:tts_mod_vault/domain/models/mod_ref.dart';

part 'library_queries.g.dart';

/// A cached file no mod references (cleanup candidate).
typedef OrphanedFile = ({AssetType type, String fileKey, String path});

/// Read queries over `mods`, `mod_assets` and `existing_files`
/// (`docs/v3-rewrite-plan.md`, sections 4.3 and 4.4). Mods are addressed by
/// their normalised `json_path` (`ModRef.jsonPath`).
///
/// Every method is one SQL round trip. IN-lists are passed as a JSON array
/// and expanded with `json_each`, so they are not limited by SQLite's
/// bound-parameter count.
@DriftAccessor(tables: [Mods, ModAssets, ExistingFiles])
class LibraryQueries extends DatabaseAccessor<AppDatabase>
    with _$LibraryQueriesMixin {
  LibraryQueries(super.db);

  static const _audioType = AssetType.audio;

  /// The library summary for every mod of [type], sorted by save name.
  ///
  /// Each [Mod] carries its [AssetSummary] from a `mod_assets LEFT JOIN
  /// existing_files` aggregate. Audio assets are excluded from the counts of
  /// a mod when `AudioVisibility.hideAudio(ignoreAudioGlobally)` says so;
  /// `summary.hasAudio` is unaffected. `backup` is null and `backupStatus`
  /// is [BackupStatus.none]: the caller matches backups and fills them in
  /// with `copyWith`.
  Future<List<Mod>> modSummaries(
    ModType type, {
    required bool ignoreAudioGlobally,
  }) async {
    final rows = await customSelect(
      '$_summarySelect WHERE m.type = ? $_summaryGroupAndOrder',
      variables: [Variable.withInt(type.dbValue)],
      readsFrom: {mods, modAssets, existingFiles},
    ).get();
    return [for (final row in rows) _modFromRow(row, ignoreAudioGlobally)];
  }

  /// The summary of the mod at [jsonPath] (see [modSummaries]), or null if
  /// it is not indexed. Used to refresh a single card after downloads or
  /// edits.
  Future<Mod?> modSummary(
    String jsonPath, {
    required bool ignoreAudioGlobally,
  }) async {
    final row = await customSelect(
      '$_summarySelect WHERE m.json_path = ? $_summaryGroupAndOrder',
      variables: [Variable.withString(jsonPath)],
      readsFrom: {mods, modAssets, existingFiles},
    ).getSingleOrNull();
    return row == null ? null : _modFromRow(row, ignoreAudioGlobally);
  }

  /// All assets of the mod at [jsonPath] joined with their cached file,
  /// ordered by type then URL. `invalid` is set for URLs in the mod's
  /// `invalid_urls_json`.
  Future<List<Asset>> assetsForMod(
    String jsonPath, {
    bool includeAudio = true,
  }) async {
    final audioFilter = includeAudio
        ? ''
        : 'AND a.asset_type != ${_audioType.dbValue} ';
    final rows = await customSelect(
      'SELECT a.url, a.asset_type, a.file_key, e.path, m.invalid_urls_json '
      'FROM mod_assets a '
      'JOIN mods m ON m.json_path = a.mod_path '
      'LEFT JOIN existing_files e '
      'ON e.asset_type = a.asset_type AND e.file_key = a.file_key '
      'WHERE a.mod_path = ? $audioFilter'
      'ORDER BY a.asset_type, a.url',
      variables: [Variable.withString(jsonPath)],
      readsFrom: {mods, modAssets, existingFiles},
    ).get();
    if (rows.isEmpty) return const [];
    final invalid = _decodeInvalidUrls(
      rows.first.readNullable<String>('invalid_urls_json'),
    ).toSet();
    return [
      for (final row in rows)
        Asset(
          url: row.read<String>('url'),
          type: AssetType.fromDbValue(row.read<int>('asset_type')),
          fileKey: row.read<String>('file_key'),
          path: row.readNullable<String>('path'),
          invalid: invalid.contains(row.read<String>('url')),
        ),
    ];
  }

  /// Every distinct asset URL of the mods of [types] (audio included),
  /// sorted. Used to collect the domains the Settings domain check tries.
  Future<List<String>> distinctAssetUrls(Iterable<ModType> types) async {
    final values = [for (final type in types) type.dbValue];
    if (values.isEmpty) return const [];
    final rows = await customSelect(
      'SELECT DISTINCT a.url FROM mod_assets a '
      'JOIN mods m ON m.json_path = a.mod_path '
      'WHERE m.type IN (SELECT value FROM json_each(?)) '
      'ORDER BY a.url',
      variables: [Variable.withString(jsonEncode(values))],
      readsFrom: {mods, modAssets},
    ).get();
    return [for (final row in rows) row.read<String>('url')];
  }

  /// `json_path`s of the mods that reference any of [fileKeys], optionally
  /// without [excludeModPath] ("which other mods share these files").
  Future<Set<String>> modPathsReferencingFileKeys(
    Iterable<String> fileKeys, {
    String? excludeModPath,
  }) async {
    final keys = fileKeys.toList(growable: false);
    if (keys.isEmpty) return const {};
    final rows = await customSelect(
      'SELECT DISTINCT mod_path FROM mod_assets '
      'WHERE file_key IN (SELECT value FROM json_each(?)) '
      '${excludeModPath == null ? '' : 'AND mod_path != ? '}',
      variables: [
        Variable.withString(jsonEncode(keys)),
        if (excludeModPath != null) Variable.withString(excludeModPath),
      ],
      readsFrom: {modAssets},
    ).get();
    return {for (final row in rows) row.read<String>('mod_path')};
  }

  /// Cached files that no indexed mod references, ordered by type then key.
  Future<List<OrphanedFile>> orphanedExistingFiles() async {
    final rows = await customSelect(
      'SELECT e.asset_type, e.file_key, e.path FROM existing_files e '
      'WHERE NOT EXISTS (SELECT 1 FROM mod_assets a '
      'WHERE a.file_key = e.file_key AND a.asset_type = e.asset_type) '
      'ORDER BY e.asset_type, e.file_key',
      readsFrom: {modAssets, existingFiles},
    ).get();
    return [
      for (final row in rows)
        (
          type: AssetType.fromDbValue(row.read<int>('asset_type')),
          fileKey: row.read<String>('file_key'),
          path: row.read<String>('path'),
        ),
    ];
  }

  /// `file_key` to the number of distinct mods referencing it. Keys that no
  /// mod references are absent from the result.
  Future<Map<String, int>> sharedUsageCounts(Iterable<String> fileKeys) async {
    final keys = fileKeys.toList(growable: false);
    if (keys.isEmpty) return const {};
    final rows = await customSelect(
      'SELECT file_key, COUNT(DISTINCT mod_path) AS n FROM mod_assets '
      'WHERE file_key IN (SELECT value FROM json_each(?)) '
      'GROUP BY file_key',
      variables: [Variable.withString(jsonEncode(keys))],
      readsFrom: {modAssets},
    ).get();
    return {
      for (final row in rows) row.read<String>('file_key'): row.read<int>('n'),
    };
  }

  // One row per mod: the mod columns plus total/present overall, per type
  // (`total_<dbValue>` / `present_<dbValue>`), `has_audio`, and the missing
  // assets whose URL is in the stored invalid list (`missing_invalid`, and
  // `missing_invalid_audio` so hidden audio can be subtracted). The
  // json_each lookup only runs for mods that have an invalid list.
  static final String _summarySelect = () {
    final perType = [
      for (final t in AssetType.values) ...[
        'SUM(CASE WHEN a.asset_type = ${t.dbValue} THEN 1 ELSE 0 END) '
            'AS total_${t.dbValue}',
        'SUM(CASE WHEN a.asset_type = ${t.dbValue} '
            'AND e.file_key IS NOT NULL THEN 1 ELSE 0 END) '
            'AS present_${t.dbValue}',
      ],
    ].join(', ');
    return 'SELECT m.json_path, m.id, m.type, m.folder, m.save_name, '
        'm.epoch_time, m.mtime_ms, m.size_bytes, m.image_path, '
        'm.audio_visibility, m.invalid_urls_json, '
        'COUNT(a.url) AS total, COUNT(e.file_key) AS present, '
        'MAX(CASE WHEN a.asset_type = ${_audioType.dbValue} THEN 1 ELSE 0 END) '
        'AS has_audio, '
        'SUM(CASE WHEN e.file_key IS NULL AND m.invalid_urls_json IS NOT NULL '
        'AND a.url IN (SELECT value FROM json_each(m.invalid_urls_json)) '
        'THEN 1 ELSE 0 END) AS missing_invalid, '
        'SUM(CASE WHEN a.asset_type = ${_audioType.dbValue} '
        'AND e.file_key IS NULL AND m.invalid_urls_json IS NOT NULL '
        'AND a.url IN (SELECT value FROM json_each(m.invalid_urls_json)) '
        'THEN 1 ELSE 0 END) AS missing_invalid_audio, $perType '
        'FROM mods m '
        'LEFT JOIN mod_assets a ON a.mod_path = m.json_path '
        'LEFT JOIN existing_files e '
        'ON e.asset_type = a.asset_type AND e.file_key = a.file_key';
  }();

  static const _summaryGroupAndOrder =
      'GROUP BY m.json_path ORDER BY m.save_name COLLATE NOCASE, m.json_path';

  static Mod _modFromRow(QueryRow row, bool ignoreAudioGlobally) {
    final audio = AudioVisibility.fromDbValue(
      row.read<int>('audio_visibility'),
    );
    final hideAudio = audio.hideAudio(ignoreAudioGlobally: ignoreAudioGlobally);

    var total = row.read<int>('total');
    var present = row.read<int>('present');
    var missingInvalid = row.readNullable<int>('missing_invalid') ?? 0;
    if (hideAudio) {
      missingInvalid -= row.readNullable<int>('missing_invalid_audio') ?? 0;
    }
    final totalByType = <AssetType, int>{};
    final presentByType = <AssetType, int>{};
    for (final t in AssetType.values) {
      final typeTotal = row.readNullable<int>('total_${t.dbValue}') ?? 0;
      if (typeTotal == 0) continue;
      final typePresent = row.readNullable<int>('present_${t.dbValue}') ?? 0;
      if (hideAudio && t == _audioType) {
        total -= typeTotal;
        present -= typePresent;
        continue;
      }
      totalByType[t] = typeTotal;
      presentByType[t] = typePresent;
    }

    return Mod(
      ref: ModRef(
        type: ModType.fromDbValue(row.read<int>('type')),
        jsonPath: row.read<String>('json_path'),
        id: row.read<String>('id'),
      ),
      saveName: row.read<String>('save_name'),
      folder: row.read<String>('folder'),
      epochTime: row.readNullable<int>('epoch_time'),
      modified: DateTime.fromMillisecondsSinceEpoch(row.read<int>('mtime_ms')),
      sizeBytes: row.read<int>('size_bytes'),
      imagePath: row.readNullable<String>('image_path'),
      audio: audio,
      summary: AssetSummary(
        total: total,
        present: present,
        hasAudio: row.read<int>('has_audio') == 1,
        totalByType: totalByType,
        presentByType: presentByType,
        missingInvalid: missingInvalid,
      ),
      invalidUrls: _decodeInvalidUrls(
        row.readNullable<String>('invalid_urls_json'),
      ),
    );
  }

  static List<String> _decodeInvalidUrls(String? json) {
    if (json == null || json.isEmpty) return const [];
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is String) item,
    ];
  }
}
