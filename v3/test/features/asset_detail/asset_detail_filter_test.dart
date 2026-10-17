import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/asset_detail/application/asset_detail_filter.dart';

Asset _asset(
  String url,
  AssetType type, {
  bool present = true,
  bool invalid = false,
}) => Asset(
  url: url,
  type: type,
  fileKey: fileKeyFromUrl(url),
  path: present ? '/cache/${fileNameFromUrl(url)}.bin' : null,
  invalid: invalid,
);

// The mod under test: 3 images (1 missing, 1 flagged), 1 model (missing),
// 1 PDF (present), 1 audio (present). No asset bundles.
final _imgA = _asset('https://example.com/Alpha.png', AssetType.image);
final _imgB = _asset(
  'https://example.com/beta.png',
  AssetType.image,
  present: false,
);
final _imgC = _asset(
  'https://example.com/gamma.jpg',
  AssetType.image,
  invalid: true,
);
final _model = _asset(
  'https://example.com/mesh.obj',
  AssetType.model,
  present: false,
);
final _pdf = _asset('https://example.com/rules.pdf', AssetType.pdf);
final _audio = _asset('https://example.com/theme.mp3', AssetType.audio);
final _assets = [_imgA, _imgB, _imgC, _model, _pdf, _audio];

List<String> _urls(List<AssetGroup> groups, AssetType type) =>
    groups.singleWhere((g) => g.type == type).assets.map((a) => a.url).toList();

