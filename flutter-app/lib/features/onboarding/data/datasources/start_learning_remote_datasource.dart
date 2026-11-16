import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/onboarding/data/models/start_learning_target_model.dart';

abstract class StartLearningRemoteDataSource {
  Future<StartLearningTargetModel> startLearning({String? courseId});
}

class StartLearningRemoteDataSourceImpl
    implements StartLearningRemoteDataSource {
  final ApiClient apiClient;

  StartLearningRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<StartLearningTargetModel> startLearning({String? courseId}) async {
    final response = await apiClient.post(
      '/users/me/start-learning',
      body: courseId == null ? null : {'course_id': courseId},
    );
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('start-learning response has no data');
    }
    return StartLearningTargetModel.fromJson(data);
  }
}
