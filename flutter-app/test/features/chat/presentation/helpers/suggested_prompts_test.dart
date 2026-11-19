import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/chat/presentation/helpers/suggested_prompts.dart';

void main() {
  const prompts = [
    'I have a toothache.',
    'Can you tell me about the cleaning?',
  ];

  test('a prompt the learner already sent is hidden', () {
    expect(remainingSuggestedPrompts(prompts, ['I have a toothache.']), [
      'Can you tell me about the cleaning?',
    ]);
  });

  test('matching ignores case, spacing and trailing punctuation', () {
    expect(remainingSuggestedPrompts(prompts, ['  i HAVE a  toothache ']), [
      'Can you tell me about the cleaning?',
    ]);
  });

  test('all used leaves nothing, so the strip can disappear', () {
    expect(remainingSuggestedPrompts(prompts, prompts), isEmpty);
  });

  test('typed text that only resembles a prompt does not hide it', () {
    expect(remainingSuggestedPrompts(prompts, ['I has a toothache']), prompts);
  });

  test('no messages leaves every prompt', () {
    expect(remainingSuggestedPrompts(prompts, const []), prompts);
  });
}
