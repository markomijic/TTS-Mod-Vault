import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

class DownloadState {
  final bool downloading;
  final bool cancelledDownloads;
  final double progress;
  final AssetTypeEnum? downloadingType;

  const DownloadState({
    this.downloading = false,
    this.cancelledDownloads = false,
    this.progress = 0.0,
    this.downloadingType,
  });

  DownloadState copyWith({
    bool? downloading,
    bool? cancelledDownloads,
    double? progress,
    AssetTypeEnum? downloadingType,
  }) {
    return DownloadState(
      downloading: downloading ?? this.downloading,
      cancelledDownloads: cancelledDownloads ?? this.cancelledDownloads,
      progress: progress ?? this.progress,
      downloadingType: downloadingType ?? this.downloadingType,
    );
  }
}
