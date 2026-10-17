/// Turns the free text of the "Download Workshop mods" dialog into Workshop
/// ids.
library;

final RegExp _separators = RegExp(r'[\s,;]+');
final RegExp _digits = RegExp(r'^\d+$');
final RegExp _idQuery = RegExp(r'[?&]id=(\d+)');

/// Extracts the numeric Workshop ids from [input].
///
/// Tokens are separated by newlines, commas, semicolons or spaces. A token
/// that is all digits is an id; a token containing `?id=<digits>` (a
/// `steamcommunity.com/sharedfiles/filedetails/?id=…` or
/// `steamcommunity.com/workshop/filedetails/?id=…` URL, with or without a
/// scheme) yields that id. Anything else is ignored. Duplicates are
/// dropped, first occurrence wins, order is preserved.
List<String> parseWorkshopIds(String input) {
  final seen = <String>{};
  final ids = <String>[];
  for (final raw in input.split(_separators)) {
    final token = raw.trim();
    if (token.isEmpty) continue;
    final String? id;
    if (_digits.hasMatch(token)) {
      id = token;
    } else {
      id = _idQuery.firstMatch(token)?.group(1);
    }
    if (id == null || !seen.add(id)) continue;
    ids.add(id);
  }
  return ids;
}
