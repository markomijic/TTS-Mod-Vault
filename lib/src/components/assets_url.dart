import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/state/asset/asset_model.dart';

import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/provider.dart';
import 'package:tts_mod_vault/src/utils.dart';

class AssetsUrl extends ConsumerWidget {
  final Asset asset;
  final AssetType type;

  const AssetsUrl({
    super.key,
    required this.asset,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAssetNotifier = ref.watch(selectedAssetProvider.notifier);
    final selectedAsset = ref.watch(selectedAssetProvider);

    return Container(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => selectedAssetNotifier.setAsset(asset, type),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: asset.url));
            showSnackBar(
              context,
              '${asset.url} copied to clipboard',
              Duration(seconds: 3),
            );
          },
          child: Text(
            asset.url,
            style: TextStyle(
              fontSize: 12,
              color: selectedAsset != null && asset == selectedAsset.asset
                  ? Colors.blue
                  : asset.fileExists
                      ? Colors.green
                      : Colors.red,
            ),
          ),
        ),
      ),
    );
  }
}
