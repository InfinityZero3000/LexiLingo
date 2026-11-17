import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/featured_courses_section.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/recommendations_section.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/section_title.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';

/// Recommendations split by what the learner would do with them: study
/// (lessons, courses), review (words), watch or read (videos, news).
({
  List<RecommendationItem> study,
  List<RecommendationItem> words,
  List<RecommendationItem> media,
})
groupRecommendations(List<RecommendationItem> items) {
  final study = <RecommendationItem>[];
  final words = <RecommendationItem>[];
  final media = <RecommendationItem>[];
  for (final item in items) {
    switch (item.itemType) {
      case 'lesson' || 'course':
        study.add(item);
      case 'vocab':
        words.add(item);
      case 'video' || 'news':
        media.add(item);
    }
  }
  // Lessons are the smaller commitment, so they lead the study rail.
  study.sort(
    (a, b) =>
        (a.itemType == 'lesson' ? 0 : 1) - (b.itemType == 'lesson' ? 0 : 1),
  );
  return (study: study, words: words, media: media);
}

/// Everything the learner has not chosen yet, one titled rail per kind of
/// content. A kind with nothing to show is left out.
class DiscoverRail extends StatefulWidget {
  const DiscoverRail({super.key, this.loader = loadHomeRecommendations});

  final Future<List<RecommendationItem>> Function() loader;

  static const double railHeight = 212;
  static const double wordsRailHeight = 112;

  @override
  State<DiscoverRail> createState() => _DiscoverRailState();
}

class _DiscoverRailState extends State<DiscoverRail> {
  late final Future<List<RecommendationItem>> _future = widget.loader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecommendationItem>>(
      future: _future,
      builder: (context, snapshot) {
        final loadingRecommendations =
            snapshot.connectionState == ConnectionState.waiting;
        final groups = groupRecommendations(
          snapshot.data ?? const <RecommendationItem>[],
        );

        return Consumer<HomeProvider>(
          builder: (context, home, _) {
            final recommendedCourseIds = {
              for (final item in groups.study)
                if (item.itemType == 'course') item.itemId,
            };
            final courses = home.featuredCourses
                .where((course) => !recommendedCourseIds.contains(course.id))
                .toList();
            final loading =
                loadingRecommendations ||
                (home.isLoadingCourses && home.featuredCourses.isEmpty);
            final studyCount = groups.study.length + courses.length;

            final Widget study;
            if (studyCount > 0) {
              study = _rail(
                height: DiscoverRail.railHeight,
                itemCount: studyCount,
                itemBuilder: (context, index) => index < groups.study.length
                    ? RecommendationCard(
                        item: groups.study[index],
                        slot: index % 5,
                      )
                    : FeaturedCourseCard(
                        course: courses[index - groups.study.length],
                      ),
              );
            } else if (loading) {
              study = _rail(
                height: DiscoverRail.railHeight,
                itemCount: 3,
                itemBuilder: (context, index) => const SizedBox(
                  width: 220,
                  child: CardSkeleton(isHorizontal: false),
                ),
              );
            } else {
              study = FeaturedCoursesEmptyState(provider: home);
            }

            return Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    title: 'home.discoverStudy'.tr(),
                    actionLabel: 'common.seeAll'.tr(),
                    onAction: () => Navigator.pushNamed(context, '/courses'),
                  ),
                  const SizedBox(height: 8),
                  study,
                  if (groups.words.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    SectionTitle(
                      title: 'home.discoverWords'.tr(),
                      actionLabel: 'home.discoverWordsAction'.tr(),
                      onAction: () =>
                          Navigator.pushNamed(context, '/vocabulary/review'),
                    ),
                    const SizedBox(height: 8),
                    _rail(
                      height: DiscoverRail.wordsRailHeight,
                      itemCount: groups.words.length,
                      itemBuilder: (context, index) =>
                          VocabSuggestionTile(item: groups.words[index]),
                    ),
                  ],
                  if (groups.media.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    SectionTitle(
                      title: 'home.discoverMedia'.tr(),
                      actionLabel: 'common.seeAll'.tr(),
                      onAction: () => Navigator.pushNamed(context, '/youtube'),
                    ),
                    const SizedBox(height: 8),
                    _rail(
                      height: DiscoverRail.railHeight,
                      itemCount: groups.media.length,
                      itemBuilder: (context, index) => RecommendationCard(
                        item: groups.media[index],
                        slot: index % 5,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Bottom padding leaves room for the tactile cards' drop edge.
  Widget _rail({
    required double height,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
  }) => SizedBox(
    // Fixed-height cards hold wrapped text, so they grow with the text size.
    height: height * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 6),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    ),
  );
}
