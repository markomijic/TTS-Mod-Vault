import 'dart:convert' show base64Decode;
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/images_viewer/presentation/asset_file_actions.dart';
import 'package:tts_mod_vault/features/images_viewer/presentation/images_viewer_grid_card.dart';
import 'package:tts_mod_vault/features/images_viewer/presentation/images_viewer_page.dart';

import 'themed_app.dart';

/// A 1x1 transparent PNG.
final List<int> _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

Mod _mod(String name) => Mod(
  ref: ModRef.fromPath(ModType.mod, p.join('C:', 'Mods', 'Workshop', '1.json')),
  saveName: name,
  folder: 'Workshop',
  epochTime: null,
  modified: DateTime(2024),
  sizeBytes: 1,
  imagePath: null,
  audio: AudioVisibility.useGlobalSetting,
  summary: const AssetSummary(
    total: 0,
    present: 0,
    hasAudio: false,
    totalByType: {},
    presentByType: {},
  ),
);

Asset _asset(String url, AssetType type, {String? path}) =>
    Asset(url: url, type: type, fileKey: url, path: path);

void main() {
  late Directory dir;
  late String pngA;
  late String pngB;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('ttsmv_images_viewer');
    pngA = p.join(dir.path, 'a.png');
    pngB = p.join(dir.path, 'b.png');
    File(pngA).writeAsBytesSync(_onePixelPng);
    File(pngB).writeAsBytesSync(_onePixelPng);
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  group('urlTail', () {
    test('takes the last path segment, ignoring trailing slash and query', () {
      expect(urlTail('https://h/ugc/123/ABCDEF/'), 'ABCDEF');
      expect(urlTail('https://h/a/b/pic.png?x=1'), 'pic.png');
      expect(urlTail('pic.png'), 'pic.png');
      expect(urlTail('https://'), 'https://');
    });
  });

  group('downloadedImages', () {
    test('keeps image assets that are on disk', () {
      final assets = [
        _asset('u1', AssetType.image, path: 'p1'),
        _asset('u2', AssetType.image),
        _asset('u3', AssetType.model, path: 'p3'),
        _asset('u4', AssetType.pdf),
      ];
      expect(downloadedImages(assets).map((a) => a.url), ['u1']);
    });
  });

  testWidgets('shows only downloaded images with the count in the title', (
    tester,
  ) async {
    final mod = _mod('Alpha Mod');
    await pumpThemedApp(
      tester,
      home: ImagesViewerPage(mod: mod),
      overrides: [
        modAssetsProvider.overrideWith((ref, jsonPath) async {
          expect(jsonPath, mod.jsonPath);
          return [
            _asset('https://h/ugc/1/AAA/', AssetType.image, path: pngA),
            _asset('https://h/ugc/1/BBB/', AssetType.image, path: pngB),
            _asset('https://h/ugc/1/CCC/', AssetType.image),
            _asset('https://h/ugc/1/DDD.obj', AssetType.model, path: pngA),
          ];
        }),
      ],
    );

    expect(find.text('Alpha Mod – 2 images'), findsOneWidget);
    expect(find.byType(ImagesViewerGridCard), findsNWidgets(2));
    expect(find.text('AAA'), findsOneWidget);
    expect(find.text('BBB'), findsOneWidget);
    expect(find.text('CCC'), findsNothing);
    expect(find.text('DDD.obj'), findsNothing);
    expect(find.byTooltip('https://h/ugc/1/AAA/'), findsOneWidget);
  });

  testWidgets('shows the empty state when no image is downloaded', (
    tester,
  ) async {
    await pumpThemedApp(
      tester,
      home: ImagesViewerPage(mod: _mod('Beta Mod')),
      overrides: [
        modAssetsProvider.overrideWith(
          (ref, jsonPath) async => [
            _asset('https://h/ugc/1/CCC/', AssetType.image),
          ],
        ),
      ],
    );

    expect(find.text('Beta Mod – 0 images'), findsOneWidget);
    expect(find.text('No downloaded images'), findsOneWidget);
    expect(find.byType(ImagesViewerGridCard), findsNothing);
  });

  testWidgets('right-click on a tile shows the file menu', (tester) async {
    await pumpThemedApp(
      tester,
      home: ImagesViewerPage(mod: _mod('Alpha Mod')),
      overrides: [
        modAssetsProvider.overrideWith(
          (ref, jsonPath) async => [
            _asset('https://h/ugc/1/AAA/', AssetType.image, path: pngA),
          ],
        ),
      ],
    );

    await tester.tap(
      find.byType(ImagesViewerGridCard),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Open file'), findsOneWidget);
    expect(find.text('Open in file explorer'), findsOneWidget);
    expect(find.text('Copy URL'), findsOneWidget);
  });

  testWidgets('openImagesViewer pushes the page; Back and Esc pop it', (
    tester,
  ) async {
    final mod = _mod('Alpha Mod');
    await pumpThemedApp(
      tester,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => openImagesViewer(context, mod),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      overrides: [
        modAssetsProvider.overrideWith((ref, jsonPath) async => const []),
      ],
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ImagesViewerPage), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ImagesViewerPage), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ImagesViewerPage), findsNothing);
  });
}
