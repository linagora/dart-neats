import 'package:sanitize_html/src/css_dangerous_patterns.dart';
import 'package:sanitize_html/src/css_token_mask.dart';
import 'package:sanitize_html/src/html_sanitize_config.dart';

class CssSanitizer {
  /// Check safe url(...)
  static bool _isSafeUrlValue(String raw) {
    final clean = raw.trim().toLowerCase();

    // url(x) extract
    if (!clean.startsWith("url(") || !clean.endsWith(")")) return false;

    String inside = clean.substring(4, clean.length - 1).trim();

    // Remove comments to avoid bypass
    inside = inside.replaceAll(HtmlSanitizeConfig.cssCommentPattern, '').trim();

    // Strip optional wrapping quotes: url("...") or url('...')
    if ((inside.startsWith('"') && inside.endsWith('"')) ||
        (inside.startsWith("'") && inside.endsWith("'"))) {
      inside = inside.substring(1, inside.length - 1).trim();
    }

    // Block protocol-relative URL
    if (inside.startsWith("//")) return false;

    // Block javascript: data: vbscript:
    if (inside.startsWith("javascript:")) return false;
    if (inside.startsWith("vbscript:")) return false;

    // Block non-image data: URIs
    if (inside.startsWith("data:") &&
        !HtmlSanitizeConfig.base64ImageRegex.hasMatch(inside)) {
      return false;
    }

    // Allow base64 image
    if (HtmlSanitizeConfig.base64ImageRegex.hasMatch(inside)) return true;

    // Allow http, https, relative path
    if (inside.startsWith("/") ||
        inside.startsWith("http://") ||
        inside.startsWith("https://")) {
      return true;
    }

    return false;
  }

  // Strip CSS comments inside a value (/* ... */).
  static String _stripCssComments(String value) {
    if (!HtmlSanitizeConfig.cssCommentPattern.hasMatch(value)) {
      return value;
    }
    return value.replaceAll(HtmlSanitizeConfig.cssCommentPattern, ' ');
  }

