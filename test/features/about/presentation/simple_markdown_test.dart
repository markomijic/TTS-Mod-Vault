// The in-house Markdown subset parser.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/about/presentation/simple_markdown.dart';

void main() {
  test('parses headings, bullets, paragraphs and gaps', () {
    const source = '''
# Title

## Section
Text line
    Indented line
· Dot bullet
- Dash bullet
  • Nested bullet
* Star bullet


### Deep
''';

    expect(parseSimpleMarkdown(source), const [
      MarkdownHeading(1, 'Title'),
      MarkdownGap(),
      MarkdownHeading(2, 'Section'),
      MarkdownParagraph('Text line'),
      MarkdownParagraph('Indented line', indent: 4),
      MarkdownBullet('Dot bullet'),
      MarkdownBullet('Dash bullet'),
      MarkdownBullet('Nested bullet', indent: 2),
      MarkdownBullet('Star bullet'),
      MarkdownGap(),
      MarkdownHeading(3, 'Deep'),
    ]);
  });

  test('a lone # or dash without a space is plain text', () {
    expect(parseSimpleMarkdown('#hashtag\n-dash'), const [
      MarkdownParagraph('#hashtag'),
      MarkdownParagraph('-dash'),
    ]);
  });

  test('inline code splits at backtick pairs; an odd backtick is literal', () {
    const code = TextStyle(fontFamily: 'monospace');
    final spans = inlineSpans('a `b` c', code: code).cast<TextSpan>();
    expect(spans.map((s) => s.text), ['a ', 'b', ' c']);
    expect(spans[1].style, code);
    expect(spans[0].style, isNull);

    final odd = inlineSpans('x `y', code: code).cast<TextSpan>();
    expect(odd.map((s) => s.text), ['x ', '`y']);
  });
}
