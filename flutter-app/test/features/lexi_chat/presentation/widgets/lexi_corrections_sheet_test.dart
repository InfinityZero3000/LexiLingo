import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_corrections_sheet.dart';

void main() {
  test('server title wins over the slug', () {
    final chips = describeConcepts(
      ['concept:vocab.word.cefr-word-00005-200c7e6220'],
      {'concept:vocab.word.cefr-word-00005-200c7e6220': 'activate'},
    );
    expect(chips.single.kind, 'vocab');
    expect(chips.single.label, 'activate');
  });

  test('slug fallback drops word. prefix and trailing hash', () {
    final chips = describeConcepts([
      'concept:vocab.word.hello',
      'concept:grammar.difference-between-words-269b1e90b0',
      'grammar:story_ai_product_demo_advanced_conditionals',
    ], {});
    expect(chips[0].label, 'Hello');
    expect(chips[1].kind, 'usage');
    expect(chips[1].label, 'Difference Between Words');
    expect(chips[2].kind, 'grammar');
    expect(chips[2].label, 'Ai Product Demo Advanced Conditionals');
  });

  test('duplicates and unparseable ids are dropped', () {
    final chips = describeConcepts(
      ['concept:function.greeting', 'concept:function.greeting', 'greeting', ''],
      {},
    );
    expect(chips.length, 1);
  });
}
