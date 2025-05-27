class ExistingAssetsListsState {
  final List<String> assetBundles;
  final List<String> audio;
  final List<String> images;
  final List<String> models;
  final List<String> pdfs;

  ExistingAssetsListsState({
    required this.assetBundles,
    required this.audio,
    required this.images,
    required this.models,
    required this.pdfs,
  });

  ExistingAssetsListsState.empty()
      : assetBundles = [],
        audio = [],
        images = [],
        models = [],
        pdfs = [];

  ExistingAssetsListsState copyWith({
    List<String>? assetBundles,
    List<String>? audio,
    List<String>? images,
    List<String>? models,
    List<String>? pdfs,
  }) {
    return ExistingAssetsListsState(
      assetBundles: assetBundles ?? this.assetBundles,
      audio: audio ?? this.audio,
      images: images ?? this.images,
      models: models ?? this.models,
      pdfs: pdfs ?? this.pdfs,
    );
  }
}
