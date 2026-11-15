import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/featured_courses_section.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/recommendations_section.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/section_title.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';

/// One rail for everything the learner has not chosen yet: personal
/// recommendations first, then featured courses not already recommended.
class DiscoverRail extends StatefulWidget {
  const DiscoverRail({super.key});

  static const double railHeight = 212;

  @override
  State<DiscoverRail> createState() => _DiscoverRailState();
}

class _DiscoverRailState extends State<DiscoverRail> {
  late final Future<List<RecommendationItem>> _future =
      loadHomeRecommendations();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecommendationItem>>(
      future: _future,
      builder: (context, snapshot) {
        final loadingRecommendations =
            snapshot.connectionState == ConnectionState.waiting;
        final recommendations = snapshot.data ?? const <RecommendationItem>[];

        return Consumer<HomeProvider>(
          builder: (context, home, _) {
            final recommendedCourseIds = {
              for (final item in recommendations)
                if (item.itemType == 'course') item.itemId,
            };
            final courses = home.featuredCourses
                .where((course) => !recommendedCourseIds.contains(course.id))
                .toList();
            final loadingCourses =
                home.isLoadingCourses && home.featuredCourses.isEmpty;

            final Widget body;
            if (recommendations.isEmpty && courses.isEmpty) {
              body = loadingCourses || loadingRecommendations
                  ? ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: 3,
                      itemBuilder: (context, index) => const SizedBox(
                        width: 220,
                        child: CardSkeleton(isHorizontal: false),
                      ),
                    )
                  : FeaturedCoursesEmptyState(provider: home);
            } else {
              body = ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: recommendations.length + courses.length,
                itemBuilder: (context, index) => index < recommendations.length
                    ? RecommendationCard(
                        item: recommendations[index],
                        slot: index % 5,
                      )
                    : FeaturedCourseCard(
                        course: courses[index - recommendations.length],
                      ),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(title: 'home.discover'.tr()),
                  const SizedBox(height: 8),
                  SizedBox(height: DiscoverRail.railHeight, child: body),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
