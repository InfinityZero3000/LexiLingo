/// Course Local Datasource
/// Handles local caching for course-related data
/// 
/// Following agent-skills/language-learning-patterns:
/// - Improve UX with offline-first data when available
/// - Reduce API calls for rarely-changing data like categories

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/features/course/data/models/course_category_model.dart';

abstract class CourseLocalDataSource {
  /// Get cached categories
  Future<List<CourseCategoryModel>?> getCachedCategories();
  
  /// Cache categories
  Future<void> cacheCategories(List<CourseCategoryModel> categories);
  
  /// Check if cache is still valid
  Future<bool> isCategoryCacheValid();
  
  /// Clear category cache
  Future<void> clearCategoryCache();
}

class CourseLocalDataSourceImpl implements CourseLocalDataSource {
  final SharedPreferences sharedPreferences;
  
  // Cache keys
  static const String _categoriesKey = 'cached_categories';
  static const String _categoriesCacheTimeKey = 'categories_cache_time';
  
  // Cache duration: 1 hour (categories rarely change)
  static const Duration _cacheDuration = Duration(hours: 1);

  CourseLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<List<CourseCategoryModel>?> getCachedCategories() async {
    try {
      final jsonString = sharedPreferences.getString(_categoriesKey);
      if (jsonString == null) return null;
      
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList
          .map((json) => CourseCategoryModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error reading cached categories: $e');
      return null;
    }
  }

  @override
  Future<void> cacheCategories(List<CourseCategoryModel> categories) async {
    try {
      final jsonList = categories.map((c) => c.toJson()).toList();
      final jsonString = json.encode(jsonList);
      
      await sharedPreferences.setString(_categoriesKey, jsonString);
      await sharedPreferences.setInt(
        _categoriesCacheTimeKey, 
        DateTime.now().millisecondsSinceEpoch,
      );
      
      debugPrint('Cached ${categories.length} categories');
    } catch (e) {
      debugPrint('Error caching categories: $e');
    }
  }

  @override
  Future<bool> isCategoryCacheValid() async {
    try {
      final cacheTime = sharedPreferences.getInt(_categoriesCacheTimeKey);
      if (cacheTime == null) return false;
      
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cacheTime);
      final now = DateTime.now();
      
      return now.difference(cachedAt) < _cacheDuration;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> clearCategoryCache() async {
    await sharedPreferences.remove(_categoriesKey);
    await sharedPreferences.remove(_categoriesCacheTimeKey);
  }
}
