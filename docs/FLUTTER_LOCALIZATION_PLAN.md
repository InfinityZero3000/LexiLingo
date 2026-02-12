# Flutter Localization Implementation Plan

## 📋 Overview

Implement multi-language support for LexiLingo Flutter app using `easy_localization` package with Crowdin cloud sync for collaborative translations.

**Target Languages (Phase 1):**
- 🇻🇳 Vietnamese (vi) - Default
- 🇺🇸 English (en)
- 🇯🇵 Japanese (ja)
- 🇰🇷 Korean (ko)

**Architecture:**
```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│   Crowdin   │────▶│  GitHub CI   │────▶│  Flutter App    │
│  (Web UI)   │     │  Auto-sync   │     │  assets/i18n/   │
│  Translators│     │  JSON files  │     │  easy_localization
└─────────────┘     └──────────────┘     └─────────────────┘
```

---

## 🛠️ Phase 1: Setup easy_localization (Day 1-2)

### Step 1.1: Add Dependencies

**File:** `pubspec.yaml`
```yaml
dependencies:
  # ... existing dependencies
  easy_localization: ^3.0.7
  
  # Already have these:
  # flutter_localizations:
  #   sdk: flutter
  # intl: ^0.20.2
```

### Step 1.2: Create Translation Files

**Directory Structure:**
```
flutter-app/
└── assets/
    └── i18n/
        ├── vi.json          # Vietnamese (source)
        ├── en.json          # English
        ├── ja.json          # Japanese
        └── ko.json          # Korean
```

**File:** `assets/i18n/vi.json` (Source of truth)
```json
{
  "app": {
    "name": "LexiLingo",
    "tagline": "Học tiếng Anh thông minh"
  },
  "common": {
    "loading": "Đang tải...",
    "error": "Đã xảy ra lỗi",
    "retry": "Thử lại",
    "cancel": "Hủy",
    "save": "Lưu",
    "delete": "Xóa",
    "edit": "Sửa",
    "confirm": "Xác nhận",
    "back": "Quay lại",
    "next": "Tiếp theo",
    "skip": "Bỏ qua",
    "done": "Hoàn thành",
    "yes": "Có",
    "no": "Không"
  },
  "auth": {
    "login": "Đăng nhập",
    "logout": "Đăng xuất",
    "register": "Đăng ký",
    "email": "Email",
    "password": "Mật khẩu",
    "forgotPassword": "Quên mật khẩu?",
    "loginWithGoogle": "Đăng nhập với Google",
    "welcomeBack": "Chào mừng trở lại!",
    "createAccount": "Tạo tài khoản mới"
  },
  "home": {
    "greeting": "Xin chào, {name}!",
    "dailyGoal": "Mục tiêu hôm nay",
    "streak": "Chuỗi ngày: {count} ngày",
    "continueLesson": "Tiếp tục học",
    "startLesson": "Bắt đầu bài học"
  },
  "course": {
    "title": "Khóa học",
    "units": "Chương",
    "lessons": "Bài học",
    "progress": "Tiến độ: {percent}%",
    "completed": "Hoàn thành",
    "locked": "Đã khóa",
    "start": "Bắt đầu"
  },
  "lesson": {
    "vocabulary": "Từ vựng",
    "grammar": "Ngữ pháp",
    "listening": "Nghe",
    "speaking": "Nói",
    "writing": "Viết",
    "quiz": "Kiểm tra",
    "correct": "Chính xác!",
    "incorrect": "Chưa đúng",
    "tryAgain": "Thử lại",
    "hint": "Gợi ý",
    "skip": "Bỏ qua"
  },
  "flashcard": {
    "title": "Flashcard",
    "front": "Mặt trước",
    "back": "Mặt sau",
    "flip": "Lật thẻ",
    "know": "Đã biết",
    "dontKnow": "Chưa biết",
    "review": "Ôn tập",
    "cardsRemaining": "{count} thẻ còn lại"
  },
  "voice": {
    "speak": "Nói",
    "listen": "Nghe",
    "recording": "Đang ghi âm...",
    "processing": "Đang xử lý...",
    "tryAgain": "Nói lại",
    "goodJob": "Tốt lắm!",
    "pronunciation": "Phát âm"
  },
  "chat": {
    "title": "Trò chuyện AI",
    "placeholder": "Nhập tin nhắn...",
    "send": "Gửi",
    "thinking": "Đang suy nghĩ...",
    "newConversation": "Cuộc trò chuyện mới",
    "history": "Lịch sử"
  },
  "achievements": {
    "title": "Thành tựu",
    "unlocked": "Đã mở khóa!",
    "progress": "Tiến độ",
    "badges": "Huy hiệu",
    "newBadge": "Huy hiệu mới!"
  },
  "profile": {
    "title": "Hồ sơ",
    "settings": "Cài đặt",
    "statistics": "Thống kê",
    "level": "Cấp độ {level}",
    "xp": "{xp} XP",
    "wordsLearned": "{count} từ đã học",
    "lessonsCompleted": "{count} bài đã hoàn thành"
  },
  "settings": {
    "title": "Cài đặt",
    "language": "Ngôn ngữ",
    "notifications": "Thông báo",
    "sound": "Âm thanh",
    "darkMode": "Chế độ tối",
    "about": "Về ứng dụng",
    "privacy": "Quyền riêng tư",
    "terms": "Điều khoản",
    "version": "Phiên bản {version}"
  },
  "notifications": {
    "reminderTitle": "Đừng quên học hôm nay!",
    "reminderBody": "Duy trì chuỗi học {streak} ngày của bạn",
    "achievementTitle": "Thành tựu mới!",
    "levelUpTitle": "Lên cấp!"
  },
  "errors": {
    "networkError": "Lỗi kết nối mạng",
    "serverError": "Lỗi máy chủ",
    "unauthorized": "Phiên đăng nhập hết hạn",
    "notFound": "Không tìm thấy",
    "unknown": "Đã xảy ra lỗi không xác định"
  },
  "plural": {
    "days": {
      "one": "{} ngày",
      "other": "{} ngày"
    },
    "words": {
      "one": "{} từ",
      "other": "{} từ"
    },
    "lessons": {
      "one": "{} bài học",
      "other": "{} bài học"
    }
  }
}
```

