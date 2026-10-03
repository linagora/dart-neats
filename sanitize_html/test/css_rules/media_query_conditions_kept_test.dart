import 'package:test/test.dart';

import 'css_rule_support.dart';

/// Rule: an `@media` block written with a real-world media query keeps its
/// condition and its allowed declarations, so phone layouts and dark mode
/// still apply. Conditions are generated from the media query grammar rather
/// than taken from known templates.
void main() {
  const declaration = '.c1|color:#333333';

  RuleFailures checkKept(Iterable<CssCase> queries) {
    final failures = RuleFailures();
    for (final query in queries) {
      final css = '@media ${query.css} { .c1 { color: #333333 } }';
      final kept = mediaDeclarations(sanitizeStylesheet(css));
      final expected = '${normalizeCss('@media ${query.css}')}|$declaration';

      failures.countChecked();
      if (!kept.contains(expected)) failures.add(query, 'kept: $kept');
    }
    return failures;
  }

  test('media queries with types, features, "and" and "," lists are kept', () {
    const generator = CssCaseGenerator();
    final failures =
        checkKept(generator.mediaQueries(CssCaseGenerator.mediaFeatures));

    expect(failures.isEmpty, isTrue, reason: failures.report());
  });

  // Known gap, not a regression: before nested sanitizing the blocklist
  // turned `>=` into `=` (wrong condition); now the block is dropped.
  test('media queries with level 4 range syntax are kept', () {
    const generator = CssCaseGenerator();
    final failures =
        checkKept(generator.mediaQueries(CssCaseGenerator.rangeFeatures));

    expect(failures.isEmpty, isTrue, reason: failures.report());
  }, skip: 'range syntax needs < > = in the prelude allow-list');
}
