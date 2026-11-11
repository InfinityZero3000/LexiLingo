import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:easy_localization/easy_localization.dart';

/// Home-screen tile for the Word of the Day. Has no outer margin: the parent
/// row owns the gutters, and it stretches to the row's height.
/// Navigates to the full word screen on tap.
class WordOfDayCard extends StatelessWidget {
  const WordOfDayCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        if (provider.isLoadingWordOfDay) {
          return const SkeletonBox(height: 132, borderRadius: 20);
        }
        final word = provider.wordOfDay;
        if (word == null) return const SizedBox.shrink();
        return _WordCard(word: word);
      },
    );
  }
}

class _WordCard extends StatelessWidget {
  final VocabularyItemEntity word;
  const _WordCard({required this.word});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).pushNamed('/vocabulary/word-of-day', arguments: word),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColorRoles.primaryGradient(isDark),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'vocabulary.wordOfTheDay'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CefrBadge(
                    level: word.difficultyLevel,
                    size: CefrBadgeSize.small,
                    onColored: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                word.word,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              if (word.pronunciation != null)
                Text(
                  word.pronunciation!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.75),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                word.definition,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
