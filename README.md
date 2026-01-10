# LexiLingo

> AI-Powered Language Learning Platform with Personalized Vocabulary Management

[![Flutter](https://img.shields.io/badge/Flutter-3.24.0-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.8.1-0175C2?style=for-the-badge&logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=for-the-badge)](CONTRIBUTING.md)

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20Web-lightgrey?style=flat-square)
![Build Status](https://img.shields.io/badge/build-passing-brightgreen?style=flat-square)
![Code Coverage](https://img.shields.io/badge/coverage-80%25-yellowgreen?style=flat-square)

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Development Workflow](#development-workflow)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

LexiLingo is a modern language learning application that combines artificial intelligence tutoring with personalized vocabulary management. Built with Flutter and following Clean Architecture principles, the app provides an intuitive and efficient learning experience across multiple platforms.

The application leverages Google's Gemini AI for intelligent conversation practice and implements a comprehensive vocabulary system that adapts to individual learning patterns.

### Design Philosophy

- **Clean Architecture**: Separation of concerns with clear dependency rules
- **SOLID Principles**: Maintainable and scalable codebase
- **Test-Driven Development**: High code coverage with unit and widget tests
- **Enterprise-Grade**: Production-ready code following industry best practices

---

## Key Features

### AI Chat Tutor
Engage in natural conversations with an AI tutor powered by Google Gemini. Practice language skills through contextual dialogue and receive instant feedback.

### Vocabulary Management
- Personal vocabulary library with search functionality
- Word of the Day feature
- Progress tracking and learning analytics
- Categorized word collections

### Structured Learning
- Multiple course levels (Beginner, Intermediate, Advanced)
- Progress tracking across courses
- Personalized learning paths
- Achievement system

### User Experience
- Google Sign-In authentication
- Cross-platform synchronization
- Offline mode support
- Push notifications for learning reminders
- Dark mode support

---

## Architecture

The application follows **Clean Architecture** with three distinct layers:

```
┌─────────────────────────────────────────────────────────┐
│                   Presentation Layer                    │
│              (UI, Widgets, State Management)            │
└────────────────────┬────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│                    Domain Layer                         │
│        (Entities, Use Cases, Repository Interfaces)     │
└────────────────────┬────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│                     Data Layer                          │
│    (Repository Implementations, Data Sources, Models)   │
└─────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

**Presentation Layer**
- UI components and screens
- State management (Provider)
- User interaction handling

**Domain Layer**
- Business logic and rules
- Entity definitions
- Use case implementations
- Repository contracts

**Data Layer**
- API integrations
- Local database operations
- Data transformation (Models)
- Repository implementations

### Dependency Injection

Dependencies are managed using **GetIt** service locator, providing:
- Loose coupling between layers
- Easy testing and mocking
- Centralized dependency management
- Lifecycle management

---

## Technology Stack

### Core Technologies

| Component | Technology | Version |
|-----------|-----------|---------|
| Framework | Flutter | 3.24.0 |
| Language | Dart | 3.8.1 |
| State Management | Provider | 6.1.5 |
| Dependency Injection | GetIt | 8.0.3 |
| Functional Programming | Dartz | 0.10.1 |

### Backend & Services

| Service | Technology | Purpose |
|---------|-----------|---------|
| AI Integration | Google Gemini API | Conversational AI |
| Authentication | Google Sign-In | User authentication |
| Local Database | SQLite | Offline data storage |
| Notifications | Flutter Local Notifications | Push notifications |

### Development Tools

- **Git Flow**: Branching strategy
- **Conventional Commits**: Commit message standard
- **GitHub Actions**: CI/CD pipeline
- **Flutter Analyze**: Static code analysis
- **Flutter Test**: Unit and widget testing

---

## Getting Started

### Prerequisites

```bash
Flutter SDK: 3.24.0 or higher
Dart SDK: 3.8.1 or higher
iOS: 13.0+
Android: API 24+ (Android 7.0)
```

### Installation

1. Clone the repository
```bash
git clone https://github.com/InfinityZero3000/LexiLingo.git
cd LexiLingo/lexilingo_app
```

2. Install dependencies
```bash
flutter pub get
```

3. Run the application
```bash
flutter run
```

### Configuration

Create a `.env` file for environment variables:
```env
GEMINI_API_KEY=your_api_key_here
```

### Build for Production

```bash
# iOS
flutter build ios --release

# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release
```

---

## Project Structure

```
lib/
├── core/                           # Core functionality
│   ├── di/                        # Dependency injection
│   ├── error/                     # Error handling
│   ├── usecase/                   # Base use case
│   ├── utils/                     # Utilities
│   ├── network/                   # Network layer
│   ├── services/                  # Shared services
│   └── theme/                     # App theming
│
└── features/                      # Feature modules
    ├── auth/                      # Authentication
    ├── vocabulary/                # Vocabulary management
    ├── chat/                      # AI Chat
    ├── course/                    # Learning courses
    ├── profile/                   # User profile
    ├── notifications/             # Notifications
    └── home/                      # Dashboard
    
    Each feature contains:
    ├── domain/                    # Business logic
    │   ├── entities/             # Business objects
    │   ├── repositories/         # Repository interfaces
    │   └── usecases/            # Use cases
    ├── data/                     # Data implementation
    │   ├── models/              # Data models
    │   ├── datasources/         # Data sources
    │   └── repositories/        # Repository implementations
    └── presentation/            # UI components
        ├── pages/              # Screens
        ├── widgets/            # Reusable widgets
        └── providers/          # State management
```

---

## Development Workflow

### Branch Strategy

We follow **Git Flow** branching model:

```
main            → Production releases
develop         → Development integration
feature/*       → New features
bugfix/*        → Bug fixes
hotfix/*        → Production hotfixes
release/*       → Release preparation
```

### Branch Naming Convention

```bash
feature/LEXI-123-add-vocabulary-search
bugfix/LEXI-456-fix-login-crash
hotfix/LEXI-789-critical-security-fix
release/v1.0.0
```

### Commit Message Format

Following Conventional Commits:

```bash
feat(vocabulary): add word search functionality
fix(auth): resolve token refresh issue
docs(readme): update installation guide
refactor(core): apply clean architecture
test(chat): add unit tests for message service
```

### Pull Request Process

1. Create feature branch from `develop`
2. Implement changes following coding standards
3. Write/update tests
4. Ensure all tests pass
5. Create Pull Request using template
6. Address review comments
7. Merge after approval

---

## Documentation

Comprehensive documentation is available:

| Document | Description | Link |
|----------|-------------|------|
| Quick Start | 5-minute setup guide | [QUICKSTART.md](QUICKSTART.md) |
| Technical Docs | Architecture & setup | [lexilingo_app/README.md](lexilingo_app/README.md) |
| Contributing | Coding standards & guidelines | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Git Workflow | Complete workflow guide | [GIT_WORKFLOW.md](GIT_WORKFLOW.md) |
| Git Reference | Command cheat sheet | [GIT_QUICK_REFERENCE.md](GIT_QUICK_REFERENCE.md) |
| Git Examples | Real-world scenarios | [GIT_EXAMPLES.md](GIT_EXAMPLES.md) |
| Requirements | Software specifications | [SRS.md](SRS.md) |

---

## Contributing

We welcome contributions from the community! Here's how to get started:

### For New Contributors

1. Read [QUICKSTART.md](QUICKSTART.md) for quick setup
2. Review [CONTRIBUTING.md](CONTRIBUTING.md) for coding standards
3. Check [GIT_WORKFLOW.md](GIT_WORKFLOW.md) for workflow guidelines
4. Look for issues labeled `good first issue`

### Contribution Guidelines

- Follow Clean Architecture principles
- Write tests for new features
- Update documentation as needed
- Use Conventional Commits format
- Ensure CI checks pass
- Request review from maintainers

### Code Quality Standards

```bash
# Run code analysis
flutter analyze

# Format code
dart format .

# Run tests
flutter test

# Check coverage
flutter test --coverage
```

---

## Testing

### Test Structure

```
test/
├── unit/              # Unit tests
├── widget/            # Widget tests
└── integration/       # Integration tests
```

### Running Tests

```bash
# All tests
flutter test

# Specific test file
flutter test test/features/vocabulary/domain/usecases/get_words_usecase_test.dart

# With coverage
flutter test --coverage
```

### Coverage Goals

- Overall: 80%+
- Use Cases: 90%+
- Repositories: 85%+
- UI: 70%+

---

## Roadmap

### Version 1.0.0 (Current)
- [x] Core vocabulary management
- [x] AI chat integration
- [x] User authentication
- [x] Clean Architecture implementation
- [ ] Full test coverage
- [ ] CI/CD pipeline

### Version 1.1.0
- [ ] Offline mode
- [ ] Voice recognition
- [ ] Advanced analytics
- [ ] Social features

### Version 2.0.0
- [ ] Personalized AI learning paths
- [ ] Speech evaluation
- [ ] Multi-language support
- [ ] Gamification features

---

## Support

### Getting Help

- **Issues**: [GitHub Issues](https://github.com/InfinityZero3000/LexiLingo/issues) for bugs and features
- **Discussions**: [GitHub Discussions](https://github.com/InfinityZero3000/LexiLingo/discussions) for questions
- **Documentation**: Check relevant docs in the table above

### Reporting Bugs

When reporting bugs, include:
- Device and OS version
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable
- Relevant logs

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Flutter team for the excellent framework
- Google AI for Gemini API
- Open source community for valuable packages
- Contributors who help improve this project

---

<div align="center">

**Built with Flutter**

[Report Bug](https://github.com/InfinityZero3000/LexiLingo/issues) • [Request Feature](https://github.com/InfinityZero3000/LexiLingo/issues) • [Documentation](lexilingo_app/README.md)

</div>
