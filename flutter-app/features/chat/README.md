# 💬 Chat System - Quick Start

## 🎯 Đã Hoàn Thành

**100% Backend Logic**
- Clean Architecture
- AI Integration (Gemini + HuggingFace)
- SQLite Database
- State Management
- Error Handling

## 🚀 Cách SửỤng

### 1. Setup API Keys

**Tạo file `.env` hoặc hardcode tạm:**

```dart
// Trong: lib/core/di/injection_container.dart
// Dòng ~30, thay:
final geminiApiKey = sharedPreferences.getString('gemini_api_key') ?? '';

// Bằng:
final geminiApiKey = 'YOUR_GEMINI_API_KEY_HERE';
```

**Lấy API Key:**
- Gemini (Free): https://ai.google.dev/

### 2. Install & Run

```bash
flutter pub get
flutter run
```

### 3. Test Basic Flow

```dart
// 1. Provider đã setup, chỉ cần inject vào UI
final chatProvider = Provider.of<ChatProvider>(context);

// 2. Tạo session
await chatProvider.createNewSession('user_123');

// 3. Gửi message
await chatProvider.sendMessage('Hello!');

// 4. Xem messages
print(chatProvider.messages);
```

## 📁 Cấu Trúc Code

```
features/chat/
├── domain/         ← Business logic
├── data/          ← Database & AI
└── presentation/  ← UI & State
```

## 🧪 Test

```bash
# Run tests
flutter test

# Run specific test
flutter test test/features/chat/domain/entities/chat_entities_test.dart
```

**Result**: 6/6 tests passed

## Documentation

Implementation notes and test commands are maintained in this README and the repository test suite.

## 🎨 Next: Build UI

Provider đã sẵn sàng, chỉ cần tạo:
1. ChatScreen
2. MessageBubble widget
3. ChatInput widget

**ETA**: 2-4 hours

---

**Status**: Backend Ready | 🎨 UI Needed
**Built**: 2026-01-13
