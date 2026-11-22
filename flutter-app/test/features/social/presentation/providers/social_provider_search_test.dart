import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/social/data/datasources/social_remote_datasource.dart';
import 'package:lexilingo_app/features/social/data/repositories/social_repository.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';

class _SearchRemote extends SocialRemoteDataSource {
  _SearchRemote() : super(apiClient: ApiClient());

  final pending = <String, Completer<List<UserSocialProfileEntity>>>{};

  @override
  Future<List<UserSocialProfileEntity>> searchUsers(
    String query, {
    int limit = 20,
  }) {
    return (pending[query] = Completer()).future;
  }
}

UserSocialProfileEntity _user(String name) => UserSocialProfileEntity(
  userId: name,
  username: name,
  displayName: name,
);

void main() {
  test('a slow earlier search cannot overwrite a newer one', () async {
    final remote = _SearchRemote();
    final provider = SocialProvider(
      repository: SocialRepository(remote: remote),
    );

    final first = provider.searchUsers('ab');
    final second = provider.searchUsers('abc');

    remote.pending['abc']!.complete([_user('abc')]);
    await second;
    remote.pending['ab']!.complete([_user('ab-old')]);
    await first;

    expect(provider.searchResults.map((u) => u.username), ['abc']);
    expect(provider.isSearching, isFalse);
  });

  test('clearSearch drops an in-flight response', () async {
    final remote = _SearchRemote();
    final provider = SocialProvider(
      repository: SocialRepository(remote: remote),
    );

    final search = provider.searchUsers('abc');
    provider.clearSearch();
    remote.pending['abc']!.complete([_user('abc')]);
    await search;

    expect(provider.searchResults, isEmpty);
    expect(provider.searchQuery, isEmpty);
    expect(provider.isSearching, isFalse);
  });
}
