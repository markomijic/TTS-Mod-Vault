import 'package:flutter/material.dart' show BuildContext, WidgetsBinding;
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart'
    show CleanUpStatusEnum;
import 'package:tts_mod_vault/src/state/provider.dart' show cleanupProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

void useCleanupSnackbar(BuildContext context, WidgetRef ref) {
  final cleanUpState = ref.watch(cleanupProvider);
  final cleanUpNotifier = ref.read(cleanupProvider.notifier);

  useEffect(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (cleanUpState.status) {
        case CleanUpStatusEnum.idle:
        case CleanUpStatusEnum.awaitingConfirmation:
          break;

        case CleanUpStatusEnum.deleting:
          showSnackBar(context, 'Deleting files...');
          break;

        case CleanUpStatusEnum.scanning:
          showSnackBar(context, 'Scanning for files...');
          break;

        case CleanUpStatusEnum.completed:
          showSnackBar(context, 'Cleanup finished!');
          cleanUpNotifier.resetState();
          break;

        case CleanUpStatusEnum.error:
          showSnackBar(
            context,
            'Cleanup error: ${cleanUpState.errorMessage}',
          );
          cleanUpNotifier.resetState();
          break;
      }
    });

    return null;
  }, [cleanUpState.status]);
}
