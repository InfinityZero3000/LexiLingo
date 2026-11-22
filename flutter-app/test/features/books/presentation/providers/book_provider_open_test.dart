import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';

class _Repo extends BookRepository {
  _Repo({this.fail = false});

  bool fail;

  @override
  Future<UserBook?> getProgress(String bookId) async {
    if (fail) throw Exception('offline');
    return null;
  }

  @override
  Future<List<Bookmark>> getBookmarks(String bookId) async => const [];

  @override
  Future<String?> getDownloadedPath(String bookId) async => null;
}

const _book = Book(id: 'b1', title: 'T');

void main() {
  test('openBook reports a repository failure instead of throwing', () async {
    final repo = _Repo(fail: true);
    final provider = BookProvider(repository: repo);

    await provider.openBook(_book);

    expect(provider.openFailed, isTrue);
    expect(provider.error, isNotNull);
    expect(provider.isLoading, isFalse);
  });

  test('a retry that succeeds clears the failure', () async {
    final repo = _Repo(fail: true);
    final provider = BookProvider(repository: repo);
    await provider.openBook(_book);

    repo.fail = false;
    await provider.openBook(_book);

    expect(provider.openFailed, isFalse);
    expect(provider.error, isNull);
  });
}
