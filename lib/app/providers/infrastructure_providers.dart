import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/core/workers/worker_pool.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';

/// The open SQLite database. Created in `bootstrap()` and injected through a
/// `ProviderScope` override in `main.dart`; tests override it with
/// `AppDatabase(NativeDatabase.memory())`.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('override appDatabaseProvider in main'),
);

/// The persistent key-value store (settings, folders, theme, view options).
///
/// Created in `bootstrap()` on top of the database and injected through a
/// `ProviderScope` override in `main.dart`; tests override it with
/// `InMemoryKeyValueStore`. Reading it without an override throws.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError('override keyValueStoreProvider in main'),
);

/// Shared isolate pool for file scanning and parsing. Created lazily on first
/// use and disposed with the container.
final workerPoolProvider = Provider<WorkerPool>((ref) {
  final pool = WorkerPool(debugName: 'vault-workers');
  // Disposal kills idle isolates immediately; the returned future is not
  // awaited because onDispose callbacks are synchronous.
  ref.onDispose(pool.dispose);
  return pool;
});
