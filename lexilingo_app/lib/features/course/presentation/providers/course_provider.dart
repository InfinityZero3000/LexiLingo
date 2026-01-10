import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/course/domain/entities/course.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

class CourseProvider extends ChangeNotifier {
  final CourseRepository repository;
  List<Course> _courses = [];

  CourseProvider({required this.repository}) {
    loadCourses();
  }

  List<Course> get courses => _courses;

  Future<void> loadCourses() async {
    _courses = await repository.getCourses();
    notifyListeners();
  }
}
