import 'package:test/test.dart';

import 'css_rule_support.dart';

/// Rule: adding an unrelated `@media` block to a stylesheet does not change
/// how its plain rules are sanitized. One `@media` must not switch the whole
/// sheet to a weaker (or stricter) policy.
void main() {
  const unrelatedMedia = '@media print { .footer { color: #000000 } }';

  test('plain rules keep the same declarations next to an unrelated @media',
      () {
    final failures = RuleFailures();

    for (final input in const CssCaseGenerator().cases()) {
      final alone = plainDeclarations(sanitizeStylesheet(input.css));
      final withMedia =
          plainDeclarations(sanitizeStylesheet('${input.css} $unrelatedMedia'));

      if (alone.isNotEmpty) failures.countChecked();
      if (alone.length != withMedia.length || !alone.containsAll(withMedia)) {
        failures.add(
            input,
            'only alone: ${alone.difference(withMedia)}, '
            'only next to @media: ${withMedia.difference(alone)}');
      }
    }

    expect(failures.isEmpty, isTrue, reason: failures.report());
    expect(failures.checkedMostCases, isTrue,
        reason: 'most cases must keep declarations');
  });
}
