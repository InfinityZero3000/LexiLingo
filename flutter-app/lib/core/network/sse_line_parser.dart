import 'dart:convert';

/// One parsed SSE frame: the `event:` name (null if the server omitted it)
/// and the raw `data:` payload string.
class SseEvent {
  final String? event;
  final String data;
  const SseEvent(this.event, this.data);
}

/// Parses a raw SSE byte stream (as returned by `ApiClient.postStream`) into
/// [SseEvent]s, buffering across chunks since network reads don't align to
/// SSE frame boundaries.
///
/// Extracted from `LexiChatDataSource.sendMessageStream`'s inline parsing
/// loop so new SSE consumers (e.g. topic chat) reuse the same buffering
/// instead of reimplementing it. The Lexi data source itself is left
/// untouched to avoid any risk to its already-proven parsing path.
Stream<SseEvent> parseSseLines(Stream<List<int>> raw) async* {
  String? currentEvent;
  final buffer = StringBuffer();

  await for (final chunk in raw.transform(utf8.decoder)) {
    buffer.write(chunk);
    while (true) {
      final content = buffer.toString();
      final newlineIdx = content.indexOf('\n');
      if (newlineIdx == -1) break;

      final line = content.substring(0, newlineIdx).trimRight();
      buffer.clear();
      if (newlineIdx + 1 < content.length) {
        buffer.write(content.substring(newlineIdx + 1));
      }

      if (line.isEmpty) {
        // Empty line = end of SSE event block; reset event name.
        currentEvent = null;
        continue;
      }
      if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        yield SseEvent(currentEvent, line.substring(5).trim());
      }
    }
  }
}
