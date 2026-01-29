// Firebase packages - temporarily disabled until Firebase is configured
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
// import 'package:firebase_core/firebase_core.dart';

/// Stub FirestoreService when Firebase is not configured
/// TODO: Enable Firebase imports when firebase_options.dart is generated
class FirestoreService {
  static FirestoreService? _instance;
  static const bool _initialized = false;
  
  FirestoreService._init() {
    print('⚠️ FirestoreService: Firebase not configured - using stub');
  }
  
  static FirestoreService get instance {
    _instance ??= FirestoreService._init();
    return _instance!;
  }
  
  static bool get isInitialized => _initialized;
  
  /// Check if Firebase/Firestore is available for use
  bool get isAvailable => false;

  // Get current user ID - returns null when Firebase not available
  String? get currentUserId => null;

  // Check connection - always false when Firebase not available
  Future<bool> checkConnection() async => false;

  // Stub methods that return null - these are only called when Firebase is available
  // but we need them to compile. At runtime, code should check isAvailable first.
  
  /// Get user document reference - returns null (stub)
  dynamic getUserDocument(String? userId) => null;
  
  /// Get user chat sessions collection - returns null (stub)
  dynamic getUserChatSessions(String? userId) => null;
  
  /// Get user enrollments collection - returns null (stub)
  dynamic getUserEnrollments(String? userId) => null;
  
  /// Get user achievements collection - returns null (stub)
  dynamic getUserAchievements(String? userId) => null;
  
  /// Get firestore instance - returns null (stub)
  dynamic get firestore => null;
  
  /// Get users collection - returns null (stub)
  dynamic get usersCollection => null;
  
  /// Get courses collection - returns null (stub)
  dynamic get coursesCollection => null;
  
  /// Get leaderboard collection - returns null (stub)
  dynamic get leaderboardCollection => null;
  
  /// Create batch - returns null (stub)
  dynamic batch() => null;
  
  /// Run transaction - returns null (stub)
  Future<T>? runTransaction<T>(
    dynamic transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
  }) => null;
  
  /// Enable persistence - no-op (stub)
  Future<void> enablePersistence() async {}
}
