class DirectoriesState {
  final String ttsDir;
  final String savesDir;
  final String savedObjectsDir;
  final String workshopDir;
  final String modsDir;
  final String assetBundlesDir;
  final String audioDir;
  final String imagesDir;
  final String imagesRawDir;
  final String modelsDir;
  final String modelsRawDir;
  final String pdfDir;

  const DirectoriesState({
    required this.ttsDir,
    required this.savesDir,
    required this.savedObjectsDir,
    required this.workshopDir,
    required this.modsDir,
    required this.assetBundlesDir,
    required this.audioDir,
    required this.imagesDir,
    required this.imagesRawDir,
    required this.modelsDir,
    required this.modelsRawDir,
    required this.pdfDir,
  });

  factory DirectoriesState.fromDir(String dir, String? savesDir) {
    final modsDir = '$dir/Mods';

    return DirectoriesState(
      ttsDir: dir,
      // Saves
      savesDir: savesDir != null ? '$savesDir/Saves' : '$dir/Saves',
      savedObjectsDir: savesDir != null
          ? '$savesDir/Saves/Saved Objects'
          : '$dir/Saves/Saved Objects',
      // Mods
      modsDir: modsDir,
      workshopDir: '$modsDir/Workshop',
      assetBundlesDir: '$modsDir/Assetbundles',
      audioDir: '$modsDir/Audio',
      imagesDir: '$modsDir/Images',
      imagesRawDir: '$modsDir/Images Raw',
      modelsDir: '$modsDir/Models',
      modelsRawDir: '$modsDir/Models Raw',
      pdfDir: '$modsDir/PDF',
    );
  }

  factory DirectoriesState.empty() {
    const emptyPath = '';
    return const DirectoriesState(
      ttsDir: emptyPath,
      savesDir: emptyPath,
      savedObjectsDir: emptyPath,
      workshopDir: emptyPath,
      modsDir: emptyPath,
      assetBundlesDir: emptyPath,
      audioDir: emptyPath,
      imagesDir: emptyPath,
      imagesRawDir: emptyPath,
      modelsDir: emptyPath,
      modelsRawDir: emptyPath,
      pdfDir: emptyPath,
    );
  }
}
