import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:easy_localization/easy_localization.dart';

/// One-row Word of the Day tile for Home. Owns its gutters so it takes no
/// space at all when there is no word. Navigates to the full word screen.
class WordOfDayCard extends StatelessWidget {
  const WordOfDayCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        final word = provider.wordOfDay;
        if (!provider.isLoadingWordOfDay && word == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: word == null
              ? const SkeletonBox(height: 96, borderRadius: 20)
              : _WordCard(word: word),
        );
      },
    );
  }
}

class _WordCard extends StatelessWidget {
  final VocabularyItemEntity word;
  const _WordCard({required this.word});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const onColor = Colors.white;
    final meaning =
        word.getTranslation(context.locale.languageCode) ?? word.definition;

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
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
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
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: onColor.withValues(alpha: 0.85),
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
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: word.word,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: onColor,
                            ),
                          ),
                          if (word.pronunciation != null)
                            TextSpan(
                              text: '  ${word.pronunciation}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: onColor.withValues(alpha: 0.8),
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meaning,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                        color: onColor.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: onColor.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
