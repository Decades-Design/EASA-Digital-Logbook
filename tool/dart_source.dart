/// Shared source-text helpers for the `tool/` guards.
///
/// Both guards match Dart syntactically rather than depending on
/// `package:analyzer` (see ADR-0001). They therefore share one comment
/// stripper — duplicating this regex would mean fixing it twice.
library;

/// Matches a line comment or a block comment — whichever opens first.
///
/// The single alternation is load-bearing. The engine tries the alternatives
/// left to right at each position, so `// toggle: /*` is consumed as a line
/// comment (its `/*` never opens a block) and `/* a // b */` is consumed as a
/// block comment. Stripping one kind before the other — in *either* order —
/// lets the loser swallow real code: block-first turns a `/*` inside a `//`
/// comment into an opener that deletes every directive up to the next `*/`.
final RegExp _comment = RegExp(r'//[^\n]*|/\*[\s\S]*?\*/');

/// Replaces comments with blanks, preserving line breaks so violation line
/// numbers still point at the real line.
String stripComments(String source) => source.replaceAllMapped(
  _comment,
  (match) => '\n' * '\n'.allMatches(match.group(0)!).length,
);
