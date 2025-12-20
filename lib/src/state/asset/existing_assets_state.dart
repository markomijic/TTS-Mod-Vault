class ExistingAssetsListsState {
  // Maps: filename -> filepath for O(1) lookups
  final Map<String, String> assetBundles;
  final Map<String, String> audio;
  final Map<String, String> images;
  final Map<String, String> models;
  final Map<String, String> pdf;

  ExistingAssetsListsState({
    required this.assetBundles,
    required this.audio,
    required this.images,
    required this.models,
    required this.pdf,
  });

  ExistingAssetsListsState.empty()
      : assetBundles = {},
        audio = {},
        images = {},
        models = {},
        pdf = {};

  ExistingAssetsListsState copyWith({
    Map<String, String>? assetBundles,
    Map<String, String>? audio,
    Map<String, String>? images,
    Map<String, String>? models,
    Map<String, String>? pdf,
  }) {
    return ExistingAssetsListsState(
      assetBundles: assetBundles ?? this.assetBundles,
      audio: audio ?? this.audio,
      images: images ?? this.images,
      models: models ?? this.models,
      pdf: pdf ?? this.pdf,
    );
  }
}
