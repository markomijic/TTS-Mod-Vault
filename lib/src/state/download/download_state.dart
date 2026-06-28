class DownloadState {
  final bool isDownloading;
  final bool isCheckingUrls;
  final bool cancelledDownloads;
  final double progress;
  final String? statusMessage;

  const DownloadState({
    this.isDownloading = false,
    this.isCheckingUrls = false,
    this.cancelledDownloads = false,
    this.progress = 0.0,
    this.statusMessage,
  });

  DownloadState copyWith({
    bool? isDownloading,
    bool? isCheckingUrls,
    bool? cancelledDownloads,
    double? progress,
    String? statusMessage,
  }) {
    return DownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      isCheckingUrls: isCheckingUrls ?? this.isCheckingUrls,
      cancelledDownloads: cancelledDownloads ?? this.cancelledDownloads,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
