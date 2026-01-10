class Course {
  final int? id;
  final String title;
  final String description;
  final String level;
  final double progress;

  Course({this.id, required this.title, required this.description, required this.level, this.progress = 0.0});
}