**File:** `assets/i18n/en.json`
```json
{
  "app": {
    "name": "LexiLingo",
    "tagline": "Learn English Smartly"
  },
  "common": {
    "loading": "Loading...",
    "error": "An error occurred",
    "retry": "Retry",
    "cancel": "Cancel",
    "save": "Save",
    "delete": "Delete",
    "edit": "Edit",
    "confirm": "Confirm",
    "back": "Back",
    "next": "Next",
    "skip": "Skip",
    "done": "Done",
    "yes": "Yes",
    "no": "No"
  },
  "auth": {
    "login": "Login",
    "logout": "Logout",
    "register": "Register",
    "email": "Email",
    "password": "Password",
    "forgotPassword": "Forgot password?",
    "loginWithGoogle": "Sign in with Google",
    "welcomeBack": "Welcome back!",
    "createAccount": "Create new account"
  }
}
```
*(Các key còn lại tương tự)*

### Step 1.3: Register Assets

**File:** `pubspec.yaml`
```yaml
flutter:
  assets:
    - assets/logo/
    - assets/avatar/
    - assets/badges/
    - assets/i18n/          # ADD THIS
```

### Step 1.4: Initialize in main.dart

**File:** `lib/main.dart`
```dart
import 'package:easy_localization/easy_localization.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize easy_localization
  await EasyLocalization.ensureInitialized();
  
  // ... existing initialization code ...
  
  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('vi'),
        Locale('en'),
        Locale('ja'),
        Locale('ko'),
      ],
      path: 'assets/i18n',
      fallbackLocale: const Locale('vi'),
      startLocale: const Locale('vi'),
      child: const LexiLingoApp(),
    ),
  );
}
```

### Step 1.5: Update MaterialApp

**File:** `lib/main.dart` (trong LexiLingoApp widget)
```dart
class LexiLingoApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Localization
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      
      // ... existing config
    );
  }
}
```

---

## 🔧 Phase 2: Create Localization Utilities (Day 2-3)

### Step 2.1: Create Extension for Easy Usage

