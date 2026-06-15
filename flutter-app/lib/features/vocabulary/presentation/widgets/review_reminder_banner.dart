import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/flashcard_review_screen.dart';
import 'package:lexilingo_app/features/vocabulary/vocabulary_di.dart' as vocab_di;

/// Hiển thị banner nhắc nhở ở đầu màn hình khi có từ cần ôn tập.
/// Tự động ẩn sau 8 giây hoặc khi user bấm nút dismiss.
class ReviewReminderBanner extends StatefulWidget {
  const ReviewReminderBanner({super.key});

  @override
  State<ReviewReminderBanner> createState() => _ReviewReminderBannerState();
}

class _ReviewReminderBannerState extends State<ReviewReminderBanner>
    with SingleTickerProviderStateMixin {
  int _dueCount = 0;
  bool _dismissed = false;
  bool _loaded = false;
  late final AnimationController _controller;
  late final Animation<double> _heightAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heightAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _loadDueCount();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadDueCount() async {
    final result = await vocab_di
        .getIt<VocabularyRepository>()
        .getVocabularyStats();
    if (!mounted) return;
    final count = result.fold(
      (_) => 0,
      (stats) => stats['due_for_review'] as int? ?? 0,
    );
    setState(() {
      _dueCount = count;
      _loaded = true;
    });
    if (count > 0) {
      _controller.forward();
    }
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      if (mounted) setState(() => _dismissed = true);
    });
  }

  void _startReview() {
    _dismiss();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => vocab_di.getIt<FlashcardProvider>(),
          child: const FlashcardReviewScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _dismissed || _dueCount == 0) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A2744) : const Color(0xFFE8F1FF);
    final textColor = isDark ? Colors.white : const Color(0xFF1A237E);
    final accentColor = AppColorRoles.primary(isDark);

    return SizeTransition(
      sizeFactor: _heightAnim,
      axisAlignment: -1,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_active_rounded,
                color: accentColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 13, color: textColor),
                  children: [
                    TextSpan(
                      text: '$_dueCount từ ',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: accentColor),
                    ),
                    const TextSpan(text: 'đang đợi bạn ôn tập!'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _startReview,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Ôn ngay',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _dismiss,
              child: Icon(Icons.close, size: 18, color: textColor.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
