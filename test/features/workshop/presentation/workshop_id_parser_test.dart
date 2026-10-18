import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/features/workshop/presentation/workshop_id_parser.dart';

void main() {
  test('plain ids separated by commas, spaces, semicolons and newlines', () {
    expect(parseWorkshopIds('123, 456 789;321\n654\r\n987'), [
      '123',
      '456',
      '789',
      '321',
      '654',
      '987',
    ]);
  });

  test('Workshop URLs yield the id query parameter', () {
    expect(
      parseWorkshopIds(
        'https://steamcommunity.com/sharedfiles/filedetails/?id=2971190123\n'
        'steamcommunity.com/workshop/filedetails/?id=1234&searchtext=x\n'
        'https://steamcommunity.com/sharedfiles/filedetails/?l=en&id=55',
      ),
      ['2971190123', '1234', '55'],
    );
  });

  test('ignores junk, drops duplicates and keeps the first order', () {
    expect(
      parseWorkshopIds(
        '12ab, abc, https://example.com/?foo=1, 999, 999, '
        'https://steamcommunity.com/sharedfiles/filedetails/?id=999',
      ),
      ['999'],
    );
    expect(parseWorkshopIds(''), isEmpty);
    expect(parseWorkshopIds('  \n , '), isEmpty);
  });
}
