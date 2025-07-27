import 'package:flutter/material.dart' show BuildContext, WidgetsBinding;
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart' show backupProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

void useBackupSnackbar(BuildContext context, WidgetRef ref) {
  final message = ref.watch(backupProvider).message;

  useEffect(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (message.isNotEmpty) {
        showSnackBar(context, message);
        ref.read(backupProvider.notifier).resetMessage();
      }
    });

    return null;
  }, [message]);
}
