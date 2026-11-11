import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_detail_entity.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';
import 'package:lexilingo_app/features/course/domain/usecases/enroll_in_course_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_categories_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_course_detail_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_by_category_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';

class _Repo implements CourseRepository {
  final pending = <String, Completer<Either<Failure, CourseDetailEntity>>>{};

  @override
  Future<Either<Failure, CourseDetailEntity>> getCourseDetail(String id) =>
      (pending[id] = Completer()).future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

CourseDetailEntity _detail(String id) => CourseDetailEntity(
  id: id,
  title: 'Course $id',
  language: 'English',
  level: 'A2',
  tags: const [],
  totalXp: 0,
  estimatedDuration: 0,
  totalLessons: 0,
  isPublished: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  units: const [],
);

CourseProvider _provider(_Repo repo) => CourseProvider(
  getCoursesUseCase: GetCoursesUseCase(repo),
  getCourseDetailUseCase: GetCourseDetailUseCase(repo),
  enrollInCourseUseCase: EnrollInCourseUseCase(repo),
  getCategoriesUseCase: GetCategoriesUseCase(repo),
  getCoursesByCategoryUseCase: GetCoursesByCategoryUseCase(repo),
  getEnrolledCoursesUseCase: GetEnrolledCoursesUseCase(repo),
);

void main() {
  test('a slow refresh of course A cannot replace the course B the learner opened', () async {
    final repo = _Repo();
    final provider = _provider(repo);

    // Warm the cache for A, then complete a first load.
    final first = provider.loadCourseDetail('a');
    repo.pending['a']!.complete(Right(_detail('a')));
    await first;
    expect(provider.courseDetail?.id, 'a');

    // Returning to A refreshes in the background; the learner then opens B.
    final refreshA = provider.loadCourseDetail('a');
    final loadB = provider.loadCourseDetail('b');
    expect(provider.isLoadingDetail, isTrue, reason: 'B is not cached');

    repo.pending['a']!.complete(Right(_detail('a')));
    await refreshA;

    expect(provider.courseDetail, isNull, reason: "A's answer must not show up as B");
    expect(provider.isLoadingDetail, isTrue, reason: "B is still loading");

    repo.pending['b']!.complete(Right(_detail('b')));
    await loadB;
    expect(provider.courseDetail?.id, 'b');
    expect(provider.isLoadingDetail, isFalse);
  });
}
