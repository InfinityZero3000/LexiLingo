import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// FirestoreService - Centralized Firestore access with error handling
/// Provides singleton access to Firestore collections and operations
class FirestoreService {
  static FirestoreService? _instance;
  static bool _initialized = false;
  
  late final FirebaseFirestore _firestore;
  
  FirestoreService._init() {
    try {
      _firestore = FirebaseFirestore.instance;
      _initialized = true;
      debugPrint('✅ FirestoreService: Initialized successfully');
    } catch (e) {
      debugPrint('❌ FirestoreService: Failed to initialize: $e');
      _initialized = false;
    }
  }
  
  static FirestoreService get instance {
    _instance ??= FirestoreService._init();
    return _instance!;
  }
  
  static bool get isInitialized => _initialized;
  
  /// Check if Firebase/Firestore is available for use
  bool get isAvailable => _initialized && Firebase.apps.isNotEmpty;

  // Get current user ID from Firebase Auth
  String? get currentUserId => firebase_auth.FirebaseAuth.instance.currentUser?.uid;

  // Check Firestore connection by attempting a simple read
  Future<bool> checkConnection() async {
    if (!isAvailable) return false;
    try {
      await _firestore.collection('_healthcheck').doc('ping').get();
      return true;
    } catch (e) {
      debugPrint('FirestoreService: Connection check failed: $e');
      return false;
    }
  }

  /// Get Firestore instance
  FirebaseFirestore get firestore => _firestore;

  // ========== Collection References ==========

  /// Users collection
  CollectionReference<Map<String, dynamic>> get usersCollection => 
      _firestore.collection('users');
  
  /// Courses collection
  CollectionReference<Map<String, dynamic>> get coursesCollection => 
      _firestore.collection('courses');
  
  /// Leaderboard collection
  CollectionReference<Map<String, dynamic>> get leaderboardCollection => 
      _firestore.collection('leaderboard');

  // ========== User Document & Subcollections ==========

  /// Get user document reference
  DocumentReference<Map<String, dynamic>>? getUserDocument(String? userId) {
    final uid = userId ?? currentUserId;
    if (uid == null) return null;
    return usersCollection.doc(uid);
  }
  
  /// Get user chat sessions subcollection
  CollectionReference<Map<String, dynamic>>? getUserChatSessions(String? userId) {
    final userDoc = getUserDocument(userId);
    if (userDoc == null) return null;
    return userDoc.collection('chatSessions');
  }
  
  /// Get user enrollments subcollection
  CollectionReference<Map<String, dynamic>>? getUserEnrollments(String? userId) {
    final userDoc = getUserDocument(userId);
    if (userDoc == null) return null;
    return userDoc.collection('enrollments');
  }
  
  /// Get user achievements subcollection
  CollectionReference<Map<String, dynamic>>? getUserAchievements(String? userId) {
    final userDoc = getUserDocument(userId);
    if (userDoc == null) return null;
    return userDoc.collection('achievements');
  }

  // ========== Batch & Transaction Operations ==========

  /// Create a new write batch
  WriteBatch batch() => _firestore.batch();
  
  /// Run a transaction
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _firestore.runTransaction(transactionHandler, timeout: timeout);
  }

  // ========== Persistence Settings ==========

  /// Enable offline persistence (call early in app startup)
  Future<void> enablePersistence() async {
    if (!isAvailable) return;
    try {
      _firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('FirestoreService: Offline persistence enabled');
    } catch (e) {
      debugPrint('FirestoreService: Could not enable persistence: $e');
    }
  }
}
