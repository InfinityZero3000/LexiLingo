/// Badge Generator - Custom painted badges for achievements
/// 
/// Provides professional-looking, animated badges with various styles:
/// - Shield, Circle, Star, Hexagon, Medal shapes
/// - Gradient fills, glowing effects
/// - Animated shine effects
/// - Rarity-based styling

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Badge shape types
enum BadgeShape {
  circle,
  shield,
  star,
  hexagon,
  medal,
  diamond,
  ribbon,
  banner,
}

/// Badge rarity determines visual style
enum BadgeRarity {
  common,    // Gray/Bronze
  rare,      // Blue/Silver
  epic,      // Purple/Gold
  legendary, // Gold/Animated glow
}

/// Configuration for a badge
class BadgeConfig {
  final BadgeShape shape;
  final BadgeRarity rarity;
  final IconData icon;
  final String? iconUrl;
  final String? text;
  final Color? primaryColor;
  final Color? secondaryColor;
  final bool isLocked;
  final bool showShine;
  final double progress; // 0.0 - 1.0 for progress badges

  const BadgeConfig({
    this.shape = BadgeShape.circle,
    this.rarity = BadgeRarity.common,
    this.icon = Icons.emoji_events,
    this.iconUrl,
    this.text,
    this.primaryColor,
    this.secondaryColor,
    this.isLocked = false,
    this.showShine = true,
    this.progress = 1.0,
  });

  /// Get colors based on rarity
  List<Color> get rarityGradient {
    if (primaryColor != null && secondaryColor != null) {
      return [primaryColor!, secondaryColor!];
    }
    
    switch (rarity) {
      case BadgeRarity.common:
        return [const Color(0xFF9E9E9E), const Color(0xFF757575)]; // Gray
      case BadgeRarity.rare:
        return [const Color(0xFF2196F3), const Color(0xFF1565C0)]; // Blue
      case BadgeRarity.epic:
        return [const Color(0xFF9C27B0), const Color(0xFF6A1B9A)]; // Purple
      case BadgeRarity.legendary:
        return [const Color(0xFFFFD700), const Color(0xFFFFA000)]; // Gold
    }
  }

  /// Get glow color
  Color get glowColor {
    switch (rarity) {
      case BadgeRarity.common:
        return Colors.grey.withValues(alpha: 0.3);
      case BadgeRarity.rare:
        return Colors.blue.withValues(alpha: 0.4);
      case BadgeRarity.epic:
        return Colors.purple.withValues(alpha: 0.5);
      case BadgeRarity.legendary:
        return Colors.amber.withValues(alpha: 0.6);
    }
  }
}

/// Main Badge Widget with custom painting
class GeneratedBadge extends StatefulWidget {
  final BadgeConfig config;
  final double size;
  final VoidCallback? onTap;

  const GeneratedBadge({
    super.key,
    required this.config,
    this.size = 80,
    this.onTap,
  });

  @override
  State<GeneratedBadge> createState() => _GeneratedBadgeState();
}

