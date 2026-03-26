import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';

/// Minimalist dialogue bubble for Lexi chat.
///
/// Clean, simple design without avatars:
///  - Lexi (left-aligned): Simple text bubble with subtle styling
///  - User (right-aligned): Clean colored bubble
class LexiDialogueBubble extends StatelessWidget {
  final LexiMessage message;
  final VoidCallback? onPlayAudio;
  final VoidCallback? onShowCorrections;
  final String? lexiAvatarUrl;

  const LexiDialogueBubble({
    super.key,
    required this.message,
    this.onPlayAudio,
    this.onShowCorrections,
    this.lexiAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return message.isLexi
        ? _buildLexiBubble(context)
        : _buildUserBubble(context);
  }

  Widget _buildLexiBubble(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sender label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lexi',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : AppColors.textGrey,
                  letterSpacing: 0.2,
                ),
              ),
              if (message.hasCorrections) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow.withValues(alpha: isDark ? 0.2 : 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_fix_high_rounded,
                        size: 10,
                        color: AppColors.accentYellow,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Correction',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: AppColors.accentYellow,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Message bubble
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C2A38)
                : const Color(0xFFF6F7F8),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF2A3A4A)
                  : const Color(0xFFE8ECEF),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Message text
              Text(
                message.content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: isDark ? Colors.white : AppColors.textDark,
                  letterSpacing: -0.1,
                ),
              ),
              // Action buttons row
              if (message.hasAudio || message.hasCorrections)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (message.hasAudio)
                        _buildActionChip(
                          context,
                          icon: Icons.volume_up_rounded,
                          label: 'Listen',
                          onTap: onPlayAudio,
                        ),
                      if (message.hasCorrections)
                        _buildActionChip(
                          context,
                          icon: Icons.auto_fix_high_rounded,
                          label: 'View Notes',
                          onTap: onShowCorrections,
                          color: AppColors.accentYellow,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserBubble(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Text(
            message.content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.white,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipColor = color ?? AppColors.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: chipColor.withValues(alpha: isDark ? 0.3 : 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: chipColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: chipColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
