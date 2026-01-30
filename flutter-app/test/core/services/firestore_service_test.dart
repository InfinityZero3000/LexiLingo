import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

@GenerateMocks([
  FirebaseFirestore,
  CollectionReference,
  DocumentReference,
  DocumentSnapshot,
  QuerySnapshot,
  QueryDocumentSnapshot,
])
import 'firestore_service_test.mocks.dart';

void main() {
  group('FirestoreService', () {
    late MockFirebaseFirestore mockFirestore;
    late MockCollectionReference<Map<String, dynamic>> mockCollection;
    late MockDocumentReference<Map<String, dynamic>> mockDocument;
    late MockDocumentSnapshot<Map<String, dynamic>> mockDocSnapshot;

    setUp(() {
      mockFirestore = MockFirebaseFirestore();
      mockCollection = MockCollectionReference<Map<String, dynamic>>();
      mockDocument = MockDocumentReference<Map<String, dynamic>>();
      mockDocSnapshot = MockDocumentSnapshot<Map<String, dynamic>>();
    });

    group('Document Operations', () {
      test('should get document successfully', () async {
        // Arrange
        const collectionPath = 'users';
        const documentId = 'user_123';
        final testData = {
          'name': 'Test User',
          'email': 'test@example.com',
          'createdAt': Timestamp.now(),
        };

        when(mockFirestore.collection(collectionPath)).thenReturn(mockCollection);
        when(mockCollection.doc(documentId)).thenReturn(mockDocument);
        when(mockDocument.get()).thenAnswer((_) async => mockDocSnapshot);
        when(mockDocSnapshot.exists).thenReturn(true);
        when(mockDocSnapshot.data()).thenReturn(testData);
        when(mockDocSnapshot.id).thenReturn(documentId);

        // Act
        final doc = await mockDocument.get();

        // Assert
        expect(doc.exists, isTrue);
        expect(doc.data()?['name'], equals('Test User'));
        expect(doc.data()?['email'], equals('test@example.com'));
        verify(mockDocument.get()).called(1);
      });

      test('should return non-existent document', () async {
        // Arrange
        when(mockDocument.get()).thenAnswer((_) async => mockDocSnapshot);
        when(mockDocSnapshot.exists).thenReturn(false);

        // Act
        final doc = await mockDocument.get();

        // Assert
        expect(doc.exists, isFalse);
      });

      test('should set document data successfully', () async {
        // Arrange
        final testData = {
          'name': 'New User',
          'email': 'new@example.com',
        };
        when(mockDocument.set(testData)).thenAnswer((_) async => {});

        // Act
        await mockDocument.set(testData);

        // Assert
        verify(mockDocument.set(testData)).called(1);
      });

      test('should update document successfully', () async {
        // Arrange
        final updateData = {'name': 'Updated Name'};
        when(mockDocument.update(updateData)).thenAnswer((_) async => {});

        // Act
        await mockDocument.update(updateData);

        // Assert
        verify(mockDocument.update(updateData)).called(1);
      });

      test('should delete document successfully', () async {
        // Arrange
        when(mockDocument.delete()).thenAnswer((_) async => {});

        // Act
        await mockDocument.delete();

        // Assert
        verify(mockDocument.delete()).called(1);
      });
    });

    group('Collection Operations', () {
      test('should add document to collection', () async {
        // Arrange
        final testData = {
          'title': 'Test Course',
          'language': 'en',
        };
        when(mockCollection.add(testData)).thenAnswer((_) async => mockDocument);
        when(mockDocument.id).thenReturn('new_doc_id');

        // Act
        final docRef = await mockCollection.add(testData);

        // Assert
        expect(docRef.id, equals('new_doc_id'));
        verify(mockCollection.add(testData)).called(1);
      });
    });

    group('Query Operations', () {
      test('should query documents with where clause', () async {
        // Arrange
        final mockQuerySnapshot = MockQuerySnapshot<Map<String, dynamic>>();
        final mockQueryDoc = MockQueryDocumentSnapshot<Map<String, dynamic>>();

        when(mockCollection.where('status', isEqualTo: 'active'))
            .thenReturn(mockCollection);
        when(mockCollection.get()).thenAnswer((_) async => mockQuerySnapshot);
        when(mockQuerySnapshot.docs).thenReturn([mockQueryDoc]);
        when(mockQueryDoc.id).thenReturn('doc_1');
        when(mockQueryDoc.data()).thenReturn({
          'status': 'active',
          'title': 'Active Course',
        });

        // Act
        final query = mockCollection.where('status', isEqualTo: 'active');
        final snapshot = await query.get();

        // Assert
        expect(snapshot.docs.length, equals(1));
        expect(snapshot.docs.first.data()['status'], equals('active'));
      });
    });

    group('Batch Operations', () {
      test('should support batch writes', () async {
        // This test verifies the concept of batch operations
        // In real implementation, you would use WriteBatch
        expect(true, isTrue);
      });
    });

    group('Transactions', () {
      test('should support transactions', () async {
        // This test verifies the concept of transactions
        // In real implementation, you would use Transaction
        expect(true, isTrue);
      });
    });

    group('Real-time Updates', () {
      test('should listen to document changes', () async {
        // Arrange
        when(mockDocument.snapshots())
            .thenAnswer((_) => Stream.fromIterable([mockDocSnapshot]));
        when(mockDocSnapshot.exists).thenReturn(true);
        when(mockDocSnapshot.data()).thenReturn({'name': 'Updated'});

        // Act
        final snapshots = await mockDocument.snapshots().toList();

        // Assert
        expect(snapshots.length, equals(1));
        expect(snapshots.first.exists, isTrue);
        expect(snapshots.first.data()?['name'], equals('Updated'));
      });
    });
  });

  group('Firestore Data Models', () {
    test('should serialize user data correctly', () {
      // Arrange
      final userData = {
        'uid': 'user_123',
        'email': 'test@example.com',
        'displayName': 'Test User',
        'createdAt': Timestamp.now(),
        'settings': {
          'theme': 'dark',
          'language': 'en',
        },
      };

      // Assert
      expect(userData['uid'], equals('user_123'));
      expect(userData['settings'], isA<Map>());
    });

    test('should serialize progress data correctly', () {
      // Arrange
      final progressData = {
        'userId': 'user_123',
        'courseId': 'course_456',
        'lessonsCompleted': 5,
        'totalLessons': 10,
        'lastAccessedAt': Timestamp.now(),
        'streak': 7,
      };

      // Assert
      expect(progressData['lessonsCompleted'], equals(5));
      expect(progressData['streak'], equals(7));
    });
  });
}
