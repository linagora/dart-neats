import 'dart:math';

import 'package:sanitize_html/sanitize_html.dart';

/// Shared helpers for the CSS sanitizing rule tests.
///
/// Each rule runs the sanitizer on many generated stylesheets. A case is
/// rebuilt from `seed + index` alone, so a failing case can be replayed with
/// `CssCaseGenerator(seed).caseAt(index)`.

const ruleSeed = 2509;
const ruleCaseCount = 2000;

/// One generated input, with what is needed to replay and read it.
class CssCase {
  final int index;
  final String css;

  const CssCase(this.index, this.css);

  String describe() => 'case #$index (seed $ruleSeed): $css';
}

/// Builds realistic email CSS: allowed and disallowed declarations, varied
/// selectors, comments, `!important` and letter case.
class CssCaseGenerator {
  final int seed;

  const CssCaseGenerator([this.seed = ruleSeed]);

  static const selectors = [
    '.c1',
    '#main',
    'td.col',
    'a:hover',
    'h1',
    'div > p',
    '[data-x]',
    'table td',
  ];

  static const allowedDeclarations = [
    'color: #333333',
    'padding: 4px',
    'width: 100%',
    'font-size: 14px',
    'margin: 0 auto',
    'background-color: #ffffff',
    'text-align: center',
    'display: block',
    'border: 1px solid #cccccc',
    'line-height: 1.4',
    'max-width: 600px',
    'font-weight: 700',
  ];

  static const disallowedDeclarations = [
    'position: fixed',
    'position: absolute',
    'z-index: 9999',
    'behavior: url(x.htc)',
    '-moz-binding: url(x.xml#y)',
  ];

  Iterable<CssCase> cases([int count = ruleCaseCount]) =>
      Iterable.generate(count, caseAt);

  CssCase caseAt(int index) => CssCase(index, ruleAt(Random(seed + index)));

  /// A single rule such as `.c1 { color: #333333; position: fixed }`.
  String ruleAt(Random random) {
    final count = 1 + random.nextInt(4);
    final declarations = List.generate(count, (_) => declarationAt(random));
    final rule = '${pick(random, selectors)} { ${declarations.join('; ')} }';
    return random.nextInt(4) == 0 ? '/* note */ $rule' : rule;
  }

  String declarationAt(Random random) {
    final pool =
        random.nextInt(3) == 0 ? disallowedDeclarations : allowedDeclarations;
    var declaration = pick(random, pool);
    if (random.nextBool()) declaration = '$declaration !important';
    if (random.nextInt(5) == 0) declaration = declaration.toUpperCase();
    return declaration;
  }

  static const wrappers = [
    '{rule}',
    '@media (max-width: 600px) { {rule} }',
    '@media screen and (prefers-color-scheme: dark) { {rule} }',
    '@supports (display: grid) { {rule} }',
    '@media all { @media (min-width: 1px) { {rule} } }',
    '@media print { } {rule}',
  ];

  /// A stylesheet of 1 to 3 rules, each placed in a random nesting.
  CssCase nestedSheetAt(int index) {
    final random = Random(seed + index);
    final count = 1 + random.nextInt(3);
    final rules = List.generate(
      count,
      (_) => pick(random, wrappers).replaceFirst('{rule}', ruleAt(random)),
    );
    return CssCase(index, rules.join(' /* between */ '));
  }

  Iterable<CssCase> nestedSheets([int count = ruleCaseCount]) =>
      Iterable.generate(count, nestedSheetAt);

  static const junkTokens = [
    '{',
    '}',
    ';',
    ':',
    '"',
    "'",
    '(',
    ')',
    '/*',
    '*/',
    '\\',
    '\n',
    '<',
    '>',
    r'\3c /style\3e ',
    r'\3C img src=x\3E ',
    '<img src=x>',
    '@media ',
    '@import ',
    'url(',
    'position:fixed',
    '.a',
    ' ',
    'color:red',
    '!important',
    '&lt;',
    '\u0000',
    '</style><img src=x onerror=alert(1)>',
    'font-family: "</style><img src=x>"',
  ];

  /// Malformed or hostile CSS made of 1 to 40 random tokens.
  CssCase junkSheetAt(int index) {
    final random = Random(seed + index);
    final count = 1 + random.nextInt(40);
    return CssCase(
        index, List.generate(count, (_) => pick(random, junkTokens)).join());
  }

  Iterable<CssCase> junkSheets([int count = ruleCaseCount]) =>
      Iterable.generate(count, junkSheetAt);

  static const mediaTypes = [
    '',
    'screen and ',
    'only screen and ',
    'all and ',
    'print and ',
    'not print and '
  ];

  static const mediaFeatures = [
    '(max-width: {n}px)',
    '(min-width: {n}px)',
    '(max-device-width: {n}px)',
    '(min-device-width: {n}px)',
    '(max-width: {n}em)',
    '(orientation: landscape)',
    '(prefers-color-scheme: dark)',
    '(-webkit-min-device-pixel-ratio: 2)',
    '(min-resolution: 192dpi)',
    '(min-resolution: 2dppx)',
    '(hover: hover)',
  ];

