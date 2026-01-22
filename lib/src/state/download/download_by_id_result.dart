class DownloadByIdResult {
  final String modId;
  final String? modName;
  final bool success;
  final String? errorMessage;

  DownloadByIdResult({
    required this.modId,
    this.modName,
    required this.success,
    this.errorMessage,
  });
}

class DownloadByIdSummary {
  final List<DownloadByIdResult> results;

  DownloadByIdSummary(this.results);

  int get successCount => results.where((r) => r.success).length;
  int get failCount => results.where((r) => !r.success).length;
  int get totalCount => results.length;

  List<DownloadByIdResult> get successful =>
      results.where((r) => r.success).toList();
  List<DownloadByIdResult> get failed =>
      results.where((r) => !r.success).toList();

  String toDisplayString() {
    if (totalCount == 1) {
      final result = results.first;
      if (result.success) {
        return 'Mod downloaded successfully: ${result.modName ?? result.modId}';
      } else {
        return '[${result.modId}] ${result.errorMessage ?? "Unknown error"}';
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('Downloaded $successCount of $totalCount mods successfully');

    if (successful.isNotEmpty) {
      buffer.writeln('\nSuccessfully downloaded:');
      for (final result in successful) {
        buffer.writeln('  • ${result.modName ?? result.modId}');
      }
    }

    if (failed.isNotEmpty) {
      buffer.writeln('\nFailed:');
      for (final result in failed) {
        buffer.writeln(
            '  • [${result.modId}] ${result.errorMessage ?? "Unknown error"}');
      }
    }

    return buffer.toString().trim();
  }
}
