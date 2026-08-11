import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';

abstract class MistakeNotebookRemoteDataSource {
  Future<List<MistakeNotebookEntry>> getEntries({String status = 'all'});

  Future<MistakeNotebookEntry> saveMistake(MistakeNotebookEntry entry);

  Future<MistakeNotebookEntry> markReviewed(String id);

  Future<MistakeNotebookEntry> reopen(String id);

  Future<void> delete(String id);
}

class ApiMistakeNotebookRemoteDataSource
    implements MistakeNotebookRemoteDataSource {
  final ApiClient apiClient;

  ApiMistakeNotebookRemoteDataSource({required this.apiClient});

  @override
  Future<List<MistakeNotebookEntry>> getEntries({String status = 'all'}) async {
    const limit = 100;
    var offset = 0;
    final entries = <MistakeNotebookEntry>[];

    while (true) {
      final path = Uri(
        path: '/mistakes',
        queryParameters: {
          'status': status,
          'limit': '$limit',
          'offset': '$offset',
        },
      ).toString();
      final response = await apiClient.get(path);
      final rawItems = response['data'];
      if (rawItems is! List) return entries;

      final pageEntries = rawItems
          .whereType<Map<String, dynamic>>()
          .map(MistakeNotebookEntry.fromJson)
          .where((entry) => entry.id.isNotEmpty)
          .toList();
      entries.addAll(pageEntries);

      if (pageEntries.length < limit) return entries;
      offset += limit;
    }
  }

  @override
  Future<MistakeNotebookEntry> saveMistake(MistakeNotebookEntry entry) async {
    final response = await apiClient.post('/mistakes', body: entry.toJson());
    return MistakeNotebookEntry.fromJson(response);
  }

  @override
  Future<MistakeNotebookEntry> markReviewed(String id) async {
    final encodedId = Uri.encodeComponent(id);
    final response = await apiClient.patch('/mistakes/$encodedId/review');
    return MistakeNotebookEntry.fromJson(response);
  }

  @override
  Future<MistakeNotebookEntry> reopen(String id) async {
    final encodedId = Uri.encodeComponent(id);
    final response = await apiClient.patch('/mistakes/$encodedId/reopen');
    return MistakeNotebookEntry.fromJson(response);
  }

  @override
  Future<void> delete(String id) async {
    final encodedId = Uri.encodeComponent(id);
    await apiClient.delete('/mistakes/$encodedId');
  }
}
