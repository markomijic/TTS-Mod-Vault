import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/domain/parsing/version_compare.dart';

void main() {
  group('isNewerVersion', () {
    test('v2 semantics for plain three-part versions', () {
      expect(isNewerVersion('2.1.0', '2.1.1'), isTrue);
      expect(isNewerVersion('2.1.0', '2.2.0'), isTrue);
      expect(isNewerVersion('2.1.0', '3.0.0'), isTrue);
      expect(isNewerVersion('2.1.0', '2.1.0'), isFalse);
      expect(isNewerVersion('2.1.1', '2.1.0'), isFalse);
      expect(isNewerVersion('3.0.0', '2.9.9'), isFalse);
    });

    test('components compare numerically, not lexically', () {
      expect(isNewerVersion('2.9.0', '2.10.0'), isTrue);
      expect(isNewerVersion('2.10.0', '2.9.0'), isFalse);
    });

    test('tolerates a leading v on either side', () {
      expect(isNewerVersion('2.1.0', 'v2.1.1'), isTrue);
      expect(isNewerVersion('v2.1.0', '2.1.1'), isTrue);
      expect(isNewerVersion('V2.1.0', 'v2.1.0'), isFalse);
    });

    test('missing components count as zero', () {
      expect(isNewerVersion('3.0', '3.0.0'), isFalse);
      expect(isNewerVersion('3.0.0', '3.0'), isFalse);
      expect(isNewerVersion('3', '3.0.1'), isTrue);
      expect(isNewerVersion('3.0.0', '3.0.0.1'), isTrue);
    });

    test('ignores pre-release and build suffixes', () {
      expect(isNewerVersion('3.0.0-dev', '3.0.0'), isFalse);
      expect(isNewerVersion('3.0.0', '3.0.0-dev'), isFalse);
      expect(isNewerVersion('3.0.0-dev', '3.0.1'), isTrue);
      expect(isNewerVersion('3.0.0+1', '3.0.1+2'), isTrue);
      expect(isNewerVersion('2.1.0', '3.0.0-beta.1'), isTrue);
    });

    test('never throws on garbage', () {
      expect(isNewerVersion('', ''), isFalse);
      expect(isNewerVersion('abc', 'def'), isFalse);
      expect(isNewerVersion('abc', '0.0.1'), isTrue);
      expect(isNewerVersion(' 2.1.0 ', '2.1.1'), isTrue);
    });
  });
}
