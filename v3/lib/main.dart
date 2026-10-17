import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/app.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/bootstrap/bootstrap.dart';

Future<void> main() async {
  final result = await bootstrap();
  runApp(
    ProviderScope(
      // Riverpod 3 retries failed providers by default; a failed file scan or
      // download must surface as AsyncError, not re-run in a loop (plan 4.5).
      retry: (retryCount, error) => null,
      overrides: [
        keyValueStoreProvider.overrideWithValue(result.kv),
        appLogProvider.overrideWithValue(result.log),
      ],
      child: const App(),
    ),
  );
}