class _GeneratedBadgeState extends State<GeneratedBadge> 
    with SingleTickerProviderStateMixin {
  late AnimationController _shineController;
  late Animation<double> _shineAnimation;

  @override
  void initState() {
    super.initState();
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _shineAnimation = Tween<double>(begin: -0.5, end: 1.5).animate(
      CurvedAnimation(parent: _shineController, curve: Curves.easeInOut),
    );
    
    if (widget.config.showShine && !widget.config.isLocked) {
      _shineController.repeat(reverse: false);
    }
  }

  @override
  void dispose() {
    _shineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _shineAnimation,
          builder: (context, child) {
            return CustomPaint(
              painter: BadgePainter(
                config: widget.config,
                shinePosition: widget.config.showShine ? _shineAnimation.value : null,
              ),
              child: Center(
                child: _buildIcon(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final iconSize = widget.size * 0.4;
    final color = widget.config.isLocked ? Colors.grey : Colors.white;

    if (widget.config.isLocked) {
      return Icon(Icons.lock, size: iconSize, color: color);
    }

    if (widget.config.iconUrl != null) {
      return Image.network(
        widget.config.iconUrl!,
        width: iconSize,
        height: iconSize,
        color: color,
        errorBuilder: (_, __, ___) => Icon(
          widget.config.icon,
          size: iconSize,
          color: color,
        ),
      );
    }

    return Icon(widget.config.icon, size: iconSize, color: color);
  }
}

/// Custom painter for badge shapes
class BadgePainter extends CustomPainter {
  final BadgeConfig config;
  final double? shinePosition;

  BadgePainter({required this.config, this.shinePosition});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Draw glow effect for epic/legendary
    if (!config.isLocked && 
        (config.rarity == BadgeRarity.epic || config.rarity == BadgeRarity.legendary)) {
      _drawGlow(canvas, center, radius);
    }

    // Draw main shape
    switch (config.shape) {
      case BadgeShape.circle:
        _drawCircle(canvas, center, radius);
        break;
      case BadgeShape.shield:
        _drawShield(canvas, size);
        break;
      case BadgeShape.star:
        _drawStar(canvas, center, radius);
        break;
      case BadgeShape.hexagon:
        _drawHexagon(canvas, center, radius);
        break;
      case BadgeShape.medal:
        _drawMedal(canvas, size, center, radius);
        break;
      case BadgeShape.diamond:
        _drawDiamond(canvas, center, radius);
        break;
      case BadgeShape.ribbon:
        _drawRibbon(canvas, size);
        break;
      case BadgeShape.banner:
        _drawBanner(canvas, size);
        break;
    }

    // Draw shine effect
    if (shinePosition != null && !config.isLocked) {
      _drawShine(canvas, size);
    }
  }

  void _drawGlow(Canvas canvas, Offset center, double radius) {
    final glowPaint = Paint()
      ..color = config.glowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    
    canvas.drawCircle(center, radius + 5, glowPaint);
  }

  void _drawCircle(Canvas canvas, Offset center, double radius) {
    final colors = config.isLocked 
        ? [Colors.grey.shade400, Colors.grey.shade600]
        : config.rarityGradient;

    // Gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    
    canvas.drawCircle(center, radius, fillPaint);

    // Border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = config.isLocked ? Colors.grey : colors[1].withValues(alpha: 0.8);
    
    canvas.drawCircle(center, radius, borderPaint);

    // Inner highlight
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.3);
    
    canvas.drawCircle(center, radius - 8, highlightPaint);
  }

  void _drawShield(Canvas canvas, Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(w * 0.5, h * 0.05);
    path.lineTo(w * 0.95, h * 0.15);
    path.lineTo(w * 0.95, h * 0.55);
    path.quadraticBezierTo(w * 0.95, h * 0.75, w * 0.5, h * 0.95);
    path.quadraticBezierTo(w * 0.05, h * 0.75, w * 0.05, h * 0.55);
    path.lineTo(w * 0.05, h * 0.15);
    path.close();

    _drawPathWithGradient(canvas, path, size);
  }

  void _drawStar(Canvas canvas, Offset center, double radius) {
    final path = Path();
    const points = 5;
    final innerRadius = radius * 0.5;
    
    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : innerRadius;
      final angle = -math.pi / 2 + (i * math.pi / points);
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    _drawPathWithGradient(canvas, path, Size(radius * 2, radius * 2));
  }

  void _drawHexagon(Canvas canvas, Offset center, double radius) {
    final path = Path();
    const sides = 6;
    
    for (int i = 0; i < sides; i++) {
      final angle = -math.pi / 2 + (i * 2 * math.pi / sides);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    _drawPathWithGradient(canvas, path, Size(radius * 2, radius * 2));
  }

  void _drawMedal(Canvas canvas, Size size, Offset center, double radius) {
    // Draw ribbon
    final ribbonPaint = Paint()
      ..color = config.isLocked ? Colors.grey.shade400 : config.rarityGradient[1];
    
    final ribbonPath = Path();
    ribbonPath.moveTo(size.width * 0.35, 0);
    ribbonPath.lineTo(size.width * 0.35, size.height * 0.4);
    ribbonPath.lineTo(size.width * 0.5, size.height * 0.3);
    ribbonPath.lineTo(size.width * 0.65, size.height * 0.4);
    ribbonPath.lineTo(size.width * 0.65, 0);
    ribbonPath.close();
    
    canvas.drawPath(ribbonPath, ribbonPaint);

    // Draw medal circle
    _drawCircle(canvas, Offset(center.dx, center.dy + radius * 0.15), radius * 0.7);
  }

  void _drawDiamond(Canvas canvas, Offset center, double radius) {
    final path = Path();
    
    path.moveTo(center.dx, center.dy - radius);  // Top
    path.lineTo(center.dx + radius, center.dy);   // Right
    path.lineTo(center.dx, center.dy + radius);   // Bottom
    path.lineTo(center.dx - radius, center.dy);   // Left
    path.close();

    _drawPathWithGradient(canvas, path, Size(radius * 2, radius * 2));
  }

  void _drawRibbon(Canvas canvas, Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    // Main ribbon body
    path.moveTo(0, h * 0.3);
    path.lineTo(w * 0.15, h * 0.2);
    path.lineTo(w * 0.85, h * 0.2);
    path.lineTo(w, h * 0.3);
    path.lineTo(w, h * 0.7);
    path.lineTo(w * 0.85, h * 0.8);
    path.lineTo(w * 0.15, h * 0.8);
    path.lineTo(0, h * 0.7);
    path.close();

    _drawPathWithGradient(canvas, path, size);
  }

  void _drawBanner(Canvas canvas, Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(w * 0.1, 0);
    path.lineTo(w * 0.9, 0);
    path.lineTo(w * 0.9, h * 0.7);
    path.lineTo(w * 0.5, h);
    path.lineTo(w * 0.1, h * 0.7);
    path.close();

    _drawPathWithGradient(canvas, path, size);
  }

  void _drawPathWithGradient(Canvas canvas, Path path, Size size) {
    final colors = config.isLocked 
        ? [Colors.grey.shade400, Colors.grey.shade600]
        : config.rarityGradient;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    
    canvas.drawPath(path, fillPaint);

    // Border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = config.isLocked ? Colors.grey : colors[1];
    
    canvas.drawPath(path, borderPaint);
  }

  void _drawShine(Canvas canvas, Size size) {
    if (shinePosition == null) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final shinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.4),
          Colors.white.withValues(alpha: 0.0),
          Colors.transparent,
        ],
        stops: [
          0.0,
          (shinePosition! - 0.1).clamp(0.0, 1.0),
          shinePosition!.clamp(0.0, 1.0),
          (shinePosition! + 0.1).clamp(0.0, 1.0),
          1.0,
        ],
      ).createShader(rect);

    canvas.drawRect(rect, shinePaint);
  }

  @override
  bool shouldRepaint(BadgePainter oldDelegate) {
    return oldDelegate.shinePosition != shinePosition ||
           oldDelegate.config != config;
  }
}

