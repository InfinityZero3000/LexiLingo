import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/admin_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class TopicsScreen extends StatelessWidget {
  const TopicsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        backgroundColor: AdminColors.background,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AdminColors.onSurface),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text(
          'Conversation Topics',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AdminColors.outlineVariant, width: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AdminColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    color: AdminColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Topic management is not available in the mobile admin yet',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.sectionTitle?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AdminColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Conversation topics are managed by the separate AI admin service. Use the web admin until that service is configured for mobile.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AdminColors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
