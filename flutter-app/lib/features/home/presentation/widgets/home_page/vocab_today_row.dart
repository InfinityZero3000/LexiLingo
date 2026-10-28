import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/daily_review_card.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/word_of_day_card.dart';

/// Word of the day (wide) beside the daily review (narrow), same height.
class VocabTodayRow extends StatelessWidget {
  const VocabTodayRow({super.key});

  @override
  Widget build(BuildContext context) {
    final hasWord = context.select<HomeProvider, bool>(
      (p) => p.isLoadingWordOfDay || p.wordOfDay != null,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: hasWord
          ? const IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: WordOfDayCard()),
                  SizedBox(width: 12),
                  Expanded(flex: 2, child: DailyReviewCard()),
                ],
              ),
            )
          : const DailyReviewCard(),
    );
  }
}
