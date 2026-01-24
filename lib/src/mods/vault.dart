import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/backups/backups_page.dart' show BackupsPage;
import 'package:tts_mod_vault/src/mods/components/components.dart' show Sidebar;
import 'package:tts_mod_vault/src/mods/mods_page.dart' show ModsPage;
import 'package:tts_mod_vault/src/state/provider.dart'
    show selectedPageProvider, AppPage;
import 'package:tts_mod_vault/src/mods/hooks/hooks.dart'
    show useCleanupSnackbar, useBackupSnackbar;

class Vault extends HookConsumerWidget {
  const Vault({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPage = ref.watch(selectedPageProvider);
    final sidebarWidth = useState<double>(40);
    useCleanupSnackbar(context, ref);
    useBackupSnackbar(context, ref);

    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            Row(
              children: [
                SizedBox(width: sidebarWidth.value),
                Expanded(
                    child: selectedPage == AppPage.mods
                        ? const ModsPage()
                        : const BackupsPage()),
              ],
            ),
            Sidebar(width: sidebarWidth.value),
          ],
        ),
      ),
    );
  }
}
