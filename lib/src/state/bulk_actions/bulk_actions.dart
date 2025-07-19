import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkActionsState;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show downloadProvider, modsProvider;

class BulkActionsNotifier extends StateNotifier<BulkActionsState> {
  final Ref ref;

  BulkActionsNotifier(this.ref) : super(const BulkActionsState());

  Future<void> downloadAllMods(List<Mod> mods) async {
    state =
        state.copyWith(downloadingAllMods: true, totalModNumber: mods.length);

    for (final mod in mods) {
      if (state.cancelledDownloadingAllMods) {
        continue;
      }

      debugPrint('Downloading: ${mod.saveName}');

      state = state.copyWith(currentModNumber: mods.indexOf(mod) + 1);

      final completeMod =
          await ref.read(modsProvider.notifier).getCardMod(mod.jsonFileName);

      ref.read(modsProvider.notifier).setSelectedMod(completeMod);
      await ref.read(downloadProvider.notifier).downloadAllFiles(completeMod);
      await ref.read(modsProvider.notifier).updateSelectedMod(completeMod);
    }

    state = BulkActionsState(
      downloadingAllMods: false,
      cancelledDownloadingAllMods: false,
      currentModNumber: 0,
      totalModNumber: 0,
    );
  }

  Future<void> cancelAllDownloads() async {
    state = state.copyWith(cancelledDownloadingAllMods: true);

    ref.read(downloadProvider.notifier).cancelAllDownloads();
  }
}
