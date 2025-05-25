class BackupState {
  final bool importInProgress;
  final bool backupInProgress;
  final String importFileName;
  final String lastImportedJsonFileName;

  const BackupState({
    this.importInProgress = false,
    this.backupInProgress = false,
    this.importFileName = "",
    this.lastImportedJsonFileName = "",
  });

  BackupState copyWith({
    bool? importInProgress,
    bool? backupInProgress,
    String? importFileName,
    String? lastImportedJsonFileName,
  }) {
    return BackupState(
      importInProgress: importInProgress ?? this.importInProgress,
      backupInProgress: backupInProgress ?? this.backupInProgress,
      importFileName: importFileName ?? this.importFileName,
      lastImportedJsonFileName:
          lastImportedJsonFileName ?? this.lastImportedJsonFileName,
    );
  }
}