**File:** `lib/core/utils/localization_utils.dart`
```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Extension for easy string localization
extension StringLocalization on String {
  /// Translate string: 'common.loading'.tr()
  String get tr => this.tr();
  
  /// Translate with named arguments: 'home.greeting'.trParams({'name': 'An'})
  String trParams(Map<String, String> params) => this.tr(namedArgs: params);
  
  /// Plural translation: 'plural.days'.plural(5)
  String plural(int count) => this.plural(count);
}

/// Localization helper class
class L10n {
  /// Get current locale
  static Locale currentLocale(BuildContext context) => context.locale;
  
  /// Change locale
  static Future<void> setLocale(BuildContext context, Locale locale) async {
    await context.setLocale(locale);
  }
  
  /// Get locale display name
  static String getLocaleName(Locale locale) {
    switch (locale.languageCode) {
      case 'vi': return 'Tiếng Việt';
      case 'en': return 'English';
      case 'ja': return '日本語';
      case 'ko': return '한국어';
      default: return locale.languageCode;
    }
  }
  
  /// Get all supported locales
  static List<Locale> get supportedLocales => const [
    Locale('vi'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
  ];
}
```

### Step 2.2: Create Language Selector Widget

**File:** `lib/core/widgets/language_selector.dart`
```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../utils/localization_utils.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final currentLocale = context.locale;
    
    return PopupMenuButton<Locale>(
      initialValue: currentLocale,
      onSelected: (locale) => context.setLocale(locale),
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_getFlag(currentLocale)),
          const SizedBox(width: 4),
          Text(L10n.getLocaleName(currentLocale)),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
      itemBuilder: (context) => L10n.supportedLocales.map((locale) {
        return PopupMenuItem(
          value: locale,
          child: Row(
            children: [
              Text(_getFlag(locale)),
              const SizedBox(width: 8),
              Text(L10n.getLocaleName(locale)),
              if (locale == currentLocale)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, size: 18),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
  
  String _getFlag(Locale locale) {
    switch (locale.languageCode) {
      case 'vi': return '🇻🇳';
      case 'en': return '🇺🇸';
      case 'ja': return '🇯🇵';
      case 'ko': return '🇰🇷';
      default: return '🌐';
    }
  }
}
```

---

## ☁️ Phase 3: Crowdin Integration (Day 3-4)

### Step 3.1: Create Crowdin Project

