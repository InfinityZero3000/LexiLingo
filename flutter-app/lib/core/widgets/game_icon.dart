import 'package:flutter/material.dart';

/// Semantic icon keys used across the app's "game" visual style.
///
/// Icons render through Material symbols so the web build does not request
/// optional icon-library assets that are not bundled in production.
enum GameIcon {
  star,
  trophy,
  xp,
  gem,
  crown,
  checkmark,
  giftBox,
  treasureChest,
  speechBubble,
  settings,
  padlockUnlocked,
  clock,
  lessonBoard,
  playArrow,
  fastForward,
  rewind,
  backArrow,
  speakerOn,
  speakerMuted,
  lightBulb,
  heart,
  flashcards,
  grammar,
  listening,
  quizzes,
  speaking,
  vocabulary,
  nextButton,
  prevButton,
  streakFire,
  bolt,
  gameController,
  notificationBell,
  calendar,
  sunMorning,
  moonNight,
  book,
  refresh,
  trendingUp,
  video,
  snowflakeFreeze,
  microphone,
  peoplePair,
  forwardArrow,
  sparkle,
  sunsetAfternoon,

  // Game power-up icons (shop items usable mid-game).
  timeFreezeClock,
  hourglassTime,
  lightningBoltPower,
  magnifyingGlass,
  shieldPowerUp,
  luckyClover,
  swapArrow,

  // Pending custom art — rendered with a Material fallback for now.
  newspaper,
  headphones,
  translate,
}

const Map<GameIcon, IconData> _fallbackIcon = {
  GameIcon.star: Icons.star_rounded,
  GameIcon.trophy: Icons.emoji_events_rounded,
  GameIcon.xp: Icons.bolt_rounded,
  GameIcon.gem: Icons.diamond_rounded,
  GameIcon.crown: Icons.workspace_premium_rounded,
  GameIcon.checkmark: Icons.check_circle_rounded,
  GameIcon.giftBox: Icons.card_giftcard_rounded,
  GameIcon.treasureChest: Icons.inventory_2_rounded,
  GameIcon.speechBubble: Icons.chat_bubble_rounded,
  GameIcon.settings: Icons.settings_rounded,
  GameIcon.padlockUnlocked: Icons.lock_open_rounded,
  GameIcon.clock: Icons.schedule_rounded,
  GameIcon.lessonBoard: Icons.menu_book_rounded,
  GameIcon.playArrow: Icons.play_arrow_rounded,
  GameIcon.fastForward: Icons.fast_forward_rounded,
  GameIcon.rewind: Icons.fast_rewind_rounded,
  GameIcon.backArrow: Icons.arrow_back_rounded,
  GameIcon.nextButton: Icons.navigate_next_rounded,
  GameIcon.prevButton: Icons.navigate_before_rounded,
  GameIcon.speakerOn: Icons.volume_up_rounded,
  GameIcon.speakerMuted: Icons.volume_off_rounded,
  GameIcon.lightBulb: Icons.lightbulb_rounded,
  GameIcon.heart: Icons.favorite_rounded,
  GameIcon.flashcards: Icons.style_rounded,
  GameIcon.grammar: Icons.spellcheck_rounded,
  GameIcon.listening: Icons.headphones_rounded,
  GameIcon.quizzes: Icons.quiz_rounded,
  GameIcon.speaking: Icons.mic_rounded,
  GameIcon.vocabulary: Icons.translate_rounded,
  GameIcon.streakFire: Icons.local_fire_department_rounded,
  GameIcon.bolt: Icons.bolt_rounded,
  GameIcon.gameController: Icons.sports_esports_rounded,
  GameIcon.notificationBell: Icons.notifications_rounded,
  GameIcon.calendar: Icons.calendar_month_rounded,
  GameIcon.sunMorning: Icons.wb_sunny_rounded,
  GameIcon.moonNight: Icons.nightlight_round,
  GameIcon.book: Icons.book_rounded,
  GameIcon.refresh: Icons.refresh_rounded,
  GameIcon.trendingUp: Icons.trending_up_rounded,
  GameIcon.video: Icons.videocam_rounded,
  GameIcon.snowflakeFreeze: Icons.ac_unit_rounded,
  GameIcon.microphone: Icons.mic_rounded,
  GameIcon.peoplePair: Icons.people_rounded,
  GameIcon.forwardArrow: Icons.arrow_forward_rounded,
  GameIcon.sparkle: Icons.auto_awesome_rounded,
  GameIcon.sunsetAfternoon: Icons.wb_twilight_rounded,
  GameIcon.timeFreezeClock: Icons.more_time_rounded,
  GameIcon.hourglassTime: Icons.hourglass_bottom_rounded,
  GameIcon.lightningBoltPower: Icons.flash_on_rounded,
  GameIcon.magnifyingGlass: Icons.search_rounded,
  GameIcon.shieldPowerUp: Icons.shield_rounded,
  GameIcon.luckyClover: Icons.local_florist_rounded,
  GameIcon.swapArrow: Icons.swap_horiz_rounded,
  GameIcon.newspaper: Icons.article_rounded,
  GameIcon.headphones: Icons.headphones_rounded,
  GameIcon.translate: Icons.translate_rounded,
};

/// Maps a shop `item_type` string for an in-game power-up (time_freeze,
/// skip_token, reveal_hint, ...) to its [GameIcon]. Shared by the shop
/// item card and the in-game power-up tray so both render the same art.
const Map<String, GameIcon> gamePowerUpIcons = {
  'time_freeze': GameIcon.timeFreezeClock,
  'extra_time': GameIcon.hourglassTime,
  'skip_token': GameIcon.lightningBoltPower,
  'reveal_hint': GameIcon.magnifyingGlass,
  'translate_hint': GameIcon.speechBubble,
  'mistake_shield': GameIcon.shieldPowerUp,
  'extra_heart': GameIcon.heart,
  'lucky_clover': GameIcon.luckyClover,
  'score_multiplier': GameIcon.trendingUp,
  'pair_swap': GameIcon.swapArrow,
};

/// Renders a game-style Material icon by semantic [GameIcon] key.
class AppGameIcon extends StatelessWidget {
  final GameIcon icon;
  final double size;
  final Color? fallbackColor;

  const AppGameIcon(this.icon, {super.key, this.size = 24, this.fallbackColor});

  bool get hasCustomAsset => false;

  @override
  Widget build(BuildContext context) => _buildFallbackIcon();

  Widget _buildFallbackIcon() {
    return Icon(
      _fallbackIcon[icon] ?? Icons.help_outline,
      size: size,
      color: fallbackColor,
    );
  }
}