/// Pre-built badge templates for common achievements
class AchievementBadgeTemplates {
  /// Streak achievement badges (fire theme)
  static BadgeConfig streak(int days) {
    BadgeRarity rarity;
    if (days >= 365) {
      rarity = BadgeRarity.legendary;
    } else if (days >= 30) {
      rarity = BadgeRarity.epic;
    } else if (days >= 7) {
      rarity = BadgeRarity.rare;
    } else {
      rarity = BadgeRarity.common;
    }

    return BadgeConfig(
      shape: BadgeShape.shield,
      rarity: rarity,
      icon: Icons.local_fire_department,
      primaryColor: const Color(0xFFFF5722),
      secondaryColor: const Color(0xFFE64A19),
    );
  }

  /// Lesson completion badges (book theme)
  static BadgeConfig lessons(int count) {
    BadgeRarity rarity;
    if (count >= 500) {
      rarity = BadgeRarity.legendary;
    } else if (count >= 100) {
      rarity = BadgeRarity.epic;
    } else if (count >= 50) {
      rarity = BadgeRarity.rare;
    } else {
      rarity = BadgeRarity.common;
    }

    return BadgeConfig(
      shape: BadgeShape.circle,
      rarity: rarity,
      icon: Icons.school,
      primaryColor: const Color(0xFF4CAF50),
      secondaryColor: const Color(0xFF388E3C),
    );
  }

