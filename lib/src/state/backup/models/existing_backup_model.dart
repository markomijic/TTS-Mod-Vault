class ExistingBackup {
  final String filename;
  final String filepath;
  final String parentFolderName;
  final int lastModifiedTimestamp;
  final int totalAssetCount;
  final int fileSize; // in bytes
  final String? matchingModFilepath;

  const ExistingBackup({
    required this.filename,
    required this.filepath,
    required this.parentFolderName,
    required this.lastModifiedTimestamp,
    required this.totalAssetCount,
    required this.fileSize,
    this.matchingModFilepath,
  });

  /// File size formatted in megabytes (e.g. "12.3 MB").
  String get fileSizeMB => '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';

  ExistingBackup copyWith({
    String? filename,
    String? filepath,
    String? parentFolderName,
    int? lastModifiedTimestamp,
    int? totalAssetCount,
    int? fileSize,
    String? matchingModFilepath,
  }) {
    return ExistingBackup(
      filename: filename ?? this.filename,
      filepath: filepath ?? this.filepath,
      parentFolderName: parentFolderName ?? this.parentFolderName,
      lastModifiedTimestamp:
          lastModifiedTimestamp ?? this.lastModifiedTimestamp,
      totalAssetCount: totalAssetCount ?? this.totalAssetCount,
      fileSize: fileSize ?? this.fileSize,
      matchingModFilepath: matchingModFilepath ?? this.matchingModFilepath,
    );
  }
}
