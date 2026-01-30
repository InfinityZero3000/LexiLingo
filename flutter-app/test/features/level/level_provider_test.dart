import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/level/domain/entities/level_entity.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';

void main() {
  late LevelProvider provider;

  setUp(() {
    provider = LevelProvider();
  });

  group('LevelProvider initial state', () {
    test('should start with empty level status', () {
      expect(provider.levelStatus.totalXP, 0);
      expect(provider.currentTier, LevelTiers.a1);
      expect(provider.isLoading, false);
      expect(provider.errorMessage, null);
      expect(provider.showLevelUpDialog, false);
    });

    test('should have correct initial values', () {
      expect(provider.totalXP, 0);
      expect(provider.progressPercentage, 0.0);
      expect(provider.levelDisplayName, 'A1 Beginner');
      expect(provider.levelShortName, 'A1');
      expect(provider.isAtMaxLevel, false);
    });
  });

  group('LevelProvider.updateLevel', () {
    test('should update level status correctly', () {
      provider.updateLevel(5000);

      expect(provider.totalXP, 5000);
      expect(provider.currentTier, LevelTiers.b1);
      expect(provider.levelDisplayName, 'B1 Intermediate');
    });

    test('should trigger level up dialog when leveling up', () {
      provider.updateLevel(500); // A1
      expect(provider.showLevelUpDialog, false);

      provider.updateLevel(1500); // A2
      expect(provider.showLevelUpDialog, true);
      expect(provider.previousTier, LevelTiers.a1);
    });

    test('should not trigger level up for same level', () {
      provider.updateLevel(500);
      provider.updateLevel(700);

      expect(provider.showLevelUpDialog, false);
    });
  });

  group('LevelProvider.addXP', () {
    test('should add XP and update status', () {
      provider.updateLevel(500);
      final leveledUp = provider.addXP(100);

      expect(provider.totalXP, 600);
      expect(leveledUp, false);
    });

    test('should return true when leveling up', () {
      provider.updateLevel(900);
      final leveledUp = provider.addXP(200);

      expect(leveledUp, true);
      expect(provider.currentTier, LevelTiers.a2);
    });

    test('should not add negative XP', () {
      provider.updateLevel(500);
      final result = provider.addXP(-100);

      expect(result, false);
      expect(provider.totalXP, 500);
    });

    test('should not add zero XP', () {
      provider.updateLevel(500);
      final result = provider.addXP(0);

      expect(result, false);
      expect(provider.totalXP, 500);
    });
  });

  group('LevelProvider.dismissLevelUpDialog', () {
    test('should dismiss dialog and clear previous tier', () {
      provider.updateLevel(500);
      provider.updateLevel(1500); // Level up

      expect(provider.showLevelUpDialog, true);
      expect(provider.previousTier, isNotNull);

      provider.dismissLevelUpDialog();

      expect(provider.showLevelUpDialog, false);
      expect(provider.previousTier, null);
    });
  });

  group('LevelProvider display methods', () {
    test('getFormattedTotalXP should return formatted string', () {
      provider.updateLevel(1500);
      expect(provider.getFormattedTotalXP(), '1,500');

      provider.updateLevel(15000);
      expect(provider.getFormattedTotalXP(), '15.0K');
    });

    test('getProgressDisplayString should show progress', () {
      provider.updateLevel(1500);
      final display = provider.getProgressDisplayString();
      expect(display, contains('XP'));
    });

    test('getProgressDisplayString should show max level message', () {
      provider.updateLevel(50000);
      final display = provider.getProgressDisplayString();
      expect(display, contains('Max Level'));
    });

    test('getLevelProgressString should show level progress', () {
      provider.updateLevel(5000);
      final display = provider.getLevelProgressString();
      expect(display, contains('XP'));
    });

    test('getMotivationalMessage should return a message', () {
      provider.updateLevel(500);
      final message = provider.getMotivationalMessage();
      expect(message.isNotEmpty, true);
    });
  });

  group('LevelProvider.wouldLevelUp', () {
    test('should predict level up correctly', () {
      provider.updateLevel(900);

      expect(provider.wouldLevelUp(50), false);
      expect(provider.wouldLevelUp(100), true);
    });
  });

  group('LevelProvider.getXPRequiredForLevel', () {
    test('should calculate XP required for target level', () {
      provider.updateLevel(500);

      expect(provider.getXPRequiredForLevel(LevelTiers.a2), 500);
      expect(provider.getXPRequiredForLevel(LevelTiers.b1), 2500);
    });

    test('should return 0 if already at or above target', () {
      provider.updateLevel(5000);

      expect(provider.getXPRequiredForLevel(LevelTiers.a1), 0);
      expect(provider.getXPRequiredForLevel(LevelTiers.a2), 0);
      expect(provider.getXPRequiredForLevel(LevelTiers.b1), 0);
    });
  });

  group('LevelProvider.reset', () {
    test('should reset all state', () {
      provider.updateLevel(5000);
      provider.setError('Test error');
      provider.setLoading(true);

      provider.reset();

      expect(provider.totalXP, 0);
      expect(provider.currentTier, LevelTiers.a1);
      expect(provider.isLoading, false);
      expect(provider.errorMessage, null);
      expect(provider.showLevelUpDialog, false);
    });
  });

  group('LevelProvider error handling', () {
    test('should set and clear error', () {
      expect(provider.errorMessage, null);

      provider.setError('Test error');
      expect(provider.errorMessage, 'Test error');

      provider.clearError();
      expect(provider.errorMessage, null);
    });

    test('should set loading state', () {
      expect(provider.isLoading, false);

      provider.setLoading(true);
      expect(provider.isLoading, true);

      provider.setLoading(false);
      expect(provider.isLoading, false);
    });
  });

  group('LevelProvider max level behavior', () {
    test('should handle max level correctly', () {
      provider.updateLevel(50000);

      expect(provider.isAtMaxLevel, true);
      expect(provider.nextTier, null);
      expect(provider.xpToNextLevel, 0);
      expect(provider.progressPercentage, 1.0);
    });

    test('should not trigger level up at max level', () {
      provider.updateLevel(50000);
      provider.dismissLevelUpDialog();

      provider.addXP(10000);

      expect(provider.showLevelUpDialog, false);
      expect(provider.currentTier, LevelTiers.c2);
    });
  });
}
