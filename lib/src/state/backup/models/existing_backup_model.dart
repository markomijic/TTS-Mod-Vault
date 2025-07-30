class ExistingBackup {
  final String filename;
  final String filepath;
  final int lastModifiedTimestamp;
  //final int totalAssetCount;

  const ExistingBackup({
    required this.filename,
    required this.filepath,
    required this.lastModifiedTimestamp,
    //required this.totalAssetCount,
  });

  ExistingBackup copyWith({
    String? filename,
    String? filepath,
    int? lastModifiedTimestamp,
    //int? totalAssetCount,
  }) {
    return ExistingBackup(
      filename: filename ?? this.filename,
      filepath: filepath ?? this.filepath,
      lastModifiedTimestamp:
          lastModifiedTimestamp ?? this.lastModifiedTimestamp,
      //totalAssetCount: totalAssetCount ?? this.totalAssetCount,
    );
  }
}
