enum ImportBackupStatusEnum {
  idle,
  awaitingBackupFile,
  importingBackup,
}

class ImportBackupState {
  final ImportBackupStatusEnum status;
  final String importFileName;
  final String lastImportedJsonFileName;
  final int totalCount;
  final int currentCount;

  const ImportBackupState({
    this.status = ImportBackupStatusEnum.idle,
    this.importFileName = "",
    this.lastImportedJsonFileName = "",
    this.totalCount = 0,
    this.currentCount = 0,
  });

  ImportBackupState copyWith({
    ImportBackupStatusEnum? status,
    String? importFileName,
    String? lastImportedJsonFileName,
    int? totalCount,
    int? currentCount,
  }) {
    return ImportBackupState(
      status: status ?? this.status,
      importFileName: importFileName ?? this.importFileName,
      lastImportedJsonFileName:
          lastImportedJsonFileName ?? this.lastImportedJsonFileName,
      totalCount: totalCount ?? this.totalCount,
      currentCount: currentCount ?? this.currentCount,
    );
  }
}
