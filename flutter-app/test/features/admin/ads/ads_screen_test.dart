import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';
import 'package:lexilingo_app/features/admin/features/ads/data/banner_repository.dart';
import 'package:lexilingo_app/features/admin/features/ads/presentation/ads_screen.dart';
import 'package:provider/provider.dart';

class _FakeRepo extends BannerRepository {
  _FakeRepo({this.banners = const [], this.error});
  final List<BannerItem> banners;
  final Object? error;
  final toggled = <String, bool>{};

  @override
  Future<List<BannerItem>> listBanners() async {
    if (error != null) throw error!;
    return banners;
  }

  @override
  Future<void> setActive(String id, bool active) async => toggled[id] = active;
}

BannerItem _banner({bool active = true}) => BannerItem(
  id: 'b1',
  title: 'Spring promo',
  imageUrl: 'https://x/y.png',
  position: 'hero',
  priority: 3,
  isActive: active,
);

Future<void> _pump(
  WidgetTester tester,
  BannerRepository repo, {
  List<String> perms = const ['banners:read', 'banners:update'],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final p = AdminPermissions()..apply({'all': false, 'permissions': perms});
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
  test('BannerItem parses level and schedule fields', () {
    final b = BannerItem.fromJson({
      'id': 7,
      'title': 'T',
      'image_url': 'u',
      'position': 'sidebar',
      'priority': 2,
      'is_active': false,
      'target_min_level': 'A2',
      'start_at': '2026-01-02T00:00:00Z',
    });
    expect(b.id, '7');
    expect(b.isActive, isFalse);
    expect(b.targetMinLevel, 'A2');
    expect(b.startAt, isNotNull);
  });

  testWidgets('lists banners and toggles one', (tester) async {
    final repo = _FakeRepo(banners: [_banner()]);
    await _pump(tester, repo);
    expect(find.text('Spring promo'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(repo.toggled['b1'], isFalse);
  });

  testWidgets('read-only role sees no create, edit or switch action', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRepo(banners: [_banner()]),
      perms: ['banners:read'],
    );
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });

  testWidgets('empty state', (tester) async {
    await _pump(tester, _FakeRepo());
    expect(find.text('adminGrowth.ads.empty'), findsOneWidget);
  });

  testWidgets('403 shows the no-access state, not a retry error', (
    tester,
  ) async {
    final err = DioException(
      requestOptions: RequestOptions(path: '/banners'),
      response: Response(
        requestOptions: RequestOptions(path: '/banners'),
        statusCode: 403,
      ),
      type: DioExceptionType.badResponse,
    );
    await _pump(tester, _FakeRepo(error: err));
    expect(find.text('admin.access.forbiddenTitle'), findsOneWidget);
  });

  testWidgets('generic failure keeps the list empty and does not crash', (
    tester,
  ) async {
    await _pump(tester, _FakeRepo(error: Exception('boom')));
    expect(find.byType(AdsScreen), findsOneWidget);
    expect(find.text('Spring promo'), findsNothing);
  });
}
