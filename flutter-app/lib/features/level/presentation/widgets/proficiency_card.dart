import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_list_screen.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/level/presentation/widgets/proficiency_radar_chart.dart';

/// Proficiency card with radar chart for profile page
/// Shows 5 proficiency dimensions evaluated by AI from conversations
class ProficiencyCard extends StatelessWidget {
  const ProficiencyCard({super.key});

  /// Minimum lessons/interactions before scores are shown
  static const int unlockThreshold = 15;

  @override
  Widget build(BuildContext context) {
    return Consumer<ProficiencyProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading &&
            provider.profile == ProficiencyProfile.empty()) {
          return _buildLoadingState(context);
        }

        return _buildContent(context, provider);
      },
    );
  }

  Widget _buildContent(BuildContext context, ProficiencyProvider provider) {
    final profile = provider.profile;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    final hasEnoughData =
        profile.exercisesCompleted >= unlockThreshold ||
        profile.lessonsCompleted >= unlockThreshold;

    // Map backend 6 skills → 5 display dimensions
    final displayScores = _mapToDisplayDimensions(profile.skills);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Text(
            'Your Proficiency',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? accent.withValues(alpha: 0.22)
                  : AppColors.slate200,
            ),
          ),
          child: Column(
            children: [
              // Description text
              if (!hasEnoughData) ...[
                Text(
                  'Your scores will show after you do first few lessons. Start learning now!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Radar chart with center icon
              Center(
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ProficiencyRadarChart(
                        scores: hasEnoughData
                            ? displayScores
                            : {
                                'Pronunciation': 0.0,
                                'Vocabulary': 0.0,
                                'Fluency': 0.0,
                                'Grammar': 0.0,
                                'Intonation': 0.0,
                              },
                        size: 240,
                        fillColor: isDark
                            ? accent.withValues(alpha: 0.25)
                            : AppColors.primary.withValues(alpha: 0.15),
                        strokeColor: accent,
                        gridColor: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : AppColors.slate200,
                        animate: true,
                      ),
                      // Center decorative icon
                      if (!hasEnoughData)
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceDarkMuted.withValues(
                                    alpha: 0.9,
                                  )
                                : Colors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(
                                      0xFF6366F1,
                                    ).withValues(alpha: 0.3)
                                  : AppColors.slate200,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.hourglass_bottom_rounded,
                            size: 28,
                            color: isDark
                                ? accent.withValues(alpha: 0.6)
                                : const Color(
                                    0xFF6366F1,
                                  ).withValues(alpha: 0.4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Unlock message
              if (!hasEnoughData) ...[
                Text(
                  'Your scores unlock after around $unlockThreshold lessons',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action buttons
              Row(
                children: [
                  // Share button
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () {
                        // TODO: Implement share proficiency
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.15)
                                : AppColors.slate200,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.share_rounded,
                              size: 16,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Share',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Start Lessons button
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CourseListScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Start Lessons',
                              style: TextStyle(
                                color: AppColors.surfaceLight,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Text(
            'Your Proficiency',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? accent.withValues(alpha: 0.22)
                  : AppColors.slate200,
            ),
          ),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: LottieLoadingWidget.medium(),
            ),
          ),
        ),
      ],
    );
  }

  /// Map 6 backend skill scores to 5 display dimensions
  Map<String, double> _mapToDisplayDimensions(
    Map<SkillType, SkillScore> skills,
  ) {
    final speaking = skills[SkillType.speaking]?.score ?? 0;
    final listening = skills[SkillType.listening]?.score ?? 0;
    final vocabulary = skills[SkillType.vocabulary]?.score ?? 0;
    final grammar = skills[SkillType.grammar]?.score ?? 0;
    final reading = skills[SkillType.reading]?.score ?? 0;
    final writing = skills[SkillType.writing]?.score ?? 0;

    return {
      'Pronunciation': speaking,
      'Vocabulary': vocabulary * 0.7 + reading * 0.3,
      'Fluency': speaking * 0.6 + listening * 0.4,
      'Grammar': grammar * 0.8 + writing * 0.2,
      'Intonation': speaking * 0.5 + listening * 0.5,
    };
  }
}
