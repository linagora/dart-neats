import 'package:test/test.dart';

import 'css_rule_support.dart';

/// Rule: sanitizing already sanitized CSS changes nothing. Drafts, templates
/// and signatures are sanitized again each time they are reopened and saved,
/// so any drift would erode them a little more on every save.
void main() {
  test('sanitizing a second time gives the same stylesheet', () {
    final failures = RuleFailures();

    for (final input in const CssCaseGenerator().nestedSheets()) {
      final once = sanitizeStylesheet(input.css);
      final twice = sanitizeStylesheet(once);

      if (normalizeCss(once).isNotEmpty) failures.countChecked();
      if (normalizeCss(twice) != normalizeCss(once)) {
        failures.add(input,
            'once: ${normalizeCss(once)}\n    twice: ${normalizeCss(twice)}');
      }
    }

    expect(failures.isEmpty, isTrue, reason: failures.report());
    expect(failures.checkedMostCases, isTrue,
        reason: 'most cases must keep some CSS');
  });
}
