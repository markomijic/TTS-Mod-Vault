class DirectoriesState {
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

  factory DirectoriesState.fromDirs(
    String modsDir,
    String savesDir,
  ) {
    return DirectoriesState(
      // Saves
      savesDir: savesDir,
      savedObjectsDir: '$savesDir/Saved Objects',

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

extension DirectoriesStateExtensions on DirectoriesState {
  DirectoriesState updateSaves(String newSavesDir) {
    return DirectoriesState(
      // Saves
      savesDir: newSavesDir,
      savedObjectsDir: '$newSavesDir/Saved Objects',
      // Mods
      workshopDir: workshopDir,
      modsDir: modsDir,
      assetBundlesDir: assetBundlesDir,
      audioDir: audioDir,
      imagesDir: imagesDir,
      imagesRawDir: imagesRawDir,
      modelsDir: modelsDir,
      modelsRawDir: modelsRawDir,
      pdfDir: pdfDir,
    );
  }

  DirectoriesState updateMods(String newModsDir) {
    return DirectoriesState(
      // Saves
      savesDir: savesDir,
      savedObjectsDir: savedObjectsDir,
      // Mods
      modsDir: newModsDir,
      workshopDir: '$newModsDir/Workshop',
      assetBundlesDir: '$newModsDir/Assetbundles',
      audioDir: '$newModsDir/Audio',
      imagesDir: '$newModsDir/Images',
      imagesRawDir: '$newModsDir/Images Raw',
      modelsDir: '$newModsDir/Models',
      modelsRawDir: '$newModsDir/Models Raw',
      pdfDir: '$newModsDir/PDF',
    );
  }
}
