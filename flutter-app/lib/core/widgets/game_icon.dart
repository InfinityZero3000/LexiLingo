import 'package:flutter/material.dart';

/// Semantic icon keys used across the app's "game" visual style. Each key
/// maps to a flat, hand-styled asset under assets/icon-library (including
/// its learning-icons/ and button/ subfolders). Keys with no asset yet
/// fall back to a Material icon (see [_fallbackIcon]) so screens can be
/// wired up before art lands —
/// dropping the file in and adding its path to [_assetPath] swaps every call
/// site over automatically.
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

const Map<GameIcon, String> _assetPath = {
  GameIcon.star: 'assets/icon-library/star.png',
  GameIcon.trophy: 'assets/icon-library/trophy.png',
  GameIcon.xp: 'assets/icon-library/xp_badge.png',
  GameIcon.gem: 'assets/icon-library/purple_gem.png',
  GameIcon.crown: 'assets/icon-library/crown.png',
  GameIcon.checkmark: 'assets/icon-library/checkmarkmarkk.png',
  GameIcon.giftBox: 'assets/icon-library/gift_box.png',
  GameIcon.treasureChest: 'assets/icon-library/treasure_chest.png',
  GameIcon.speechBubble: 'assets/icon-library/speech_bubble.png',
  GameIcon.settings: 'assets/icon-library/gear.png',
  GameIcon.padlockUnlocked: 'assets/icon-library/unlocked_padlock.png',
  GameIcon.clock: 'assets/icon-library/clock.png',
  GameIcon.lessonBoard: 'assets/icon-library/chalkboard_abc.png',
  GameIcon.playArrow: 'assets/icon-library/button/triangle_right.png',
  GameIcon.fastForward: 'assets/icon-library/button/fast_forward_button.png',
  GameIcon.rewind: 'assets/icon-library/button/rewind_button.png',
  GameIcon.backArrow: 'assets/icon-library/button/left_arrow.png',
  GameIcon.nextButton: 'assets/icon-library/button/next_button.png',
  GameIcon.prevButton: 'assets/icon-library/button/prev_button.png',
  GameIcon.speakerOn: 'assets/icon-library/speaker_on.png',
  GameIcon.speakerMuted: 'assets/icon-library/speaker_muted.png',
  GameIcon.lightBulb: 'assets/icon-library/yellow_light_bulb.png',
  GameIcon.heart: 'assets/icon-library/heart.png',
  GameIcon.flashcards: 'assets/icon-library/learning-icons/flashcards_icon.png',
  GameIcon.grammar: 'assets/icon-library/learning-icons/grammar_icon.png',
  GameIcon.listening: 'assets/icon-library/learning-icons/listening_icon.png',
  GameIcon.quizzes: 'assets/icon-library/learning-icons/quizzes_icon.png',
  GameIcon.speaking: 'assets/icon-library/learning-icons/speaking_icon.png',
  GameIcon.vocabulary: 'assets/icon-library/learning-icons/vocabulary_icon.png',
  GameIcon.streakFire: 'assets/icon-library/fire_flame.png',
  GameIcon.bolt: 'assets/icon-library/lightning_bolt_3.png',
  GameIcon.gameController: 'assets/icon-library/joystick.png',
  GameIcon.notificationBell: 'assets/icon-library/bell.png',
  GameIcon.calendar: 'assets/icon-library/calendar.png',
  GameIcon.sunMorning: 'assets/icon-library/yellow_sun.png',
  GameIcon.moonNight: 'assets/icon-library/crescent_moon.png',
  GameIcon.book: 'assets/icon-library/blue_book.png',
  GameIcon.refresh: 'assets/icon-library/button/refresh_arrow.png',
  GameIcon.trendingUp: 'assets/icon-library/double_up_arrow.png',
  GameIcon.video: 'assets/icon-library/clapperboard.png',
  GameIcon.snowflakeFreeze: 'assets/icon-library/snowflake_badge.png',
  GameIcon.microphone: 'assets/icon-library/microphone.png',
  GameIcon.peoplePair: 'assets/icon-library/character_pair.png',
  GameIcon.forwardArrow: 'assets/icon-library/button/right_arrow.png',
  GameIcon.sparkle: 'assets/icon-library/sparkles.png',
  GameIcon.sunsetAfternoon: 'assets/icon-library/sun.png',
  GameIcon.timeFreezeClock: 'assets/icon-library/clock_freeze.png',
  GameIcon.hourglassTime: 'assets/icon-library/hourglass.png',
  GameIcon.lightningBoltPower: 'assets/icon-library/lightning_bolt.png',
  GameIcon.magnifyingGlass: 'assets/icon-library/magnifying_glass.png',
  GameIcon.shieldPowerUp: 'assets/icon-library/shield.png',
  GameIcon.luckyClover: 'assets/icon-library/four_leaf_clover.png',
  GameIcon.swapArrow: 'assets/icon-library/swap_arrow.png',
};

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

/// Renders a custom flat game-style icon by semantic [GameIcon] key,
/// falling back to a Material icon when no asset has been supplied yet.
class AppGameIcon extends StatelessWidget {
  final GameIcon icon;
  final double size;
  final Color? fallbackColor;

  const AppGameIcon(this.icon, {super.key, this.size = 24, this.fallbackColor});

  bool get hasCustomAsset => _assetPath.containsKey(icon);

  @override
  Widget build(BuildContext context) {
    final path = _assetPath[icon];
    if (path != null) {
      return Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
      );
    }
    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() {
    return Icon(
      _fallbackIcon[icon] ?? Icons.help_outline,
      size: size,
      color: fallbackColor,
    );
  }
}
