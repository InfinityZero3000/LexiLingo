# Firebase Security Rules Configuration

## Firestore Security Rules

Để cấu hình bảo mật cho Firestore, cần thêm rules vào Firebase Console.

### Truy cập Firebase Console
1. Mở [Firebase Console](https://console.firebase.google.com/)
2. Chọn project **LexiLingo**
3. Vào **Firestore Database** → **Rules**

### Rules Code

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function: Check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Helper function: Check if user owns the resource
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }
    
    // Users collection - Each user can only read/write their own data
    match /users/{userId} {
      allow read: if isOwner(userId);
      allow create: if isOwner(userId);
      allow update: if isOwner(userId);
      allow delete: if false; // Never allow deletion
      
      // User's settings (embedded in user document)
      // Covered by parent rules
      
      // User's enrollments subcollection
      match /enrollments/{enrollmentId} {
        allow read: if isOwner(userId);
        allow write: if isOwner(userId);
      }
      
      // User's daily goals subcollection
      match /dailyGoals/{goalId} {
        allow read: if isOwner(userId);
        allow write: if isOwner(userId);
      }
      
      // User's chat sessions subcollection
      match /chatSessions/{sessionId} {
        allow read: if isOwner(userId);
        allow create: if isOwner(userId);
        allow update: if isOwner(userId);
        allow delete: if isOwner(userId);
        
        // Messages in chat session
        match /messages/{messageId} {
          allow read: if isOwner(userId);
          allow create: if isOwner(userId);
          allow delete: if false; // Don't allow message deletion
        }
      }
      
      // User's achievements subcollection
      match /achievements/{achievementId} {
        allow read: if isOwner(userId);
        allow write: if false; // Only server can write achievements
      }
    }
    
    // Courses collection - Read-only for all authenticated users
    match /courses/{courseId} {
      allow read: if isAuthenticated();
      allow write: if false; // Only admins can modify courses (via Admin SDK)
    }
    
    // Leaderboard collection - Read-only for all authenticated users
    match /leaderboard/{entryId} {
      allow read: if isAuthenticated();
      allow write: if false; // Only server can update leaderboard
    }
  }
}
```

### Giải thích Rules

#### 1. Users Collection
- **Read/Write**: Chỉ user sở hữu mới được truy cập data của mình
- **Delete**: Không cho phép xóa user document (data retention)
- User ID phải khớp với Firebase Auth UID

#### 2. Subcollections
- **enrollments**: Lưu courses đã enroll, user tự quản lý
- **dailyGoals**: Daily goals và progress, user tự update
- **chatSessions**: Chat history với AI, user có full control
- **achievements**: Read-only, chỉ server được write (prevent cheating)

#### 3. Shared Collections
- **courses**: Read-only cho authenticated users, admin update via SDK
- **leaderboard**: Read-only, server-side updates only

### Triển khai Rules

#### Bước 1: Copy rules
Copy toàn bộ code JavaScript ở trên

#### Bước 2: Paste vào Firebase Console
1. Vào **Firestore Database** → **Rules**
2. Paste code vào editor
3. Click **Publish**

#### Bước 3: Test Rules
```javascript
// Test trong Firebase Console → Rules → Playground

// Test 1: User đọc data của chính mình ✅
Authenticated as: test-user-uid
Operation: get
Path: /users/test-user-uid
→ Should ALLOW

// Test 2: User đọc data của người khác ❌
Authenticated as: test-user-uid
Operation: get
Path: /users/another-user-uid
→ Should DENY

// Test 3: User tạo enrollment mới ✅
Authenticated as: test-user-uid
Operation: create
Path: /users/test-user-uid/enrollments/course-123
→ Should ALLOW

// Test 4: User xóa document ❌
Authenticated as: test-user-uid
Operation: delete
Path: /users/test-user-uid
→ Should DENY
```

## Firestore Indexes

### Indexes cần thiết cho queries

Vào **Firestore Database** → **Indexes** và tạo composite indexes sau:

#### Index 1: Chat Messages (ordered by timestamp)
```
Collection: users/{userId}/chatSessions/{sessionId}/messages
Fields:
  - timestamp (Ascending)
Query Scope: Collection
```

#### Index 2: Daily Goals (range queries)
```
Collection: users/{userId}/dailyGoals
Fields:
  - date (Ascending)
Query Scope: Collection
```

#### Index 3: Leaderboard (sort by XP)
```
Collection: leaderboard
Fields:
  - totalXP (Descending)
  - updatedAt (Descending)
Query Scope: Collection
```

### Auto-create Indexes

Firestore sẽ tự đề xuất create indexes khi app thực hiện queries phức tạp. Khi thấy error:
```
FAILED_PRECONDITION: The query requires an index.
```

Click vào link trong error message để tự động tạo index.

## Storage Rules (nếu dùng Firebase Storage cho avatars)

Vào **Storage** → **Rules**:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    
    // User avatars
    match /avatars/{userId}/{fileName} {
      // Allow users to upload their own avatar
      allow read: if request.auth != null;
      allow write: if request.auth != null 
                   && request.auth.uid == userId
                   && request.resource.size < 5 * 1024 * 1024 // Max 5MB
                   && request.resource.contentType.matches('image/.*');
    }
  }
}
```

## Monitoring và Bảo mật

### 1. Enable Firestore Analytics
- Vào **Firestore Database** → **Usage**
- Monitor read/write operations
- Set up billing alerts

### 2. App Check (Optional - Recommended)
Ngăn chặn abuse từ unauthorized apps:
```bash
# Enable App Check trong Firebase Console
# Add SHA-256 fingerprint cho Android
# Add Bundle ID cho iOS
```

### 3. Rate Limiting
Implement client-side rate limiting:
```dart
// Example: Limit chat messages to 10/minute
class RateLimiter {
  final Map<String, List<DateTime>> _requestTimes = {};
  
  bool canMakeRequest(String userId, {int maxRequests = 10, Duration window = const Duration(minutes: 1)}) {
    final now = DateTime.now();
    _requestTimes[userId] ??= [];
    
    // Remove old requests
    _requestTimes[userId]!.removeWhere((time) => now.difference(time) > window);
    
    if (_requestTimes[userId]!.length >= maxRequests) {
      return false;
    }
    
    _requestTimes[userId]!.add(now);
    return true;
  }
}
```

## Next Steps

1. Publish Firestore rules vào Firebase Console
2. Test rules với Firebase Rules Playground
3. Create composite indexes cho queries
4. ⏳ Monitor usage trong 1-2 tuần đầu
5. ⏳ Adjust rules nếu cần based on actual usage patterns

## Troubleshooting

### Issue: "Permission Denied"
- Check Firebase Auth: User đã login chưa?
- Check Rules: userId có khớp với auth.uid không?
- Check Firestore Console: Rules đã publish chưa?

### Issue: "Index Required"
- Click vào error link để auto-create index
- Hoặc manual create trong Console → Indexes

### Issue: "Quota Exceeded"
- Check billing trong Firebase Console
- Enable Blaze plan (pay-as-you-go)
- Set spending limits
