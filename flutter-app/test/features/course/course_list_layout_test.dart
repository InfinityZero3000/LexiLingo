import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';

void main() {
  group('Course List Horizontal Layout Tests', () {
    group('Category Section UI Tests', () {
      testWidgets('should render category header with correct icon and color', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestCategoryHeader(
                title: 'Beginner',
                courseCount: 5,
              ),
            ),
          ),
        );

        // Should display category title
        expect(find.text('Beginner'), findsOneWidget);

        // Should display course count
        expect(find.text('5 courses'), findsOneWidget);

        // Should have icon
        expect(find.byIcon(Icons.school_outlined), findsOneWidget);

        // Should have "See All" button
        expect(find.text('See All'), findsOneWidget);
      });

      testWidgets('should render singular course text for single course', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestCategoryHeader(
                title: 'Advanced',
                courseCount: 1,
              ),
            ),
          ),
        );

        expect(find.text('1 course'), findsOneWidget);
      });

      testWidgets('should use correct colors for different categories', (tester) async {
        // Test Beginner - Green
        expect(_getCategoryColor('Beginner'), Colors.green);

        // Test Intermediate - Orange
        expect(_getCategoryColor('Intermediate'), Colors.orange);

        // Test Advanced - Red
        expect(_getCategoryColor('Advanced'), Colors.red);

        // Test Unknown - Blue
        expect(_getCategoryColor('Unknown'), Colors.blue);
      });

      testWidgets('should use correct icons for different categories', (tester) async {
        // Test Beginner
        expect(_getCategoryIcon('Beginner'), Icons.school_outlined);

        // Test Intermediate
        expect(_getCategoryIcon('Intermediate'), Icons.trending_up);

        // Test Advanced
        expect(_getCategoryIcon('Advanced'), Icons.emoji_events_outlined);

        // Test Unknown
        expect(_getCategoryIcon('Unknown'), Icons.book_outlined);
      });
    });

    group('Horizontal Course Card Tests', () {
      final testCourse = CourseEntity(
        id: '1',
        title: 'English for Beginners - Complete Guide',
        description: 'Learn English from scratch',
        language: 'English',
        level: 'Beginner',
        tags: ['Grammar', 'Vocabulary'],
        thumbnailUrl: 'https://example.com/image.jpg',
        totalXp: 150,
        estimatedDuration: 60,
        totalLessons: 12,
        isPublished: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isEnrolled: false,
      );

      testWidgets('should render course card with title', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestCourseCard(course: testCourse),
            ),
          ),
        );

        expect(find.text('English for Beginners - Complete Guide'), findsOneWidget);
      });

      testWidgets('should render language chip', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestCourseCard(course: testCourse),
            ),
          ),
        );

        expect(find.text('English'), findsOneWidget);
      });

      testWidgets('should render XP and lesson count', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestCourseCard(course: testCourse),
            ),
          ),
        );

        expect(find.text('150 XP'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
      });

      testWidgets('should show Start Learning button when not enrolled', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestCourseCard(course: testCourse),
            ),
          ),
        );

        expect(find.text('Start Learning'), findsOneWidget);
      });

      testWidgets('should show progress when enrolled', (tester) async {
        final enrolledCourse = CourseEntity(
          id: '1',
          title: 'English Course',
          language: 'English',
          level: 'Beginner',
          tags: [],
          totalXp: 100,
          estimatedDuration: 60,
          totalLessons: 10,
          isPublished: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isEnrolled: true,
          userProgress: 45.5,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestCourseCard(course: enrolledCourse),
            ),
          ),
        );

        expect(find.text('46% Complete'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      });

      testWidgets('should be tappable', (tester) async {
        bool tapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestCourseCard(
                course: testCourse,
                onTap: () => tapped = true,
              ),
            ),
          ),
        );

        await tester.tap(find.byType(InkWell).first);
        expect(tapped, true);
      });
    });

    group('Horizontal Scroll Layout Tests', () {
      testWidgets('should render horizontal ListView for courses', (tester) async {
        final courses = List.generate(
          5,
          (i) => CourseEntity(
            id: '$i',
            title: 'Course $i',
            language: 'English',
            level: 'Beginner',
            tags: [],
            totalXp: 100,
            estimatedDuration: 60,
            totalLessons: 10,
            isPublished: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestHorizontalCourseList(courses: courses),
            ),
          ),
        );

        // Should find horizontal ListView
        final listViewFinder = find.byType(ListView);
        expect(listViewFinder, findsOneWidget);

        final ListView listView = tester.widget(listViewFinder);
        expect(listView.scrollDirection, Axis.horizontal);
      });

      testWidgets('should have fixed height for horizontal course list', (tester) async {
        final courses = [
          CourseEntity(
            id: '1',
            title: 'Test Course',
            language: 'English',
            level: 'Beginner',
            tags: [],
            totalXp: 100,
            estimatedDuration: 60,
            totalLessons: 10,
            isPublished: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestHorizontalCourseList(courses: courses),
            ),
          ),
        );

        // The height should be 280 as defined in the implementation
        final sizedBoxFinder = find.byType(SizedBox).first;
        final SizedBox sizedBox = tester.widget(sizedBoxFinder);
        expect(sizedBox.height, 280);
      });

      testWidgets('should render all courses in horizontal list', (tester) async {
        final courses = [
          _createTestCourse(id: '1', title: 'Course A'),
          _createTestCourse(id: '2', title: 'Course B'),
          _createTestCourse(id: '3', title: 'Course C'),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _TestCourseCard(course: courses[0]),
                    _TestCourseCard(course: courses[1]),
                    _TestCourseCard(course: courses[2]),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(find.text('Course A'), findsOneWidget);
        expect(find.text('Course B'), findsOneWidget);
        expect(find.text('Course C'), findsOneWidget);
      });
    });

    group('Course Grouping Display Tests', () {
      test('should group courses by category correctly', () {
        final courses = [
          _createTestCourse(id: '1', level: 'Beginner'),
          _createTestCourse(id: '2', level: 'Beginner'),
          _createTestCourse(id: '3', level: 'Intermediate'),
          _createTestCourse(id: '4', level: 'Advanced'),
        ];

        final grouped = _groupCoursesByCategory(courses);

        expect(grouped['Beginner']!.length, 2);
        expect(grouped['Intermediate']!.length, 1);
        expect(grouped['Advanced']!.length, 1);
      });

      test('should maintain category order', () {
        final courses = [
          _createTestCourse(id: '1', level: 'Advanced'),
          _createTestCourse(id: '2', level: 'Beginner'),
          _createTestCourse(id: '3', level: 'Intermediate'),
        ];

        final grouped = _groupCoursesByCategory(courses);
        final keys = grouped.keys.toList();

        // Beginner should come before Intermediate which comes before Advanced
        expect(keys.indexOf('Beginner') < keys.indexOf('Intermediate'), true);
        expect(keys.indexOf('Intermediate') < keys.indexOf('Advanced'), true);
      });

      test('should not include empty categories', () {
        final courses = [
          _createTestCourse(id: '1', level: 'Beginner'),
          _createTestCourse(id: '2', level: 'Advanced'),
        ];

        final grouped = _groupCoursesByCategory(courses);

        expect(grouped.containsKey('Intermediate'), false);
        expect(grouped.keys.length, 2);
      });
    });
  });
}

