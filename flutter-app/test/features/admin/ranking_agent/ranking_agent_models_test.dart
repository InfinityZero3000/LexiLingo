import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/ranking_agent/data/ranking_agent_repository.dart';

void main() {
  test('RankingAgentJob.fromJson parses fields and clamps progress percent', () {
    final job = RankingAgentJob.fromJson({
      'id': 5,
      'job_type': 'league_reset',
      'status': 'applying',
      'created_at': '2026-08-06T08:30:00Z',
      'progress': {'percent': 120},
      'config': {'league': 'gold'},
      'created_entity_ids': {'league_id': 'gold'},
      'warnings': ['high load'],
      'blocking_errors': [],
      'artifact': {'affected_users': 42},
    });

    expect(job.id, '5');
    expect(job.jobType, 'league_reset');
    expect(job.status, 'applying');
    expect(job.progressPercent, 100, reason: 'progress should clamp to 100');
    expect(job.config['league'], 'gold');
    expect(job.createdEntityIds['league_id'], 'gold');
    expect(job.warnings, ['high load']);
    expect(job.artifact?['affected_users'], 42);
    expect(job.isActive, isTrue);
  });

  test('RankingAgentJob defaults maps/lists when fields are missing', () {
    final job = RankingAgentJob.fromJson({
      'id': '1',
      'job_type': 'xp_event',
      'status': 'queued',
      'created_at': '2026-08-06T08:30:00Z',
    });

    expect(job.progress, isEmpty);
    expect(job.config, isEmpty);
    expect(job.createdEntityIds, isEmpty);
    expect(job.warnings, isEmpty);
    expect(job.blockingErrors, isEmpty);
    expect(job.artifact, isNull);
    expect(job.progressPercent, 0);
  });

  test('canApply requires preview_ready status with no blocking errors', () {
    final ready = RankingAgentJob.fromJson({
      'id': '1', 'job_type': 'xp_event', 'status': 'preview_ready', 'created_at': '',
    });
    final blocked = RankingAgentJob.fromJson({
      'id': '2', 'job_type': 'xp_event', 'status': 'preview_ready', 'created_at': '',
      'blocking_errors': ['bad multiplier'],
    });

    expect(ready.canApply, isTrue);
    expect(blocked.canApply, isFalse);
  });

  test('RankingAgentPreview.fromJson parses artifact and warnings', () {
    final preview = RankingAgentPreview.fromJson({
      'artifact': {'affected_users': 10},
      'warnings': ['review before applying'],
      'blocking_errors': [],
    });

    expect(preview.artifact['affected_users'], 10);
    expect(preview.warnings, ['review before applying']);
    expect(preview.blockingErrors, isEmpty);
  });
}
