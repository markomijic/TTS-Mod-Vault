import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/fs/zip/zip_asset_counter.dart';

import 'zip_fixtures.dart';

void main() {
  group('ZipAssetCounter.countAssetsFromFileNames', () {
    test('counts files under the five asset prefixes only', () {
      expect(
        ZipAssetCounter.countAssetsFromFileNames([
          'Mods/Assetbundles/a.unity3d',
          'Mods/Audio/b.mp3',
          'Mods/Images/c.png',
          'Mods/PDF/d.pdf',
          'Mods/Models/e.obj',
          'Mods/Images/nested/f.png', // prefix match, still counted
          'Mods/Workshop/123.json',
          'Mods/Workshop/123.png',
          'Mods/Images Raw/g.png',
          'Mods/Models Raw/h.obj',
          'Mods/Text/i.txt',
          'mods/images/lowercase.png', // prefixes are case-sensitive
          'Saves/1.json',
        ]),
        6,
      );
    });

    test('skips directory entries', () {
      expect(
        ZipAssetCounter.countAssetsFromFileNames([
          'Mods/',
          'Mods/Images/',
          'Mods/Images/Sub/',
          'Mods/Models/',
          'Mods/Models/real.obj',
        ]),
        1,
      );
    });

    test('is zero for an empty list', () {
      expect(ZipAssetCounter.countAssetsFromFileNames(const []), 0);
    });
  });

  group('ZipAssetCounter.countAssetsWith / countBackupAssetsWith', () {
    late MemoryFileSystem fs;

    final backup = <String, List<int>>{
      'Mods/Workshop/123.json': [1],
      'Mods/Workshop/123.png': [2],
      'Mods/Images/a.png': [3],
      'Mods/Images/b.jpg': [4],
      'Mods/Models/c.obj': [5],
      'Mods/PDF/d.pdf': [6],
      'Mods/Audio/e.mp3': [7],
      'Mods/Assetbundles/f.unity3d': [8],
    };

    setUp(() {
      fs = MemoryFileSystem.test();
      fs.directory('/b').createSync();
    });

    test('counts assets of a real archive', () async {
      fs
          .file('/b/one.ttsmod')
          .writeAsBytesSync(
            buildZip(backup, directories: ['Mods/Images', 'Mods/Text']),
          );

      expect(await ZipAssetCounter.countAssetsWith('/b/one.ttsmod', fs), 6);
    });

    test('counts assets of a backslash-named archive', () async {
      fs
          .file('/b/bs.ttsmod')
          .writeAsBytesSync(
            withBackslashNames(buildZip(backup), backup.keys.toList()),
          );

      expect(await ZipAssetCounter.countAssetsWith('/b/bs.ttsmod', fs), 6);
    });

    test('returns 0 for missing or unreadable archives', () async {
      fs.file('/b/garbage.ttsmod').writeAsBytesSync(List.filled(100, 1));

      expect(await ZipAssetCounter.countAssetsWith('/b/missing.ttsmod', fs), 0);
      expect(await ZipAssetCounter.countAssetsWith('/b/garbage.ttsmod', fs), 0);
    });

    test('countBackupAssetsWith returns counts in request order', () async {
      fs.file('/b/full.ttsmod').writeAsBytesSync(buildZip(backup));
      fs
          .file('/b/two.ttsmod')
          .writeAsBytesSync(
            buildZip({
              'Mods/Images/x.png': [1],
              'Mods/Images/y.png': [2],
            }),
          );
      fs
          .file('/b/none.ttsmod')
          .writeAsBytesSync(
            buildZip({
              'Mods/Workshop/1.json': [1],
            }),
          );

      final counts = await countBackupAssetsWith([
        '/b/two.ttsmod',
        '/b/missing.ttsmod',
        '/b/full.ttsmod',
        '/b/none.ttsmod',
      ], fs);

      expect(counts, [2, 0, 6, 0]);
    });

    test('countBackupAssetsWith of an empty list is empty', () async {
      expect(await countBackupAssetsWith(const [], fs), isEmpty);
    });
  });
}
