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

    final segments = useMemoized(() {
      return [
        ModTypeEnum.mod,
        ModTypeEnum.save,
        if (showSavedObjects) ModTypeEnum.savedObject,
      ];
    }, [showSavedObjects]);

    final menuController = useMemoized(() => MenuController());

    String getTypeLabel(ModTypeEnum type) {
      switch (type) {
        case ModTypeEnum.mod:
          return 'Mods';
        case ModTypeEnum.save:
          return 'Saves';
        case ModTypeEnum.savedObject:
          return 'Saved Objects';
      }
    }

    return CustomTooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        constraints: BoxConstraints(minWidth: 118),
        child: MenuAnchor(
          controller: menuController,
          menuChildren: segments.map((type) {
            final isSelected = type == selectedModType;
            return MenuItemButton(
              closeOnActivate: true,
              style: MenuItemButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                iconColor: Colors.black,
              ),
              child: Row(
                spacing: 8,
                children: [
                  Icon(isSelected ? Icons.check : null),
                  Expanded(
                    child: Text(
                      getTypeLabel(type),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              onPressed: () {
                if (ref.read(actionInProgressProvider)) {
                  return;
                }
                ref.read(selectedModTypeProvider.notifier).state = type;
                ref.read(selectedModProvider.notifier).state = null;
                ref.read(searchQueryProvider.notifier).state = '';
              },
            );
          }).toList(),
          builder: (context, controller, child) {
            return ElevatedButton.icon(
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.white),
                foregroundColor: WidgetStateProperty.all(Colors.black),
              ),
              icon: Icon(Icons.arrow_drop_down, size: 26),
              label: Text(getTypeLabel(selectedModType)),
            );
          },
        ),
      ),
    );
  }
}
