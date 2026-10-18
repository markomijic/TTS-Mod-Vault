import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/data/pdf/pdf_thumbnail_renderer.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/pdf_thumbnail.dart';

import '../../images_viewer/themed_app.dart';

/// A 1x1 transparent PNG.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// Renderer double: records requested paths and answers from a completer.
final class _FakeRenderer implements PdfThumbnailRenderer {
  final List<String> paths = [];
  final List<double> dpis = [];
  final Completer<Uint8List?> completer = Completer();

  @override
  Future<Uint8List?> renderFirstPage(
    String path, {
    double dpi = defaultPdfThumbnailDpi,
  }) {
    paths.add(path);
    dpis.add(dpi);
    return completer.future;
  }
}

const _asset = Asset(
  url: 'https://h/ugc/9/RULES/',
  type: AssetType.pdf,
  fileKey: 'k',
  path: r'C:\Mods\PDF\rules.pdf',
);

final Mod _mod = Mod(
  ref: ModRef.fromPath(ModType.mod, p.join('C:', 'Mods', 'Workshop', '1.json')),
  saveName: 'Alpha Mod',
  folder: 'Workshop',
  epochTime: null,
  modified: DateTime(2024),
  sizeBytes: 1,
  imagePath: null,
  audio: AudioVisibility.useGlobalSetting,
  summary: const AssetSummary(
    total: 1,
    present: 1,
    hasAudio: false,
    totalByType: {AssetType.pdf: 1},
    presentByType: {AssetType.pdf: 1},
  ),
);

Future<_FakeRenderer> _pumpTile(WidgetTester tester, Asset asset) async {
  final renderer = _FakeRenderer();
  await pumpThemedApp(
    tester,
    home: Scaffold(
      body: Center(
        child: PdfThumbnail(mod: _mod, asset: asset),
      ),
    ),
    overrides: [pdfThumbnailRendererProvider.overrideWithValue(renderer)],
  );
  return renderer;
}

void main() {
  testWidgets('renders after the delay and shows the image', (tester) async {
    final renderer = await _pumpTile(tester, _asset);

    // Placeholder, caption and tooltip before anything was requested.
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text('RULES'), findsOneWidget);
    expect(find.byTooltip(_asset.url), findsOneWidget);
    expect(renderer.paths, isEmpty);

    await tester.pump(pdfThumbnailRenderDelay);
    await tester.pump();
    expect(renderer.paths, [_asset.path]);
    expect(renderer.dpis, [defaultPdfThumbnailDpi]);
    // Still the placeholder while the render is in flight.
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);

    renderer.completer.complete(_onePixelPng);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
    expect(find.text('Could not render PDF'), findsNothing);

    final size = tester.getSize(find.byType(PdfThumbnail));
    expect(size, const Size(192, 192));
  });

  testWidgets('a null render shows the failure placeholder', (tester) async {
    final renderer = await _pumpTile(tester, _asset);
    await tester.pump(pdfThumbnailRenderDelay);
    await tester.pump();
    renderer.completer.complete(null);
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.text('Could not render PDF'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
  });

  testWidgets('a missing file shows "Not downloaded" and never renders', (
    tester,
  ) async {
    final renderer = await _pumpTile(tester, _asset.copyWith(path: null));
    await tester.pump(pdfThumbnailRenderDelay * 2);
    await tester.pump();

    expect(renderer.paths, isEmpty);
    expect(find.text('Not downloaded'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
  });

  testWidgets('a tile removed before the delay never renders', (tester) async {
    final renderer = _FakeRenderer();
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    await pumpThemedApp(
      tester,
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: show,
          builder: (context, visible, _) => visible
              ? PdfThumbnail(mod: _mod, asset: _asset)
              : const SizedBox(),
        ),
      ),
      overrides: [pdfThumbnailRendererProvider.overrideWithValue(renderer)],
    );

    await tester.pump(pdfThumbnailRenderDelay ~/ 2);
    show.value = false;
    await tester.pump(pdfThumbnailRenderDelay);
    await tester.pump();
    expect(renderer.paths, isEmpty);
  });

  testWidgets('respects a custom size', (tester) async {
    await pumpThemedApp(
      tester,
      home: Scaffold(
        body: Center(
          child: PdfThumbnail(mod: _mod, asset: _asset, size: 96),
        ),
      ),
      overrides: [
        pdfThumbnailRendererProvider.overrideWithValue(_FakeRenderer()),
      ],
    );
    expect(tester.getSize(find.byType(PdfThumbnail)), const Size(96, 96));
  });

  testWidgets('right-click shows the full asset context menu', (tester) async {
    await _pumpTile(tester, _asset);
    await tester.tap(find.byType(PdfThumbnail), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    for (final label in [
      'Open URL in browser',
      'Copy URL',
      'Copy filename',
      'Open file',
      'Open in file explorer',
      'Replace URL…',
      'Check URL',
      'Shared with…',
      'Delete file',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // The file is on disk, so Download is not offered.
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('right-click on a missing file offers Download, no file items', (
    tester,
  ) async {
    await _pumpTile(tester, _asset.copyWith(path: null));
    await tester.tap(find.byType(PdfThumbnail), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Open file'), findsNothing);
    expect(find.text('Delete file'), findsNothing);
    expect(find.text('Check URL'), findsOneWidget);
  });
}