// Test helper widgets
class _TestCategoryHeader extends StatelessWidget {
  final String title;
  final int courseCount;

  const _TestCategoryHeader({
    required this.title,
    required this.courseCount,
  });

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor(title);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getCategoryIcon(title),
              color: categoryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  '$courseCount ${courseCount == 1 ? 'course' : 'courses'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {},
            child: const Text('See All'),
          ),
        ],
      ),
    );
  }
}

class _TestCourseCard extends StatelessWidget {
  final CourseEntity course;
  final VoidCallback? onTap;

  const _TestCourseCard({
    required this.course,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        course.language,
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 14,
                          color: Colors.amber[700],
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${course.totalXp} XP',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.book_outlined,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${course.totalLessons}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (course.isEnrolled == true) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (course.userProgress ?? 0) / 100,
                          backgroundColor: Colors.grey[300],
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${course.userProgress?.toStringAsFixed(0) ?? '0'}% Complete',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Start Learning',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestHorizontalCourseList extends StatelessWidget {
  final List<CourseEntity> courses;

  const _TestHorizontalCourseList({required this.courses});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: courses.length,
        itemBuilder: (context, index) {
          return _TestCourseCard(course: courses[index]);
        },
      ),
    );
  }
}

// Helper functions
Color _getCategoryColor(String category) {
  switch (category.toLowerCase()) {
    case 'beginner':
      return Colors.green;
    case 'intermediate':
      return Colors.orange;
    case 'advanced':
      return Colors.red;
    default:
      return Colors.blue;
  }
}

IconData _getCategoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'beginner':
      return Icons.school_outlined;
    case 'intermediate':
      return Icons.trending_up;
    case 'advanced':
      return Icons.emoji_events_outlined;
    default:
      return Icons.book_outlined;
  }
}

Map<String, List<CourseEntity>> _groupCoursesByCategory(
    List<CourseEntity> courses) {
  final Map<String, List<CourseEntity>> grouped = {};
  const categoryOrder = ['Beginner', 'Intermediate', 'Advanced'];

  for (final category in categoryOrder) {
    grouped[category] = [];
  }

  for (final course in courses) {
    final category = course.level;
    if (grouped.containsKey(category)) {
      grouped[category]!.add(course);
    } else {
      grouped[category] = [course];
    }
  }

  grouped.removeWhere((key, value) => value.isEmpty);
  return grouped;
}

CourseEntity _createTestCourse({
  required String id,
  String title = 'Test Course',
  String language = 'English',
  String level = 'Beginner',
}) {
  return CourseEntity(
    id: id,
    title: title,
    language: language,
    level: level,
    tags: [],
    totalXp: 100,
    estimatedDuration: 60,
    totalLessons: 10,
    isPublished: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}
