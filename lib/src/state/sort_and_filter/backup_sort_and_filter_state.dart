enum BackupSortOptionEnum {
  alphabeticalAsc('A-Z'),
  newestFirst('Newest'),
  largestFirst('Largest');

  const BackupSortOptionEnum(this.label);
  final String label;
}

enum BackupMatchStatusEnum {
  hasMatchingMod('Has matching mod'),
  noMatchingMod('No matching mod');

  const BackupMatchStatusEnum(this.label);
  final String label;
}

class BackupSortAndFilterState {
  final BackupSortOptionEnum sortOption;
  final Set<String> backupFolders;
  final Set<String> filteredBackupFolders;
  final Set<BackupMatchStatusEnum> filteredMatchStatuses;

  const BackupSortAndFilterState({
    required this.sortOption,
    required this.backupFolders,
    required this.filteredBackupFolders,
    required this.filteredMatchStatuses,
  });

  factory BackupSortAndFilterState.initial() {
    return const BackupSortAndFilterState(
      sortOption: BackupSortOptionEnum.alphabeticalAsc,
      backupFolders: {},
      filteredBackupFolders: {},
      filteredMatchStatuses: {},
    );
  }

  BackupSortAndFilterState copyWith({
    BackupSortOptionEnum? sortOption,
    Set<String>? backupFolders,
    Set<String>? filteredBackupFolders,
    Set<BackupMatchStatusEnum>? filteredMatchStatuses,
  }) {
    return BackupSortAndFilterState(
      sortOption: sortOption ?? this.sortOption,
      backupFolders: backupFolders ?? this.backupFolders,
      filteredBackupFolders:
          filteredBackupFolders ?? this.filteredBackupFolders,
      filteredMatchStatuses:
          filteredMatchStatuses ?? this.filteredMatchStatuses,
    );
  }
}
