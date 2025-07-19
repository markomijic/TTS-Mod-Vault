class BulkActionsState {
  final bool downloadingAllMods;
  final bool cancelledDownloadingAllMods;
  final int currentModNumber;
  final int totalModNumber;

  const BulkActionsState({
    this.downloadingAllMods = false,
    this.cancelledDownloadingAllMods = false,
    this.currentModNumber = 0,
    this.totalModNumber = 0,
  });

  BulkActionsState copyWith({
    bool? downloadingAllMods,
    bool? cancelledDownloadingAllMods,
    int? currentModNumber,
    int? totalModNumber,
  }) {
    return BulkActionsState(
      downloadingAllMods: downloadingAllMods ?? this.downloadingAllMods,
      cancelledDownloadingAllMods:
          cancelledDownloadingAllMods ?? this.cancelledDownloadingAllMods,
      currentModNumber: currentModNumber ?? this.currentModNumber,
      totalModNumber: totalModNumber ?? this.totalModNumber,
    );
  }
}
