import 'package:sanitize_html/src/css_token_mask.dart';
import 'package:test/test.dart';

// Each case pins one CSS Syntax tokenizer rule. A null mask means the input
// is rejected.
class _Case {
  final String name;
  final String css;
  final String? expected;

  const _Case(this.name, this.css, this.expected);
}

const _cases = [
  _Case(
    'the whitespace after a hex escape belongs to the escape',
    'a\\28 url(x)',
    null,
  ),
  _Case(
    'a CRLF after a hex escape belongs to the escape',
    'a\\28\r\nurl(x)',
    null,
  ),
  _Case(
    'a backslash before a newline is not an escape',
    '\\41\\\n(x)',
    '____\n(x)',
  ),
  _Case('a string ends the identifier before it', '\\41"x"(y)', '___"_"(y)'),
  _Case('a comment ends the identifier before it', '\\41/**/(y)', '_______(y)'),
  _Case('an escaped CRLF continues a string', '"a\\\r\nb"', '"_____"'),
  _Case('an unclosed comment runs to the end', 'a /* (', 'a ____'),
  _Case('url( is matched case-insensitively', 'URL(/a"b)', 'URL(____)'),
  _Case(
    'url( inside another function is still a url',
    'image-set(url(/a"b) 1x)',
    'image-set(url(____) 1x)',
  ),
  _Case('a quoted url( keeps its string', 'url("a)b")', 'url("___")'),
  _Case(
    'a quoted url( after whitespace keeps its string',
    'url( "a)b" )',
    'url( "___" )',
  ),
  _Case(
      'an escaped ) does not end an unquoted url(', r'url(a\)b)', 'url(____)'),
  _Case('a hex escape takes letters in either case', 'a\\2aA url(x)', null),
  _Case(
    'a control character is not a hex digit',
    'a\\2\u0010url(x)',
    'a__\u0010url(_)',
  ),
  _Case(
      'a tab after a hex escape belongs to the escape', 'a\\28\turl(x)', null),
  _Case(
    'a newline after a hex escape belongs to the escape',
    'a\\28\nurl(x)',
    null,
  ),
  _Case('a digit continues the name before (', 'a1url(x)', 'a1url(x)'),
  _Case('an underscore continues the name before (', '_url(x)', '_url(x)'),
  _Case('a hyphen continues the name before (', '-url(x)', '-url(x)'),
  _Case(
    'a non-ASCII letter continues the name before (',
    'éurl(x)',
    'éurl(x)',
  ),
  _Case('a [ before url( keeps it a url', '[url(x)', '[url(_)'),
];

void main() {
  group('CssTokenMask', () {
    for (final c in _cases) {
      test(c.name, () => expect(CssTokenMask.of(c.css), c.expected));
    }
  });
}
