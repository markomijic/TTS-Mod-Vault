import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart';

class AssetLists {
  final List<Asset> assetBundles;
  final List<Asset> audio;
  final List<Asset> images;
  final List<Asset> models;
  final List<Asset> pdf;

  AssetLists({
    List<Asset>? assetBundles,
    List<Asset>? audio,
    List<Asset>? images,
    List<Asset>? models,
    List<Asset>? pdf,
  })  : assetBundles = assetBundles ?? [],
        audio = audio ?? [],
        images = images ?? [],
        models = models ?? [],
        pdf = pdf ?? [];
}
