import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/course/presentation/utils/course_tag_label.dart';

void main() {
  test('exam and framework names keep their capitals', () {
    expect(courseTagLabel('ielts'), 'IELTS');
    expect(courseTagLabel('toeic'), 'TOEIC');
    expect(courseTagLabel('cefr_a1'), 'CEFR A1');
    expect(courseTagLabel('Cefr B2'), 'CEFR B2');
  });

  test('an IELTS band is written with its decimal point', () {
    expect(courseTagLabel('band_6_5'), 'Band 6.5');
    expect(courseTagLabel('band_6'), 'Band 6');
    expect(courseTagLabel('Band 7'), 'Band 7');
  });

  test('a decimal is only made after "band"', () {
    expect(courseTagLabel('grade_1_2'), 'Grade 1 2');
  });

  test('pre- words keep their hyphen', () {
    expect(courseTagLabel('pre_intermediate'), 'Pre-Intermediate');
    expect(courseTagLabel('upper_intermediate'), 'Upper Intermediate');
  });

  test('plain slugs are title-cased as before', () {
    expect(courseTagLabel('test_prep'), 'Test Prep');
    expect(courseTagLabel('daily-life'), 'Daily Life');
    expect(courseTagLabel('  Foundation '), 'Foundation');
    expect(courseTagLabel(''), '');
  });
}
