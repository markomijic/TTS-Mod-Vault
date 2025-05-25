import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

class DownloadState {
  final bool isDownloading;
  final double progress;
  final String? errorMessage;
  final AssetTypeEnum? downloadingType;

  const DownloadState({
    this.isDownloading = false,
    this.progress = 0.0,
    this.errorMessage,
    this.downloadingType,
  });

  DownloadState copyWith({
    bool? isDownloading,
    double? progress,
    String? errorMessage,
    AssetTypeEnum? downloadingType,
  }) {
    return DownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      downloadingType: downloadingType ?? this.downloadingType,
    );
  }
}
