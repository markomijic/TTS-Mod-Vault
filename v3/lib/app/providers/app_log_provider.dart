import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';

/// The application-wide structured log (store + file sink).
///
/// Created in `bootstrap()` and injected through a `ProviderScope` override in
/// `main.dart`; tests override it with an `AppLog` that has no sinks.
final appLogProvider = Provider<AppLog>(
  (ref) => throw UnimplementedError('override appLogProvider in main'),
);
