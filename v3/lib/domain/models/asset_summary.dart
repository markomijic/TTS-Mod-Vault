import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';

part 'asset_summary.freezed.dart';

/// Asset counts for one mod, computed by the library summary query.
///
/// Only counts are kept here; the full asset list is loaded on selection.
/// When audio is hidden for a mod (see `AudioVisibility.hideAudio`), audio
/// assets are excluded from [total], [present] and the per-type maps, but
/// [hasAudio] still reports whether the mod references any audio at all so
/// the UI can offer the per-mod override.
@freezed
abstract class AssetSummary with _$AssetSummary {
  const factory AssetSummary({
    required int total,
    required int present,
    required bool hasAudio,
    required Map<AssetType, int> totalByType,
    required Map<AssetType, int> presentByType,
  }) = _AssetSummary;

  const AssetSummary._();

  /// A summary with no assets.
  static const AssetSummary empty = AssetSummary(
    total: 0,
    present: 0,
    hasAudio: false,
    totalByType: {},
    presentByType: {},
  );

  /// Assets referenced by the mod that are not on disk.
  int get missing => total - present;

  /// Whether every counted asset is on disk.
  bool get isComplete => missing == 0;

  /// Referenced assets of [type] (0 when the type is absent or hidden).
  int totalOf(AssetType type) => totalByType[type] ?? 0;

  /// On-disk assets of [type] (0 when the type is absent or hidden).
  int presentOf(AssetType type) => presentByType[type] ?? 0;

  /// Missing assets of [type].
  int missingOf(AssetType type) => totalOf(type) - presentOf(type);
}
