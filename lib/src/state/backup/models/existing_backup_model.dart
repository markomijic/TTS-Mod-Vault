class ExistingBackup {
  final String filename;
  final String filepath;
  final int lastModifiedTimestamp;
  final int? totalAssetCount;
  final String? matchingModImagePath;

  const ExistingBackup({
    required this.filename,
    required this.filepath,
    required this.lastModifiedTimestamp,
    this.totalAssetCount,
    this.matchingModImagePath,
  });

  ExistingBackup copyWith({
    String? filename,
    String? filepath,
    int? lastModifiedTimestamp,
    int? totalAssetCount,
    String? matchingModImagePath,
  }) {
    return ExistingBackup(
      filename: filename ?? this.filename,
      filepath: filepath ?? this.filepath,
      lastModifiedTimestamp:
          lastModifiedTimestamp ?? this.lastModifiedTimestamp,
      totalAssetCount: totalAssetCount ?? this.totalAssetCount,
      matchingModImagePath: matchingModImagePath ?? this.matchingModImagePath,
    );
  }
}
