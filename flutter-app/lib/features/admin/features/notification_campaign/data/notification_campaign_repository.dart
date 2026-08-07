import '../../../core/network/api_client.dart';

enum NotificationCampaignJobType { targetedPush, inAppBroadcast, scheduledPush }

extension NotificationCampaignJobTypeValue on NotificationCampaignJobType {
  String get value => switch (this) {
        NotificationCampaignJobType.targetedPush => 'targeted_push',
        NotificationCampaignJobType.inAppBroadcast => 'in_app_broadcast',
        NotificationCampaignJobType.scheduledPush => 'scheduled_push',
      };

  String get label => switch (this) {
        NotificationCampaignJobType.targetedPush => 'Targeted Push',
        NotificationCampaignJobType.inAppBroadcast => 'In-App Broadcast',
        NotificationCampaignJobType.scheduledPush => 'Scheduled Push',
      };
}

class NotificationCampaignJob {
  final String id, jobType, status, createdAt;
  final String? scheduledAt, errorMessage;
  final int progressPercent;
  final Map<String, dynamic> config;
  final List<String> warnings, blockingErrors;

  const NotificationCampaignJob({
    required this.id,
    required this.jobType,
    required this.status,
    required this.createdAt,
    required this.progressPercent,
    required this.config,
    required this.warnings,
    required this.blockingErrors,
    this.scheduledAt,
    this.errorMessage,
  });

  factory NotificationCampaignJob.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'] as Map<String, dynamic>? ?? const {};
    return NotificationCampaignJob(
      id: json['id']?.toString() ?? '',
      jobType: json['job_type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      scheduledAt: json['scheduled_at']?.toString(),
      errorMessage: json['error_message']?.toString(),
      progressPercent: (progress['percent'] as num?)?.round() ?? 0,
      config: (json['config'] as Map?)?.cast<String, dynamic>() ?? const {},
      warnings: ((json['warnings'] as List?) ?? const []).map((e) => e.toString()).toList(),
      blockingErrors: ((json['blocking_errors'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }

  bool get needsAttention => const {
        'queued', 'segmenting', 'generating', 'validating', 'sending', 'preview_ready'
      }.contains(status);
  bool get canApply => status == 'preview_ready' && blockingErrors.isEmpty;
  bool get canCancel => const {'queued', 'segmenting', 'generating', 'validating', 'sending', 'preview_ready'}.contains(status);
  bool get canRetry => status == 'failed' || status == 'cancelled';
}

class NotificationCampaignRepository {
  static const _path = '/admin/notification-campaign/jobs';
  final _api = ApiClient.instance;

  NotificationCampaignJob _job(Map<String, dynamic> response) =>
      NotificationCampaignJob.fromJson(response['data'] as Map<String, dynamic>);

  Future<List<NotificationCampaignJob>> getJobs({int limit = 50, int offset = 0}) async {
    final response = await _api.get(_path, params: {'limit': limit, 'offset': offset});
    return ((response['data'] as List?) ?? const [])
        .map((e) => NotificationCampaignJob.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<NotificationCampaignJob> getJob(String id) async => _job(await _api.get('$_path/$id'));
  Future<NotificationCampaignJob> createJob(Map<String, dynamic> payload) async => _job(await _api.post(_path, data: payload));
  Future<NotificationCampaignJob> apply(String id) async => _job(await _api.post('$_path/$id/apply'));
  Future<NotificationCampaignJob> cancel(String id) async => _job(await _api.post('$_path/$id/cancel'));
  Future<NotificationCampaignJob> retry(String id) async => _job(await _api.post('$_path/$id/retry'));
}
