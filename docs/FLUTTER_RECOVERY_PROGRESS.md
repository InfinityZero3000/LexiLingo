# Flutter App - Tiến Trình Khôi Phục & Hoàn Thiện

**Ngày**: 27/01/2026  
**Trạng thái**: 🟡 Đang khắc phục lỗi compilation

---

## ✅ Đã Hoàn Thành

### 1. Tạo Missing Files (100%)
- ✅ `home_provider.dart` - Home screen state management  
- ✅ `vocab_repository_impl.dart` - Vocabulary repository implementation  
- ✅ Created missing directories

### 2. Fix Configuration & Dependencies (100%)
- ✅ Disabled `CourseImportService` (old schema không tương thích)
- ✅ Fixed `auth_header_provider.dart` nullable check
- ✅ Updated DI registrations (HomeProvider, AuthModule)
- ✅ Commented out old course seeding logic

### 3. Auth Module Fixes (100%)  
- ✅ Updated `AuthBackendDataSource` usage in DI
- ✅ Registered `TokenStorage` và `DeviceManager`  
- ✅ Fixed `UserEntity` constructor calls (added `username`, `createdAt`)
- ✅ Fixed 4 places in `auth_remote_data_source.dart`

### 4. Errors Reduced
- **Before**: 282 errors
- **After current fixes**: ~90-100 errors
- **Progress**: 65% reduction ✅

---

## 🔧 Còn Cần Khắc Phục

### 1. UseCase Return Types (CRITICAL - ~20 files)

**Vấn đề**: UseCases không implement đúng interface `UseCase<Type, Params>`  
**Yêu cầu**: Return `Future<Either<Failure, Type>>` thay vì `Future<Type>`

**Files cần fix**:

#### Auth Usecases (4 files)
```dart
// ❌ Sai
Future<UserEntity?> call(NoParams params) async {
  return await repository.getCurrentUser();
}

// ✅ Đúng  
@override
Future<Either<Failure, UserEntity?>> call(NoParams params) async {
  return await repository.getCurrentUser();
}
```

Files:
1. `lib/features/auth/domain/usecases/get_current_user_usecase.dart`
2. `lib/features/auth/domain/usecases/sign_in_with_email_password_usecase.dart`
3. `lib/features/auth/domain/usecases/sign_in_with_google_usecase.dart`
4. `lib/features/auth/domain/usecases/sign_out_usecase.dart`

#### Vocabulary Usecases (2 files)
5. `lib/features/vocabulary/domain/usecases/add_word_usecase.dart`
6. `lib/features/vocabulary/domain/usecases/get_words_usecase.dart`

#### Chat Usecases (2 files)
7. `lib/features/chat/domain/usecases/save_message_usecase.dart`
8. `lib/features/chat/domain/usecases/send_message_to_ai_usecase.dart`

### 2. Auth Repository Methods

**Vấn đề**: UseCases đang gọi methods không tồn tại

Files cần check:
- `lib/features/auth/domain/repositories/auth_repository.dart`
  - Missing: `signInWithEmailPassword()` ?
  - Missing: `signInWithGoogle()` ?
  - Missing: `signOut()` ?

**Solution**:  
Check AuthRepository interface và ensure các methods cần thiết tồn tại, hoặc update usecases để dùng đúng method names.

### 3. Vocabulary Repository Return Types

VocabRepository cần return `Future<Either<Failure, Type>>`:

```dart
abstract class VocabRepository {
  Future<Either<Failure, List<VocabWord>>> getWords();
  Future<Either<Failure, void>> addWord(VocabWord word);
}
```

### 4. Testing & Validation
- [ ] Flutter analyze 0 errors
- [ ] Flutter run (debug build)
- [ ] Test basic navigation
- [ ] Test authentication flow
- [ ] Test course listing

---

## 📋 Execution Plan (Next Steps)

### Phase 1: Fix Auth UseCases (30 min)
1. Update return types to `Either<Failure, Type>`
2. Wrap repository calls with try-catch + Either
3. Check AuthRepository interface methods

### Phase 2: Fix Vocabulary UseCases (15 min)
1. Update VocabRepository interface
2. Fix vocab_repository_impl.dart
3. Update usecases return types

### Phase 3: Fix Chat UseCases (15 min)
1. Review ChatRepository  
2. Fix usecase implementations

### Phase 4: Final Verification (30 min)
1. `flutter analyze` - 0 errors
2. `flutter pub get`
3. `flutter run` - test app startup
4. Fix any runtime errors

---

## 🎯 Estimated Time to Completion

| Task | Status | Time |
|------|--------|------|
| Create missing files | ✅ Done | - |
| Fix configuration | ✅ Done | - |
| Fix auth datasource | ✅ Done | - |
| **Fix auth usecases** | ⏸️ Next | 30 min |
| Fix vocab usecases | ⏸️ Pending | 15 min |
| Fix chat usecases | ⏸️ Pending | 15 min |
| Final testing | ⏸️ Pending | 30 min |
| **TOTAL** | | **~90 minutes** |

---

## 📊 Error Statistics

```
Initial:     282 errors
After fixes: ~100 errors  (65% reduction)
Target:        0 errors
Remaining:   ~100 errors
```

**Main Categories**:
- UseCase interface violations: ~20-30 errors
- Repository method issues: ~10 errors
- Misc compilation: ~60 errors

---

## 💡 Key Insights

### 1. Architecture Pattern
App đang dùng **Clean Architecture** với:
- **Domain**: Entities, Repositories (interfaces), UseCases
- **Data**: Models, Repositories (impl), DataSources
- **Presentation**: Providers (ChangeNotifier), Pages, Widgets

### 2. Error Handling  
Tất cả UseCases phải return `Either<Failure, SuccessType>`:
```dart
abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}
```

### 3. Dual Auth System
- **Firebase Auth**: Google Sign-In (auth_remote_data_source.dart)
- **Backend API**: Email/Password + User management (auth_backend_datasource.dart)

Current implementation ưu tiên **Backend API**.

### 4. Course Data Source
- **Old**: Local SQLite với `CourseImportService`  
- **New**: Backend REST API với `CourseBackendDataSource`

Đã disable old system.

---

## 🔗 Related Files

### Created/Modified:
1. `/flutter-app/lib/features/home/presentation/providers/home_provider.dart` - NEW ✅
2. `/flutter-app/lib/features/vocabulary/data/repositories/vocab_repository_impl.dart` - NEW ✅  
3. `/flutter-app/lib/core/network/auth_header_provider.dart` - FIXED ✅
4. `/flutter-app/lib/core/di/core_di.dart` - UPDATED ✅
5. `/flutter-app/lib/features/home/di/home_di.dart` - UPDATED ✅
6. `/flutter-app/lib/features/auth/di/auth_di.dart` - UPDATED ✅
7. `/flutter-app/lib/features/auth/data/datasources/auth_remote_data_source.dart` - FIXED ✅
8. `/flutter-app/lib/main.dart` - UPDATED ✅

### Disabled:
- `/flutter-app/lib/core/services/course_import_service.dart.bak` - Renamed to .bak

---

## 📝 Notes

- **Backend API**: Running on port 8002 (Phase 1-3 complete)
- **Flutter Version**: 3.24.0
- **Dart Version**: 3.8.1  
- **State Management**: Provider pattern
- **Network**: Dio with interceptors
- **Error Handling**: dartz (Either monad)

---

**Last Updated**: 27/01/2026 05:30  
**Next Action**: Fix auth usecases return types  
**Blocker**: None - can proceed
