import 'package:flutter/material.dart';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/components/assets_url.dart';
import 'package:tts_mod_vault/src/state/asset/asset_model.dart';

import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/provider.dart';

class AssetLinksColumn extends HookConsumerWidget {
  final AssetType type;
  final List<Asset> assets;

  const AssetLinksColumn({
    super.key,
    required this.type,
    required this.assets,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAssetNotifier = ref.watch(selectedAssetProvider.notifier);
    final downloadNotifier = ref.watch(downloadProvider.notifier);
    final isDownloading = ref.watch(downloadProvider).isDownloading;

    final hasMissingFiles = useMemoized(
      () => assets.any((e) => !e.fileExists),
      [assets],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                bottom: BorderSide(
                  color: Colors.white,
                  width: 2.0,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 2,
              children: [
                Text(
                  type.label,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (hasMissingFiles && !isDownloading)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () async {
                        final urls = assets
                            .map((e) => e.fileExists ? null : e.url)
                            .nonNulls
                            .toList();
                        final name = ref.read(modsProvider).selectedMod!.name;
                        await downloadNotifier.downloadFiles(
                          modName: name,
                          urls: urls,
                          type: type,
                        );

                        await ref.read(modsProvider.notifier).updateMod(name);

                        selectedAssetNotifier.resetState();
                      },
                      child: Icon(Icons.download, size: 20),
                    ),
                  )
              ],
            ),
          ),
          ...assets.map((asset) {
            return AssetsUrl(asset: asset, type: type);
          }),
        ],
      ),
    );
  }
}
