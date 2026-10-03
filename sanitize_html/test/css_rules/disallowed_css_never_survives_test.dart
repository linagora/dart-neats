import 'package:test/test.dart';

import 'css_rule_support.dart';

/// Rule: declarations that can draw over the app or run code never survive
/// sanitizing, whatever the nesting (`@media`, `@supports`, nested `@media`,
/// comments between rules).
void main() {
  const forbidden = [
    'position',
    'z-index',
    'behavior',
    '-moz-binding',
    'expression(',
    'javascript:'
  ];

  test('no disallowed declaration survives in any nesting', () {
    final failures = RuleFailures();

    for (final input in const CssCaseGenerator().nestedSheets()) {
      final kept = normalizeCss(sanitizeStylesheet(input.css));
      final leaked = forbidden.where(kept.contains).toList();

      if (kept.isNotEmpty) failures.countChecked();
      if (leaked.isNotEmpty) failures.add(input, 'leaked $leaked in: $kept');
    }

    expect(failures.isEmpty, isTrue, reason: failures.report());
    expect(failures.checkedMostCases, isTrue,
        reason: 'most cases must keep some CSS');
  });
}
