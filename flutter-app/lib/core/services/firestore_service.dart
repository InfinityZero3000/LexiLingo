import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

class FirestoreService {
  static final FirestoreService instance = FirestoreService._init();
  
  late FirebaseFirestore _firestore;
  
  FirestoreService._init() {
    _firestore = FirebaseFirestore.instance;
  }

  // Get Firestore instance
  FirebaseFirestore get firestore => _firestore;

  // Get current user ID from Firebase Auth
  String? get currentUserId => firebase_auth.FirebaseAuth.instance.currentUser?.uid;

  // Collections
  CollectionReference get usersCollection => _firestore.collection('users');
  CollectionReference get coursesCollection => _firestore.collection('courses');
  CollectionReference get leaderboardCollection => _firestore.collection('leaderboard');

  // User document reference
  DocumentReference? getUserDocument(String? userId) {
    if (userId == null) return null;
    return usersCollection.doc(userId);
  }

  // User subcollections
  CollectionReference? getUserEnrollments(String? userId) {
    final userDoc = getUserDocument(userId);
    if (userDoc == null) return null;
    return userDoc.collection('enrollments');
  }

  CollectionReference? getUserChatSessions(String? userId) {
    final userDoc = getUserDocument(userId);
    if (userDoc == null) return null;
    return userDoc.collection('chatSessions');
  }

  CollectionReference? getUserAchievements(String? userId) {
    final userDoc = getUserDocument(userId);
    if (userDoc == null) return null;
    return userDoc.collection('achievements');
  }

  // Batch operations
  WriteBatch batch() => _firestore.batch();

  // Transaction
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _firestore.runTransaction(transactionHandler, timeout: timeout);
  }

  // Check connection
  Future<bool> checkConnection() async {
    try {
      await _firestore.collection('_health_check').limit(1).get();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Enable offline persistence
  Future<void> enablePersistence() async {
    try {
      await _firestore.settings.persistenceEnabled;
    } catch (e) {
      // Already enabled or not supported on platform
    }
  }
}
