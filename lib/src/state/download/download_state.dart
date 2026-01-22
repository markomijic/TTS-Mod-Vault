class DownloadState {
  final bool isDownloading;
  final bool cancelledDownloads;
  final double progress;
  final String? statusMessage;

  const DownloadState({
    this.isDownloading = false,
    this.cancelledDownloads = false,
    this.progress = 0.0,
    this.statusMessage,
  });

  DownloadState copyWith({
    bool? isDownloading,
    bool? cancelledDownloads,
    double? progress,
    String? statusMessage,
  }) {
    return DownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      cancelledDownloads: cancelledDownloads ?? this.cancelledDownloads,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
