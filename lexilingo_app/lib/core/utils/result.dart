// Generic Result type if dartz is not used
// ignore_for_file: depend_on_referenced_packages

import '../error/failures.dart';

/// A generic Result class to handle Success and Failure cases.
/// This works similar to Either<Failure, T> from dartz.
class Result<T> {
  final T? _data;
  final Failure? _failure;

  const Result.success(T data)
      : _data = data,
        _failure = null;

  const Result.failure(Failure failure)
      : _data = null,
        _failure = failure;

  bool get isSuccess => _failure == null;
  bool get isFailure => _failure != null;

  T get data {
    if (_data == null) throw Exception("Cannot get data from a failure result");
    return _data!;
  }

  Failure get failure {
    if (_failure == null) throw Exception("Cannot get failure from a success result");
    return _failure!;
  }

  R fold<R>(R Function(Failure) onFailure, R Function(T) onSuccess) {
    if (isFailure) {
      return onFailure(_failure!);
    } else {
      return onSuccess(_data as T);
    }
  }
}
