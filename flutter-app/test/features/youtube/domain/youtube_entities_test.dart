import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/youtube/domain/entities/youtube_entities.dart';

void main() {
  test('decodeHtmlEntities decodes numeric and named entities once', () {
    expect(decodeHtmlEntities('I&#39;m scared I won&#39;t'), "I'm scared I won't");
    expect(decodeHtmlEntities('A &amp; B &quot;x&quot; &#x27;y&#x27;'), 'A & B "x" \'y\'');
    expect(decodeHtmlEntities('&amp;#39;'), '&#39;');
    expect(decodeHtmlEntities('plain'), 'plain');
  });

  test('YouTubeVideo.fromJson decodes a cached escaped title', () {
    final v = YouTubeVideo.fromJson({'video_id': 'x', 'title': 'I&#39;m scared', 'channel_title': 'Tom &amp; Jerry'});
    expect(v.title, "I'm scared");
    expect(v.channelTitle, 'Tom & Jerry');
  });
}
