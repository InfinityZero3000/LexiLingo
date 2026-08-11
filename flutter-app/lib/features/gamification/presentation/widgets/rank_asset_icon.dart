import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class RankVisualData {
  final String key;
  final String name;
  final String assetPath;
  final Color color;
  final Color colorDark;

  const RankVisualData({
    required this.key,
    required this.name,
    required this.assetPath,
    required this.color,
    required this.colorDark,
  });
}

const Map<String, RankVisualData> _rankVisuals = {
  'bronze': RankVisualData(
    key: 'bronze',
    name: 'Bronze',
    assetPath: 'assets/ranking/1-bronze.png',
    color: AppColors.bronze,
    colorDark: AppColors.goldDark,
  ),
  'silver': RankVisualData(
    key: 'silver',
    name: 'Silver',
    assetPath: 'assets/ranking/2-silver.png',
    color: AppColors.silver,
    colorDark: AppColors.grey500,
  ),
  'gold': RankVisualData(
    key: 'gold',
    name: 'Gold',
    assetPath: 'assets/ranking/3-gold.png',
    color: AppColors.gold,
    colorDark: Color(0xFFE5C100),
  ),
  'platinum': RankVisualData(
    key: 'platinum',
    name: 'Platinum',
    assetPath: 'assets/ranking/4-platinum.png',
    color: Color(0xFF00E5FF),
    colorDark: Color(0xFF00B8D4),
  ),
  'sapphire': RankVisualData(
    key: 'sapphire',
    name: 'Sapphire',
    assetPath: 'assets/ranking/5-sapphire.png',
    color: Color(0xFF4783EB),
    colorDark: Color(0xFF1251BD),
  ),
  'ruby': RankVisualData(
    key: 'ruby',
    name: 'Ruby',
    assetPath: 'assets/ranking/6-ruby.png',
    color: Color(0xFFE14242),
    colorDark: Color(0xFF981F2A),
  ),
  'amethyst': RankVisualData(
    key: 'amethyst',
    name: 'Amethyst',
    assetPath: 'assets/ranking/7-amethyst.png',
    color: Color(0xFF9652E3),
    colorDark: Color(0xFF3A0C8F),
  ),
  'master': RankVisualData(
    key: 'master',
    name: 'Master',
    assetPath: 'assets/ranking/8-master.png',
    color: Color(0xFF9966CC),
    colorDark: Color(0xFF4A256B),
  ),
};

const Map<String, String> _rankAliases = {'diamond': 'sapphire'};

RankVisualData rankVisualDataFor(String rank) {
  final normalized = rank.toLowerCase().trim();
  final key = _rankAliases[normalized] ?? normalized;
  return _rankVisuals[key] ?? _rankVisuals['bronze']!;
}

String rankDisplayNameFor(String rank) {
  if (rank.toLowerCase().trim() == 'diamond') {
    return 'Diamond';
  }
  return rankVisualDataFor(rank).name;
}

class RankAssetIcon extends StatelessWidget {
  final String rank;
  final double size;
  final bool decorated;
  final double iconScale;
  final Offset iconOffset;
  final double paddingRatio;

  const RankAssetIcon({
    super.key,
    required this.rank,
    this.size = 32,
    this.decorated = true,
    this.iconScale = 1,
    this.iconOffset = Offset.zero,
    this.paddingRatio = 0.08,
  });

  @override
  Widget build(BuildContext context) {
    final data = rankVisualDataFor(rank);
    final icon = Image.asset(
      data.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.workspace_premium_rounded,
        size: size * 0.72,
        color: data.color,
      ),
    );

    if (!decorated) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Transform.translate(
            offset: iconOffset,
            child: Transform.scale(scale: iconScale, child: icon),
          ),
        ),
      );
    }

    final isMaster = data.key == 'master';

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft gradient glow — no border, no clip
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: isMaster
                      ? [
                          AppColors.masterGradient[0].withValues(alpha: 0.28),
                          AppColors.masterGradient[1].withValues(alpha: 0.12),
                          Colors.transparent,
                        ]
                      : [
                          data.color.withValues(alpha: 0.22),
                          data.color.withValues(alpha: 0.06),
                          Colors.transparent,
                        ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: iconOffset,
            child: Transform.scale(scale: iconScale, child: icon),
          ),
        ],
      ),
    );
  }
}
