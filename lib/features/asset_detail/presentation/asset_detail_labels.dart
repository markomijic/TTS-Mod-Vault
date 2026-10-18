import 'package:tts_mod_vault/features/asset_detail/application/asset_detail_filter.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Localised names of [AssetStatusFilter].
extension AssetStatusFilterLabels on AssetStatusFilter {
  /// Menu and button label.
  String label(AppLocalizations l10n) => switch (this) {
    AssetStatusFilter.all => l10n.assetStatusAll,
    AssetStatusFilter.missing => l10n.assetStatusMissing,
    AssetStatusFilter.downloaded => l10n.assetStatusDownloaded,
  };
}
