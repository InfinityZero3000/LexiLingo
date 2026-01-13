# 📱 LexiLingo - AI-Powered Language Learning App

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.24.0-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.8.1-0175C2?logo=dart)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey)

**Learn languages smarter with AI-powered tutoring and personalized vocabulary management**

[Features](#features) • [Architecture](#architecture) • [Getting Started](#getting-started) • [Contributing](#contributing)

</div>

---

## 📖 About

LexiLingo là ứng dụng học ngoại ngữ thông minh, kết hợp AI tutoring với quản lý từ vựng cá nhân hoá. Ứng dụng được xây dựng theo **Clean Architecture** chuẩn enterprise, đảm bảo code dễ maintain và scale.

## ✨ Features

### 🎓 Core Features
- **AI Chat Tutor**: Chat với AI để học và luyện tập ngôn ngữ
- **Vocabulary Library**: Quản lý từ vựng cá nhân với tính năng tìm kiếm
- **Learning Courses**: Các khóa học có cấu trúc với nhiều level
- **Word of the Day**: Học từ mới mỗi ngày
- **Progress Tracking**: Theo dõi tiến độ học tập

### 🔐 Authentication
- Google Sign-In integration
- Secure user authentication
- Profile management

### 📊 User Dashboard
- Learning statistics
- Course progress
- Achievement tracking

### 🔔 Notifications
- Daily word reminders
- Learning streak notifications
- Course updates

## 🏗️ Architecture

Project tuân thủ **Clean Architecture** principles:

```
lib/
├── core/                    # Shared core functionality
│   ├── di/                 # Dependency Injection (get_it)
│   ├── error/              # Error handling & exceptions
│   ├── usecase/            # Base use case pattern
│   ├── utils/              # Utilities & constants
│   ├── network/            # Network layer
│   ├── services/           # Shared services
│   └── theme/              # App theming
│
└── features/               # Feature modules
    ├── auth/              # Authentication
    ├── vocabulary/        # Vocabulary management
    ├── chat/              # AI Chat
    ├── course/            # Learning courses
    ├── profile/           # User profile
    ├── notifications/     # Notifications
    └── home/              # Dashboard
    
    Each feature has:
    ├── domain/            # Business logic
    │   ├── entities/      # Business objects
    │   ├── repositories/  # Repository interfaces
    │   └── usecases/      # Business use cases
    ├── data/              # Data layer
    │   ├── models/        # Data models
    │   ├── datasources/   # Data sources (local/remote)
    │   └── repositories/  # Repository implementations
    └── presentation/      # UI layer
        ├── pages/         # Screens
        ├── widgets/       # Reusable widgets
        └── providers/     # State management (Provider)
```

### 🔄 Data Flow

```
UI (Widgets) → Provider → Use Case → Repository → Data Source → API/DB
     ↑                                                              ↓
     └──────────────────── Entities/Models ←───────────────────────┘
```

### 🎯 Dependency Rule

- **Domain Layer**: Không phụ thuộc vào layer nào (pure business logic)
- **Data Layer**: Phụ thuộc vào Domain
- **Presentation Layer**: Phụ thuộc vào Domain
- Dependencies được inject thông qua **GetIt**

## 🚀 Getting Started

### Prerequisites

```bash
Flutter SDK: 3.24.0+
Dart SDK: 3.8.1+
iOS: 13.0+
Android: API 24+ (Android 7.0)
```

### Installation

1. **Clone repository**
```bash
git clone https://github.com/InfinityZero3000/LexiLingo.git
cd LexiLingo/lexilingo_app
```

2. **Install dependencies**
```bash
flutter pub get
```

3. **Configure environment** (if needed)
```bash
# Copy environment template
cp .env.example .env
# Add your API keys
```

4. **Run the app**
```bash
flutter run
```

### Build

```bash
# Build for iOS
flutter build ios --release

# Build for Android
flutter build apk --release
flutter build appbundle --release
```

## 📦 Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | SDK | Flutter framework |
| `provider` | ^6.1.5 | State management |
| `get_it` | ^8.0.3 | Dependency injection |
| `dartz` | ^0.10.1 | Functional programming |
| `sqflite` | ^2.4.2 | Local database |
| `google_sign_in` | ^7.2.0 | Google authentication |
| `google_generative_ai` | ^0.4.7 | AI integration |
| `google_fonts` | ^6.3.2 | Custom fonts |
| `http` | ^1.6.0 | HTTP client |

## 🧪 Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test
flutter test test/features/vocabulary/domain/usecases/get_words_usecase_test.dart
```

### Test Structure
```
test/
├── unit/              # Unit tests
├── widget/            # Widget tests
└── integration/       # Integration tests
```

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines:

- **[CONTRIBUTING.md](../CONTRIBUTING.md)** - Full contribution guide
- **[GIT_WORKFLOW.md](../GIT_WORKFLOW.md)** - Git workflow and branching strategy
- **[GIT_QUICK_REFERENCE.md](../GIT_QUICK_REFERENCE.md)** - Quick reference
- **[GIT_EXAMPLES.md](../GIT_EXAMPLES.md)** - Practical examples

### Quick Start for Contributors

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/LexiLingo.git

# Create feature branch
git checkout develop
git checkout -b feature/LEXI-XXX-your-feature

# Make changes and commit
git commit -m "feat(scope): description"

# Push and create PR
git push origin feature/LEXI-XXX-your-feature
```

## 📝 Documentation

- **[SRS.md](../SRS.md)** - Software Requirements Specification
- **Architecture Guide** - See this README
- **API Documentation** - Coming soon
- **User Guide** - Coming soon

## 🎨 Code Style

We follow [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines:

```dart
// Good
class VocabRepository {}
final userName = 'John';
const maxRetryCount = 3;

// Bad
class vocab_repository {}
final UserName = 'John';
```

Run formatter before commit:
```bash
dart format .
flutter analyze
```

## 🐛 Known Issues

- None currently

## 📈 Roadmap

- [ ] v1.0.0 - MVP Release
  - [x] Core features
  - [x] Authentication
  - [x] Clean Architecture implementation
  - [ ] Full test coverage
  - [ ] CI/CD pipeline

- [ ] v1.1.0 - Enhanced Features
  - [ ] Offline mode
  - [ ] Voice recognition
  - [ ] Advanced analytics

- [ ] v2.0.0 - AI Enhancements
  - [ ] Personalized learning paths
  - [ ] Speech evaluation
  - [ ] Multi-language support

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/InfinityZero3000/LexiLingo/issues)
- **Discussions**: [GitHub Discussions](https://github.com/InfinityZero3000/LexiLingo/discussions)
- **Email**: support@lexilingo.com

## 👥 Team

- **Developer**: Nguyen Huu Thang (@InfinityZero3000)
- **Contributors**: See [CONTRIBUTORS.md](../CONTRIBUTORS.md)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

## 🙏 Acknowledgments

- Flutter team for amazing framework
- Google AI for Gemini API
- Open source community

---

<div align="center">

**Made with ❤️ using Flutter**

⭐ Star us on GitHub — it helps!

[Report Bug](https://github.com/InfinityZero3000/LexiLingo/issues) • [Request Feature](https://github.com/InfinityZero3000/LexiLingo/issues)

</div>

