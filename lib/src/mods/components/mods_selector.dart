import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef, AsyncValueX;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        modsProvider,
        searchQueryProvider,
        selectedModProvider,
        selectedModTypeProvider,
        settingsProvider;

class ModsSelector extends HookConsumerWidget {
  const ModsSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modsState = ref.watch(modsProvider);
    final selectedModType = ref.watch(selectedModTypeProvider);
    final showSavedObjects = ref.watch(settingsProvider).showSavedObjects;

    final modsMessage = useMemoized(() {
      return modsState.whenOrNull(
        data: (data) {
          if (data.mods.isEmpty) return null;
          return '${data.mods.length} mods';
        },
      );
    }, [modsState.value?.mods]);

    final savesMessage = useMemoized(() {
      return modsState.whenOrNull(
        data: (data) {
          if (data.saves.isEmpty) return null;
          return '${data.saves.length} saves';
        },
      );
    }, [modsState.value?.saves]);

    final savedObjectsMessage = useMemoized(() {
      return modsState.whenOrNull(
        data: (data) {
          if (data.savedObjects.isEmpty) return null;
          return '${data.savedObjects.length} saved objects';
        },
      );
    }, [modsState.value?.savedObjects]);

    final tooltipMessage = useMemoized(() {
      final messages = <String>[];

      if (modsMessage != null) messages.add(modsMessage);
      if (savesMessage != null) messages.add(savesMessage);
      if (savedObjectsMessage != null) messages.add(savedObjectsMessage);

      return messages.isEmpty ? null : messages.join(', ');
    }, [modsMessage, savesMessage, savedObjectsMessage]);

    return CustomTooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 300),
      child: SegmentedButton<ModTypeEnum>(
        showSelectedIcon: false,
        segments: [
          const ButtonSegment(value: ModTypeEnum.mod, label: Text('Mods')),
          const ButtonSegment(value: ModTypeEnum.save, label: Text('Saves')),
          if (showSavedObjects)
            const ButtonSegment(
              value: ModTypeEnum.savedObject,
              label: Text('Saved Objects'),
            ),
        ],
        selected: {selectedModType},
        onSelectionChanged: (newSelection) {
          if (ref.read(actionInProgressProvider)) {
            return;
          }

          ref.read(selectedModTypeProvider.notifier).state = newSelection.first;
          ref.read(selectedModProvider.notifier).state = null;
          ref.read(searchQueryProvider.notifier).state = '';
        },
      ),
    );
  }
}
