class ExistingBackup {
  final String filename;
  final String filepath;
  final int lastModifiedTimestamp;
  final int totalAssetCount;
  final String? matchingModFilepath;

  const ExistingBackup({
    required this.filename,
    required this.filepath,
    required this.lastModifiedTimestamp,
    required this.totalAssetCount,
    this.matchingModFilepath,
  });

  ExistingBackup copyWith({
    String? filename,
    String? filepath,
    int? lastModifiedTimestamp,
    int? totalAssetCount,
    String? matchingModFilepath,
  }) {
    return ExistingBackup(
      filename: filename ?? this.filename,
      filepath: filepath ?? this.filepath,
      lastModifiedTimestamp:
          lastModifiedTimestamp ?? this.lastModifiedTimestamp,
      totalAssetCount: totalAssetCount ?? this.totalAssetCount,
      matchingModFilepath: matchingModFilepath ?? this.matchingModFilepath,
    );
  }
}
