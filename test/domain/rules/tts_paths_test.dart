import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/rules/tts_paths.dart';

void main() {
  bool never(String _) => false;

  group('defaultTtsDirectory / defaultDirectories', () {
    test('windows uses Documents/My Games', () {
      const home = r'C:\Users\Marko';
      final tts = defaultTtsDirectory(
        platform: 'windows',
        home: home,
        directoryExists: never,
      );
      expect(tts, r'C:\Users\Marko\Documents\My Games\Tabletop Simulator');

      final dirs = defaultDirectories(
        platform: 'windows',
        home: home,
        directoryExists: never,
      );
      expect(dirs.modsDir, p.windows.join(tts, 'Mods'));
      expect(dirs.savesDir, p.windows.join(tts, 'Saves'));
      expect(dirs.backupsDir, '');
    });

    test('macos uses Library/Tabletop Simulator', () {
      const home = '/Users/marko';
      final tts = defaultTtsDirectory(
        platform: 'macos',
        home: home,
        directoryExists: never,
      );
      expect(tts, '/Users/marko/Library/Tabletop Simulator');

      final dirs = defaultDirectories(
        platform: 'macos',
        home: home,
        directoryExists: never,
      );
      expect(dirs.modsDir, '/Users/marko/Library/Tabletop Simulator/Mods');
      expect(dirs.savesDir, '/Users/marko/Library/Tabletop Simulator/Saves');
    });

    test('linux prefers the Steam snap folder when it exists', () {
      const home = '/home/marko';
      const snap =
          '/home/marko/snap/steam/common/.local/share/Tabletop Simulator';
      final checked = <String>[];
      final tts = defaultTtsDirectory(
        platform: 'linux',
        home: home,
        directoryExists: (path) {
          checked.add(path);
          return path == snap;
        },
      );
      expect(tts, snap);
      expect(checked, [snap]);
    });

    test('linux falls back to .local/share without the snap folder', () {
      final dirs = defaultDirectories(
        platform: 'linux',
        home: '/home/marko',
        directoryExists: never,
      );
      expect(dirs.modsDir, '/home/marko/.local/share/Tabletop Simulator/Mods');
      expect(
        dirs.savesDir,
        '/home/marko/.local/share/Tabletop Simulator/Saves',
      );
    });

    test('unknown platforms behave like linux', () {
      expect(
        defaultTtsDirectory(
          platform: 'fuchsia',
          home: '/home/x',
          directoryExists: never,
        ),
        '/home/x/.local/share/Tabletop Simulator',
      );
    });

    test('windows and macos never consult the file system', () {
      var calls = 0;
      bool counting(String _) {
        calls++;
        return true;
      }

      defaultTtsDirectory(
        platform: 'windows',
        home: r'C:\U',
        directoryExists: counting,
      );
      defaultTtsDirectory(
        platform: 'macos',
        home: '/u',
        directoryExists: counting,
      );
      expect(calls, 0);
    });
  });

  group('resolveModsDir', () {
    final tts = p.join('C:', 'TTS');
    final modsDir = p.join(tts, 'Mods');

    DirectoryExists existsIn(Set<String> dirs) =>
        (String path) => dirs.contains(path);

    test('accepts the Mods folder itself', () {
      expect(
        resolveModsDir(modsDir, directoryExists: existsIn({modsDir})),
        modsDir,
      );
    });

    test('normalises a trailing separator before matching', () {
      expect(
        resolveModsDir(
          '$modsDir${p.separator}',
          directoryExists: existsIn({modsDir}),
        ),
        modsDir,
      );
    });

    test('accepts the parent and resolves to its Mods child', () {
      expect(
        resolveModsDir(tts, directoryExists: existsIn({tts, modsDir})),
        modsDir,
      );
    });

    test('rejects a parent without a Mods child', () {
      expect(resolveModsDir(tts, directoryExists: existsIn({tts})), isNull);
    });

    test('rejects a folder that does not exist', () {
      expect(resolveModsDir(modsDir, directoryExists: never), isNull);
    });

    test('a folder merely ending in "Mods" is treated as a parent', () {
      final myMods = p.join(tts, 'MyMods');
      expect(
        resolveModsDir(myMods, directoryExists: existsIn({myMods})),
        isNull,
      );
      final child = p.join(myMods, 'Mods');
      expect(
        resolveModsDir(myMods, directoryExists: existsIn({myMods, child})),
        child,
      );
    });
  });

  group('resolveSavesDir', () {
    final tts = p.join('C:', 'TTS');
    final savesDir = p.join(tts, 'Saves');
    final custom = p.join('D:', 'MySaves');

    DirectoryExists existsIn(Set<String> dirs) =>
        (String path) => dirs.contains(path);

    test('accepts the Saves folder itself and the parent', () {
      expect(
        resolveSavesDir(savesDir, directoryExists: existsIn({savesDir})),
        savesDir,
      );
      expect(
        resolveSavesDir(tts, directoryExists: existsIn({tts, savesDir})),
        savesDir,
      );
      expect(resolveSavesDir(tts, directoryExists: existsIn({tts})), isNull);
    });

    test('rejects an arbitrary folder unless allowCustomPath is set', () {
      expect(
        resolveSavesDir(custom, directoryExists: existsIn({custom})),
        isNull,
      );
      expect(
        resolveSavesDir(
          custom,
          allowCustomPath: true,
          directoryExists: existsIn({custom}),
        ),
        custom,
      );
    });

    test('allowCustomPath still requires the folder to exist', () {
      expect(
        resolveSavesDir(custom, allowCustomPath: true, directoryExists: never),
        isNull,
      );
    });

    test('allowCustomPath returns the folder as picked, not a child', () {
      expect(
        resolveSavesDir(
          tts,
          allowCustomPath: true,
          directoryExists: existsIn({tts, savesDir}),
        ),
        tts,
      );
    });
  });
}
