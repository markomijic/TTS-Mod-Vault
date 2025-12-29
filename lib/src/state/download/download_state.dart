import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

class DownloadState {
  final bool downloadingAssets;
  final bool downloadingMods;
  final bool cancelledDownloads;
  final double progress;
  final AssetTypeEnum? downloadingType;

  const DownloadState({
    this.downloadingAssets = false,
    this.downloadingMods = false,
    this.cancelledDownloads = false,
    this.progress = 0.0,
    this.downloadingType,
  });

  DownloadState copyWith({
    bool? downloadingAssets,
    bool? downloadingMods,
    bool? cancelledDownloads,
    double? progress,
    AssetTypeEnum? downloadingType,
  }) {
    return DownloadState(
      downloadingAssets: downloadingAssets ?? this.downloadingAssets,
      downloadingMods: downloadingMods ?? this.downloadingMods,
      cancelledDownloads: cancelledDownloads ?? this.cancelledDownloads,
      progress: progress ?? this.progress,
      downloadingType: downloadingType ?? this.downloadingType,
    );
  }
}
