/// Course Category Entity
/// 
/// Represents a category for organizing courses (e.g., Grammar, Vocabulary, Business English)
class CourseCategoryEntity {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? icon;
  final String? color;
  final int courseCount;

  const CourseCategoryEntity({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.icon,
    this.color,
    required this.courseCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourseCategoryEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          slug == other.slug;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ slug.hashCode;

  @override
  String toString() {
    return 'CourseCategoryEntity{id: $id, name: $name, slug: $slug, courseCount: $courseCount}';
  }
}
