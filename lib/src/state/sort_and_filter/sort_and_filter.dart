import 'package:hooks_riverpod/hooks_riverpod.dart' show StateNotifier, Ref;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show ModTypeEnum, Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show sortAndFilterProvider;
import 'package:tts_mod_vault/src/state/sort_and_filter/sort_and_filter_state.dart'
    show SortAndFilterState;

class SortAndFilterNotifier extends StateNotifier<SortAndFilterState> {
  Ref ref;

  SortAndFilterNotifier(this.ref) : super(SortAndFilterState.initial());

  void setFolders(List<Mod> mods) {
    for (final mod in mods) {
      switch (mod.modType) {
        case ModTypeEnum.mod:
          ref
              .read(sortAndFilterProvider.notifier)
              .addModFolder(mod.parentFolderName);
          break;
        case ModTypeEnum.save:
          ref
              .read(sortAndFilterProvider.notifier)
              .addSaveFolder(mod.parentFolderName);
          break;
        case ModTypeEnum.savedObject:
          ref
              .read(sortAndFilterProvider.notifier)
              .addSavedObjectFolder(mod.parentFolderName);
          break;
      }
    }
  }

  void resetState() {
    state = SortAndFilterState.initial();
  }

  // Methods to add folders
  void addModFolder(String folder) {
    state = state.copyWith(
      modsFolders: {...state.modsFolders, folder},
    );
  }

  void addSaveFolder(String folder) {
    state = state.copyWith(
      savesFolders: {...state.savesFolders, folder},
    );
  }

  void addSavedObjectFolder(String folder) {
    state = state.copyWith(
      savedObjectsFolders: {...state.savedObjectsFolders, folder},
    );
  }

  // Methods for adding filtered
  void addFilteredFolder(String folder, ModTypeEnum type) {
    switch (type) {
      case ModTypeEnum.mod:
        addFilteredModFolder(folder);
      case ModTypeEnum.save:
        addFilteredSaveFolder(folder);
      case ModTypeEnum.savedObject:
        addFilteredSavedObjectFolder(folder);
    }
  }

  void addFilteredModFolder(String folder) {
    state = state.copyWith(
      filteredModsFolders: {...state.filteredModsFolders, folder},
    );
  }

  void addFilteredSaveFolder(String folder) {
    state = state.copyWith(
      filteredSavesFolders: {...state.filteredSavesFolders, folder},
    );
  }

  void addFilteredSavedObjectFolder(String folder) {
    state = state.copyWith(
      filteredSavedObjectsFolders: {
        ...state.filteredSavedObjectsFolders,
        folder
      },
    );
  }

  void addFilteredBackupStatus(ExistingBackupStatusEnum status) {
    state = state.copyWith(
      filteredBackupStatuses: {...state.filteredBackupStatuses, status},
    );
  }

  // Methods to remove
  void removeFilteredFolder(String folder, ModTypeEnum type) {
    switch (type) {
      case ModTypeEnum.mod:
        removeFilteredModFolder(folder);
      case ModTypeEnum.save:
        removeFilteredSaveFolder(folder);
      case ModTypeEnum.savedObject:
        removeFilteredSavedObjectFolder(folder);
    }
  }

  void removeFilteredModFolder(String folder) {
    final updatedSet = Set<String>.from(state.filteredModsFolders);
    updatedSet.remove(folder);
    state = state.copyWith(filteredModsFolders: updatedSet);
  }

  void removeFilteredSaveFolder(String folder) {
    final updatedSet = Set<String>.from(state.filteredSavesFolders);
    updatedSet.remove(folder);
    state = state.copyWith(filteredSavesFolders: updatedSet);
  }

  void removeFilteredSavedObjectFolder(String folder) {
    final updatedSet = Set<String>.from(state.filteredSavedObjectsFolders);
    updatedSet.remove(folder);
    state = state.copyWith(filteredSavedObjectsFolders: updatedSet);
  }

  void removeFilteredBackupStatus(ExistingBackupStatusEnum status) {
    final updatedSet =
        Set<ExistingBackupStatusEnum>.from(state.filteredBackupStatuses);
    updatedSet.remove(status);
    state = state.copyWith(filteredBackupStatuses: updatedSet);
  }

  // Methods to clear
  void clearFilteredFolders(ModTypeEnum type) {
    switch (type) {
      case ModTypeEnum.mod:
        clearFilteredModsFolders();
      case ModTypeEnum.save:
        clearFilteredSavesFolders();
      case ModTypeEnum.savedObject:
        clearFilteredSavedObjectsFolders();
    }
  }

  void clearFilteredModsFolders() {
    state = state.copyWith(filteredModsFolders: {});
  }

  void clearFilteredSavesFolders() {
    state = state.copyWith(filteredSavesFolders: {});
  }

  void clearFilteredSavedObjectsFolders() {
    state = state.copyWith(filteredSavedObjectsFolders: {});
  }

  void clearFilteredBackupStatuses() {
    state = state.copyWith(filteredBackupStatuses: {});
  }
}
