import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_context_menu.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_detail_selection.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';

/// One URL line of the asset list (port of 2.x `AssetsUrl`).
///
/// Colour: selected → primary, invalid → [VaultColors.assetInvalid], on
/// disk → [VaultColors.assetPresent], otherwise [VaultColors.assetMissing].
/// Left click toggles the selection and opens the context menu when the
/// row was not selected yet; right click selects and opens the menu. Both
/// are ignored while an operation runs.
class AssetUrlRow extends ConsumerWidget {
  /// Creates the row.
  const AssetUrlRow({super.key, required this.mod, required this.asset});

  /// The mod the asset belongs to.
  final Mod mod;

  /// The asset shown.
  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = asset.url;
    final selected = ref.watch(
      selectedAssetUrlProvider.select((selectedUrl) => selectedUrl == url),
    );
    final fontSize = ref.watch(assetUrlFontSizeSettingProvider);
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);

    final color = selected
        ? theme.colorScheme.primary
        : asset.invalid
        ? colors.assetInvalid
        : asset.exists
        ? colors.assetPresent
        : colors.assetMissing;

    void onTapDown(TapDownDetails details) {
      if (ref.read(operationRunningProvider)) return;
      if (!selected) {
        showAssetContextMenu(context, ref, details.globalPosition, mod, asset);
      }
      ref.read(selectedAssetUrlProvider.notifier).toggle(url);
    }

    void onSecondaryTapDown(TapDownDetails details) {
      if (ref.read(operationRunningProvider)) return;
      showAssetContextMenu(context, ref, details.globalPosition, mod, asset);
      ref.read(selectedAssetUrlProvider.notifier).select(url);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTapDown,
        onSecondaryTapDown: onSecondaryTapDown,
        child: Text(
          url,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: fontSize,
            color: color,
          ),
        ),
      ),
    );
  }
}
