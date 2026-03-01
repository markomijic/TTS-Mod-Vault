import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;

enum FilterAssetsEnum {
  missing('Missing'),
  complete('Complete'),
  assetBundle('AssetBundles'),
  audio('Audio'),
  image('Images'),
  model('Models'),
  pdf('PDF');

  const FilterAssetsEnum(this.label);

  final String label;
}

class SortAndFilterState {
  final Set<String> modsFolders;
  final Set<String> savesFolders;
  final Set<String> savedObjectsFolders;

  // Filtered versions
  final Set<String> filteredModsFolders;
  final Set<String> filteredSavesFolders;
  final Set<String> filteredSavedObjectsFolders;
  final Set<FilterAssetsEnum> filteredAssets;
  final Set<ExistingBackupStatusEnum> filteredBackupStatuses;
  final bool filterHasAudio;

  // Sort
  final SortOptionEnum sortOption;

  const SortAndFilterState({
    required this.modsFolders,
    required this.savesFolders,
    required this.savedObjectsFolders,
    required this.filteredModsFolders,
    required this.filteredSavesFolders,
    required this.filteredSavedObjectsFolders,
    required this.filteredAssets,
    required this.filteredBackupStatuses,
    this.filterHasAudio = false,
    required this.sortOption,
  });

  factory SortAndFilterState.emptyFilters(SortOptionEnum sortOption) {
    return SortAndFilterState(
      modsFolders: {},
      savesFolders: {},
      savedObjectsFolders: {},
      filteredModsFolders: {},
      filteredSavesFolders: {},
      filteredSavedObjectsFolders: {},
      filteredAssets: {},
      filteredBackupStatuses: {},
      filterHasAudio: false,
      sortOption: sortOption,
    );
  }

  SortAndFilterState copyWith({
    Set<String>? modsFolders,
    Set<String>? savesFolders,
    Set<String>? savedObjectsFolders,
    Set<String>? filteredModsFolders,
    Set<String>? filteredSavesFolders,
    Set<String>? filteredSavedObjectsFolders,
    Set<FilterAssetsEnum>? filteredAssets,
    Set<ExistingBackupStatusEnum>? filteredBackupStatuses,
    bool? filterHasAudio,
    SortOptionEnum? sortOption,
  }) {
    return SortAndFilterState(
      modsFolders: modsFolders ?? this.modsFolders,
      savesFolders: savesFolders ?? this.savesFolders,
      savedObjectsFolders: savedObjectsFolders ?? this.savedObjectsFolders,
      filteredModsFolders: filteredModsFolders ?? this.filteredModsFolders,
      filteredSavesFolders: filteredSavesFolders ?? this.filteredSavesFolders,
      filteredSavedObjectsFolders:
          filteredSavedObjectsFolders ?? this.filteredSavedObjectsFolders,
      filteredAssets: filteredAssets ?? this.filteredAssets,
      filteredBackupStatuses:
          filteredBackupStatuses ?? this.filteredBackupStatuses,
      filterHasAudio: filterHasAudio ?? this.filterHasAudio,
      sortOption: sortOption ?? this.sortOption,
    );
  }
}

enum SortOptionEnum {
  alphabeticalAsc('A-Z'),
  dateCreatedDesc('Newest'),
  lastModifiedDesc('Recently updated'),
  missingAssets('Missing assets');

  final String label;
  const SortOptionEnum(this.label);

  static SortOptionEnum fromLabel(String label) {
    for (SortOptionEnum option in SortOptionEnum.values) {
      if (option.label == label) {
        return option;
      }
    }
    return alphabeticalAsc;
  }
}
