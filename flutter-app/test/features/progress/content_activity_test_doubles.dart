import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/domain/entities/content_activity_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';

/// Only `getContentActivity` is exercised; the rest of the interface is routed
/// to noSuchMethod so this double does not have to track every method on it.
class FakeProgressRepository implements ProgressRepository {
  FakeProgressRepository({this.activity, this.failure});

  final ContentActivityEntity? activity;
  final Failure? failure;

  int calls = 0;
  int? lastDays;

  @override
  Future<Either<Failure, ContentActivityEntity>> getContentActivity({
    int days = 7,
  }) async {
    calls += 1;
    lastDays = days;
    final error = failure;
    if (error != null) return Left(error);
    return Right(activity ?? ContentActivityEntity.empty);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
