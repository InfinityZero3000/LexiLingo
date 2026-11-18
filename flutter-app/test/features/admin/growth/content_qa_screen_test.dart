import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';
import 'package:lexilingo_app/features/admin/features/content_qa/data/content_qa_repository.dart';
import 'package:lexilingo_app/features/admin/features/content_qa/presentation/content_qa_screen.dart';
import 'package:provider/provider.dart';

class _Repo extends ContentQaRepository {
  _Repo({this.queue, this.error});
  final ContentQaQueue? queue;
  final Object? error;

  @override
  Future<ContentQaQueue> getQueue() async {
    if (error != null) throw error!;
    return queue!;
  }
}

ContentQaJob _job(String id, String status) => ContentQaJob.fromJson({
  'id': id,
  'status': status,
  'config': {'title_focus': 'Job $id'},
});

Future<void> _pump(WidgetTester tester, ContentQaRepository repo) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final p = AdminPermissions()
    ..apply({
      'all': false,
      'permissions': ['content_agent:read'],
    });
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: p,
      child: MaterialApp(home: ContentQaScreen(repository: repo)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('shows the needs-approval bucket first and switches buckets', (
    tester,
  ) async {
    await _pump(
      tester,
      _Repo(
        queue: ContentQaQueue(
          reviewable: [_job('a', 'preview_ready')],
          failed: [_job('b', 'failed')],
          applied: const [],
          total: 2,
        ),
      ),
    );
    expect(find.text('Job a'), findsOneWidget);
    expect(find.text('Job b'), findsNothing);
    final repair = find.textContaining('adminGrowth.qa.tabRepair');
    await tester.ensureVisible(repair);
    await tester.pump();
    await tester.tap(repair);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Job b'), findsOneWidget);
  });

  testWidgets('empty bucket', (tester) async {
    await _pump(
      tester,
      _Repo(
        queue: const ContentQaQueue(
          reviewable: [],
          failed: [],
          applied: [],
          total: 0,
        ),
      ),
    );
    expect(find.text('adminGrowth.qa.emptyBucket'), findsOneWidget);
  });

  testWidgets('503 (agent switched off) is a normal state', (tester) async {
    final err = DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 503,
      ),
      type: DioExceptionType.badResponse,
    );
    await _pump(tester, _Repo(error: err));
    expect(find.text('admin.access.featureOffTitle'), findsOneWidget);
  });
}
