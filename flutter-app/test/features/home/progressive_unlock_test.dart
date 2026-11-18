import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/auth/data/models/user_model.dart';
import 'package:lexilingo_app/features/home/domain/progressive_unlock.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/quick_actions_grid.dart';

const _starters = [
  'home.navLearning',
  'home.navLexi',
  'home.vocabulary',
  'home.games',
];

const _secondary = ['home.youtube', 'home.news', 'home.podcast', 'home.books'];

void main() {
  tearDown(() {
    dotenv.loadFromString(envString: 'ENVIRONMENT=development');
  });

  group('secondaryFeaturesLocked', () {
    bool locked({bool flag = true, int? lessons = 0, int? xp = 0}) =>
        secondaryFeaturesLocked(
          flagEnabled: flag,
          lessonsCompleted: lessons,
          totalXp: xp,
        );

    test('flag on, no lessons and no XP locks', () {
      expect(locked(), isTrue);
    });

    test('flag on and one lesson unlocks', () {
      expect(locked(lessons: 1), isFalse);
    });

    test('no lessons but XP from elsewhere unlocks', () {
      expect(locked(xp: 15), isFalse);
    });

    test('flag off never locks', () {
      expect(locked(flag: false), isFalse);
    });

    test('an unknown lesson count or XP never locks', () {
      expect(locked(lessons: null), isFalse);
      expect(locked(xp: null), isFalse);
    });
  });

  group('ApiConfig.progressiveUnlock', () {
    test('defaults on in production and off in development', () {
      dotenv.loadFromString(envString: 'ENVIRONMENT=production');
      expect(ApiConfig.progressiveUnlock, isTrue);
      dotenv.loadFromString(envString: 'ENVIRONMENT=development');
      expect(ApiConfig.progressiveUnlock, isFalse);
    });

    test('the env value wins over the default', () {
      dotenv.loadFromString(
        envString: 'ENVIRONMENT=production\nPROGRESSIVE_UNLOCK=false',
      );
      expect(ApiConfig.progressiveUnlock, isFalse);
      dotenv.loadFromString(
        envString: 'ENVIRONMENT=development\nPROGRESSIVE_UNLOCK=true',
      );
      expect(ApiConfig.progressiveUnlock, isTrue);
    });
  });

  group('UserModel.lessonsCompleted', () {
    Map<String, dynamic> json([int? lessons]) => {
      'id': 'u1',
      'email': 'a@b.co',
      'username': 'abc',
      'lessons_completed': ?lessons,
    };

    test('reads the count from /users/me', () {
      expect(UserModel.fromJson(json(3)).lessonsCompleted, 3);
      expect(UserModel.fromJson(json(0)).lessonsCompleted, 0);
    });

    test('stays null when the backend does not send it', () {
      expect(UserModel.fromJson(json()).lessonsCompleted, isNull);
    });
  });

  group('QuickActionsGrid', () {
    Future<void> pump(WidgetTester tester, {required bool lock}) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuickActionsGrid(lockSecondary: lock),
            ),
          ),
        ),
      );
    }

    testWidgets('locked: four starting tiles and the hint remain', (
      tester,
    ) async {
      await pump(tester, lock: true);

      for (final label in _secondary) {
        expect(find.text(label), findsNothing);
      }
      for (final label in _starters) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byType(InkResponse), findsNWidgets(_starters.length));
      expect(find.text('home.unlockHint'), findsOneWidget);
    });

    testWidgets('unlocked: every tile shows and the hint is gone', (
      tester,
    ) async {
      await pump(tester, lock: false);

      for (final label in [..._starters, ..._secondary]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('home.unlockHint'), findsNothing);
    });

    testWidgets('the Vocabulary tile keeps a 44 px target when locked', (
      tester,
    ) async {
      await pump(tester, lock: true);

      final size = tester.getSize(find.text('home.vocabulary'));
      expect(size.height, greaterThan(0));
      final tile = tester.getSize(
        find.ancestor(
          of: find.text('home.vocabulary'),
          matching: find.byType(InkResponse),
        ),
      );
      expect(tile.width, greaterThanOrEqualTo(44));
      expect(tile.height, greaterThanOrEqualTo(44));
    });
  });
}
