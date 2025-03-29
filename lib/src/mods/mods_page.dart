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
    final cleanUpNotifier = ref.watch(cleanupProvider.notifier);
    final cleanUpState = ref.watch(cleanupProvider);
    final mods = ref.watch(modsProvider);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (cleanUpState.status == CleanUpStatusEnum.completed) {
          showSnackBar(context, 'Cleanup finished!');
          cleanUpNotifier.resetState();
        } else if (cleanUpState.status == CleanUpStatusEnum.error) {
          showSnackBar(
            context,
            'Cleanup error: ${ref.read(cleanupProvider).errorMessage}',
          );
          cleanUpNotifier.resetState();
        }
      });

      return null;
    }, [cleanUpState]);

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
              child: mods.when(
                data: (data) {
                  return Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: ModsGrid(mods: data.mods),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: AssetsList(),
                      ),
                    ],
                  );
                },
                // TODO test and improve error handling
                error: (e, st) => Center(
                  child: Text('Error: $e'),
                ),
                loading: () => Center(
                  child: Text(
                    "Loading...",
                    style: TextStyle(fontSize: 32),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
