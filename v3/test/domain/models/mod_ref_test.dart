import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';

void main() {
  group('modIdFromPath', () {
    test('strips a .json extension, case-insensitively', () {
      expect(modIdFromPath(p.join('Workshop', '123456.json')), '123456');
      expect(modIdFromPath(p.join('Saves', 'TS_Save_1.JSON')), 'TS_Save_1');
    });

    test('keeps other extensions and dotted names', () {
      expect(modIdFromPath(p.join('x', 'notes.txt')), 'notes.txt');
      expect(modIdFromPath(p.join('x', 'My.Mod.v2.json')), 'My.Mod.v2');
    });

    test('a bare ".json" file name is kept as is', () {
      expect(modIdFromPath('.json'), '.json');
    });
  });

  group('ModRef.fromPath', () {
    test('normalises the path and derives the id', () {
      final raw = p.join(
        'C:',
        'TTS',
        'Mods',
        'Workshop',
        '..',
        'Workshop',
        '42.json',
      );
      final ref = ModRef.fromPath(ModType.mod, raw);
      expect(ref.jsonPath, p.normalize(raw));
      expect(ref.id, '42');
      expect(ref.type, ModType.mod);
      expect(ref.fileName, '42.json');
    });

    test('two references to the same file are equal', () {
      final a = ModRef.fromPath(ModType.save, p.join('Saves', 'a.json'));
      final b = ModRef.fromPath(ModType.save, p.join('Saves', '.', 'a.json'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith keeps unrelated fields', () {
      final ref = ModRef.fromPath(ModType.mod, p.join('Workshop', '1.json'));
      final copy = ref.copyWith(type: ModType.savedObject);
      expect(copy.type, ModType.savedObject);
      expect(copy.id, '1');
      expect(copy.jsonPath, ref.jsonPath);
    });
  });
}
