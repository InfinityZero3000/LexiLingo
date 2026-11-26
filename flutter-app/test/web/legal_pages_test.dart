import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The public legal pages are static files, because a crawler runs no JavaScript and the web app answers
/// every path with its own shell. They are generated from the strings the in-app pages show; these tests
/// fail when the two drift, and when the SPA rewrite would swallow them.
void main() {
  const fix = 'run: python3 scripts/build-legal-pages.py';

  Map<String, dynamic> legal(String lang) =>
      (jsonDecode(File('assets/i18n/$lang.json').readAsStringSync())
              as Map<String, dynamic>)['legal']
          as Map<String, dynamic>;

  String plain(String name) => File('web/$name')
      .readAsStringSync()
      .replaceAll(RegExp(r'<style>.*?</style>', dotAll: true), '')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  for (final (file, key, sections) in [
    ('privacy.html', 'privacy', 7),
    ('terms.html', 'terms', 8),
  ]) {
    for (final lang in ['en', 'vi']) {
      test('$file carries every $lang section of the in-app page', () {
        final text = plain(file);
        final strings = legal(lang);
        for (var n = 1; n <= sections; n++) {
          expect(text, contains(strings['$key${n}Title']), reason: fix);
          expect(text, contains(strings['$key${n}Body']), reason: fix);
        }
      });
    }
  }

  test('the privacy policy discloses Facebook sign-in', () {
    for (final lang in ['en', 'vi']) {
      expect(legal(lang)['privacy4Body'], contains('Facebook'));
    }
    expect(plain('privacy.html'), contains('Facebook'));
  });

  test('the deletion page names the in-app path and a contact', () {
    final text = plain('data-deletion.html');
    expect(text, contains('Settings → Account → Delete account'));
    expect(text, contains('Cài đặt → Tài khoản → Xoá tài khoản'));
    final email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+\w')
        .firstMatch(legal('en')['privacy7Body'] as String)!
        .group(0)!;
    expect(text, contains(email));
  });

  test('the SPA rewrite leaves the static pages alone', () {
    final config =
        jsonDecode(File('../vercel.json').readAsStringSync())
            as Map<String, dynamic>;
    final source =
        ((config['rewrites'] as List).first as Map<String, dynamic>)['source']
            as String;
    final rewritten = RegExp('^$source\$');
    for (final page in ['privacy', 'terms', 'data-deletion']) {
      expect(rewritten.hasMatch('/$page.html'), isFalse, reason: page);
    }
    expect(rewritten.hasMatch('/learn/lesson/3'), isTrue);
  });
}
