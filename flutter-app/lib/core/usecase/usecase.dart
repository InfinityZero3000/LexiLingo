import 'package:dartz/dartz.dart';
import '../error/failures.dart';

/// Base class for all use cases with Either error handling
abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

/// Use this class when the use case doesn't accept any parameters.
class NoParams {
  const NoParams();
}
