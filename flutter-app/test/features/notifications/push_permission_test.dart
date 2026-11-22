import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/features/notifications/domain/services/push_permission_gateway.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/push_permission_provider.dart';
import 'package:lexilingo_app/features/notifications/presentation/widgets/push_permission_card.dart';

class _FakeGateway implements PushPermissionGateway {
  PushPermission current;
  PushPermission onRequest;
  int requests = 0;
  _FakeGateway(this.current, {this.onRequest = PushPermission.granted});

  @override
  Future<PushPermission> status() async => current;

  @override
  Future<PushPermission> requestPermission() async {
    requests++;
    return onRequest;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PushPermissionProvider', () {
    test('shows when permission is undecided', () async {
      final p = PushPermissionProvider(
        gateway: _FakeGateway(PushPermission.notDetermined),
      );
      await p.evaluate();
      expect(p.visible, isTrue);
    });

    for (final s in [
      PushPermission.granted,
      PushPermission.denied,
      PushPermission.unsupported,
    ]) {
      test('stays hidden when status is $s', () async {
        final p = PushPermissionProvider(gateway: _FakeGateway(s));
        await p.evaluate();
        expect(p.visible, isFalse);
      });
    }

    test('Not now hides it and suppresses it for a week', () async {
      var clock = DateTime(2026, 1, 1);
      final gateway = _FakeGateway(PushPermission.notDetermined);
      final p = PushPermissionProvider(gateway: gateway, now: () => clock);
      await p.evaluate();
      await p.notNow();
      expect(p.visible, isFalse);

      clock = clock.add(const Duration(days: 6));
      final again = PushPermissionProvider(gateway: gateway, now: () => clock);
      await again.evaluate();
      expect(again.visible, isFalse);

      clock = clock.add(const Duration(days: 2));
      final later = PushPermissionProvider(gateway: gateway, now: () => clock);
      await later.evaluate();
      expect(later.visible, isTrue);
    });

    test('allow requests permission once and hides the card', () async {
      final gateway = _FakeGateway(PushPermission.notDetermined);
      final p = PushPermissionProvider(gateway: gateway);
      await p.evaluate();
      await p.allow();
      expect(gateway.requests, 1);
      expect(p.visible, isFalse);
    });

    test('a denied system prompt starts the one-week cooldown', () async {
      final gateway = _FakeGateway(
        PushPermission.notDetermined,
        onRequest: PushPermission.denied,
      );
      final p = PushPermissionProvider(gateway: gateway);
      await p.evaluate();
      await p.allow();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PushPermissionProvider.declinedAtKey), isNotNull);
    });
  });

  group('PushPermissionCard', () {
    Future<void> pump(WidgetTester t, _FakeGateway g) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PushPermissionCard(gateway: g)),
        ),
      );
      await t.pumpAndSettle();
    }

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await EasyLocalization.ensureInitialized();
    });

    testWidgets('renders nothing once granted', (t) async {
      await pump(t, _FakeGateway(PushPermission.granted));
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('both actions are at least 44px tall and Not now hides', (
      t,
    ) async {
      final g = _FakeGateway(PushPermission.notDetermined);
      await pump(t, g);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        t.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        t.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(44),
      );
      await t.tap(find.byType(TextButton));
      await t.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
      expect(g.requests, 0);
    });

    testWidgets('Allow asks the gateway', (t) async {
      final g = _FakeGateway(PushPermission.notDetermined);
      await pump(t, g);
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(g.requests, 1);
    });
  });
}