void main() {
  group('AssetDetailFilter', () {
    test('defaults are empty and showPdfThumbnails is not a filter', () {
      expect(AssetDetailFilter.empty.isEmpty, isTrue);
      expect(const AssetDetailFilter(showPdfThumbnails: true).isEmpty, isTrue);
      expect(const AssetDetailFilter(query: '   ').isEmpty, isTrue);
      expect(const AssetDetailFilter(type: AssetType.pdf).isEmpty, isFalse);
      expect(
        const AssetDetailFilter(status: AssetStatusFilter.missing).isEmpty,
        isFalse,
      );
      expect(const AssetDetailFilter(invalidOnly: true).isEmpty, isFalse);
      expect(const AssetDetailFilter(query: 'x').isEmpty, isFalse);
    });

    test('copyWith can clear the type and keeps the rest', () {
      const filter = AssetDetailFilter(
        type: AssetType.image,
        status: AssetStatusFilter.missing,
        invalidOnly: true,
        query: 'q',
        showPdfThumbnails: true,
      );
      expect(filter.copyWith(), filter);
      expect(filter.copyWith(type: null).type, isNull);
      expect(filter.copyWith(type: null).query, 'q');
      expect(filter.copyWith(type: AssetType.pdf).type, AssetType.pdf);
      expect(filter.copyWith(query: '').query, '');
      expect(filter.hashCode, filter.copyWith().hashCode);
    });
  });

  group('groupAssets', () {
    test('no filter: one group per referenced type, in enum order', () {
      final groups = groupAssets(
        _assets,
        AssetDetailFilter.empty,
        invalidUrls: const {},
      );

      expect(groups.map((g) => g.type), [
        AssetType.audio,
        AssetType.image,
        AssetType.model,
        AssetType.pdf,
      ]);
      final images = groups[1];
      expect(images.total, 3);
      expect(images.missing, 1);
      expect(images.present, 2);
      expect(images.isComplete, isFalse);
      expect(images.assets, [_imgA, _imgB, _imgC]);
      final model = groups[2];
      expect(model.total, 1);
      expect(model.missing, 1);
      expect(groups[3].isComplete, isTrue);
      expect(groups[0].assets, [_audio]);
    });

    test('empty input yields no groups', () {
      expect(
        groupAssets(const [], AssetDetailFilter.empty, invalidUrls: const {}),
        isEmpty,
      );
    });

    test('type filter keeps the other groups with empty assets', () {
      final groups = groupAssets(
        _assets,
        const AssetDetailFilter(type: AssetType.pdf),
        invalidUrls: const {},
      );

      expect(groups, hasLength(4));
      expect(_urls(groups, AssetType.pdf), [_pdf.url]);
      expect(_urls(groups, AssetType.image), isEmpty);
      expect(groups.singleWhere((g) => g.type == AssetType.image).total, 3);
    });

    test('status missing / downloaded', () {
      final missing = groupAssets(
        _assets,
        const AssetDetailFilter(status: AssetStatusFilter.missing),
        invalidUrls: const {},
      );
      expect(_urls(missing, AssetType.image), [_imgB.url]);
      expect(_urls(missing, AssetType.model), [_model.url]);
      expect(_urls(missing, AssetType.pdf), isEmpty);
      expect(_urls(missing, AssetType.audio), isEmpty);

      final downloaded = groupAssets(
        _assets,
        const AssetDetailFilter(status: AssetStatusFilter.downloaded),
        invalidUrls: const {},
      );
      expect(_urls(downloaded, AssetType.image), [_imgA.url, _imgC.url]);
      expect(_urls(downloaded, AssetType.model), isEmpty);
      expect(_urls(downloaded, AssetType.pdf), [_pdf.url]);
      expect(_urls(downloaded, AssetType.audio), [_audio.url]);
      // Totals never change with the filter.
      expect(downloaded.map((g) => (g.total, g.missing)), [
        (1, 0),
        (3, 1),
        (1, 1),
        (1, 0),
      ]);
    });

    test('invalidOnly uses the asset flag and the mod list', () {
      final flagged = groupAssets(
        _assets,
        const AssetDetailFilter(invalidOnly: true),
        invalidUrls: const {},
      );
      expect(_urls(flagged, AssetType.image), [_imgC.url]);
      expect(_urls(flagged, AssetType.pdf), isEmpty);

      final withList = groupAssets(
        _assets,
        const AssetDetailFilter(invalidOnly: true),
        invalidUrls: {_pdf.url},
      );
      expect(_urls(withList, AssetType.image), [_imgC.url]);
      expect(_urls(withList, AssetType.pdf), [_pdf.url]);
    });

    test('query is a trimmed, case-insensitive URL substring', () {
      final groups = groupAssets(
        _assets,
        const AssetDetailFilter(query: '  ALPHA '),
        invalidUrls: const {},
      );
      expect(_urls(groups, AssetType.image), [_imgA.url]);
      expect(_urls(groups, AssetType.pdf), isEmpty);

      final byExt = groupAssets(
        _assets,
        const AssetDetailFilter(query: '.png'),
        invalidUrls: const {},
      );
      expect(_urls(byExt, AssetType.image), [_imgA.url, _imgB.url]);
    });

    test('filters combine with AND', () {
      final groups = groupAssets(
        _assets,
        const AssetDetailFilter(
          type: AssetType.image,
          status: AssetStatusFilter.downloaded,
          invalidOnly: true,
          query: 'example',
        ),
        invalidUrls: const {},
      );
      expect(_urls(groups, AssetType.image), [_imgC.url]);
      expect(groups.where((g) => g.assets.isNotEmpty), hasLength(1));

      final none = groupAssets(
        _assets,
        const AssetDetailFilter(
          type: AssetType.image,
          status: AssetStatusFilter.missing,
          invalidOnly: true,
        ),
        invalidUrls: const {},
      );
      expect(none.every((g) => g.assets.isEmpty), isTrue);
      expect(none, hasLength(4), reason: 'totals are still reported');
    });

    test('showPdfThumbnails changes nothing', () {
      expect(
        groupAssets(
          _assets,
          const AssetDetailFilter(showPdfThumbnails: true),
          invalidUrls: const {},
        ),
        groupAssets(_assets, AssetDetailFilter.empty, invalidUrls: const {}),
      );
    });
  });

  group('AssetDetailFilterController', () {
    late ProviderContainer container;
    late AssetDetailFilterController controller;

    setUp(() {
      container = ProviderContainer.test();
      controller = container.read(assetDetailFilterProvider.notifier);
    });

    AssetDetailFilter filter() => container.read(assetDetailFilterProvider);

    test('setType toggles', () {
      controller.setType(AssetType.image);
      expect(filter().type, AssetType.image);
      controller.setType(AssetType.model);
      expect(filter().type, AssetType.model);
      controller.setType(AssetType.model);
      expect(filter().type, isNull);
      controller.setType(AssetType.pdf);
      controller.setType(null);
      expect(filter().type, isNull);
    });

    test('setters replace their field only', () {
      controller
        ..setStatus(AssetStatusFilter.missing)
        ..setInvalidOnly(true)
        ..setQuery('abc')
        ..setShowPdfThumbnails(true)
        ..setType(AssetType.pdf);
      expect(
        filter(),
        const AssetDetailFilter(
          type: AssetType.pdf,
          status: AssetStatusFilter.missing,
          invalidOnly: true,
          query: 'abc',
          showPdfThumbnails: true,
        ),
      );
      controller.setStatus(AssetStatusFilter.all);
      expect(filter().status, AssetStatusFilter.all);
      expect(filter().query, 'abc');
    });

    test('reset clears the filters but keeps the thumbnail toggle', () {
      controller
        ..setStatus(AssetStatusFilter.downloaded)
        ..setInvalidOnly(true)
        ..setQuery('abc')
        ..setShowPdfThumbnails(true)
        ..setType(AssetType.pdf);

      controller.reset();

      expect(filter(), const AssetDetailFilter(showPdfThumbnails: true));
      expect(filter().isEmpty, isTrue);
    });
  });
}
