import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_paged_list.dart';

class CourseCategory {
  const CourseCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.icon,
    this.color,
    this.orderIndex = 0,
    this.isActive = true,
    this.courseCount = 0,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? icon;
  final String? color;
  final int orderIndex;
  final bool isActive;
  final int courseCount;

  factory CourseCategory.fromJson(Map<String, dynamic> j) => CourseCategory(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    slug: j['slug']?.toString() ?? '',
    description: j['description']?.toString(),
    icon: j['icon']?.toString(),
    color: j['color']?.toString(),
    orderIndex: (j['order_index'] as num?)?.toInt() ?? 0,
    isActive: j['is_active'] != false,
    courseCount: (j['course_count'] as num?)?.toInt() ?? 0,
  );
}

class CategoriesRepository {
  CategoriesRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  static const path = '/categories';

  /// The list route is not paged (it returns up to 100), so one request is the
  /// whole list.
  Future<PageResult<CourseCategory>> list() async {
    final body = await _api.getData(path, params: {'active_only': false});
    final page = adminPage(body, CourseCategory.fromJson);
    return PageResult(items: page.items, total: page.items.length);
  }

  Future<void> save({String? id, required Map<String, dynamic> data}) async {
    if (id == null) {
      await _api.post(path, data: data);
    } else {
      await _api.put('$path/$id', data: data);
    }
  }
}
