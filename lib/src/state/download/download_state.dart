import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

class DownloadState {
  final bool isDownloading;
  final bool cancelledDownloads;
  final double progress;
  final AssetTypeEnum? downloadingType;

  const DownloadState({
    this.isDownloading = false,
    this.cancelledDownloads = false,
    this.progress = 0.0,
    this.downloadingType,
  });

  DownloadState copyWith({
    bool? isDownloading,
    bool? cancelledDownloads,
    double? progress,
    AssetTypeEnum? downloadingType,
  }) {
    return DownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      cancelledDownloads: cancelledDownloads ?? this.cancelledDownloads,
      progress: progress ?? this.progress,
      downloadingType: downloadingType ?? this.downloadingType,
    );
  }
}
