import 'package:tts_mod_vault/src/state/asset/asset_model.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

class SelectedAssetState {
  final Asset asset;
  final AssetTypeEnum type;

  const SelectedAssetState({
    required this.asset,
    required this.type,
  });
}
