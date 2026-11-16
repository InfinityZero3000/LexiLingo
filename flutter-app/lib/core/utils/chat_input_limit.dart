import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/network/response_models.dart';

/// Mirrors `MAX_CHAT_MESSAGE_CHARS` in ai-service/api/models/schemas.py.
const int kMaxChatMessageChars = 4000;

/// The counter stays hidden until the learner is this close to the limit.
const int kChatCounterThreshold = 3500;

/// Truncates by code point, the unit the server counts, so a paste can never
/// push the message past the limit and a surrogate pair is never split.
class ChatMessageLengthFormatter extends TextInputFormatter {
  const ChatMessageLengthFormatter({this.maxChars = kMaxChatMessageChars});

  final int maxChars;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final runes = newValue.text.runes;
    if (runes.length <= maxChars) return newValue;
    final text = String.fromCharCodes(runes.take(maxChars));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Use with `TextField.inputFormatters`.
const List<TextInputFormatter> chatInputFormatters = [
  ChatMessageLengthFormatter(),
];

/// Use with `TextField.buildCounter`
/// (enforcement is [ChatMessageLengthFormatter]); null hides the counter.
Widget? buildChatInputCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) {
  if (currentLength < kChatCounterThreshold) return null;
  final theme = Theme.of(context);
  final atLimit = currentLength >= kMaxChatMessageChars;
  return Text(
    '$currentLength / $kMaxChatMessageChars',
    style: theme.textTheme.bodySmall?.copyWith(
      color: atLimit
          ? theme.colorScheme.error
          : theme.colorScheme.onSurfaceVariant,
    ),
  );
}

/// True when a chat endpoint refused the message as invalid (HTTP 422), which for
/// these endpoints means longer than [kMaxChatMessageChars]. Not worth retrying or queueing.
bool isMessageTooLongError(Object error) {
  if (error is ApiErrorException) return error.isValidationError;
  return error.toString().contains('status 422');
}

String messageTooLongText() =>
    'errors.messageTooLong'.tr(namedArgs: {'max': '$kMaxChatMessageChars'});
