enum DeleteAssetsStatusEnum {
  idle,
  scanning,
  awaitingConfirmation,
  deleting,
  completed,
  error,
}

class SharedAssetInfo {
  final int sharedWithMods;
  final int sharedWithSaves;
  final int sharedWithSavedObjects;
  final Map<String, List<String>>
      sharedAssetDetails; // assetUrl -> list of mod names

  const SharedAssetInfo({
    this.sharedWithMods = 0,
    this.sharedWithSaves = 0,
    this.sharedWithSavedObjects = 0,
    this.sharedAssetDetails = const {},
  });

  int get total => sharedWithMods + sharedWithSaves + sharedWithSavedObjects;
}

class ScanResult {
  final List<String> filesToDelete;
  final SharedAssetInfo sharedAssetInfo;

  const ScanResult({
    required this.filesToDelete,
    required this.sharedAssetInfo,
  });
}

class DeleteAssetsState {
  final DeleteAssetsStatusEnum status;
  final List<String> filesToDelete;
  final int totalFiles;
  final int currentFile;
  final String? errorMessage;
  final String? statusMessage;
  final SharedAssetInfo? sharedAssetInfo;

  const DeleteAssetsState({
    this.status = DeleteAssetsStatusEnum.idle,
    this.filesToDelete = const [],
    this.totalFiles = 0,
    this.currentFile = 0,
    this.errorMessage,
    this.statusMessage,
    this.sharedAssetInfo,
  });

  DeleteAssetsState copyWith({
    DeleteAssetsStatusEnum? status,
    List<String>? filesToDelete,
    int? totalFiles,
    int? currentFile,
    String? errorMessage,
    String? statusMessage,
    SharedAssetInfo? sharedAssetInfo,
  }) {
    return DeleteAssetsState(
      status: status ?? this.status,
      filesToDelete: filesToDelete ?? this.filesToDelete,
      totalFiles: totalFiles ?? this.totalFiles,
      currentFile: currentFile ?? this.currentFile,
      errorMessage: errorMessage ?? this.errorMessage,
      statusMessage: statusMessage ?? this.statusMessage,
      sharedAssetInfo: sharedAssetInfo ?? this.sharedAssetInfo,
    );
  }
}
