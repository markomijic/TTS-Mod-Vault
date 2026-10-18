import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/asset_detail_filter.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_list.dart';

import 'asset_detail_test_harness.dart';

void main() {
  final fixture = AssetDetailFixture();

  List<AssetGroup> groups(AssetDetailFilter filter) =>
      groupAssets(fixture.alphaAssets, filter, invalidUrls: const {});

  test('one header per group followed by its URL rows', () {
    final rows = buildAssetListRows(
      groups(AssetDetailFilter.empty),
      showPdfThumbnails: false,
    );

    expect(rows.whereType<HeaderRow>().map((r) => r.type), [
      AssetType.assetBundle,
      AssetType.audio,
      AssetType.image,
      AssetType.model,
      AssetType.pdf,
    ]);
    // 5 headers + 6 URLs; nothing else.
    expect(rows, hasLength(11));
    expect(
      rows.whereType<UrlRow>().map((r) => r.asset),
      fixture.alphaAssets.toSet(),
    );
    expect(rows.whereType<PdfGridRow>(), isEmpty);
    // Only the first header is flagged first.
    expect(rows.whereType<HeaderRow>().map((r) => r.isFirst), [
      true,
      false,
      false,
      false,
      false,
    ]);
    // Missing flag follows the group's missing count.
    final byType = {for (final r in rows.whereType<HeaderRow>()) r.type: r};
    expect(byType[AssetType.image]!.hasMissing, isTrue);
    expect(byType[AssetType.model]!.hasMissing, isFalse);
    expect(byType[AssetType.pdf]!.hasMissing, isFalse);
  });

  test('PDF group collapses to one grid row while thumbnails are on', () {
    final rows = buildAssetListRows(
      groups(AssetDetailFilter.empty),
      showPdfThumbnails: true,
    );

    final pdfIndex = rows.indexWhere(
      (r) => r is HeaderRow && r.type == AssetType.pdf,
    );
    expect(rows[pdfIndex + 1], isA<PdfGridRow>());
    expect((rows[pdfIndex + 1] as PdfGridRow).assets, [fixture.doc]);
    expect(
      rows.whereType<UrlRow>().map((r) => r.asset),
      isNot(contains(fixture.doc)),
    );
    expect(rows, hasLength(11)); // 5 headers + 5 URLs + 1 grid
  });

  test('filtered-out groups produce no rows and the first header moves', () {
    final rows = buildAssetListRows(
      groups(const AssetDetailFilter(status: AssetStatusFilter.downloaded)),
      showPdfThumbnails: false,
    );

    // Asset bundles and audio are missing, so their groups are gone.
    expect(rows.whereType<HeaderRow>().map((r) => r.type), [
      AssetType.image,
      AssetType.model,
      AssetType.pdf,
    ]);
    expect(
      rows.first,
      isA<HeaderRow>().having((r) => r.isFirst, 'isFirst', true),
    );
    expect(rows.whereType<UrlRow>().map((r) => r.asset), [
      fixture.img1,
      fixture.model,
      fixture.doc,
    ]);
  });

  test('a filter matching nothing yields an empty list', () {
    final rows = buildAssetListRows(
      groups(const AssetDetailFilter(query: 'nothing-here')),
      showPdfThumbnails: true,
    );
    expect(rows, isEmpty);
  });
}
