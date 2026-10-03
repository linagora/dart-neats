import 'package:test/test.dart';

import 'css_rule_support.dart';

/// Rule: a CSS rule keeps exactly the same declarations whether it is plain
/// or wrapped in `@media`. Nesting must neither lose allowed declarations
/// nor let disallowed ones through.
void main() {
  const prelude = '@media(max-width:600px)';

  test('a rule keeps the same declarations inside @media as outside', () {
    final failures = RuleFailures();

    for (final input in const CssCaseGenerator().cases()) {
      final plain = plainDeclarations(sanitizeStylesheet(input.css));
      final nested =
          mediaDeclarations(sanitizeStylesheet('$prelude { ${input.css} }'))
              .map((declaration) => declaration.replaceFirst('$prelude|', ''))
              .toSet();

      if (plain.isNotEmpty) failures.countChecked();
      if (plain.length != nested.length || !plain.containsAll(nested)) {
        failures.add(
            input,
            'only plain: ${plain.difference(nested)}, '
            'only in @media: ${nested.difference(plain)}');
      }
    }

    expect(failures.isEmpty, isTrue, reason: failures.report());
    expect(failures.checkedMostCases, isTrue,
        reason: 'most cases must keep declarations');
  });
}
