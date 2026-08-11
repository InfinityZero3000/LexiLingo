import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/notification_campaign/data/notification_campaign_repository.dart';

void main() {
  test('NotificationCampaignJob.fromJson parses fields and nested progress', () {
    final job = NotificationCampaignJob.fromJson({
      'id': 3,
      'job_type': 'targeted_push',
      'status': 'sending',
      'created_at': '2026-08-06T08:30:00Z',
      'scheduled_at': null,
      'progress': {'percent': 42.6},
      'config': {'title': 'Weekend streak reminder'},
      'warnings': ['segment is large'],
      'blocking_errors': [],
    });

    expect(job.id, '3');
    expect(job.jobType, 'targeted_push');
    expect(job.status, 'sending');
    expect(job.progressPercent, 43);
    expect(job.config['title'], 'Weekend streak reminder');
    expect(job.warnings, ['segment is large']);
    expect(job.blockingErrors, isEmpty);
  });

  test('NotificationCampaignJob defaults progress to 0 when missing', () {
    final job = NotificationCampaignJob.fromJson({
      'id': '1',
      'job_type': 'in_app_broadcast',
      'status': 'queued',
      'created_at': '2026-08-06T08:30:00Z',
    });

    expect(job.progressPercent, 0);
    expect(job.config, isEmpty);
  });

  test('needsAttention/canApply/canCancel/canRetry reflect the job status', () {
    NotificationCampaignJob withStatus(String status, {List<String> blocking = const []}) =>
        NotificationCampaignJob.fromJson({
          'id': '1',
          'job_type': 'targeted_push',
          'status': status,
          'created_at': '2026-08-06T08:30:00Z',
          'blocking_errors': blocking,
        });

    expect(withStatus('preview_ready').needsAttention, isTrue);
    expect(withStatus('preview_ready').canApply, isTrue);
    expect(withStatus('preview_ready', blocking: ['bad segment']).canApply, isFalse);
    expect(withStatus('sent').needsAttention, isFalse);
    expect(withStatus('failed').canRetry, isTrue);
    expect(withStatus('cancelled').canRetry, isTrue);
    expect(withStatus('sent').canRetry, isFalse);
    expect(withStatus('queued').canCancel, isTrue);
    expect(withStatus('sent').canCancel, isFalse);
  });

  test('NotificationCampaignJobType value/label mapping is stable', () {
    expect(NotificationCampaignJobType.targetedPush.value, 'targeted_push');
    expect(NotificationCampaignJobType.inAppBroadcast.value, 'in_app_broadcast');
    expect(NotificationCampaignJobType.scheduledPush.value, 'scheduled_push');
    expect(NotificationCampaignJobType.targetedPush.label, 'Targeted Push');
  });
}
