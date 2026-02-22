import 'package:hooks_riverpod/hooks_riverpod.dart' show StateNotifier;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/sort_and_filter/backup_sort_and_filter_state.dart';

class BackupSortAndFilterNotifier
    extends StateNotifier<BackupSortAndFilterState> {
  BackupSortAndFilterNotifier() : super(BackupSortAndFilterState.initial());

  void setSortOption(BackupSortOptionEnum sortOption) {
    state = state.copyWith(sortOption: sortOption);
  }

  void setFolders(List<ExistingBackup> backups) {
    final folders = backups.map((b) => b.parentFolderName).toSet();
    state = state.copyWith(backupFolders: folders);
  }

  void addFilteredFolder(String folder) {
    state = state.copyWith(
      filteredBackupFolders: {...state.filteredBackupFolders, folder},
    );
  }

  void removeFilteredFolder(String folder) {
    state = state.copyWith(
      filteredBackupFolders:
          state.filteredBackupFolders.where((f) => f != folder).toSet(),
    );
  }

  void clearFilteredFolders() {
    state = state.copyWith(filteredBackupFolders: {});
  }

  void addFilteredMatchStatus(BackupMatchStatusEnum status) {
    state = state.copyWith(
      filteredMatchStatuses: {...state.filteredMatchStatuses, status},
    );
  }

  void removeFilteredMatchStatus(BackupMatchStatusEnum status) {
    state = state.copyWith(
      filteredMatchStatuses:
          state.filteredMatchStatuses.where((s) => s != status).toSet(),
    );
  }

  void clearFilteredMatchStatuses() {
    state = state.copyWith(filteredMatchStatuses: {});
  }

  void resetState() {
    state = BackupSortAndFilterState.initial();
  }
}
