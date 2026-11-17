import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/confirm_dialog.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';
import 'package:lexilingo_app/features/admin/features/notification_campaign/data/notification_campaign_repository.dart';
import 'package:lexilingo_app/features/admin/features/notification_campaign/presentation/notification_campaign_screen.dart';
import 'package:lexilingo_app/features/admin/features/ranking_agent/data/ranking_agent_repository.dart';
import 'package:lexilingo_app/features/admin/features/ranking_agent/presentation/ranking_agent_screen.dart';
import 'package:provider/provider.dart';

class _CampaignRepo extends NotificationCampaignRepository {
  _CampaignRepo(this.jobs, {this.error});
  final List<NotificationCampaignJob> jobs;
  final Object? error;
  final applied = <String>[];
  final cancelled = <String>[];

  @override
  Future<List<NotificationCampaignJob>> getJobs({
    int limit = 50,
    int offset = 0,
  }) async {
    if (error != null) throw error!;
    return jobs;
  }

  @override
  Future<NotificationCampaignJob> apply(String id) async {
    applied.add(id);
    return jobs.first;
  }

  @override
  Future<NotificationCampaignJob> cancel(String id) async {
    cancelled.add(id);
    return jobs.first;
  }
}

class _RankingRepo extends RankingAgentRepository {
  _RankingRepo(this.jobs, {this.error});
  final List<RankingAgentJob> jobs;
  final Object? error;
  final applied = <String>[];

  @override
  Future<List<RankingAgentJob>> listJobs({
    int limit = 50,
    int offset = 0,
  }) async {
    if (error != null) throw error!;
    return jobs;
  }

  @override
  Future<RankingAgentJob> applyJob(String id) async {
    applied.add(id);
    return jobs.first;
  }
}

NotificationCampaignJob _campaign(String status) =>
    NotificationCampaignJob.fromJson({
      'id': 'c1',
      'job_type': 'targeted_push',
      'status': status,
      'created_at': '2026-01-01T00:00:00Z',
      'blocking_errors': [],
    });

RankingAgentJob _ranking(String status) => RankingAgentJob.fromJson({
  'id': 'r1',
  'job_type': 'xp_event',
  'status': status,
  'created_at': '2026-01-01T00:00:00Z',
});

DioException _status(int code) => DioException(
  requestOptions: RequestOptions(path: '/x'),
  response: Response(
    requestOptions: RequestOptions(path: '/x'),
    statusCode: code,
  ),
  type: DioExceptionType.badResponse,
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required List<String> perms,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final p = AdminPermissions()..apply({'all': false, 'permissions': perms});
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: p,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder _sheetApply() => find.descendant(
  of: find.byType(ConfirmSheet),
  matching: find.widgetWithText(FilledButton, 'adminGrowth.jobs.apply'),
);

void main() {
  group('notification campaigns', () {
    testWidgets('apply needs the typed word before it sends', (tester) async {
      final repo = _CampaignRepo([_campaign('preview_ready')]);
      await _pump(
        tester,
        NotificationCampaignScreen(repository: repo),
        perms: ['notifications:read', 'notifications:update'],
      );
      await tester.tap(find.text('adminGrowth.jobs.apply'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(
        FilledButton,
        'adminGrowth.jobs.apply',
      );
      expect(
        tester.widget<FilledButton>(confirm.last).onPressed,
        isNull,
        reason: 'confirm stays disabled until APPLY is typed',
      );
      await tester.enterText(find.byType(TextField).last, 'APPLY');
      await tester.pump();
      await tester.tap(_sheetApply());
      await tester.pumpAndSettle();
      expect(repo.applied, ['c1']);
    });

    testWidgets('read-only role gets no action buttons', (tester) async {
      await _pump(
        tester,
        NotificationCampaignScreen(
          repository: _CampaignRepo([_campaign('preview_ready')]),
        ),
        perms: ['notifications:read'],
      );
      expect(find.text('adminGrowth.jobs.apply'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('503 reads as feature-off, not an error', (tester) async {
      await _pump(
        tester,
        NotificationCampaignScreen(
          repository: _CampaignRepo([], error: _status(503)),
        ),
        perms: ['notifications:read'],
      );
      expect(find.text('admin.access.featureOffTitle'), findsOneWidget);
    });

    testWidgets('empty list', (tester) async {
      await _pump(
        tester,
        NotificationCampaignScreen(repository: _CampaignRepo([])),
        perms: ['notifications:read'],
      );
      expect(find.text('adminGrowth.campaign.empty'), findsOneWidget);
    });
  });

  group('ranking agent', () {
    testWidgets('apply is gated by typing the word', (tester) async {
      final repo = _RankingRepo([_ranking('preview_ready')]);
      await _pump(
        tester,
        RankingAgentScreen(repository: repo),
        perms: ['ranking:read', 'ranking:update'],
      );
      await tester.tap(find.text('adminGrowth.jobs.apply'));
      await tester.pumpAndSettle();
      await tester.tap(_sheetApply());
      await tester.pumpAndSettle();
      expect(repo.applied, isEmpty);
      await tester.enterText(find.byType(TextField).last, 'APPLY');
      await tester.pump();
      await tester.tap(_sheetApply());
      await tester.pumpAndSettle();
      expect(repo.applied, ['r1']);
    });

    testWidgets('403 shows the no-access state', (tester) async {
      await _pump(
        tester,
        RankingAgentScreen(repository: _RankingRepo([], error: _status(403))),
        perms: ['ranking:read'],
      );
      expect(find.text('admin.access.forbiddenTitle'), findsOneWidget);
    });

    testWidgets('empty list and read-only role', (tester) async {
      await _pump(
        tester,
        RankingAgentScreen(repository: _RankingRepo([])),
        perms: ['ranking:read'],
      );
      expect(find.text('adminGrowth.ranking.empty'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });
}
