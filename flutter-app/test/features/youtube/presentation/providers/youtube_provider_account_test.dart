import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/youtube/data/repositories/youtube_repository.dart';
import 'package:lexilingo_app/features/youtube/domain/entities/youtube_entities.dart';
import 'package:lexilingo_app/features/youtube/presentation/providers/youtube_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo extends Fake implements YouTubeRepository {}

YouTubeVideo _video(String id) => YouTubeVideo(
  videoId: id,
  title: 'Video $id',
  description: '',
  channelTitle: 'c',
  channelId: 'c',
  publishedAt: '',
  thumbnailUrl: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'watching a video right after sign-in keeps the stored history',
    () async {
      SharedPreferences.setMockInitialValues({
        'u:user-b:youtube_watch_history': jsonEncode([
          _video('old1').toJson(),
          _video('old2').toJson(),
        ]),
      });
      await UserScopeService.setActiveUserId('user-b');
      final provider = YouTubeProvider(repository: _Repo());
      provider.reset(); // sign-out of the previous learner: memory is empty

      await provider.addToHistory(_video('new'));

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(
        prefs.getString('u:user-b:youtube_watch_history')!,
      );
      expect((stored as List).map((v) => v['video_id']), [
        'new',
        'old1',
        'old2',
      ]);
      expect(provider.watchHistory.map((v) => v.videoId), [
        'new',
        'old1',
        'old2',
      ]);
      provider.dispose();
    },
  );

  test('saving a video right after sign-in keeps the stored ones', () async {
    SharedPreferences.setMockInitialValues({});
    await UserScopeService.setActiveUserId('user-b');
    final first = YouTubeProvider(repository: _Repo());
    await first.saveVideo(_video('kept'));
    first.dispose();

    final provider = YouTubeProvider(repository: _Repo());
    provider.reset();
    await provider.saveVideo(_video('fresh'));

    expect(provider.savedVideos.map((v) => v.videoId).toSet(), {
      'kept',
      'fresh',
    });
    provider.dispose();
  });

  test('the stored lists load once, not on every action', () async {
    SharedPreferences.setMockInitialValues({});
    await UserScopeService.setActiveUserId('user-b');
    final provider = YouTubeProvider(repository: _Repo());

    await provider.addToHistory(_video('a'));
    await provider.addToHistory(_video('b'));

    expect(provider.watchHistory.map((v) => v.videoId), ['b', 'a']);
    provider.dispose();
  });

  test('a sign-out during the load drops the previous learner\'s video', () async {
    SharedPreferences.setMockInitialValues({});
    await UserScopeService.setActiveUserId('user-a');
    final provider = YouTubeProvider(repository: _Repo());

    final pending = provider.addToHistory(_video('a-video'));
    provider.reset(); // account switch while the stored lists load
    await UserScopeService.setActiveUserId('user-b');
    await pending;

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('u:user-b:youtube_watch_history'), isNull);
    expect(provider.watchHistory, isEmpty);
    provider.dispose();
  });
}
