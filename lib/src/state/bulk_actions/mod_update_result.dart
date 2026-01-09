enum ModUpdateStatus {
  updated,
  upToDate,
  failed,
}

class ModUpdateResult {
  final String modId;
  final String modName;
  final ModUpdateStatus status;
  final String? errorMessage;

  const ModUpdateResult({
    required this.modId,
    required this.modName,
    required this.status,
    this.errorMessage,
  });
}

class DownloadModUpdatesResult {
  final List<ModUpdateResult> results;
  final int successCount;
  final int failCount;
  final int skippedCount;
  final String summaryMessage;

  const DownloadModUpdatesResult({
    required this.results,
    required this.successCount,
    required this.failCount,
    required this.skippedCount,
    required this.summaryMessage,
  });
}
