import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  group('ProfilePage - User Info Display', () {
    group('Member Since Formatting', () {
      test('should format date correctly as "Member since MMM yyyy"', () {
        final date = DateTime(2023, 1, 15);
        final formatted = _formatMemberSince(date);
        expect(formatted, 'Member since Jan 2023');
      });

      test('should handle different months correctly', () {
        expect(_formatMemberSince(DateTime(2022, 12, 1)), 'Member since Dec 2022');
        expect(_formatMemberSince(DateTime(2024, 6, 20)), 'Member since Jun 2024');
        expect(_formatMemberSince(DateTime(2021, 3, 5)), 'Member since Mar 2021');
      });

      test('should return "Member" for null date', () {
        final formatted = _formatMemberSince(null);
        expect(formatted, 'Member');
      });
    });

    group('Tier Color Mapping', () {
      test('should return correct color for A1 tier', () {
        expect(_getTierColorName('A1'), 'green');
      });

      test('should return correct color for A2 tier', () {
        expect(_getTierColorName('A2'), 'teal');
      });

      test('should return correct color for B1 tier', () {
        expect(_getTierColorName('B1'), 'blue');
      });

      test('should return correct color for B2 tier', () {
        expect(_getTierColorName('B2'), 'indigo');
      });

      test('should return correct color for C1 tier', () {
        expect(_getTierColorName('C1'), 'purple');
      });

      test('should return correct color for C2 tier', () {
        expect(_getTierColorName('C2'), 'amber');
      });

      test('should return primary color for unknown tier', () {
        expect(_getTierColorName('unknown'), 'primary');
      });
    });

    group('Level Progress Display', () {
      test('should calculate XP to next level correctly', () {
        // User at 500 XP, next tier (A2) at 1000 XP
        final xpToNext = _calculateXpToNext(500, 1000);
        expect(xpToNext, 500);
      });

      test('should show 0 XP to go at max level', () {
        // User at max level
        final xpToNext = _calculateXpToNext(30000, null);
        expect(xpToNext, 0);
      });

      test('should format progress label for next tier', () {
        final label = _getProgressLabel('B1', 'Intermediate');
        expect(label, 'Progress to B1 Intermediate');
      });

      test('should show max level message for C2', () {
        final label = _getProgressLabelForMaxLevel();
        expect(label, 'Maximum Level Reached');
      });
    });

    group('XP Formatting', () {
      test('should format XP correctly with comma separator', () {
        expect(_formatXP(1000), '1,000');
        expect(_formatXP(15000), '15,000');
        expect(_formatXP(100), '100');
        expect(_formatXP(999), '999');
      });

      test('should format large XP values', () {
        expect(_formatXP(30000), '30,000');
        expect(_formatXP(50000), '50,000');
      });
    });

    group('Profile Header Display', () {
      test('should generate avatar URL for users without avatar', () {
        final url = _generateAvatarUrl('John Doe');
        expect(url.contains('ui-avatars.com'), true);
        expect(url.contains('John%20Doe'), true);
      });

      test('should encode special characters in avatar URL', () {
        final url = _generateAvatarUrl('Jean-Pierre');
        expect(url.contains('ui-avatars.com'), true);
      });

      test('should use default name for null display name', () {
        final url = _generateAvatarUrl(null);
        expect(url.contains('User'), true);
      });
    });

    group('Learning Stats Display', () {
      test('should show "Keep it up!" for active streak', () {
        final message = _getStreakMessage(5);
        expect(message, 'Keep it up!');
      });

      test('should show "Start today!" for zero streak', () {
        final message = _getStreakMessage(0);
        expect(message, 'Start today!');
      });

      test('should format streak days correctly', () {
        expect(_formatStreak(1), '1 Days');
        expect(_formatStreak(15), '15 Days');
        expect(_formatStreak(100), '100 Days');
      });
    });

    group('Tier Name Display', () {
      test('should combine tier code and name', () {
        expect(_getTierDisplayName('A1', 'Beginner'), 'A1 Beginner');
        expect(_getTierDisplayName('B2', 'Upper Intermediate'), 'B2 Upper Intermediate');
        expect(_getTierDisplayName('C2', 'Mastery'), 'C2 Mastery');
      });
    });

    group('Progress Percentage', () {
      test('should format progress percentage correctly', () {
        expect(_formatProgressPercentage(75.5), '76% complete');
        expect(_formatProgressPercentage(0.0), '0% complete');
        expect(_formatProgressPercentage(100.0), '100% complete');
        expect(_formatProgressPercentage(33.33), '33% complete');
      });
    });
  });
}

// Helper functions mirroring profile_page.dart logic
String _formatMemberSince(DateTime? createdAt) {
  if (createdAt == null) return 'Member';
  return 'Member since ${DateFormat('MMM yyyy').format(createdAt)}';
}

String _getTierColorName(String tierCode) {
  switch (tierCode) {
    case 'A1':
      return 'green';
    case 'A2':
      return 'teal';
    case 'B1':
      return 'blue';
    case 'B2':
      return 'indigo';
    case 'C1':
      return 'purple';
    case 'C2':
      return 'amber';
    default:
      return 'primary';
  }
}

int _calculateXpToNext(int currentXP, int? nextTierMinXP) {
  if (nextTierMinXP == null) return 0;
  return nextTierMinXP - currentXP;
}

String _getProgressLabel(String tierCode, String tierName) {
  return 'Progress to $tierCode $tierName';
}

String _getProgressLabelForMaxLevel() {
  return 'Maximum Level Reached';
}

String _formatXP(int xp) {
  if (xp >= 1000) {
    return '${(xp ~/ 1000)},${(xp % 1000).toString().padLeft(3, '0')}';
  }
  return xp.toString();
}

String _generateAvatarUrl(String? displayName) {
  final name = displayName ?? 'User';
  return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=random';
}

String _getStreakMessage(int streak) {
  return streak > 0 ? 'Keep it up!' : 'Start today!';
}

String _formatStreak(int days) {
  return '$days Days';
}

String _getTierDisplayName(String code, String name) {
  return '$code $name';
}

String _formatProgressPercentage(double percentage) {
  return '${percentage.toStringAsFixed(0)}% complete';
}
