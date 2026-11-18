import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';
import 'package:lexilingo_app/features/admin/features/ads/data/banner_repository.dart';
import 'package:lexilingo_app/features/admin/features/ads/presentation/ads_screen.dart';
import 'package:provider/provider.dart';

class _Repo extends BannerRepository {
  _Repo({this.failToggle = false});
  final bool failToggle;
  int lists = 0;

  @override
  Future<List<BannerItem>> listBanners() async {
    lists++;
    return const [
      BannerItem(
        id: 'b1',
        title: 'Spring promo',
        imageUrl: 'u',
        position: 'hero',
        priority: 1,
        isActive: true,
      ),
    ];
  }

  @override
  Future<void> setActive(String id, bool active) async {
    if (failToggle) throw Exception('boom');
  }
}

Future<void> _pump(WidgetTester tester, BannerRepository repo) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final p = AdminPermissions()
    ..apply({
      'all': false,
      'permissions': ['banners:read', 'banners:update'],
    });
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: p,
      child: MaterialApp(home: AdsScreen(repository: repo)),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('toggle flips the row in place without reloading the list', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(tester, repo);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(repo.lists, 1);
  });

  testWidgets('a failed toggle reverts the switch and says so', (tester) async {
    final repo = _Repo(failToggle: true);
    await _pump(tester, repo);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('end date before start date is refused inline', (tester) async {
    await _pump(tester, _Repo());
    final item = BannerItem(
      id: 'b1',
      title: 'T',
      imageUrl: 'u',
      position: 'hero',
      priority: 1,
      isActive: true,
      startAt: DateTime(2026, 5, 10),
      endAt: DateTime(2026, 5, 1),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: BannerForm(item: item))),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('adminGrowth.ads.endBeforeStart'), findsOneWidget);
  });
}
