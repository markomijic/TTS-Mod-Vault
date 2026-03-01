enum BackupSortOptionEnum {
  nameAsc('A-Z'),
  nameDesc('Z-A'),
  sizeDesc('Largest'),
  sizeAsc('Smallest'),
  dateDesc('Newest'),
  dateAsc('Oldest');

  const BackupSortOptionEnum(this.label);
  final String label;

  static BackupSortOptionEnum fromLabel(String label) {
    for (BackupSortOptionEnum option in BackupSortOptionEnum.values) {
      if (option.label == label) return option;
    }
    return nameAsc;
  }
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

  factory BackupSortAndFilterState.initial([
    BackupSortOptionEnum sortOption = BackupSortOptionEnum.nameAsc,
  ]) {
    return BackupSortAndFilterState(
      sortOption: sortOption,
      backupFolders: const {},
      filteredBackupFolders: const {},
      filteredMatchStatuses: const {},
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
