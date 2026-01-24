import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/course/domain/entities/course.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';

class CourseProvider extends ChangeNotifier {
  final GetCoursesUseCase getCoursesUseCase;
  List<Course> _courses = [];

  CourseProvider({required this.getCoursesUseCase}) {
    loadCourses();
  }

  List<Course> get courses => _courses;

  Future<void> loadCourses() async {
    _courses = await getCoursesUseCase(NoParams());
    notifyListeners();
  }
}
