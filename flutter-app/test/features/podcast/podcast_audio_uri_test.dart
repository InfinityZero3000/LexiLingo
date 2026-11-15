import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';

void main() {
  test('routes the publisher URL through the backend audio resolver', () {
    const source = 'http://open.live.bbc.co.uk/x/vpid/p0pmkqml.mp3?a=1&b=2';
    final uri = podcastAudioUri(source);

    expect(uri.toString(), startsWith('${ApiConfig.baseUrl}/podcasts/audio?'));
    expect(uri.queryParameters['url'], source);
  });

  test('leaves a URL without a scheme untouched', () {
    expect(podcastAudioUri('').toString(), '');
  });
}
