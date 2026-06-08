import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Book Layout Preservation RegExp Tests', () {
    test('should extract words and preserve single spaces', () {
      const text = 'Hello World';
      final matches = RegExp(r'(\s+|[^\s]+)').allMatches(text).map((m) => m.group(0)!).toList();

      expect(matches, ['Hello', ' ', 'World']);
    });

    test('should preserve multiple spaces', () {
      const text = 'Hello   World';
      final matches = RegExp(r'(\s+|[^\s]+)').allMatches(text).map((m) => m.group(0)!).toList();

      expect(matches, ['Hello', '   ', 'World']);
    });

    test('should preserve single newlines and carriage returns', () {
      const text = 'Line1\nLine2\r\nLine3';
      final matches = RegExp(r'(\s+|[^\s]+)').allMatches(text).map((m) => m.group(0)!).toList();

      expect(matches, ['Line1', '\n', 'Line2', '\r\n', 'Line3']);
    });

    test('should preserve double newlines (paragraphs)', () {
      const text = 'Paragraph 1.\n\nParagraph 2.';
      final matches = RegExp(r'(\s+|[^\s]+)').allMatches(text).map((m) => m.group(0)!).toList();

      expect(matches, ['Paragraph', ' ', '1.', '\n\n', 'Paragraph', ' ', '2.']);
    });

    test('should keep punctuation attached to the preceding word', () {
      const text = 'Hello, world!';
      final matches = RegExp(r'(\s+|[^\s]+)').allMatches(text).map((m) => m.group(0)!).toList();

      expect(matches, ['Hello,', ' ', 'world!']);
    });
  });
}