1. Go to [crowdin.com](https://crowdin.com)
2. Sign up / Login
3. Create new project: **LexiLingo**
4. Source language: **Vietnamese**
5. Target languages: English, Japanese, Korean
6. Upload `vi.json` as source file

### Step 3.2: Setup GitHub Integration

**Crowdin → Integrations → GitHub:**
1. Connect GitHub account
2. Select repository: `InfinityZero3000/LexiLingo`
3. Branch: `feature` (or `main`)
4. Source files path: `/flutter-app/assets/i18n/vi.json`
5. Translation files path: `/flutter-app/assets/i18n/%two_letters_code%.json`
6. Enable auto-sync (push/pull)

### Step 3.3: Create crowdin.yml Config

**File:** `flutter-app/crowdin.yml`
```yaml
project_id_env: CROWDIN_PROJECT_ID
api_token_env: CROWDIN_PERSONAL_TOKEN
base_path: "."
base_url: "https://api.crowdin.com"

preserve_hierarchy: true

files:
  - source: /assets/i18n/vi.json
    translation: /assets/i18n/%two_letters_code%.json
    type: json
    
    # Exclude keys that should not be translated
    excluded_target_languages: []
    
    # Update options
    update_option: update_as_unapproved
```

### Step 3.4: Add GitHub Actions for Auto-Sync

**File:** `.github/workflows/crowdin-sync.yml`
```yaml
name: Crowdin Sync

on:
  push:
    branches: [main, feature]
    paths:
      - 'flutter-app/assets/i18n/vi.json'
  workflow_dispatch:

jobs:
  sync-crowdin:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Upload sources to Crowdin
        uses: crowdin/github-action@v1
        with:
          upload_sources: true
          upload_translations: false
          download_translations: false
          project_id: ${{ secrets.CROWDIN_PROJECT_ID }}
          token: ${{ secrets.CROWDIN_PERSONAL_TOKEN }}
          source: 'flutter-app/assets/i18n/vi.json'
          translation: 'flutter-app/assets/i18n/%two_letters_code%.json'
          
  download-translations:
    runs-on: ubuntu-latest
    # Run weekly or manually
    if: github.event_name == 'workflow_dispatch'
    steps:
      - uses: actions/checkout@v4
      
      - name: Download translations from Crowdin
        uses: crowdin/github-action@v1
        with:
          upload_sources: false
          upload_translations: false
          download_translations: true
          localization_branch_name: l10n_crowdin_translations
          create_pull_request: true
          pull_request_title: '[Crowdin] New translations'
          pull_request_body: 'New Crowdin translations by GitHub Action'
          project_id: ${{ secrets.CROWDIN_PROJECT_ID }}
          token: ${{ secrets.CROWDIN_PERSONAL_TOKEN }}
```

### Step 3.5: Add Secrets to GitHub

Go to **GitHub → Settings → Secrets → Actions:**
- `CROWDIN_PROJECT_ID`: Your Crowdin project ID
- `CROWDIN_PERSONAL_TOKEN`: Your Crowdin API token

---

## 📱 Phase 4: UI Integration (Day 4-5)

### Step 4.1: Update Settings Page

**File:** `lib/features/user/presentation/pages/settings_page.dart`
```dart
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/widgets/language_selector.dart';

class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.title'.tr()),
      ),
      body: ListView(
        children: [
          // Language Setting
          ListTile(
            leading: const Icon(Icons.language),
            title: Text('settings.language'.tr()),
            trailing: const LanguageSelector(),
          ),
          
          // ... other settings
        ],
      ),
    );
  }
}
```

### Step 4.2: Replace Hardcoded Strings

**Before:**
```dart
Text('Đang tải...')
```

**After:**
```dart
Text('common.loading'.tr())
```

**With Parameters:**
```dart
// 'home.greeting': 'Xin chào, {name}!'
Text('home.greeting'.tr(namedArgs: {'name': userName}))
```

**Plurals:**
```dart
// 'plural.days': {'one': '{} ngày', 'other': '{} ngày'}
Text('plural.days'.plural(streakDays))
```

---

## 🧪 Phase 5: Testing (Day 5-6)

### Step 5.1: Unit Tests

**File:** `test/localization_test.dart`
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart';

void main() {
  group('Localization Tests', () {
    test('Vietnamese translations load correctly', () {
      // Test loading vi.json
    });
    
    test('English translations load correctly', () {
      // Test loading en.json
    });
    
    test('Fallback to Vietnamese when key missing', () {
      // Test fallback behavior
    });
    
    test('Plural forms work correctly', () {
      // Test plural handling
    });
  });
}
```

### Step 5.2: Integration Tests

**File:** `integration_test/language_switch_test.dart`
```dart
void main() {
  testWidgets('User can switch language', (tester) async {
    // 1. Open Settings
    // 2. Tap Language selector
    // 3. Select English
    // 4. Verify UI updates to English
  });
}
```

---

## 📋 Checklist

### Phase 1: Setup
- [ ] Add `easy_localization` to pubspec.yaml
- [ ] Create `assets/i18n/` directory
- [ ] Create `vi.json` (source file)
- [ ] Create `en.json` (basic translation)
- [ ] Register assets in pubspec.yaml
- [ ] Initialize in main.dart
- [ ] Update MaterialApp

### Phase 2: Utilities
- [ ] Create `localization_utils.dart`
- [ ] Create `LanguageSelector` widget
- [ ] Test basic translation flow

### Phase 3: Crowdin
- [ ] Create Crowdin account
- [ ] Create LexiLingo project
- [ ] Upload vi.json as source
- [ ] Setup GitHub integration
- [ ] Create `crowdin.yml`
- [ ] Add GitHub Actions workflow
- [ ] Add secrets to GitHub

### Phase 4: UI Integration
- [ ] Add LanguageSelector to Settings
- [ ] Replace hardcoded strings in common widgets
- [ ] Replace strings in feature modules
- [ ] Test all screens

### Phase 5: Testing
- [ ] Write unit tests
- [ ] Write integration tests
- [ ] Manual QA for each language

---

## 📚 Resources

- [easy_localization docs](https://pub.dev/packages/easy_localization)
- [Crowdin Flutter Guide](https://support.crowdin.com/flutter/)
- [Crowdin GitHub Action](https://github.com/crowdin/github-action)
- [ICU Message Format](https://unicode-org.github.io/icu/userguide/format_parse/messages/)

---

## 🎯 Timeline Summary

| Phase | Task | Duration |
|-------|------|----------|
| 1 | Setup easy_localization | Day 1-2 |
| 2 | Create utilities & widgets | Day 2-3 |
| 3 | Crowdin integration | Day 3-4 |
| 4 | UI integration | Day 4-5 |
| 5 | Testing | Day 5-6 |

**Total: ~6 days**

---

**Created:** February 12, 2026
**Last Updated:** February 12, 2026
**Author:** LexiLingo Team
