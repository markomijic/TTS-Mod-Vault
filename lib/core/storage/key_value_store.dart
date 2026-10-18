/// Minimal persistent string key-value store.
///
/// The app shell persists small settings (theme, sidebar state, panel sizes)
/// through this interface. `data/db` provides the SQLite-backed implementation;
/// tests and the widget layer can use [InMemoryKeyValueStore].
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Non-persistent implementation for tests and early bootstrap.
final class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
