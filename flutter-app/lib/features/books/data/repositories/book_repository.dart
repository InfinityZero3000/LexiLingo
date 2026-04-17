import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/services/local_cache_service.dart';
import '../../domain/entities/book_entities.dart';

/// Data access layer for books.
///
/// Combines backend API (Gutendex + Open Library proxy) with
/// local SQLite cache and SharedPreferences for offline access.
///
/// Phase 5: Book Reading.
class BookRepository {
  final http.Client _client;
  final LocalCacheService _cache;
  final ApiClient? _apiClient;

  BookRepository({
    http.Client? client,
    LocalCacheService? cache,
    ApiClient? apiClient,
  }) : _client = client ?? http.Client(),
       _cache = cache ?? LocalCacheService.instance,
       _apiClient = apiClient;

  String get _baseUrl => '${ApiConfig.baseUrl}/books';

  // ── Book Discovery ────────────────────────────────────────────

  /// Fetch curated books, optionally filtered by [cefrLevel].
  Future<List<Book>> getRecommendedBooks({String? cefrLevel}) async {
    final params = <String, String>{if (cefrLevel != null) 'level': cefrLevel};
    final cacheKey = 'books:recommended:${cefrLevel ?? 'all'}';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'book',
      fetchFn: () async {
        final uri = Uri.parse(
          '$_baseUrl/recommended',
        ).replace(queryParameters: params.isEmpty ? null : params);
        final response = await _client.get(uri);
        if (response.statusCode != 200) {
          throw Exception(
            'Failed to load recommended books: ${response.statusCode}',
          );
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    final books = (data?['books'] as List<dynamic>? ?? [])
        .map((e) => Book.fromJson(e as Map<String, dynamic>))
        .toList();
    return books;
  }

  /// Search for books across Gutendex + Open Library.
  Future<List<Book>> searchBooks({
    required String query,
    String? cefrLevel,
    int page = 1,
  }) async {
    final params = <String, String>{
      'q': query,
      'page': page.toString(),
      if (cefrLevel != null) 'level': cefrLevel,
    };
    final cacheKey =
        'books:search:${query.toLowerCase()}:lvl:${cefrLevel ?? 'all'}:p:$page';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'book',
      fetchFn: () async {
        final uri = Uri.parse(
          '$_baseUrl/search',
        ).replace(queryParameters: params);
        final response = await _client.get(uri);
        if (response.statusCode != 200) {
          throw Exception('Book search failed: ${response.statusCode}');
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    return (data?['books'] as List<dynamic>? ?? [])
        .map((e) => Book.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Quiz ─────────────────────────────────────────────────────

  /// Fetch the comprehension quiz for [bookId] chapter [chapter].
  Future<BookQuiz> getChapterQuiz({
    required String bookId,
    required int chapter,
  }) async {
    final cacheKey = 'books:quiz:$bookId:ch:$chapter';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'book',
      fetchFn: () async {
        final uri = Uri.parse(
          '$_baseUrl/$bookId/quiz',
        ).replace(queryParameters: {'chapter': chapter.toString()});
        final response = await _client.get(uri);
        if (response.statusCode != 200) {
          throw Exception('Quiz fetch failed: ${response.statusCode}');
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    return BookQuiz.fromJson(data ?? {});
  }

  // ── Reading Progress ──────────────────────────────────────────

  static const _progressKeyPrefix = 'book_progress_';

  Future<UserBook?> getProgress(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_progressKeyPrefix$bookId');
    if (raw == null) return null;
    return UserBook.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveProgress(UserBook progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_progressKeyPrefix${progress.bookId}',
      jsonEncode(progress.toJson()),
    );
  }

  Future<List<UserBook>> getAllProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_progressKeyPrefix));
    return keys.map((k) {
      final raw = prefs.getString(k)!;
      return UserBook.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }).toList();
  }

  // ── Bookmarks ─────────────────────────────────────────────────

  static const _bookmarksKeyPrefix = 'book_bookmarks_';

  Future<List<Bookmark>> getBookmarks(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_bookmarksKeyPrefix$bookId');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    final bookmarks = await getBookmarks(bookmark.bookId);
    // Prevent duplicates at same page
    final updated = [
      ...bookmarks.where((b) => b.page != bookmark.page),
      bookmark,
    ]..sort((a, b) => a.page.compareTo(b.page));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_bookmarksKeyPrefix${bookmark.bookId}',
      jsonEncode(updated.map((b) => b.toJson()).toList()),
    );
  }

  Future<void> removeBookmark(String bookId, int page) async {
    final bookmarks = await getBookmarks(bookId);
    final updated = bookmarks.where((b) => b.page != page).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_bookmarksKeyPrefix$bookId',
      jsonEncode(updated.map((b) => b.toJson()).toList()),
    );
  }

  Future<bool> isBookmarked(String bookId, int page) async {
    final bookmarks = await getBookmarks(bookId);
    return bookmarks.any((b) => b.page == page);
  }

  // ── Reader Settings ───────────────────────────────────────────

  static const _settingsKey = 'reader_settings';

  Future<ReaderSettings> getReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return const ReaderSettings();
    return ReaderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveReaderSettings(ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  // ── Offline Download (plain text) ─────────────────────────────

  static const _downloadedKeyPrefix = 'book_downloaded_';

  /// Download and cache the plain-text content of [book].
  ///
  /// Returns the local file path on success.
  Future<String> downloadBook(Book book) async {
    final appDir = await getApplicationDocumentsDirectory();
    final booksDir = Directory('${appDir.path}/books');
    if (!booksDir.existsSync()) booksDir.createSync(recursive: true);

    final safeId = book.id.replaceAll(RegExp(r'[^\w-]'), '_');
    final filePath = '${booksDir.path}/$safeId.txt';

    if (!File(filePath).existsSync()) {
      final request = http.Request('GET', Uri.parse(book.downloadUrl))
        ..followRedirects = true
        ..maxRedirects = 5;
      var streamed = await _client.send(request);
      // Handle redirect manually if needed
      if (streamed.statusCode == 301 || streamed.statusCode == 302) {
        final location = streamed.headers['location'];
        if (location != null) {
          final redirectRequest = http.Request('GET', Uri.parse(location))
            ..followRedirects = true
            ..maxRedirects = 5;
          streamed = await _client.send(redirectRequest);
        }
      }
      if (streamed.statusCode >= 400) {
        throw Exception('Download failed: HTTP ${streamed.statusCode}');
      }
      final sink = File(filePath).openWrite();
      await streamed.stream.pipe(sink);
      await sink.flush();
      await sink.close();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_downloadedKeyPrefix${book.id}', filePath);
    return filePath;
  }

  Future<String?> getDownloadedPath(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('$_downloadedKeyPrefix$bookId');
    if (path == null) return null;
    return File(path).existsSync() ? path : null;
  }

  Future<void> deleteDownload(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('$_downloadedKeyPrefix$bookId');
    if (path != null && File(path).existsSync()) {
      await File(path).delete();
    }
    await prefs.remove('$_downloadedKeyPrefix$bookId');
  }

  bool isDownloaded(String bookId, {required String downloadedPath}) =>
      downloadedPath.isNotEmpty && File(downloadedPath).existsSync();

  // ── XP Award ─────────────────────────────────────────────────

  /// Award XP for book activity (quiz completion, reading milestone).
  ///
  /// Silently returns on failure — XP awards should never block UX.
  Future<void> awardXP({
    required int baseXp,
    required String sourceId,
    String sourceDetail = 'book_reading',
  }) async {
    final client = _apiClient;
    if (client == null) return;

    try {
      await client.post(
        '/xp/award',
        body: {
          'source': 'book',
          'base_xp': baseXp,
          'source_id': sourceId,
          'source_detail': sourceDetail,
        },
      );
    } catch (e) {
      debugPrint('BookRepository.awardXP: $e');
    }
  }

  // ── Text Content ──────────────────────────────────────────────

  /// Fetch plain-text content for [book].
  ///
  /// Resolves: local downloaded file → streaming network fetch.
  Future<String> fetchBookText(Book book) async {
    final localPath = await getDownloadedPath(book.id);
    if (localPath != null && File(localPath).existsSync()) {
      return File(localPath).readAsString();
    }

    final request = http.Request('GET', Uri.parse(book.downloadUrl))
      ..followRedirects = true
      ..maxRedirects = 5;
    final streamed = await _client.send(request);
    if (streamed.statusCode == 301 || streamed.statusCode == 302) {
      // Manual redirect follow if auto-redirect didn't work
      final location = streamed.headers['location'];
      if (location != null) {
        final redirectRequest = http.Request('GET', Uri.parse(location))
          ..followRedirects = true
          ..maxRedirects = 5;
        final redirected = await _client.send(redirectRequest);
        if (redirected.statusCode >= 400) {
          throw Exception(
            'Failed to fetch book text: HTTP ${redirected.statusCode}',
          );
        }
        final bytes = await redirected.stream.toBytes();
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
    if (streamed.statusCode >= 400) {
      throw Exception('Failed to fetch book text: HTTP ${streamed.statusCode}');
    }
    final bytes = await streamed.stream.toBytes();
    // Gutenberg serves UTF-8; decode manually to handle BOMs
    return utf8.decode(bytes, allowMalformed: true);
  }
}
