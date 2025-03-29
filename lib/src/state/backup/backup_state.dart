class BackupState {
  final bool importInProgress;
  final bool backupInprogress;

  const BackupState({
    this.importInProgress = false,
    this.backupInprogress = false,
  });

  BackupState copyWith({
    bool? importInProgress,
    bool? backupInprogress,
  }) {
    return BackupState(
      importInProgress: importInProgress ?? this.importInProgress,
      backupInprogress: backupInprogress ?? this.backupInprogress,
    );
  }
}
