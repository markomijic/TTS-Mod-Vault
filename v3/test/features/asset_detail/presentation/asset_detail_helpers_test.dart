// The pure helpers behind two clipboard actions of the selected-mod panel:
// what "Copy filename" (asset context menu) and "Copy missing URLs"
// (bottom bar) put on the clipboard.

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_context_menu.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_actions.dart';

import 'asset_detail_test_harness.dart';

void main() {
  group('assetFileName', () {
    test('an asset on disk copies its file name without the extension', () {
      final asset = fixtureAsset(
        'https://example.com/images/img1.png',
        AssetType.image,
        exists: true,
      );
      expect(assetFileName(asset), 'httpsexamplecomimagesimg1png');
    });

    test('a missing asset copies the name TTS gives the URL', () {
      final asset = fixtureAsset(
        'https://example.com/a-b/c.d?x=1',
        AssetType.model,
      );
      expect(assetFileName(asset), 'httpsexamplecomabcdx1');
    });
  });

  group('missingUrlsText', () {
    test('lists the URLs not on disk, one per line, in list order', () {
      final fixture = AssetDetailFixture();
      final text = missingUrlsText([
        fixture.img1,
        fixture.img2,
        fixture.song,
        fixture.model,
        fixture.bundle,
      ]);
      expect(
        text,
        '${fixture.img2.url}\n${fixture.song.url}\n${fixture.bundle.url}',
      );
    });

    test('is empty when every asset is on disk', () {
      final fixture = AssetDetailFixture();
      expect(missingUrlsText([fixture.img1, fixture.model]), isEmpty);
    });
  });
}
