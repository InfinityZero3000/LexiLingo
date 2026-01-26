import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/user/domain/entities/daily_goal.dart';
import '../../features/user/data/models/daily_goal_model.dart';
import 'firestore_service.dart';

abstract class ProgressFirestoreDataSource {
  Future<void> syncDailyGoal(String userId, DailyGoal goal);
  Future<DailyGoal?> getDailyGoal(String userId, DateTime date);
}

class ProgressFirestoreDataSourceImpl implements ProgressFirestoreDataSource {
  final FirestoreService firestoreService;

  ProgressFirestoreDataSourceImpl({required this.firestoreService});

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<void> syncDailyGoal(String userId, DailyGoal goal) async {
    try {
      final dateStr = _formatDate(goal.date);
      await firestoreService.getUserDocument(userId)?.collection('dailyGoals').doc(dateStr).set({
        'date': dateStr,
        'targetXP': goal.targetXP,
        'earnedXP': goal.earnedXP,
        'lessonsCompleted': goal.lessonsCompleted,
        'wordsLearned': goal.wordsLearned,
        'minutesSpent': goal.minutesSpent,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to sync daily goal to Firestore: $e');
    }
  }

  @override
  Future<DailyGoal?> getDailyGoal(String userId, DateTime date) async {
    try {
      final dateStr = _formatDate(date);
      final doc = await firestoreService
          .getUserDocument(userId)
          ?.collection('dailyGoals')
          .doc(dateStr)
          .get();
      
      if (doc == null || !doc.exists) return null;
      
      final data = doc.data() as Map<String, dynamic>;
      return DailyGoalModel.fromJson({
        ...data,
        'id': 0,
        'userId': userId,
      });
    } catch (e) {
      throw Exception('Failed to get daily goal from Firestore: $e');
    }
  }
}
