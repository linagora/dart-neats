import 'package:test/test.dart';
import 'package:html/parser.dart' show parse;

import 'css_rule_support.dart';

/// Rule: malformed or hostile CSS never makes the sanitizer throw and never
/// escapes its `<style>` element: the email body stays exactly what it was.
/// Each case runs in a plain `<style>` and in an SVG `<style>`, where the CSS
/// text itself can contain `</style>`.
void main() {
  String? problemWith(String sanitizedHtml) {
    final body = parse(sanitizedHtml).body;
    final elements =
        body?.querySelectorAll('*').map((e) => e.localName).toList();
    if (elements == null ||
        elements.any((name) => name != 'p' && name != 'svg')) {
      return 'body elements became $elements';
    }
    final text = body!.text.trim();
    return text == 'x' ? null : 'body text became "$text"';
  }

  test('malformed CSS never throws and never leaks into the email body', () {
    final failures = RuleFailures();

    for (final input in const CssCaseGenerator().junkSheets()) {
      failures.countChecked();
      for (final sanitize in [
        sanitizePlainStyleDocument,
        sanitizeSvgStyleDocument
      ]) {
        try {
          final problem = problemWith(sanitize(input.css));
          if (problem != null) failures.add(input, problem);
        } catch (error) {
          failures.add(input, 'threw $error');
        }
      }
    }

    expect(failures.isEmpty, isTrue, reason: failures.report());
  });
}
