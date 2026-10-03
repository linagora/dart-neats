import 'package:sanitize_html/src/css_sanitizer.dart';
import 'package:test/test.dart';

import 'css_rule_support.dart';

/// Rule: compared to the old nested handling (blocklist only), the new one
/// only removes what the flat allow-list rejects, plus at-rules other than
/// `@media`. Anything else it loses would be a display regression.
void main() {
  /// The old output with `@media` unwrapped and other at-rules removed: the
  /// flat allow-list applied to it tells which declarations are acceptable.
  String flattenMedia(String css) =>
      rawTopLevelBlocks(css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ''))
          .where((block) => block.isMedia || !block.prelude.startsWith('@'))
          .map((block) =>
              block.isMedia ? block.body : '${block.prelude} { ${block.body} }')
          .join(' ');

  // The old blocklist stripped `>`, turning `div > p` into `div p`; ignore
  // `>` so a selector the new code keeps intact is not reported as lost.
  String withoutChildCombinator(String declaration) =>
      declaration.replaceAll('>', '');

  Set<String> keptDeclarations(String css) => {
        ...plainDeclarations(css),
        ...mediaDeclarations(css)
            .map((declaration) => declaration.split('|').skip(1).join('|')),
      }.map(withoutChildCombinator).toSet();

  test('nested sanitizing only removes declarations the allow-list rejects',
      () {
    final failures = RuleFailures();

    for (final input in const CssCaseGenerator().nestedSheets()) {
      final old = CssSanitizer.stripDangerousTokens(input.css);
      final lost = keptDeclarations(old).difference(
          keptDeclarations(CssSanitizer.sanitizeNestedStylesheet(input.css)));
      final acceptable =
          plainDeclarations(CssSanitizer.sanitizeStylesheet(flattenMedia(old)))
              .map(withoutChildCombinator)
              .toSet();
      final regressions = lost.intersection(acceptable);

      if (acceptable.isNotEmpty) failures.countChecked();
      if (regressions.isNotEmpty) {
        failures.add(input, 'lost although allowed: $regressions');
      }
    }

    expect(failures.isEmpty, isTrue, reason: failures.report());
    expect(failures.checkedMostCases, isTrue,
        reason: 'most cases must keep declarations');
  });
}
