class Asset {
  final String url;
  final bool fileExists;
  final String? filePath;

  Asset({
    required this.url,
    required this.fileExists,
    this.filePath,
  });
}
