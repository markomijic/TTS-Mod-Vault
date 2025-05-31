class ExistingAssetsListsState {
  final List<String> assetBundles;
  final List<String> assetBundlesFilepaths;
  final List<String> audio;
  final List<String> audioFilepaths;
  final List<String> images;
  final List<String> imagesFilepaths;
  final List<String> models;
  final List<String> modelsFilepaths;
  final List<String> pdf;
  final List<String> pdfFilepaths;

  ExistingAssetsListsState({
    required this.assetBundles,
    required this.assetBundlesFilepaths,
    required this.audio,
    required this.audioFilepaths,
    required this.images,
    required this.imagesFilepaths,
    required this.models,
    required this.modelsFilepaths,
    required this.pdf,
    required this.pdfFilepaths,
  });

  ExistingAssetsListsState.empty()
      : assetBundles = [],
        assetBundlesFilepaths = [],
        audio = [],
        audioFilepaths = [],
        images = [],
        imagesFilepaths = [],
        models = [],
        modelsFilepaths = [],
        pdf = [],
        pdfFilepaths = [];

  ExistingAssetsListsState copyWith({
    List<String>? assetBundles,
    List<String>? assetBundlesFilepaths,
    List<String>? audio,
    List<String>? audioFilepaths,
    List<String>? images,
    List<String>? imagesFilepaths,
    List<String>? models,
    List<String>? modelsFilepaths,
    List<String>? pdf,
    List<String>? pdfFilepaths,
  }) {
    return ExistingAssetsListsState(
      assetBundles: assetBundles ?? this.assetBundles,
      assetBundlesFilepaths:
          assetBundlesFilepaths ?? this.assetBundlesFilepaths,
      audio: audio ?? this.audio,
      audioFilepaths: audioFilepaths ?? this.audioFilepaths,
      images: images ?? this.images,
      imagesFilepaths: imagesFilepaths ?? this.imagesFilepaths,
      models: models ?? this.models,
      modelsFilepaths: modelsFilepaths ?? this.modelsFilepaths,
      pdf: pdf ?? this.pdf,
      pdfFilepaths: pdfFilepaths ?? this.pdfFilepaths,
    );
  }
}
