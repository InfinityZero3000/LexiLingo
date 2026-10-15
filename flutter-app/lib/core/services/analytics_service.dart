import 'dart:async';

import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:uuid/uuid.dart';

void trackProductEvent(
  String eventName, {
  required String source,
  Map<String, Object?> properties = const {},
}) {
  if (!sl.isRegistered<AnalyticsService>()) return;
  sl<AnalyticsService>().track(
    eventName,
    source: source,
    properties: properties,
  );
}

/// The single interaction signal the recommender learns topic affinity from.
/// Every graded or browsable surface should report one; `topic` is what makes
/// "the topic this learner picks most" computable at all.
void trackContentInteraction({
  required String itemType,
  required String itemId,
  required String action,
  String? topic,
  String source = 'app',
  int? dwellMs,
}) {
  trackProductEvent(
    'content_interaction',
    source: source,
    properties: {
      'item_type': itemType,
      'item_id': itemId,
      'action': action,
      if (topic != null && topic.isNotEmpty) 'topic': topic,
      if (dwellMs != null) 'dwell_ms': dwellMs,
    },
  );
}

class AnalyticsService {
  AnalyticsService({
    required ApiClient apiClient,
    this.batchSize = 10,
    this.flushInterval = const Duration(seconds: 1),
  }) : _apiClient = apiClient;

  final ApiClient _apiClient;
  final int batchSize;
  final Duration flushInterval;
  final List<Map<String, Object?>> _queue = [];
  Timer? _flushTimer;
  bool _isSending = false;

  void track(
    String eventName, {
    required String source,
    Map<String, Object?> properties = const {},
  }) {
    _queue.add({
      'event_id': const Uuid().v4(),
      'event_name': eventName,
      'source': source,
      'properties': properties,
      'client_timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    if (_queue.length >= batchSize) {
      unawaited(flush());
    } else {
      _flushTimer ??= Timer(flushInterval, flush);
    }
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_isSending || _queue.isEmpty) return;

    final count = _queue.length < batchSize ? _queue.length : batchSize;
    final events = _queue.sublist(0, count);
    _queue.removeRange(0, count);
    _isSending = true;

    try {
      await _apiClient.post(
        '/analytics/events',
        body: {'events': events},
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
    } finally {
      _isSending = false;
      if (_queue.isNotEmpty) _flushTimer ??= Timer(flushInterval, flush);
    }
  }

  void dispose() {
    _flushTimer?.cancel();
  }
}
