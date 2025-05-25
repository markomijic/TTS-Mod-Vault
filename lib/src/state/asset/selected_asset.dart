import 'package:riverpod/riverpod.dart' show StateNotifier;
import 'package:tts_mod_vault/src/state/asset/asset_model.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/asset/selected_asset_state.dart';

class SelectedAssetNotifier extends StateNotifier<SelectedAssetState?> {
  SelectedAssetNotifier() : super(null);

  void setAsset(Asset asset, AssetTypeEnum type) {
    if (asset == state?.asset || asset.fileExists) {
      state = null;
      return;
    }

    state = SelectedAssetState(asset: asset, type: type);
  }

  void resetState() {
    state = null;
  }
}
