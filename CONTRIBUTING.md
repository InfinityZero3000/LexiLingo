# 🤝 Contributing to LexiLingo

Thank you for contributing to LexiLingo! This document provides guidelines for contributing to the project.

## 📚 Table of Contents
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Branching Strategy](#branching-strategy)
- [Coding Standards](#coding-standards)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Code Review](#code-review)

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.24.0 or higher
- Dart SDK 3.8.1 or higher
- Git
- IDE: VS Code or Android Studio (recommended)

### First Time Setup
```bash
# Clone the repository
git clone https://github.com/InfinityZero3000/LexiLingo.git
cd LexiLingo

# Install dependencies
cd flutter-app
flutter pub get

# Run the app
flutter run
```

## 💻 Development Setup

### Environment Configuration
1. Copy `.env.example` to `.env` (if exists)
2. Add your API keys and configurations
3. Never commit `.env` file

### IDE Setup

#### VS Code Extensions
- Dart
- Flutter
- GitLens
- Better Comments
- Error Lens

#### Android Studio Plugins
- Flutter
- Dart
- GitToolBox

## 🌳 Branching Strategy

We follow **Git Flow** branching model. See [GIT_WORKFLOW.md](./GIT_WORKFLOW.md) for detailed guidelines.

### Branch Types
```
main           → Production-ready code
develop        → Integration branch
feature/*      → New features
bugfix/*       → Bug fixes
hotfix/*       → Critical production fixes
release/*      → Release preparation
```

### Naming Convention
```bash
feature/LEXI-123-add-vocabulary-feature
bugfix/LEXI-200-fix-login-crash
hotfix/LEXI-500-critical-crash-fix
release/v1.0.0
```

## 📝 Coding Standards

### Architecture
We follow **Clean Architecture** principles:

```
lib/
├── core/              # Shared utilities
│   ├── di/           # Dependency Injection
│   ├── error/        # Error handling
│   ├── usecase/      # Base use case
│   ├── utils/        # Utilities
│   └── services/     # Shared services
└── features/         # Feature modules
    └── [feature]/
        ├── domain/       # Business logic
        │   ├── entities/
        │   ├── repositories/
        │   └── usecases/
        ├── data/         # Data layer
        │   ├── models/
        │   ├── datasources/
        │   └── repositories/
        └── presentation/ # UI layer
            ├── pages/
            ├── widgets/
            └── providers/
```

### Dart Style Guide

#### File Naming
```dart
// Good
user_repository.dart
vocab_word_model.dart
get_words_usecase.dart

// Bad
UserRepository.dart
vocabWordModel.dart
GetWords.dart
```

#### Class Naming
```dart
// Good - PascalCase
class VocabRepository {}
class UserEntity {}
class GetWordsUseCase {}

// Bad
class vocabRepository {}
class user_entity {}
```

#### Variable Naming
```dart
// Good - camelCase
final userName = 'John';
final isAuthenticated = true;
final wordCount = 10;

// Bad
final UserName = 'John';
final is_authenticated = true;
```

#### Constants
```dart
// Good - lowerCamelCase
const maxRetryCount = 3;
const apiTimeout = Duration(seconds: 30);

// For truly global constants, can use UPPER_SNAKE_CASE
const API_BASE_URL = 'https://api.example.com';
```

#### Private Members
```dart
class MyClass {
  // Private with underscore
  final String _privateField;
  int _privateCounter = 0;
  
  void _privateMethod() {}
}
```

### Code Organization

#### Import Order
```dart
// 1. Dart imports
import 'dart:async';
import 'dart:io';

// 2. Flutter imports
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 3. Third-party packages
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';

// 4. Local imports
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
```

#### File Structure
```dart
// Imports
import 'package:flutter/material.dart';

// Constants
const kMaxWords = 100;

// Main class
class VocabPage extends StatefulWidget {
  const VocabPage({super.key});
  
  @override
  State<VocabPage> createState() => _VocabPageState();
}

// Private class
class _VocabPageState extends State<VocabPage> {
  // State variables
  
  // Lifecycle methods
  @override
  void initState() {
    super.initState();
  }
  
  // Build method
  @override
  Widget build(BuildContext context) {
    return Container();
  }
  
  // Private methods
  void _handleAction() {}
}

// Helper classes (if needed)
class _HelperClass {}
```

### Best Practices

#### Use const constructors
```dart
// Good
const Text('Hello');
const SizedBox(height: 16);

// Bad
Text('Hello');
SizedBox(height: 16);
```

#### Null Safety
```dart
// Good
String? nullableString;
final nonNullString = nullableString ?? 'default';
final length = nullableString?.length ?? 0;

// Bad
String nullableString;  // Should be String?
final length = nullableString!.length;  // Avoid ! when possible
```

#### Async/Await
```dart
// Good
Future<List<Word>> getWords() async {
  try {
    final words = await repository.getWords();
    return words;
  } catch (e) {
    throw Exception('Failed to load words');
  }
}

// Bad
Future<List<Word>> getWords() {
  return repository.getWords().then((words) {
    return words;
  }).catchError((e) {
    throw Exception('Failed to load words');
  });
}
```

#### Error Handling
```dart
// Good
try {
  await performOperation();
} on NetworkException catch (e) {
  logger.error('Network error: $e');
  throw NetworkFailure(e.message);
} on CacheException catch (e) {
  logger.error('Cache error: $e');
  throw CacheFailure(e.message);
} catch (e) {
  logger.error('Unexpected error: $e');
  throw UnexpectedFailure(e.toString());
}

// Bad
try {
  await performOperation();
} catch (e) {
  print(e);  // Don't use print
}
```

#### Widget Composition
```dart
// Good - Extract widgets
class UserProfile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildContent(),
        _buildFooter(),
      ],
    );
  }
  
  Widget _buildHeader() => Container();
  Widget _buildContent() => Container();
  Widget _buildFooter() => Container();
}

// Bad - Nested widgets
class UserProfile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          child: Row(
            children: [
              Container(
                child: Column(
                  // Deep nesting...
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

## 💬 Commit Guidelines

Follow **Conventional Commits** specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code restructuring
- `perf`: Performance
- `test`: Testing
- `chore`: Maintenance
- `ci`: CI/CD
- `build`: Build system

### Examples
```bash
feat(vocabulary): add word search functionality
fix(auth): resolve login crash on iOS
docs(readme): update setup instructions
refactor(core): apply clean architecture
test(chat): add unit tests for message service
```

See [GIT_WORKFLOW.md](./GIT_WORKFLOW.md) for detailed commit guidelines.

## 🔄 Pull Request Process

### Before Creating PR
1. Self-review your code
2. Run all tests locally
3. Update documentation
4. Sync with latest develop
5. No merge conflicts
6. CI checks passing

### PR Size Guidelines
- **Small:** < 100 lines (Ideal)
- **Medium:** 100-400 lines (Good)
- **Large:** > 400 lines (Should be split)

### PR Template
We provide a PR template. Fill it completely:
- Description
- Type of change
- Testing performed
- Screenshots (if UI changes)
- Checklist

### Review Process
1. Create PR
2. Assign reviewers (at least 1)
3. Address review comments
4. Get approval
5. Merge (squash and merge recommended)
6. Delete branch

## 👀 Code Review

### As a Reviewer
- Review within 4 hours (first pass)
- Be constructive and respectful
- Explain why, not just what
- Use comment types:
  - MUST FIX
  - SHOULD FIX
  - 💡 SUGGESTION
  - ❓ QUESTION
  - 🎉 PRAISE

### As an Author
- Don't take feedback personally
- Respond to all comments
- Ask questions if unclear
- Thank reviewers

## 🧪 Testing

### Test Structure
```
test/
├── unit/
│   ├── core/
│   └── features/
├── widget/
│   └── features/
└── integration/
    └── flows/
```

### Writing Tests
```dart
// Good test
test('should return list of words when repository call is successful', () async {
  // Arrange
  when(mockRepository.getWords()).thenAnswer((_) async => tWordList);
  
  // Act
  final result = await useCase(NoParams());
  
  // Assert
  expect(result, equals(tWordList));
  verify(mockRepository.getWords());
  verifyNoMoreInteractions(mockRepository);
});
```

### Test Coverage
- Aim for > 80% coverage
- Focus on business logic (use cases, repositories)
- Test edge cases and error scenarios

## 📦 Dependencies

### Adding Dependencies
1. Check if really needed
2. Evaluate package quality:
   - Active maintenance
   - Good documentation
   - Community support
   - Pub score > 100
3. Add to `pubspec.yaml`
4. Document usage in PR

### Updating Dependencies
```bash
# Check outdated packages
flutter pub outdated

# Update all packages
flutter pub upgrade

# Update specific package
flutter pub upgrade package_name
```

## 🐛 Bug Reports

When reporting bugs:
1. Use GitHub Issues
2. Provide clear title
3. Describe steps to reproduce
4. Include expected vs actual behavior
5. Add screenshots/videos
6. Include device/OS information
7. Add relevant logs

## 💡 Feature Requests

When requesting features:
1. Use GitHub Issues
2. Describe the problem
3. Propose solution
4. Explain use cases
5. Consider alternatives

## 📞 Getting Help

- **Questions:** GitHub Discussions
- **Bugs:** GitHub Issues
- **Security:** Email to security@lexilingo.com
- **Chat:** Team Slack/Discord

## 📜 License

By contributing, you agree that your contributions will be licensed under the project's license.

## 🙏 Thank You

Thank you for contributing to LexiLingo! Your efforts help make this project better for everyone.

---

**For detailed branching strategy, see:** [GIT_WORKFLOW.md](./GIT_WORKFLOW.md)  
**For quick reference, see:** [GIT_QUICK_REFERENCE.md](./GIT_QUICK_REFERENCE.md)

**Last Updated:** January 10, 2026
