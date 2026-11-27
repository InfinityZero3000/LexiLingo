import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/social/data/repositories/social_repository.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';

const _leo = UserSocialProfileEntity(
  userId: 'leo',
  username: 'leo',
  displayName: 'Leo',
);

class _Repo implements SocialRepository {
  @override
  Future<List<UserSocialProfileEntity>> getSuggestions({
    int limit = 10,
    int offset = 0,
  }) async => [_leo];

  @override
  Future<bool> followUser(String userId) async => true;

  @override
  Future<bool> unfollowUser(String userId) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('someone followed from suggestions shows up under Following', () async {
    final provider = SocialProvider(repository: _Repo());
    await provider.loadSuggestedUsers();

    await provider.followUser('leo');
    await provider.followUser('leo');

    expect(provider.following.map((u) => (u.userId, u.isFollowing)), [
      ('leo', true),
    ]);
    expect(provider.followingCount, 1);
  });

  test('unfollowing takes them out of Following again', () async {
    final provider = SocialProvider(repository: _Repo());
    await provider.loadSuggestedUsers();
    await provider.followUser('leo');

    await provider.unfollowUser('leo');

    expect(provider.following, isEmpty);
    expect(provider.followingCount, 0);
  });
}