  /// XP achievement badges (star theme)
  static BadgeConfig xp(int amount) {
    BadgeRarity rarity;
    if (amount >= 50000) {
      rarity = BadgeRarity.legendary;
    } else if (amount >= 10000) {
      rarity = BadgeRarity.epic;
    } else if (amount >= 1000) {
      rarity = BadgeRarity.rare;
    } else {
      rarity = BadgeRarity.common;
    }

    return BadgeConfig(
      shape: BadgeShape.star,
      rarity: rarity,
      icon: Icons.star,
      primaryColor: const Color(0xFFFFD700),
      secondaryColor: const Color(0xFFFFA000),
    );
  }

  /// Vocabulary mastery badges (diamond theme)
  static BadgeConfig vocabulary(int count) {
    BadgeRarity rarity;
    if (count >= 1000) {
      rarity = BadgeRarity.legendary;
    } else if (count >= 200) {
      rarity = BadgeRarity.epic;
    } else if (count >= 50) {
      rarity = BadgeRarity.rare;
    } else {
      rarity = BadgeRarity.common;
    }

    return BadgeConfig(
      shape: BadgeShape.diamond,
      rarity: rarity,
      icon: Icons.translate,
      primaryColor: const Color(0xFF00BCD4),
      secondaryColor: const Color(0xFF0097A7),
    );
  }

  /// Perfect score badges (medal theme)
  static BadgeConfig perfectScore() {
    return const BadgeConfig(
      shape: BadgeShape.medal,
      rarity: BadgeRarity.epic,
      icon: Icons.military_tech,
      primaryColor: Color(0xFFFFD700),
      secondaryColor: Color(0xFFDAA520),
    );
  }

  /// Voice/speaking badges (hexagon theme)
  static BadgeConfig speaking(int minutes) {
    BadgeRarity rarity;
    if (minutes >= 600) {
      rarity = BadgeRarity.legendary;
    } else if (minutes >= 120) {
      rarity = BadgeRarity.epic;
    } else if (minutes >= 30) {
      rarity = BadgeRarity.rare;
    } else {
      rarity = BadgeRarity.common;
    }

    return BadgeConfig(
      shape: BadgeShape.hexagon,
      rarity: rarity,
      icon: Icons.mic,
      primaryColor: const Color(0xFF9C27B0),
      secondaryColor: const Color(0xFF7B1FA2),
    );
  }

  /// Course completion badges (banner theme)
  static BadgeConfig course(int count) {
    BadgeRarity rarity;
    if (count >= 10) {
      rarity = BadgeRarity.legendary;
    } else if (count >= 5) {
      rarity = BadgeRarity.epic;
    } else if (count >= 2) {
      rarity = BadgeRarity.rare;
    } else {
      rarity = BadgeRarity.common;
    }

    return BadgeConfig(
      shape: BadgeShape.banner,
      rarity: rarity,
      icon: Icons.workspace_premium,
      primaryColor: const Color(0xFF3F51B5),
      secondaryColor: const Color(0xFF303F9F),
    );
  }

  /// Level up badges (shield theme)
  static BadgeConfig level(String levelCode) {
    BadgeRarity rarity;
    Color primary;
    Color secondary;

    switch (levelCode.toUpperCase()) {
      case 'A1':
        rarity = BadgeRarity.common;
        primary = const Color(0xFF8BC34A);
        secondary = const Color(0xFF689F38);
        break;
      case 'A2':
        rarity = BadgeRarity.common;
        primary = const Color(0xFF4CAF50);
        secondary = const Color(0xFF388E3C);
        break;
      case 'B1':
        rarity = BadgeRarity.rare;
        primary = const Color(0xFF2196F3);
        secondary = const Color(0xFF1976D2);
        break;
      case 'B2':
        rarity = BadgeRarity.epic;
        primary = const Color(0xFF673AB7);
        secondary = const Color(0xFF512DA8);
        break;
      case 'C1':
        rarity = BadgeRarity.epic;
        primary = const Color(0xFF9C27B0);
        secondary = const Color(0xFF7B1FA2);
        break;
      case 'C2':
        rarity = BadgeRarity.legendary;
        primary = const Color(0xFFFFD700);
        secondary = const Color(0xFFFFA000);
        break;
      default:
        rarity = BadgeRarity.common;
        primary = const Color(0xFF9E9E9E);
        secondary = const Color(0xFF757575);
    }

    return BadgeConfig(
      shape: BadgeShape.shield,
      rarity: rarity,
      icon: Icons.workspace_premium,
      primaryColor: primary,
      secondaryColor: secondary,
      text: levelCode.toUpperCase(),
    );
  }
}

