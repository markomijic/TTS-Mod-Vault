import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';

void main() {
  final mods = p.join('C:', 'TTS', 'Mods');
  final saves = p.join('C:', 'TTS', 'Saves');
  final backups = p.join('D:', 'Backups');
  final dirs = Directories(modsDir: mods, savesDir: saves, backupsDir: backups);

  test('derived folders are joined with package:path', () {
    expect(dirs.workshopDir, p.join(mods, 'Workshop'));
    expect(dirs.savedObjectsDir, p.join(saves, 'Saved Objects'));
    expect(dirs.thumbnailsDir, p.join(mods, 'Thumbnails'));
    expect(dirs.assetDir(AssetType.assetBundle), p.join(mods, 'Assetbundles'));
    expect(dirs.assetDir(AssetType.audio), p.join(mods, 'Audio'));
    expect(dirs.assetDir(AssetType.image), p.join(mods, 'Images'));
    expect(dirs.assetDir(AssetType.model), p.join(mods, 'Models'));
    expect(dirs.assetDir(AssetType.pdf), p.join(mods, 'PDF'));
  });

  test('raw folders exist only for images and models', () {
    expect(dirs.rawAssetDir(AssetType.image), p.join(mods, 'Images Raw'));
    expect(dirs.rawAssetDir(AssetType.model), p.join(mods, 'Models Raw'));
    expect(dirs.rawAssetDir(AssetType.audio), isNull);
    expect(dirs.rawAssetDir(AssetType.pdf), isNull);
    expect(dirs.rawAssetDir(AssetType.assetBundle), isNull);
  });

  test('a trailing separator on the root does not double up', () {
    final withSep = dirs.copyWith(modsDir: '$mods${p.separator}');
    expect(withSep.workshopDir, p.join(mods, 'Workshop'));
    expect(
      withSep.workshopDir.contains('${p.separator}${p.separator}'),
      isFalse,
    );
  });

  test('no derived path uses a hard-coded forward slash on this host', () {
    final derived = [
      dirs.workshopDir,
      dirs.savedObjectsDir,
      dirs.thumbnailsDir,
      for (final t in AssetType.values) dirs.assetDir(t),
      for (final t in AssetType.values) ?dirs.rawAssetDir(t),
    ];
    for (final path in derived) {
      // Only the host separator may appear between the root and the leaf.
      expect(path.startsWith(mods) || path.startsWith(saves), isTrue);
      final tail = path.substring(
        path.startsWith(mods) ? mods.length : saves.length,
      );
      expect(tail.startsWith(p.separator), isTrue, reason: path);
      expect(tail.substring(1).contains('/'), isFalse, reason: path);
      expect(tail.substring(1).contains(r'\'), isFalse, reason: path);
    }
  });

  test('empty and hasBackupsDir', () {
    expect(Directories.empty.modsDir, '');
    expect(Directories.empty.savesDir, '');
    expect(Directories.empty.backupsDir, '');
    expect(Directories.empty.hasBackupsDir, isFalse);
    expect(dirs.hasBackupsDir, isTrue);
    expect(const Directories(modsDir: 'm', savesDir: 's').backupsDir, '');
  });

  test('json round trip', () {
    final json = dirs.toJson();
    expect(json, {'modsDir': mods, 'savesDir': saves, 'backupsDir': backups});
    expect(Directories.fromJson(json), dirs);
  });

  test('copyWith replaces one root and re-derives from it', () {
    final other = p.join('E:', 'Other', 'Mods');
    final copy = dirs.copyWith(modsDir: other);
    expect(copy.workshopDir, p.join(other, 'Workshop'));
    expect(copy.savesDir, saves);
    expect(copy.backupsDir, backups);
  });
}
