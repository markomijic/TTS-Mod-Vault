class ExistingBackup {
  final String filename;
  final String filepath;
  final int lastModifiedTimestamp;

  const ExistingBackup({
    required this.filename,
    required this.filepath,
    required this.lastModifiedTimestamp,
  });
}
