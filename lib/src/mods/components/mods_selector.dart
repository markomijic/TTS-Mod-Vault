import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        searchQueryProvider,
        selectedModProvider,
        selectedModTypeProvider,
        settingsProvider;

class ModsSelector extends ConsumerWidget {
  const ModsSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedModType = ref.watch(selectedModTypeProvider);
    final showSavedObjects = ref.watch(settingsProvider).showSavedObjects;

    return SegmentedButton<ModTypeEnum>(
      showSelectedIcon: false,
      segments: <ButtonSegment<ModTypeEnum>>[
        ButtonSegment(value: ModTypeEnum.mod, label: Text('Mods')),
        ButtonSegment(value: ModTypeEnum.save, label: Text('Saves')),
        if (showSavedObjects)
          ButtonSegment(
              value: ModTypeEnum.savedObject, label: Text('Saved Objects')),
      ],
      selected: {selectedModType},
      onSelectionChanged: (newSelection) {
        ref.read(selectedModTypeProvider.notifier).state = newSelection.first;
        ref.read(selectedModProvider.notifier).state = null;
        ref.read(searchQueryProvider.notifier).state = '';
      },
    );
  }
}
