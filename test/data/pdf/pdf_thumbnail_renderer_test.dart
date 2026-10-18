import 'dart:async';
import 'dart:io' show FileSystemException;

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show ProviderContainer;
import 'package:pdfrx_engine/pdfrx_engine.dart' show PdfDocument, PdfPage;
import 'package:tts_mod_vault/data/pdf/pdf_thumbnail_renderer.dart';

/// A [PdfDocument] with no pages that records disposal; everything else
/// throws through [Fake].
final class _EmptyDocument extends Fake implements PdfDocument {
  bool disposed = false;

  @override
  List<PdfPage> get pages => const [];

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  group('RenderGate', () {
    test('runs at most maxConcurrent bodies at once, in FIFO order', () async {
      final gate = RenderGate();
      var active = 0;
      var peak = 0;
      final started = <int>[];
      final releases = <Completer<void>>[];

      Future<int> body(int id) => gate.run(() async {
        active++;
        peak = active > peak ? active : peak;
        started.add(id);
        final release = Completer<void>();
        releases.add(release);
        await release.future;
        active--;
        return id;
      });

      final futures = [for (var i = 0; i < 4; i++) body(i)];
      await pumpEventQueue();

      expect(started, [0]);
      expect(gate.active, 1);
      expect(gate.waiting, 3);

      releases[0].complete();
      await pumpEventQueue();
      expect(started, [0, 1]);
      expect(gate.waiting, 2);

      releases[1].complete();
      await pumpEventQueue();
      expect(started, [0, 1, 2]);
      releases[2].complete();
      await pumpEventQueue();
      // Body 3 only started after 2 released; 2 only after 1 released.
      expect(started, [0, 1, 2, 3]);
      releases[3].complete();

      expect(await Future.wait(futures), [0, 1, 2, 3]);
      expect(peak, 1);
      expect(gate.active, 0);
      expect(gate.waiting, 0);
    });

    test('releases the permit when the body throws', () async {
      final gate = RenderGate();
      await expectLater(
        gate.run<void>(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(gate.active, 0);
      expect(await gate.run(() async => 42), 42);
    });

    test('honours a wider gate', () async {
      final gate = RenderGate(maxConcurrent: 2);
      final blockers = [Completer<void>(), Completer<void>()];
      final futures = [
        for (final blocker in blockers) gate.run(() => blocker.future),
      ];
      await pumpEventQueue();
      expect(gate.active, 2);
      expect(gate.waiting, 0);
      for (final blocker in blockers) {
        blocker.complete();
      }
      await Future.wait(futures);
      expect(gate.active, 0);
    });
  });

  group('PdfrxThumbnailRenderer', () {
    test('returns null when the document cannot be opened and releases '
        'the gate', () async {
      final gate = RenderGate();
      final renderer = PdfrxThumbnailRenderer(
        gate: gate,
        openDocument: (path) async =>
            throw const FileSystemException('missing', 'nope.pdf'),
      );

      expect(await renderer.renderFirstPage('nope.pdf'), isNull);
      expect(gate.active, 0);
      expect(gate.waiting, 0);
    });

    test('returns null for a document without pages and disposes it', () async {
      final doc = _EmptyDocument();
      final renderer = PdfrxThumbnailRenderer(openDocument: (_) async => doc);

      expect(await renderer.renderFirstPage('empty.pdf'), isNull);
      expect(doc.disposed, isTrue);
    });

    test('serialises renders through the gate', () async {
      final opens = <String>[];
      final release = Completer<void>();
      final renderer = PdfrxThumbnailRenderer(
        openDocument: (path) async {
          opens.add(path);
          await release.future;
          throw StateError('not a pdf');
        },
      );

      final first = renderer.renderFirstPage('a.pdf');
      final second = renderer.renderFirstPage('b.pdf');
      await pumpEventQueue();
      expect(opens, ['a.pdf']);

      release.complete();
      expect(await first, isNull);
      expect(await second, isNull);
      expect(opens, ['a.pdf', 'b.pdf']);
    });

    test('provider builds the pdfrx renderer', () {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      expect(
        container.read(pdfThumbnailRendererProvider),
        isA<PdfrxThumbnailRenderer>(),
      );
    });
  });
}
