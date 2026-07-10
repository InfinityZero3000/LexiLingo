import 'package:lexilingo_app/core/network/api_client.dart';
import '../../domain/entities/notification_entity.dart';

class NotificationRemoteDataSource {
  final ApiClient apiClient;

  NotificationRemoteDataSource({required this.apiClient});

  Future<List<NotificationEntity>> getNotifications() async {
    final response = await apiClient.get('/notifications');
    final rawItems = response['data'];
    if (rawItems is! List) return [];

    return rawItems
        .whereType<Map<String, dynamic>>()
        .map(NotificationEntity.fromBackend)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> markAsRead(String id) async {
    await apiClient.patch('/notifications/$id/read');
  }

  Future<void> markAllAsRead() async {
    await apiClient.patch('/notifications/read-all');
  }

  Future<void> deleteNotification(String id) async {
    await apiClient.delete('/notifications/$id');
  }

  Future<void> deleteAllNotifications() async {
    await apiClient.delete('/notifications');
  }
}
