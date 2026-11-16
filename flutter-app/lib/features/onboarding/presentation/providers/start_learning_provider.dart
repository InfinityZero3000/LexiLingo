import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/onboarding/domain/entities/start_learning_target.dart';
import 'package:lexilingo_app/features/onboarding/domain/usecases/start_learning_usecase.dart';

enum StartLearningStatus { idle, loading, ready, failed }

class StartLearningProvider extends ChangeNotifier {
  final StartLearningUseCase startLearningUseCase;

  StartLearningProvider({required this.startLearningUseCase});

  StartLearningStatus _status = StartLearningStatus.idle;
  StartLearningTarget? _target;
  String? _errorMessage;
  bool _disposed = false;

  StartLearningStatus get status => _status;
  StartLearningTarget? get target => _target;
  String? get errorMessage => _errorMessage;

  Future<StartLearningTarget?> start({String? courseId}) async {
    if (_status == StartLearningStatus.loading) return null;
    _status = StartLearningStatus.loading;
    _errorMessage = null;
    _notify();

    final result = await startLearningUseCase(
      StartLearningParams(courseId: courseId),
    );
    return result.fold(
      (failure) {
        _status = StartLearningStatus.failed;
        _errorMessage = failure.message;
        _notify();
        return null;
      },
      (target) {
        _status = StartLearningStatus.ready;
        _target = target;
        _notify();
        return target;
      },
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