  static const rangeFeatures = [
    '(width >= {n}px)',
    '(width < {n}px)',
    '({n}px <= width <= 900px)',
  ];

  /// A media query list such as `only screen and (max-width: 600px), print`.
  String mediaQueryAt(Random random, List<String> features) {
    final count = 1 + random.nextInt(2);
    final conditions = List.generate(
      count,
      (_) => pick(random, features)
          .replaceAll('{n}', '${300 + random.nextInt(600)}'),
    );
    final query = '${pick(random, mediaTypes)}${conditions.join(' and ')}';
    return random.nextInt(4) == 0 ? '$query, print' : query;
  }

  Iterable<CssCase> mediaQueries(List<String> features,
          [int count = ruleCaseCount]) =>
      Iterable.generate(
          count,
          (index) =>
              CssCase(index, mediaQueryAt(Random(seed + index), features)));

  static T pick<T>(Random random, List<T> values) =>
      values[random.nextInt(values.length)];
}

/// Runs the sanitizer on a stylesheet and returns the CSS it keeps.
String sanitizeStylesheet(String css) => styleTextOf(sanitizeHtmlDocument(css));

String sanitizeHtmlDocument(String css) =>
    sanitizeHtml('<style>$css</style><p>x</p>');

/// In a plain <style>, a literal `</` would end the email's own <style>
/// (markup, not CSS), so it is broken up before the CSS is wrapped.
String sanitizePlainStyleDocument(String css) =>
    sanitizeHtmlDocument(css.replaceAll('</', r'<\/'));

/// Inside SVG, entities in a <style> are decoded, so encoding the CSS makes
/// its text exactly [css], `</style>` included: what the rebuilt <style>
/// must still contain.
String sanitizeSvgStyleDocument(String css) {
  final encoded = css
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return sanitizeHtml('<svg><style>$encoded</style></svg><p>x</p>');
}

String styleTextOf(String html) =>
    RegExp(r'<style[^>]*>(.*?)</style>', dotAll: true)
        .allMatches(html)
        .map((match) => match.group(1)!)
        .join(' ');

/// `prelude { body }` blocks at the top level of a stylesheet.
class CssBlock {
  final String prelude;
  final String body;

  const CssBlock(this.prelude, this.body);

  bool get isMedia => prelude.toLowerCase().startsWith('@media');
}

String normalizeCss(String css) => css
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'\s+'), '')
    .toLowerCase();

List<CssBlock> topLevelBlocks(String css) =>
    rawTopLevelBlocks(normalizeCss(css));

/// Like [topLevelBlocks] but keeps whitespace and case, so the blocks can be
/// fed back to the sanitizer.
List<CssBlock> rawTopLevelBlocks(String css) {
  final blocks = <CssBlock>[];
  var start = 0;
  while (true) {
    final open = css.indexOf('{', start);
    final close = open == -1 ? -1 : matchingBrace(css, open);
    if (close == -1) return blocks;
    final prelude =
        css.substring(start, open).split(RegExp('[;}]')).last.trim();
    blocks.add(CssBlock(prelude, css.substring(open + 1, close)));
    start = close + 1;
  }
}

int matchingBrace(String css, int open) {
  var depth = 0;
  for (var i = open; i < css.length; i++) {
    if (css[i] == '{') depth++;
    if (css[i] == '}' && --depth == 0) return i;
  }
  return -1;
}

/// `selector|property:value` for every declaration of plain (non at-rule) blocks.
Set<String> plainDeclarations(String css) => topLevelBlocks(css)
    .where((block) => !block.prelude.startsWith('@'))
    .expand((block) => declarationsOf(block.prelude, block.body))
    .toSet();

/// `prelude|selector|property:value` for every declaration inside `@media` blocks.
Set<String> mediaDeclarations(String css) => topLevelBlocks(css)
    .where((block) => block.isMedia)
    .expand((block) =>
        plainDeclarations(block.body).map((d) => '${block.prelude}|$d'))
    .toSet();

Iterable<String> declarationsOf(String selector, String body) => body
    .split(';')
    .where((declaration) => declaration.contains(':'))
    .map((declaration) => '$selector|$declaration');

/// Collects failing cases and reports how many failed plus the first few.
/// Also counts cases where the rule had something to check, so a rule
/// cannot pass only because the sanitizer dropped everything.
class RuleFailures {
  final _failures = <String>[];
  var _checkedCases = 0;

  void add(CssCase input, String detail) =>
      _failures.add('${input.describe()}\n    $detail');

  void countChecked() => _checkedCases++;

  bool get isEmpty => _failures.isEmpty;

  bool get checkedMostCases => _checkedCases * 2 > ruleCaseCount;

  String report() => '${_failures.length} failing cases, first ones:\n'
      '${_failures.take(5).join('\n')}';
}
