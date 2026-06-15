import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/asset_context_menu.dart'
    show showAssetContextMenu;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        selectedModProvider,
        selectedUrlProvider,
        settingsProvider;

class AssetsUrl extends HookConsumerWidget {
  final Asset asset;
  final AssetTypeEnum type;

  const AssetsUrl({
    super.key,
    required this.asset,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetUrlFontSize = ref.watch(settingsProvider).assetUrlFontSize;
    final mod = ref.watch(selectedModProvider);
    final url = ref.watch(selectedUrlProvider);
    final isSelected = useMemoized(
      () => asset.url == url,
      [url, mod],
    );

    void onTapDown(TapDownDetails details) {
      if (ref.read(actionInProgressProvider)) return;

      if (!isSelected) {
        showAssetContextMenu(
            context, ref, details.globalPosition, asset, type);
      }

      ref.read(selectedUrlProvider.notifier).state =
          isSelected ? '' : asset.url;
    }

    void onSecondaryTapDown(TapDownDetails details) {
      if (ref.read(actionInProgressProvider)) return;

      showAssetContextMenu(context, ref, details.globalPosition, asset, type);

      ref.read(selectedUrlProvider.notifier).state = asset.url;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) => onTapDown(details),
        onSecondaryTapDown: (details) => onSecondaryTapDown(details),
        child: Text(
          asset.url,
          style: TextStyle(
            fontSize: assetUrlFontSize,
            color: isSelected
                ? Colors.lightBlue
                : asset.fileExists
                    ? Colors.green
                    : Colors.red,
          ),
        ),
      ),
    );
  }
}
