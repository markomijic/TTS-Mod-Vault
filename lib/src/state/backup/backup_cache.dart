import 'package:hive_ce_flutter/hive_flutter.dart' show Box, Hive;

/// Manages a dedicated Hive box that caches backup zip asset counts.
///
/// Each entry is keyed by a composite string `filepath|lastModified|fileSize`
/// and stores the `int` asset count. This avoids re-reading zip central
/// directories for files that haven't changed.
class BackupCache {
  static const String _boxName = 'BackupCache';

  late Box<int> _box;
  bool _initialized = false;

  Future<void> initialize() async {
    if (!_initialized) {
      _box = await Hive.openBox<int>(_boxName);
      _initialized = true;
    }
  }

  /// Build the composite cache key for a backup file.
  static String cacheKey(String filepath, int lastModified, int fileSize) {
    return '$filepath|$lastModified|$fileSize';
  }

  /// Look up a cached asset count. Returns null on cache miss.
  int? get(String key) {
    return _box.get(key);
  }

  /// Store a computed asset count.
  Future<void> put(String key, int assetCount) async {
    await _box.put(key, assetCount);
  }

  /// Bulk-put multiple entries at once.
  Future<void> putAll(Map<String, int> entries) async {
    await _box.putAll(entries);
  }

  /// Return all cached entries as a map.
  Map<String, int> getAll() {
    return Map<String, int>.from(_box.toMap());
  }

  /// Remove entries whose keys are not in [validKeys].
  Future<void> pruneStaleEntries(Set<String> validKeys) async {
    final keysToDelete = <String>[];
    for (final key in _box.keys) {
      if (!validKeys.contains(key as String)) {
        keysToDelete.add(key);
      }
    }
    if (keysToDelete.isNotEmpty) {
      await _box.deleteAll(keysToDelete);
    }
  }

  /// Clear the entire cache.
  Future<void> clear() async {
    await _box.clear();
  }
}
