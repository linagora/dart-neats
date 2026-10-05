import 'dart:math' as math;

/// Reads CSS the way the browser tokenizer does, so every scanner in
/// `CssSanitizer` agrees with the browser on where delimiters are.
class CssTokenMask {
  /// Same-length copy of [css] where escapes, comments, string contents and
  /// unquoted url() contents become `_`; only real delimiters are left.
  /// Null when a string is left open or ended by a newline, or a function
  /// name contains an escape: rebuilt output could be read differently.
  static String? of(String css) => _Masker(css).run();
}

bool _isHex(String c) {
  final u = c.codeUnitAt(0);
  final l = u | 0x20;
  return (u >= 0x30 && u <= 0x39) || (l >= 0x61 && l <= 0x66);
}

bool _isNewline(String c) => c == '\n' || c == '\r' || c == '\f';

bool _isWhitespace(String c) => c == ' ' || c == '\t' || _isNewline(c);

bool _isQuote(String c) => c == '"' || c == "'";

bool _isNameChar(String c) {
  final u = c.codeUnitAt(0);
  final l = u | 0x20;
  return (l >= 0x61 && l <= 0x7A) ||
      (u >= 0x30 && u <= 0x39) ||
      u == 0x5F ||
      u == 0x2D ||
      u >= 0x80;
}

class _Masker {
  _Masker(this.css);

  final String css;
  final out = StringBuffer();
  var pos = 0;

  // Start of the identifier just before pos, and whether it holds an escape.
  var nameStart = -1;
  var nameEscaped = false;

  String? run() {
    while (pos < css.length) {
      if (!_step()) return null;
    }
    return out.toString();
  }

  bool _step() {
    final c = css[pos];
    if (c == r'\') return _escape();
    if (_isQuote(c)) return _string(c);
    if (css.startsWith('/*', pos)) return _comment();
    if (c == '(') return _paren();
    _plain(c);
    return true;
  }

  void _resetName() {
    nameStart = -1;
    nameEscaped = false;
  }

  // Writes `_` up to [end] and moves there.
  void _blank(int end) {
    out.write('_' * (end - pos));
    pos = end;
  }

  bool _escape() {
    final end = _escapeEnd();
    if (end - pos > 1) {
      if (nameStart < 0) nameStart = pos;
      nameEscaped = true;
    } else {
      _resetName();
    }
    _blank(end);
    return true;
  }

  // End (exclusive) of the escape at pos; `\` before a newline or at the end
  // is not one.
  int _escapeEnd() {
    final next = pos + 1;
    if (next >= css.length || _isNewline(css[next])) return next;
    if (!_isHex(css[next])) return next + 1;

    final limit = math.min(pos + 7, css.length);
    var j = next;
    while (j < limit && _isHex(css[j])) {
      j++;
    }
    return j + _hexTrailerLength(j);
  }

  // One whitespace (or CRLF) after a hex escape belongs to the escape.
  int _hexTrailerLength(int j) {
    if (css.startsWith('\r\n', j)) return 2;
    if (j < css.length && _isWhitespace(css[j])) return 1;
    return 0;
  }

  bool _string(String quote) {
    final end = _stringEnd(quote);
    if (end < 0) return false;

    out
      ..write(quote)
      ..write('_' * (end - pos - 1))
      ..write(quote);
    pos = end + 1;
    _resetName();
    return true;
  }

  // Index of the closing quote, or -1 when a newline or the end comes first.
  int _stringEnd(String quote) {
    var j = pos + 1;
    while (j < css.length) {
      final c = css[j];
      if (c == r'\') {
        j += css.startsWith('\r\n', j + 1) ? 3 : 2;
        continue;
      }
      if (c == quote) return j;
      if (_isNewline(c)) return -1;
      j++;
    }
    return -1;
  }

  bool _comment() {
    final close = css.indexOf('*/', pos + 2);
    _blank(close < 0 ? css.length : close + 2);
    _resetName();
    return true;
  }

  bool _paren() {
    if (nameEscaped) return false;

    final isUrl = nameStart >= 0 &&
        css.substring(nameStart, pos).toLowerCase() == 'url';
    out.write('(');
    pos++;
    _resetName();
    if (isUrl) _blankUnquotedUrl();
    return true;
  }

  // The browser ends an unquoted url( at its first `)`, whatever it holds.
  void _blankUnquotedUrl() {
    var j = pos;
    while (j < css.length && _isWhitespace(css[j])) {
      j++;
    }
    if (j < css.length && _isQuote(css[j])) return;

    _blank(_urlEnd(j));
  }

  int _urlEnd(int from) {
    var j = from;
    while (j < css.length) {
      if (css[j] == r'\') {
        j += 2;
        continue;
      }
      if (css[j] == ')') return j;
      j++;
    }
    return css.length;
  }

  void _plain(String c) {
    if (!_isNameChar(c)) {
      _resetName();
    } else if (nameStart < 0) {
      nameStart = pos;
    }
    out.write(c);
    pos++;
  }
}
