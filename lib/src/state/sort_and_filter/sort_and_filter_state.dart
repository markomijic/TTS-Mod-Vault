import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show BackupStatusEnum;

class SortAndFilterState {
  final Set<String> modsFolders;
  final Set<String> savesFolders;
  final Set<String> savedObjectsFolders;

  // Filtered versions
  final Set<String> filteredModsFolders;
  final Set<String> filteredSavesFolders;
  final Set<String> filteredSavedObjectsFolders;
  final Set<BackupStatusEnum> filteredBackupStatuses;

  const SortAndFilterState({
    required this.modsFolders,
    required this.savesFolders,
    required this.savedObjectsFolders,
    required this.filteredModsFolders,
    required this.filteredSavesFolders,
    required this.filteredSavedObjectsFolders,
    required this.filteredBackupStatuses,
  });

  factory SortAndFilterState.initial() {
    return const SortAndFilterState(
      modsFolders: {},
      savesFolders: {},
      savedObjectsFolders: {},
      filteredModsFolders: {},
      filteredSavesFolders: {},
      filteredSavedObjectsFolders: {},
      filteredBackupStatuses: {},
    );
  }

  SortAndFilterState copyWith({
    Set<String>? modsFolders,
    Set<String>? savesFolders,
    Set<String>? savedObjectsFolders,
    Set<String>? filteredModsFolders,
    Set<String>? filteredSavesFolders,
    Set<String>? filteredSavedObjectsFolders,
    Set<BackupStatusEnum>? filteredBackupStatuses,
  }) {
    return SortAndFilterState(
      modsFolders: modsFolders ?? this.modsFolders,
      savesFolders: savesFolders ?? this.savesFolders,
      savedObjectsFolders: savedObjectsFolders ?? this.savedObjectsFolders,
      filteredModsFolders: filteredModsFolders ?? this.filteredModsFolders,
      filteredSavesFolders: filteredSavesFolders ?? this.filteredSavesFolders,
      filteredSavedObjectsFolders:
          filteredSavedObjectsFolders ?? this.filteredSavedObjectsFolders,
      filteredBackupStatuses:
          filteredBackupStatuses ?? this.filteredBackupStatuses,
    );
  }
}
