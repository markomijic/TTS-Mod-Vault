class ImportBackupState {
  final int totalCount;
  final int currentCount;

  const ImportBackupState({
    this.totalCount = 0,
    this.currentCount = 0,
  });

  ImportBackupState copyWith({
    int? totalCount,
    int? currentCount,
  }) {
    return ImportBackupState(
      totalCount: totalCount ?? this.totalCount,
      currentCount: currentCount ?? this.currentCount,
    );
  }
}
