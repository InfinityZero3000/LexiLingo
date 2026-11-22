import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';

class DiscoverFeed {
  const DiscoverFeed({this.book, this.podcast});

  final Book? book;
  final Podcast? podcast;
}

const _cefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

/// The same pick for the whole week, so the card does not reshuffle on every
/// visit. Weeks are counted from the epoch in UTC.
T? pickWeekly<T>(List<T> items, DateTime now) {
  if (items.isEmpty) return null;
  final days =
      now.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  return items[(days ~/ 7) % items.length];
}

/// The learner's level, then the one below, then the one above.
List<String> levelsToTry(String level) {
  final upper = level.toUpperCase();
  final index = _cefrLevels.indexOf(upper);
  if (index < 0) return [upper];
  return [
    upper,
    if (index > 0) _cefrLevels[index - 1],
    if (index < _cefrLevels.length - 1) _cefrLevels[index + 1],
  ];
}

/// Items at exactly [level]; only when there are none, those one step away.
List<T> atLevelOrNeighbour<T>(
  List<T> items,
  String level,
  String Function(T item) levelOf,
) {
  final tries = levelsToTry(level);
  final exact = items.where((i) => levelOf(i).toUpperCase() == tries.first);
  if (exact.isNotEmpty) return exact.toList();
  return items
      .where((i) => tries.skip(1).contains(levelOf(i).toUpperCase()))
      .toList();
}

/// One failing source hides only its own block.
Future<DiscoverFeed> loadDiscoverFeed(
  String level, {
  BookRepository? books,
  PodcastRepository? podcasts,
  DateTime? now,
}) async {
  final clock = now ?? DateTime.now();
  final results = await Future.wait([
    _weeklyBook(level, books ?? sl<BookRepository>(), clock),
    _weeklyPodcast(level, podcasts ?? sl<PodcastRepository>(), clock),
  ]);
  return DiscoverFeed(
    book: results[0] as Book?,
    podcast: results[1] as Podcast?,
  );
}

Future<Book?> _weeklyBook(
  String level,
  BookRepository repository,
  DateTime now,
) async {
  try {
    for (final candidate in levelsToTry(level)) {
      final found = await repository.getRecommendedBooks(cefrLevel: candidate);
      if (found.isNotEmpty) return pickWeekly(found, now);
    }
  } catch (_) {
    // A failed shelf only hides the book block.
  }
  return null;
}

Future<Podcast?> _weeklyPodcast(
  String level,
  PodcastRepository repository,
  DateTime now,
) async {
  try {
    final categories = await repository.getCuratedPodcasts();
    final seen = <String>{};
    final all = [
      for (final category in categories)
        for (final podcast in category.podcasts)
          if (seen.add(podcast.id)) podcast,
    ];
    return pickWeekly(atLevelOrNeighbour(all, level, (p) => p.cefrLevel), now);
  } catch (_) {
    return null;
  }
}
