class DirectoriesState {
  final String ttsDir;
  final String savesDir;
  final String workshopDir;
  final String modsDir;
  final String assetBundlesDir;
  final String audioDir;
  final String imagesDir;
  final String modelsDir;
  final String pdfDir;

  const DirectoriesState({
    required this.ttsDir,
    required this.savesDir,
    required this.workshopDir,
    required this.modsDir,
    required this.assetBundlesDir,
    required this.audioDir,
    required this.imagesDir,
    required this.modelsDir,
    required this.pdfDir,
  });

  factory DirectoriesState.fromTtsDir(String ttsDir) {
    final modsDir = '$ttsDir/Mods';
    return DirectoriesState(
      ttsDir: ttsDir,
      savesDir: '$ttsDir/Saves',
      workshopDir: '$modsDir/Workshop',
      modsDir: modsDir,
      assetBundlesDir: '$modsDir/Assetbundles',
      audioDir: '$modsDir/Audio',
      imagesDir: '$modsDir/Images',
      modelsDir: '$modsDir/Models',
      pdfDir: '$modsDir/PDF',
    );
  }

  factory DirectoriesState.empty() {
    const emptyPath = '';
    return const DirectoriesState(
      ttsDir: emptyPath,
      savesDir: emptyPath,
      workshopDir: emptyPath,
      modsDir: emptyPath,
      assetBundlesDir: emptyPath,
      audioDir: emptyPath,
      imagesDir: emptyPath,
      modelsDir: emptyPath,
      pdfDir: emptyPath,
    );
  }
}
