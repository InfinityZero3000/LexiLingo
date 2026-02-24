import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Beautiful empty notification state widget with simple bell icon
/// Clean, minimal design without complex painters
class EmptyNotificationWidget extends StatefulWidget {
  final String title;
  final String description;
  final String? buttonText;
  final VoidCallback? onRefresh;

  const EmptyNotificationWidget({
    super.key,
    this.title = 'No Notifications Yet',
    this.description = 'You\'ll see notifications about your learning progress, achievements, and reminders here.',
    this.buttonText = 'Refresh',
    this.onRefresh,
  });

  @override
  State<EmptyNotificationWidget> createState() => _EmptyNotificationWidgetState();
}

class _EmptyNotificationWidgetState extends State<EmptyNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildIllustration(context, isDark),
            const SizedBox(height: 40),
            _buildTitle(context, isDark),
            const SizedBox(height: 16),
            _buildDescription(context, isDark),
            if (widget.buttonText != null && widget.onRefresh != null) ...[
              const SizedBox(height: 36),
              _buildRefreshButton(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIllustration(BuildContext context, bool isDark) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        );
      },
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.15),
              AppColors.primary.withValues(alpha: 0.05),
              Colors.transparent,
            ],
            stops: const [0.3, 0.7, 1.0],
          ),
        ),
        child: Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.primary.withValues(alpha: 0.1),
            ),
            child: Icon(
              Icons.notifications_outlined,
              size: 52,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, bool isDark) {
    return Text(
      widget.title,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
            letterSpacing: -0.5,
          ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildDescription(BuildContext context, bool isDark) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Text(
        widget.description,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              height: 1.6,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRefreshButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: widget.onRefresh,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 20),
            const SizedBox(width: 8),
            Text(
              widget.buttonText!,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
