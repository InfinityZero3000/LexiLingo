import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/achievements/data/badge_asset_mapper.dart';

void main() {
  const media = 'https://api.example.test';

  BadgeImage resolve(String slug, String? icon) =>
      resolveBadgeImage(slug: slug, badgeIcon: icon, mediaBaseUrl: media);

  test('a bundled badge wins over whatever the row stores', () {
    final image = resolve(
      'week_warrior',
      'https://cdn.jsdelivr.net/gh/x/LexiLingo@feature/flutter-app/assets/badges/streak7.png',
    );
    expect(image.kind, BadgeImageKind.asset);
    expect(image.value, 'assets/badges/streak7.png');
  });

  test('slug lookup is case and whitespace tolerant', () {
    expect(resolve(' Week_Warrior ', null).kind, BadgeImageKind.asset);
  });

  test('an uploaded /media path resolves against the media host', () {
    final image = resolve('custom', '/media/badges/custom.png');
    expect(image.kind, BadgeImageKind.network);
    expect(image.value, '$media/media/badges/custom.png');
  });

  test('a trailing slash on the media host does not double up', () {
    final image = resolveBadgeImage(
      slug: 'custom',
      badgeIcon: '/media/badges/custom.png',
      mediaBaseUrl: '$media/',
    );
    expect(image.value, '$media/media/badges/custom.png');
  });

  test('an absolute URL is used as is', () {
    final image = resolve('custom', 'https://cdn.example.test/b.png');
    expect(image.kind, BadgeImageKind.network);
    expect(image.value, 'https://cdn.example.test/b.png');
  });

  test('a legacy @feature pin for an unmapped slug is repointed to @main', () {
    final image = resolve(
      'custom',
      'https://cdn.jsdelivr.net/gh/x/LexiLingo@feature/flutter-app/assets/badges/c.png',
    );
    expect(image.kind, BadgeImageKind.network);
    expect(image.value, contains('@main/'));
    expect(image.value, isNot(contains('@feature')));
  });

  test('garbage never becomes an assets/badges path', () {
    for (final icon in [
      null,
      '',
      '  ',
      'custom.png',
      'not a url',
      'ftp://x/y',
    ]) {
      final image = resolve('custom', icon);
      expect(image.kind, BadgeImageKind.none, reason: '$icon');
      expect(image.value, isNull);
    }
  });
}