/// Simple helper widget to display achievement badge from entity data
class SmartAchievementBadge extends StatelessWidget {
  final String category;
  final String? badgeIcon;
  final String? badgeColor;
  final String rarity;
  final int? conditionValue;
  final bool isUnlocked;
  final double size;
  final VoidCallback? onTap;

  const SmartAchievementBadge({
    super.key,
    required this.category,
    this.badgeIcon,
    this.badgeColor,
    required this.rarity,
    this.conditionValue,
    this.isUnlocked = false,
    this.size = 80,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getConfigFromCategory();
    return GeneratedBadge(
      config: config,
      size: size,
      onTap: onTap,
    );
  }

  BadgeConfig _getConfigFromCategory() {
    BadgeConfig baseConfig;
    
    switch (category.toLowerCase()) {
      case 'streak':
        baseConfig = AchievementBadgeTemplates.streak(conditionValue ?? 0);
        break;
      case 'lessons':
        baseConfig = AchievementBadgeTemplates.lessons(conditionValue ?? 0);
        break;
      case 'xp':
        baseConfig = AchievementBadgeTemplates.xp(conditionValue ?? 0);
        break;
      case 'vocabulary':
        baseConfig = AchievementBadgeTemplates.vocabulary(conditionValue ?? 0);
        break;
      case 'voice':
        baseConfig = AchievementBadgeTemplates.speaking(conditionValue ?? 0);
        break;
      case 'course':
        baseConfig = AchievementBadgeTemplates.course(conditionValue ?? 0);
        break;
      case 'quiz':
        baseConfig = AchievementBadgeTemplates.perfectScore();
        break;
      default:
        baseConfig = BadgeConfig(
          shape: BadgeShape.circle,
          rarity: _parseRarity(),
          icon: _parseIcon(),
        );
    }

    // Override with custom colors if provided
    if (badgeColor != null) {
      final color = _parseColor(badgeColor!);
      return BadgeConfig(
        shape: baseConfig.shape,
        rarity: baseConfig.rarity,
        icon: _parseIcon(),
        primaryColor: color,
        secondaryColor: color.withValues(alpha: 0.8),
        isLocked: !isUnlocked,
        showShine: isUnlocked,
      );
    }

    return BadgeConfig(
      shape: baseConfig.shape,
      rarity: baseConfig.rarity,
      icon: baseConfig.icon,
      primaryColor: baseConfig.primaryColor,
      secondaryColor: baseConfig.secondaryColor,
      isLocked: !isUnlocked,
      showShine: isUnlocked,
    );
  }

  BadgeRarity _parseRarity() {
    switch (rarity.toLowerCase()) {
      case 'legendary':
        return BadgeRarity.legendary;
      case 'epic':
        return BadgeRarity.epic;
      case 'rare':
        return BadgeRarity.rare;
      default:
        return BadgeRarity.common;
    }
  }

  IconData _parseIcon() {
    if (badgeIcon == null) return Icons.emoji_events;

    switch (badgeIcon!.toLowerCase()) {
      case 'trophy':
        return Icons.emoji_events;
      case 'medal':
        return Icons.military_tech;
      case 'crown':
        return Icons.workspace_premium;
      case 'star':
        return Icons.star;
      case 'fire':
        return Icons.local_fire_department;
      case 'bolt':
        return Icons.bolt;
      case 'book':
        return Icons.menu_book;
      case 'school':
        return Icons.school;
      case 'diamond':
        return Icons.diamond;
      case 'mic':
        return Icons.mic;
      case 'target':
        return Icons.track_changes;
      case 'verified':
        return Icons.verified;
      default:
        return Icons.emoji_events;
    }
  }

  Color _parseColor(String colorString) {
    if (colorString.startsWith('#')) {
      return Color(int.parse(colorString.replaceFirst('#', 'FF'), radix: 16));
    }
    return Colors.amber;
  }
}
