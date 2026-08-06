import '../../../core/network/api_client.dart';

class RankingAgentJob {
  final String id, jobType, status, createdAt;
  final String? updatedAt, startedAt, completedAt, errorMessage;
  final Map<String, dynamic> progress, config, createdEntityIds;
  final Map<String, dynamic>? artifact;
  final List<String> warnings, blockingErrors;

  const RankingAgentJob({
    required this.id,
    required this.jobType,
    required this.status,
    required this.createdAt,
    required this.progress,
    required this.config,
    required this.createdEntityIds,
    required this.warnings,
    required this.blockingErrors,
    this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.errorMessage,
    this.artifact,
  });

  factory RankingAgentJob.fromJson(Map<String, dynamic> json) => RankingAgentJob(
        id: json['id']?.toString() ?? '',
        jobType: json['job_type']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        createdAt: json['created_at']?.toString() ?? '',
        updatedAt: json['updated_at']?.toString(),
        startedAt: json['started_at']?.toString(),
        completedAt: json['completed_at']?.toString(),
        errorMessage: json['error_message']?.toString(),
        progress: _map(json['progress']),
        config: _map(json['config']),
        artifact: json['artifact'] is Map ? _map(json['artifact']) : null,
        createdEntityIds: _map(json['created_entity_ids']),
        warnings: _strings(json['warnings']),
        blockingErrors: _strings(json['blocking_errors']),
      );

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  static List<String> _strings(dynamic value) =>
      value is List ? value.map((item) => item.toString()).toList() : <String>[];

  bool get isActive => const {
        'queued',
        'calculating',
        'validating',
        'applying',
      }.contains(status);
  bool get canApply => status == 'preview_ready' && blockingErrors.isEmpty;
  int get progressPercent =>
      ((progress['percent'] as num?)?.round() ?? 0).clamp(0, 100);
}

class RankingAgentPreview {
  final Map<String, dynamic> artifact;
  final List<String> warnings, blockingErrors;

  const RankingAgentPreview({
    required this.artifact,
    required this.warnings,
    required this.blockingErrors,
  });

  factory RankingAgentPreview.fromJson(Map<String, dynamic> json) =>
      RankingAgentPreview(
        artifact: RankingAgentJob._map(json['artifact']),
        warnings: RankingAgentJob._strings(json['warnings']),
        blockingErrors: RankingAgentJob._strings(json['blocking_errors']),
      );
}

class RankingAgentRepository {
  static const _jobs = '/admin/ranking-agent/jobs';
  final _api = ApiClient.instance;

  Map<String, dynamic> _data(Map<String, dynamic> response) =>
      response['data'] is Map
          ? Map<String, dynamic>.from(response['data'] as Map)
          : <String, dynamic>{};

  Future<RankingAgentJob> createJob(Map<String, dynamic> payload) async =>
      RankingAgentJob.fromJson(_data(await _api.post(_jobs, data: payload)));

  Future<List<RankingAgentJob>> listJobs({int limit = 50, int offset = 0}) async {
    final response = await _api.get(_jobs, params: {'limit': limit, 'offset': offset});
    final data = response['data'];
    return data is List
        ? data
            .whereType<Map>()
            .map((item) => RankingAgentJob.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <RankingAgentJob>[];
  }

  Future<RankingAgentJob> getJob(String id) async =>
      RankingAgentJob.fromJson(_data(await _api.get('$_jobs/$id')));

  Future<RankingAgentPreview> getPreview(String id) async =>
      RankingAgentPreview.fromJson(_data(await _api.get('$_jobs/$id/preview')));

  Future<RankingAgentJob> applyJob(String id) async {
    final result = _data(await _api.post('$_jobs/$id/apply'));
    return RankingAgentJob.fromJson(RankingAgentJob._map(result['job']));
  }

  Future<RankingAgentJob> cancelJob(String id) async =>
      RankingAgentJob.fromJson(_data(await _api.post('$_jobs/$id/cancel')));

  Future<RankingAgentJob> retryJob(String id) async =>
      RankingAgentJob.fromJson(_data(await _api.post('$_jobs/$id/retry')));
}
