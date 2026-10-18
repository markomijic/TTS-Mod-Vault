/// A deliberately small Markdown renderer for the help and changelog
/// assets: `#` / `##` / `###` headings, `·` / `-` / `•` / `*` bullets,
/// paragraphs, blank-line gaps and inline `code`. No dependency, no links,
/// no emphasis; the texts in `assets/text/` use nothing else.
library;

import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';

/// One rendered block of a [SimpleMarkdown] text.
sealed class MarkdownBlock {
  const MarkdownBlock();
}

/// A `#`, `##` or `###` heading ([level] 1..3).
final class MarkdownHeading extends MarkdownBlock {
  /// Creates a heading.
  const MarkdownHeading(this.level, this.text);

  /// Number of leading `#`.
  final int level;

  /// Heading text (no inline parsing).
  final String text;

  @override
  bool operator ==(Object other) =>
      other is MarkdownHeading && other.level == level && other.text == text;

  @override
  int get hashCode => Object.hash(level, text);

  @override
  String toString() => 'MarkdownHeading($level, $text)';
}

/// A bullet line; [indent] is the number of leading spaces before the
/// marker (nested bullets are indented further).
final class MarkdownBullet extends MarkdownBlock {
  /// Creates a bullet.
  const MarkdownBullet(this.text, {this.indent = 0});

  /// Bullet text (inline code allowed).
  final String text;

  /// Leading spaces before the marker.
  final int indent;

  @override
  bool operator ==(Object other) =>
      other is MarkdownBullet && other.text == text && other.indent == indent;

  @override
  int get hashCode => Object.hash(text, indent);

  @override
  String toString() => 'MarkdownBullet($text, indent: $indent)';
}

/// A line of plain text; [indent] is the number of leading spaces (used
/// for the indented sub-lists of the v2 changelog).
final class MarkdownParagraph extends MarkdownBlock {
  /// Creates a paragraph.
  const MarkdownParagraph(this.text, {this.indent = 0});

  /// Paragraph text (inline code allowed).
  final String text;

  /// Leading spaces.
  final int indent;

  @override
  bool operator ==(Object other) =>
      other is MarkdownParagraph &&
      other.text == text &&
      other.indent == indent;

  @override
  int get hashCode => Object.hash(text, indent);

  @override
  String toString() => 'MarkdownParagraph($text, indent: $indent)';
}

/// A blank line between blocks.
final class MarkdownGap extends MarkdownBlock {
  /// Creates a gap.
  const MarkdownGap();

  @override
  bool operator ==(Object other) => other is MarkdownGap;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'MarkdownGap()';
}

final RegExp _heading = RegExp(r'^(#{1,3})\s+(.*)$');
final RegExp _bullet = RegExp(r'^(\s*)[·•\-*]\s+(.*)$');
final RegExp _indented = RegExp(r'^(\s*)(\S.*)$');

/// Splits [source] into blocks, line by line. Consecutive blank lines
/// collapse into one [MarkdownGap]; leading and trailing gaps are dropped.
List<MarkdownBlock> parseSimpleMarkdown(String source) {
  final blocks = <MarkdownBlock>[];
  for (final rawLine in source.split('\n')) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) {
      if (blocks.isNotEmpty && blocks.last is! MarkdownGap) {
        blocks.add(const MarkdownGap());
      }
      continue;
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      blocks.add(MarkdownHeading(heading.group(1)!.length, heading.group(2)!));
      continue;
    }
    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      blocks.add(
        MarkdownBullet(bullet.group(2)!, indent: bullet.group(1)!.length),
      );
      continue;
    }
    final indented = _indented.firstMatch(line)!;
    blocks.add(
      MarkdownParagraph(indented.group(2)!, indent: indented.group(1)!.length),
    );
  }
  if (blocks.isNotEmpty && blocks.last is MarkdownGap) blocks.removeLast();
  return blocks;
}

/// Splits [text] at backtick pairs into plain and code spans.
List<InlineSpan> inlineSpans(String text, {required TextStyle? code}) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  var inCode = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '`') {
      if (buffer.isNotEmpty) {
        spans.add(
          TextSpan(text: buffer.toString(), style: inCode ? code : null),
        );
        buffer.clear();
      }
      inCode = !inCode;
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) {
    // An unclosed backtick is shown literally.
    spans.add(
      TextSpan(text: inCode ? '`${buffer.toString()}' : buffer.toString()),
    );
  }
  return spans;
}

/// Horizontal offset per level of leading spaces.
const double _indentPerSpace = Insets.xs;

/// Renders [text] (see the library doc for the supported subset) as a
/// column of themed text widgets. Scrolling is the caller's business.
class SimpleMarkdown extends StatelessWidget {
  /// Creates the renderer.
  const SimpleMarkdown(this.text, {super.key});

  /// The Markdown source.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final body = textTheme.bodyMedium?.copyWith(height: 1.5);
    final code = body?.copyWith(
      fontFamily: 'monospace',
      backgroundColor: scheme.surfaceContainerHighest,
    );
    final blocks = parseSimpleMarkdown(text);

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final block in blocks)
            switch (block) {
              MarkdownHeading(:final level, :final text) => Padding(
                padding: const EdgeInsets.only(
                  top: Insets.sm,
                  bottom: Insets.xs,
                ),
                child: Text(
                  text,
                  style: switch (level) {
                    1 => textTheme.titleLarge,
                    2 => textTheme.titleMedium,
                    _ => textTheme.titleSmall,
                  },
                ),
              ),
              MarkdownBullet(:final text, :final indent) => Padding(
                padding: EdgeInsets.only(left: indent * _indentPerSpace),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•', style: body),
                    Gaps.w8,
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: inlineSpans(text, code: code)),
                        style: body,
                      ),
                    ),
                  ],
                ),
              ),
              MarkdownParagraph(:final text, :final indent) => Padding(
                padding: EdgeInsets.only(left: indent * _indentPerSpace),
                child: Text.rich(
                  TextSpan(children: inlineSpans(text, code: code)),
                  style: body,
                ),
              ),
              MarkdownGap() => Gaps.h12,
            },
        ],
      ),
    );
  }
}
