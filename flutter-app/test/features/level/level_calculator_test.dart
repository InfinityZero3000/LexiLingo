import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/level/domain/entities/level_entity.dart';
import 'package:lexilingo_app/features/level/services/level_calculator.dart';

void main() {
  group('LevelTiers', () {
    test('should have 6 tiers from A1 to C2', () {
      expect(LevelTiers.allTiers.length, 6);
      expect(LevelTiers.allTiers.first.code, 'A1');
      expect(LevelTiers.allTiers.last.code, 'C2');
    });

    test('should have correct XP thresholds', () {
      expect(LevelTiers.a1.minXP, 0);
      expect(LevelTiers.a1.maxXP, 999);
      expect(LevelTiers.a2.minXP, 1000);
      expect(LevelTiers.a2.maxXP, 2999);
      expect(LevelTiers.b1.minXP, 3000);
      expect(LevelTiers.b1.maxXP, 6999);
      expect(LevelTiers.b2.minXP, 7000);
      expect(LevelTiers.b2.maxXP, 14999);
      expect(LevelTiers.c1.minXP, 15000);
      expect(LevelTiers.c1.maxXP, 29999);
      expect(LevelTiers.c2.minXP, 30000);
      expect(LevelTiers.c2.maxXP, null);
    });

    test('should have continuous XP ranges with no gaps', () {
      for (var i = 0; i < LevelTiers.allTiers.length - 1; i++) {
        final current = LevelTiers.allTiers[i];
        final next = LevelTiers.allTiers[i + 1];
        expect(current.maxXP! + 1, next.minXP);
      }
    });

    test('getByCode should return correct tier', () {
      expect(LevelTiers.getByCode('A1'), LevelTiers.a1);
      expect(LevelTiers.getByCode('a1'), LevelTiers.a1);
      expect(LevelTiers.getByCode('B2'), LevelTiers.b2);
      expect(LevelTiers.getByCode('C2'), LevelTiers.c2);
      expect(LevelTiers.getByCode('invalid'), null);
    });

    test('C2 should be marked as max level', () {
      expect(LevelTiers.c2.isMaxLevel, true);
      expect(LevelTiers.c1.isMaxLevel, false);
      expect(LevelTiers.a1.isMaxLevel, false);
    });
  });

  group('LevelCalculator.getCurrentTier', () {
    test('should return A1 for 0 XP', () {
      expect(LevelCalculator.getCurrentTier(0), LevelTiers.a1);
    });

    test('should return A1 for 999 XP', () {
      expect(LevelCalculator.getCurrentTier(999), LevelTiers.a1);
    });

    test('should return A2 for 1000 XP', () {
      expect(LevelCalculator.getCurrentTier(1000), LevelTiers.a2);
    });

    test('should return B1 for 3000 XP', () {
      expect(LevelCalculator.getCurrentTier(3000), LevelTiers.b1);
    });

    test('should return B2 for 7000 XP', () {
      expect(LevelCalculator.getCurrentTier(7000), LevelTiers.b2);
    });

    test('should return C1 for 15000 XP', () {
      expect(LevelCalculator.getCurrentTier(15000), LevelTiers.c1);
    });

    test('should return C2 for 30000 XP', () {
      expect(LevelCalculator.getCurrentTier(30000), LevelTiers.c2);
    });

    test('should return C2 for very high XP', () {
      expect(LevelCalculator.getCurrentTier(1000000), LevelTiers.c2);
    });

    test('should handle negative XP by treating as 0', () {
      expect(LevelCalculator.getCurrentTier(-100), LevelTiers.a1);
    });

    test('should return correct tier for boundary values', () {
      // At exact boundaries
      expect(LevelCalculator.getCurrentTier(999), LevelTiers.a1);
      expect(LevelCalculator.getCurrentTier(2999), LevelTiers.a2);
      expect(LevelCalculator.getCurrentTier(6999), LevelTiers.b1);
      expect(LevelCalculator.getCurrentTier(14999), LevelTiers.b2);
      expect(LevelCalculator.getCurrentTier(29999), LevelTiers.c1);
    });
  });

  group('LevelCalculator.getNextTier', () {
    test('should return A2 for A1', () {
      expect(LevelCalculator.getNextTier(LevelTiers.a1), LevelTiers.a2);
    });

    test('should return null for C2 (max level)', () {
      expect(LevelCalculator.getNextTier(LevelTiers.c2), null);
    });

    test('should return correct next tier for all levels', () {
      expect(LevelCalculator.getNextTier(LevelTiers.a1), LevelTiers.a2);
      expect(LevelCalculator.getNextTier(LevelTiers.a2), LevelTiers.b1);
      expect(LevelCalculator.getNextTier(LevelTiers.b1), LevelTiers.b2);
      expect(LevelCalculator.getNextTier(LevelTiers.b2), LevelTiers.c1);
      expect(LevelCalculator.getNextTier(LevelTiers.c1), LevelTiers.c2);
      expect(LevelCalculator.getNextTier(LevelTiers.c2), null);
    });
  });

  group('LevelCalculator.getXPInCurrentLevel', () {
    test('should return 0 for 0 XP', () {
      expect(LevelCalculator.getXPInCurrentLevel(0), 0);
    });

    test('should return correct XP in level', () {
      expect(LevelCalculator.getXPInCurrentLevel(500), 500); // A1
      expect(LevelCalculator.getXPInCurrentLevel(1500), 500); // A2: 1500 - 1000
      expect(LevelCalculator.getXPInCurrentLevel(5000), 2000); // B1: 5000 - 3000
      expect(LevelCalculator.getXPInCurrentLevel(10000), 3000); // B2: 10000 - 7000
    });

    test('should work at level boundaries', () {
      expect(LevelCalculator.getXPInCurrentLevel(1000), 0); // Just entered A2
      expect(LevelCalculator.getXPInCurrentLevel(3000), 0); // Just entered B1
    });
  });

  group('LevelCalculator.getXPToNextLevel', () {
    test('should return correct XP to next level for A1', () {
      expect(LevelCalculator.getXPToNextLevel(0), 1000); // Need 1000 to reach A2
      expect(LevelCalculator.getXPToNextLevel(500), 500); // Need 500 more
      expect(LevelCalculator.getXPToNextLevel(999), 1); // Just 1 more XP
    });

    test('should return 0 for max level', () {
      expect(LevelCalculator.getXPToNextLevel(30000), 0);
      expect(LevelCalculator.getXPToNextLevel(100000), 0);
    });

    test('should work at level boundaries', () {
      expect(LevelCalculator.getXPToNextLevel(1000), 2000); // A2: need 2000 more
      expect(LevelCalculator.getXPToNextLevel(3000), 4000); // B1: need 4000 more
    });
  });

  group('LevelCalculator.getProgressPercentage', () {
    test('should return 0.0 for 0 XP', () {
      expect(LevelCalculator.getProgressPercentage(0), 0.0);
    });

    test('should return approximately 0.5 for midpoint of A1', () {
      // A1 range: 0-999 (1000 XP total)
      final progress = LevelCalculator.getProgressPercentage(500);
      expect(progress, closeTo(0.5, 0.01));
    });

    test('should return 1.0 for max level', () {
      expect(LevelCalculator.getProgressPercentage(30000), 1.0);
      expect(LevelCalculator.getProgressPercentage(100000), 1.0);
    });

    test('should be between 0 and 1', () {
      for (var xp = 0; xp <= 50000; xp += 100) {
        final progress = LevelCalculator.getProgressPercentage(xp);
        expect(progress, greaterThanOrEqualTo(0.0));
        expect(progress, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('LevelCalculator.calculateLevelStatus', () {
    test('should return correct status for 0 XP', () {
      final status = LevelCalculator.calculateLevelStatus(0);

      expect(status.currentTier, LevelTiers.a1);
      expect(status.totalXP, 0);
      expect(status.xpInCurrentLevel, 0);
      expect(status.xpToNextLevel, 1000);
      expect(status.progressPercentage, 0.0);
      expect(status.nextTier, LevelTiers.a2);
      expect(status.isAtMaxLevel, false);
    });

    test('should return correct status for mid-level XP', () {
      final status = LevelCalculator.calculateLevelStatus(5000);

      expect(status.currentTier, LevelTiers.b1);
      expect(status.totalXP, 5000);
      expect(status.xpInCurrentLevel, 2000); // 5000 - 3000
      expect(status.xpToNextLevel, 2000); // 7000 - 5000
      expect(status.nextTier, LevelTiers.b2);
    });

    test('should return correct status for max level', () {
      final status = LevelCalculator.calculateLevelStatus(50000);

      expect(status.currentTier, LevelTiers.c2);
      expect(status.totalXP, 50000);
      expect(status.xpToNextLevel, 0);
      expect(status.progressPercentage, 1.0);
      expect(status.nextTier, null);
      expect(status.isAtMaxLevel, true);
    });

    test('displayName should be correct', () {
      final status = LevelCalculator.calculateLevelStatus(8000);
      expect(status.displayName, 'B2 Upper Intermediate');
      expect(status.shortName, 'B2');
    });
  });

  group('LevelCalculator.wouldLevelUp', () {
    test('should return false for XP within same level', () {
      expect(LevelCalculator.wouldLevelUp(0, 100), false);
      expect(LevelCalculator.wouldLevelUp(500, 400), false);
    });

    test('should return true for XP crossing level boundary', () {
      expect(LevelCalculator.wouldLevelUp(900, 200), true); // 900 + 200 = 1100 (A2)
      expect(LevelCalculator.wouldLevelUp(999, 1), true); // 999 + 1 = 1000 (A2)
    });

    test('should return true for multi-level jump', () {
      expect(LevelCalculator.wouldLevelUp(0, 10000), true); // 0 to B2
    });
  });

  group('LevelCalculator.getLevelsGained', () {
    test('should return 0 for XP within same level', () {
      expect(LevelCalculator.getLevelsGained(0, 100), 0);
    });

    test('should return 1 for single level up', () {
      expect(LevelCalculator.getLevelsGained(900, 200), 1);
    });

    test('should return correct count for multi-level jump', () {
      expect(LevelCalculator.getLevelsGained(0, 3000), 2); // A1 -> B1 (skip A2)
      expect(LevelCalculator.getLevelsGained(0, 30000), 5); // A1 -> C2
    });
  });

  group('LevelCalculator.formatXP', () {
    test('should format small numbers as-is', () {
      expect(LevelCalculator.formatXP(0), '0');
      expect(LevelCalculator.formatXP(999), '999');
    });

    test('should add comma for thousands', () {
      expect(LevelCalculator.formatXP(1000), '1,000');
      expect(LevelCalculator.formatXP(9999), '9,999');
    });

    test('should use K suffix for 10K+', () {
      expect(LevelCalculator.formatXP(10000), '10.0K');
      expect(LevelCalculator.formatXP(15500), '15.5K');
    });

    test('should use M suffix for 1M+', () {
      expect(LevelCalculator.formatXP(1000000), '1.0M');
      expect(LevelCalculator.formatXP(1500000), '1.5M');
    });
  });

  group('LevelStatus', () {
    test('empty factory should create valid default status', () {
      final status = LevelStatus.empty();

      expect(status.currentTier, LevelTiers.a1);
      expect(status.totalXP, 0);
      expect(status.xpInCurrentLevel, 0);
      expect(status.nextTier, LevelTiers.a2);
      expect(status.isAtMaxLevel, false);
    });

    test('should be equatable', () {
      final status1 = LevelCalculator.calculateLevelStatus(5000);
      final status2 = LevelCalculator.calculateLevelStatus(5000);
      final status3 = LevelCalculator.calculateLevelStatus(6000);

      expect(status1, status2);
      expect(status1, isNot(status3));
    });
  });
}
