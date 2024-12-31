import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/mods/components/assets_list.dart';
import 'package:tts_mod_vault/src/mods/components/mods_grid.dart';
import 'package:tts_mod_vault/src/mods/components/toolbar.dart';

class ModsPage extends ConsumerWidget {
  const ModsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
