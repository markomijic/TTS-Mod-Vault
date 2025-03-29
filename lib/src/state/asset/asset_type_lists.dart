class AssetTypeLists {
  final List<String> assetBundles;
  final List<String> audio;
  final List<String> images;
  final List<String> models;
  final List<String> pdfs;

  AssetTypeLists({
    required this.assetBundles,
    required this.audio,
    required this.images,
    required this.models,
    required this.pdfs,
  });

  AssetTypeLists.empty()
      : assetBundles = [],
        audio = [],
        images = [],
        models = [],
        pdfs = [];

  AssetTypeLists copyWith({
    List<String>? assetBundles,
    List<String>? audio,
    List<String>? images,
    List<String>? models,
    List<String>? pdfs,
  }) {
    return AssetTypeLists(
      assetBundles: assetBundles ?? this.assetBundles,
      audio: audio ?? this.audio,
      images: images ?? this.images,
      models: models ?? this.models,
      pdfs: pdfs ?? this.pdfs,
    );
  }
}