  // [s] is a CssTokenMask, so strings and escapes hold no parens.
  static int _findMatchingParen(String s, int startIndex) {
    int depth = 1;

    for (var i = startIndex; i < s.length; i++) {
      if (s[i] == '(') {
        depth++;
      } else if (s[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static bool _areAllUrlsSafeInValue(String original) {
    final mask = CssTokenMask.of(original);
    if (mask == null) return false;

    final lower = mask.toLowerCase();
    var index = 0;

    while (true) {
      final urlIndex = lower.indexOf('url(', index);
      if (urlIndex == -1) break;

      final openParen = urlIndex + 4;
      final closeParen = _findMatchingParen(mask, openParen);
      if (closeParen == -1) {
        return false;
      }

      final urlChunk = original.substring(urlIndex, closeParen + 1).trim();
      if (!_isSafeUrlValue(urlChunk)) {
        return false;
      }

      index = closeParen + 1;
    }

    return true;
  }

  /// Check forbidden CSS keywords (javascript: / expression / url("javascript:") / ...)
  static bool isSafeCssValue(String value) {
    if (value.isEmpty) return false;

    final withoutComments = _stripCssComments(value);
    var v = withoutComments.trim();
    if (v.isEmpty) return false;

    final lower = v.toLowerCase();

    if (lower.contains('url(')) {
      if (!_areAllUrlsSafeInValue(v)) {
        return false;
      }
    }

    for (final forbidden in HtmlSanitizeConfig.forbiddenCss) {
      if (lower.contains(forbidden)) {
        return false;
      }
    }

    return true;
  }

  /// Normalize whitespace: "0px   20px\n  " → "0px 20px"
  static String _normalizeWhitespace(String value) =>
      value.replaceAll(HtmlSanitizeConfig.whitespacePattern, ' ').trim();

  /// Add px to pure integer width/height values:
  /// height: 10   → height: 10px
  static String _normalizeLengthUnits(String prop, String value) {
    if ((prop == 'height' ||
            prop == 'width' ||
            prop == 'min-height' ||
            prop == 'max-height' ||
            prop == 'min-width' ||
            prop == 'max-width') &&
        HtmlSanitizeConfig.unitlessNumberPattern.hasMatch(value)) {
      return '${value}px';
    }
    return value;
  }

  /// Special-case normalization for certain CSS properties
  static String _normalizeCommonProperties(String prop, String value) {
    switch (prop) {
      case 'padding':
      case 'border':
        return _normalizeWhitespace(value);
      default:
        return value;
    }
  }

  static List<String> _splitCssDeclarations(String raw) {
    // Split on the mask so escapes, comments and url() read as in the browser.
    final mask = CssTokenMask.of(raw);
    if (mask == null) return const [];

    final result = <String>[];
    var parenDepth = 0;
    var start = 0;

    for (var i = 0; i < mask.length; i++) {
      final ch = mask[i];
      if (ch == ';' && parenDepth == 0) {
        _addTrimmed(result, raw.substring(start, i));
        start = i + 1;
      } else {
        final next = parenDepth + (ch == '(' ? 1 : (ch == ')' ? -1 : 0));
        parenDepth = next < 0 ? 0 : next;
      }
    }
    _addTrimmed(result, raw.substring(start));

    return result;
  }

  static void _addTrimmed(List<String> out, String part) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) out.add(trimmed);
  }

  // False when a `(` or `[` is left open, or the browser would read a string,
  // escape or url() differently (CssTokenMask). A closer with nothing open
  // fails too, except in a declaration body, where the browser ignores it
  // (the second `)` of `url(a(b))`); an opener after it still has to close.
  static bool _hasBalancedDelimiters(String s,
      {bool allowStrayClosers = false}) {
    final mask = CssTokenMask.of(s);
    if (mask == null) return false;

    final open = {'(': 0, '[': 0};
    for (var i = 0; i < mask.length; i++) {
      if (!_trackDelimiter(open, mask[i]) && !allowStrayClosers) return false;
    }

    return open.values.every((n) => n == 0);
  }

  static const _closerToOpener = {')': '(', ']': '['};

  // Counts [c] in [open]; false when it closes something never opened.
  static bool _trackDelimiter(Map<String, int> open, String c) {
    if (open.containsKey(c)) {
      open[c] = open[c]! + 1;
      return true;
    }
    final opener = _closerToOpener[c];
    if (opener == null) return true;
    if (open[opener] == 0) return false;

    open[opener] = open[opener]! - 1;
    return true;
  }

  /// Main CSS inline sanitizer for style="..."
  /// NOTE:
  /// For now we normalize only a subset of properties (sizes, common text layout).
  /// This keeps the sanitizer strict and simple. If we later see many benign
  /// styles being dropped, we can extend `_normalizeCommonProperties` and add
  /// per-property safe enums (similar to `safeOverflowValues`).
  static String sanitizeInline(String raw) {
    raw = raw.trim();
    if (raw.isEmpty) return '';

    final buf = StringBuffer();
    final declarations = _splitCssDeclarations(raw);

    for (var d in declarations) {
      d = d.trim();
      if (d.isEmpty) continue;

      final colon = d.indexOf(':');
      if (colon <= 0) continue;

      final prop = d.substring(0, colon).trim().toLowerCase();
      var val = d.substring(colon + 1).trim();

      // Normalize raw value for quick safety check
      final rawVal = val.trim().toLowerCase();
      // Block protocol-relative URL used directly as value
      if (rawVal.startsWith("//")) {
        continue;
      }

      // Property not allowed → skip
      if (!HtmlSanitizeConfig.allowedCssProperties.contains(prop)) continue;

      // Special safe check for overflow properties
      if (prop == 'overflow' || prop == 'overflow-x' || prop == 'overflow-y') {
        final cleanedLowered = val.trim().toLowerCase();
        if (!HtmlSanitizeConfig.safeOverflowValues.contains(cleanedLowered)) {
          continue;
        }
      }

      // Forbidden keywords → skip
      if (!isSafeCssValue(val)) continue;

      // Normalize units & whitespace based on property
      val = _normalizeLengthUnits(prop, val);
      val = _normalizeCommonProperties(prop, val);

      // Append to buffer
      if (buf.isNotEmpty) buf.write('; ');
      buf.write('$prop: $val');
    }

    return buf.toString();
  }

  // Remove comments that exist outside any rule block.
// This avoids removing comments inside url() or property values.
  static String _stripTopLevelCssComments(String css) {
    final sb = StringBuffer();
    bool inComment = false;
    int i = 0;

    while (i < css.length) {
      if (!inComment &&
          i + 1 < css.length &&
          css[i] == '/' &&
          css[i + 1] == '*') {
        inComment = true;
        i += 2;
        continue;
      }

      if (inComment &&
          i + 1 < css.length &&
          css[i] == '*' &&
          css[i + 1] == '/') {
        inComment = false;
        i += 2;
        continue;
      }

      if (!inComment) sb.write(css[i]);

      i++;
    }

    return sb.toString();
  }

  static String stripDangerousTokens(String css) {
    var out = css;

    // Remove @import rules
    out = out.replaceAll(CssDangerousPatterns.import, '');

    // Remove dangerous protocols
    out = out.replaceAll(CssDangerousPatterns.javascript, '');
    out = out.replaceAll(CssDangerousPatterns.vbscript, '');

    // Remove legacy CSS execution vectors
    out = out.replaceAll(CssDangerousPatterns.expression, '');

    // Strip SVG / HTML event handlers (onload=, onclick=, ...)
    out = out.replaceAll(CssDangerousPatterns.eventHandler, '');

    // Block data:text/* explicitly
    out = out.replaceAll(CssDangerousPatterns.dataText, '');

    // Block non-image data:* (preserve only data:image/*)
    out = out.replaceAllMapped(
      CssDangerousPatterns.dataAny,
      (m) {
        final type = (m.group(1) ?? '').toLowerCase().trim();
        return type == 'image' ? m.group(0)! : '';
      },
    );

    // Remove angle brackets to prevent tag / SVG injection
    out = out.replaceAll('<', '').replaceAll('>', '');

    return out.trim();
  }

  /// NOTE ON PARSING LIMITATION
  /// ---------------------------
  /// This sanitizer uses a simple CSS block splitter based on the `}` character.
  /// It does *not* implement a full CSS parser and does *not* track string
  /// boundaries inside CSS rules.
  ///
  /// For example, CSS like:
  ///   content: '}';
  /// contains a `}` inside a quoted literal. Because the sanitizer splits blocks
  /// using `}`, such rules may be incorrectly parsed or rejected.
  ///
  /// This limitation is intentional for a security-focused sanitizer:
  /// - It avoids complexity of a full CSS parser
  /// - It prevents obfuscation attacks using crafted CSS strings
  /// - It may reject uncommon but valid CSS, which is acceptable in sanitized email HTML
  ///
  /// Developers should be aware that styles containing `}` inside string literals
  /// may be dropped by design.
  static String sanitizeStylesheet(String css) {
    css = css.trim();
    if (css.isEmpty) return '';

    // Remove top-level comments (outside declaration blocks)
    css = _stripTopLevelCssComments(css).trim();

    // Strip @import statements safely
    css = css.replaceAll(CssDangerousPatterns.import, '');

    final buffer = StringBuffer();

    // Split by block }
    final blocks = css.split('}');

    for (final block in blocks) {
      final rule = _sanitizeFlatBlock(block.trim());
      if (rule.isNotEmpty) buffer.writeln(rule);
    }

    return buffer.toString().trim();
  }

  // One `selector { declarations` block of a flat stylesheet, '' if dropped.
  static String _sanitizeFlatBlock(String block) {
    final braceIdx = block.indexOf('{');
    if (braceIdx <= 0) return '';

    final selector = block.substring(0, braceIdx).trim();

    // Block @media, @supports, @keyframes, etc.
    if (selector.startsWith('@')) return '';

    final rawDeclarations = block.substring(braceIdx + 1).trim();

    // An open delimiter swallows `}` in the browser, so the next selector
    // would be read as declarations of this rule.
    if (!_hasBalancedDelimiters(selector) ||
        !_hasBalancedDelimiters(rawDeclarations, allowStrayClosers: true)) {
      return '';
    }

    // Use the same inline sanitizer so that:
    // - url() comment stripping works
    // - forbiddenCss inspection works uniformly
    // - multi-token url() checks are applied consistently
    final sanitized = sanitizeInline(rawDeclarations);
    if (sanitized.isEmpty) return '';

    return '$selector { $sanitized }';
  }

  // `@media` followed only by media-query characters. Anything else
  // (braces, quotes, angle brackets, url(), ...) drops the block.
  static final RegExp _safeMediaPrelude =
      RegExp(r'^@media[a-z0-9\s():,.\-]*$', caseSensitive: false);

  /// Sanitizes a stylesheet containing nested blocks.
  /// - comments are removed first so they never become part of a prelude,
  /// - `@media` blocks with a safe prelude are kept, their rules going
  ///   through [sanitizeStylesheet] (same allow-list as flat CSS),
  /// - every other at-rule (@supports, @keyframes, @font-face, ...) is dropped,
  /// - plain rules are sanitized as flat CSS,
  /// - unbalanced trailing content is dropped.
  static String sanitizeNestedStylesheet(String css) {
    css = _stripTopLevelCssComments(css.trim()).trim();

    final buffer = StringBuffer();
    for (final block in _splitTopLevelBlocks(css)) {
      final rule = _sanitizeTopLevelBlock(block);
      if (rule.isNotEmpty) buffer.writeln(rule);
    }

    return buffer.toString().trim();
  }

  static String _sanitizeTopLevelBlock(_CssBlock block) {
    final prelude = block.prelude;

    if (!prelude.startsWith('@')) {
      return sanitizeStylesheet('$prelude { ${block.body} }');
    }
    if (!_safeMediaPrelude.hasMatch(prelude) ||
        !_hasBalancedDelimiters(prelude)) {
      return '';
    }

    final inner = sanitizeStylesheet(block.body);
    if (inner.isEmpty) return '';

    return '${_normalizeWhitespace(prelude)} { $inner }';
  }

  /// Splits a stylesheet into top-level `prelude { body }` blocks. Nested
  /// blocks stay inside their parent's body. Statements ending in `;`
  /// (@import, @charset) are not part of the next prelude. Trailing
  /// unbalanced content is dropped.
  static List<_CssBlock> _splitTopLevelBlocks(String css) {
    final blocks = <_CssBlock>[];
    var start = 0;

    while (true) {
      final open = css.indexOf('{', start);
      if (open == -1) break;

      final close = _findMatchingBrace(css, open);
      if (close == -1) break;

      final prelude = _lastStatement(css.substring(start, open));
      if (prelude.isNotEmpty) {
        blocks.add(_CssBlock(prelude, css.substring(open + 1, close)));
      }
      start = close + 1;
    }

    return blocks;
  }

  static int _findMatchingBrace(String css, int open) {
    var depth = 0;
    for (var i = open; i < css.length; i++) {
      final c = css.codeUnitAt(i);
      if (c == 0x7B /* { */) depth++;
      if (c == 0x7D /* } */ && --depth == 0) return i;
    }
    return -1;
  }

  static String _lastStatement(String segment) {
    final end = segment.lastIndexOf(RegExp(r'[;}]'));
    return segment.substring(end + 1).trim();
  }
}

class _CssBlock {
  final String prelude;
  final String body;

  const _CssBlock(this.prelude, this.body);
}
