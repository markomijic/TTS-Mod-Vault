import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/mods/components/assets_list.dart';
import 'package:tts_mod_vault/src/mods/components/mods_grid.dart';
import 'package:tts_mod_vault/src/mods/components/toolbar.dart';
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart';
import 'package:tts_mod_vault/src/state/provider.dart';
import 'package:tts_mod_vault/src/utils.dart';

class ModsPage extends HookConsumerWidget {
  const ModsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cleanUpStatus = ref.watch(cleanupProvider).status;

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (cleanUpStatus == CleanUpStatusEnum.completed) {
          showSnackBar(context, 'Cleanup finished!');
          ref.read(cleanupProvider.notifier).resetState();
        } else if (cleanUpStatus == CleanUpStatusEnum.error) {
          showSnackBar(
            context,
            'Cleanup error: ${ref.read(cleanupProvider).errorMessage}',
          );
          ref.read(cleanupProvider.notifier).resetState();
        }
      });

      return null;
    }, [cleanUpStatus]);

    return SafeArea(
      child: Scaffold(
        body: Column(
          children: [
            Container(
              height: 50,
              padding: const EdgeInsets.only(left: 12.0, bottom: 4),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Toolbar(),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: ModsGrid(),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: AssetsList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
