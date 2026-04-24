# 🎯 Git Workflow - Practical Examples

Đây là các ví dụ thực tế về cách sử dụng Git workflow trong dự án LexiLingo.

## 📚 Table of Contents
1. [Tạo Feature mới](#1-tạo-feature-mới)
2. [Sửa Bug](#2-sửa-bug)
3. [Hotfix Production](#3-hotfix-production)
4. [Release Process](#4-release-process)
5. [Refactoring Code](#5-refactoring-code)
6. [Xử lý Conflicts](#6-xử-lý-conflicts)

---

## 1. Tạo Feature mới

### Ví dụ: Thêm tính năng "Word of the Day"

```bash
# Bước 1: Cập nhật develop branch
git checkout develop
git pull origin develop

# Bước 2: Tạo feature branch
git checkout -b feature/LEXI-150-word-of-the-day

# Bước 3: Implement feature theo Clean Architecture

# 3a. Tạo Entity
# File: lib/features/vocabulary/domain/entities/daily_word.dart
git add lib/features/vocabulary/domain/entities/daily_word.dart
git commit -m "feat(vocabulary): add DailyWord entity"

# 3b. Tạo Repository interface
# File: lib/features/vocabulary/domain/repositories/daily_word_repository.dart
git add lib/features/vocabulary/domain/repositories/daily_word_repository.dart
git commit -m "feat(vocabulary): add DailyWordRepository interface"

# 3c. Tạo Use Cases
# Files: lib/features/vocabulary/domain/usecases/get_daily_word_usecase.dart
git add lib/features/vocabulary/domain/usecases/
git commit -m "feat(vocabulary): add GetDailyWord use case"

# 3d. Implement Data Layer
# Files: models, datasources, repository implementation
git add lib/features/vocabulary/data/models/daily_word_model.dart
git add lib/features/vocabulary/data/datasources/daily_word_data_source.dart
git add lib/features/vocabulary/data/repositories/daily_word_repository_impl.dart
git commit -m "feat(vocabulary): implement DailyWord data layer"

# 3e. Create UI
# Files: pages, widgets, provider
git add lib/features/vocabulary/presentation/pages/daily_word_page.dart
git add lib/features/vocabulary/presentation/widgets/daily_word_card.dart
git add lib/features/vocabulary/presentation/providers/daily_word_provider.dart
git commit -m "feat(vocabulary): add Word of the Day UI"

# 3f. Update DI
git add lib/core/di/injection_container.dart
git commit -m "feat(vocabulary): register DailyWord dependencies"

# 3g. Add tests
git add test/features/vocabulary/domain/usecases/get_daily_word_usecase_test.dart
git add test/features/vocabulary/data/repositories/daily_word_repository_impl_test.dart
git commit -m "test(vocabulary): add tests for Word of the Day"

# Bước 4: Sync với develop (nếu có updates)
git fetch origin
git merge origin/develop
# Giải quyết conflicts nếu có

# Bước 5: Push branch
git push -u origin feature/LEXI-150-word-of-the-day

# Bước 6: Tạo Pull Request trên GitHub
# Title: feat(vocabulary): Add Word of the Day feature [LEXI-150]
# Description:
"""
## Description
Adds "Word of the Day" feature that shows a new vocabulary word daily to help users learn.

## Changes
- Added DailyWord entity and repository
- Implemented GetDailyWord use case
- Created UI components for displaying daily word
- Added tests with 90% coverage

## Screenshots
[Add screenshots here]

## Testing
- ✅ Tested on iOS 17.0
- ✅ Tested on Android 14
- ✅ All tests passing
"""
```

---

## 2. Sửa Bug

### Ví dụ: Fix vocabulary list not updating after adding word

```bash
# Bước 1: Tạo bugfix branch từ develop
git checkout develop
git pull origin develop
git checkout -b bugfix/LEXI-201-vocab-list-not-updating

# Bước 2: Investigate và fix bug
# Debug và tìm ra là VocabProvider không notify listeners

# Bước 3: Fix code
# File: lib/features/vocabulary/presentation/providers/vocab_provider.dart
# Thêm notifyListeners() sau khi add word

git add lib/features/vocabulary/presentation/providers/vocab_provider.dart
git commit -m "fix(vocabulary): ensure list updates after adding word

The vocabulary list was not refreshing after adding a new word.
Added notifyListeners() call after successful word addition.

Fixes LEXI-201"

# Bước 4: Add test để prevent regression
git add test/features/vocabulary/presentation/providers/vocab_provider_test.dart
git commit -m "test(vocabulary): add test for list refresh after add"

# Bước 5: Push và tạo PR
git push -u origin bugfix/LEXI-201-vocab-list-not-updating

# PR Title: fix(vocabulary): Vocabulary list not updating after adding word [LEXI-201]
```

---

## 3. Hotfix Production

### Ví dụ: App crashes on startup for iOS 17.2

```bash
# ⚠️ CRITICAL BUG IN PRODUCTION!

# Bước 1: Tạo hotfix từ main
git checkout main
git pull origin main
git checkout -b hotfix/LEXI-500-ios-crash-on-startup

# Bước 2: Quick fix (đã test kỹ locally)
# File: lib/core/services/notification_service.dart
# Add null check

git add lib/core/services/notification_service.dart
git commit -m "fix(critical): resolve app crash on iOS 17.2 startup

App was crashing on iOS 17.2 due to null pointer exception
in NotificationService initialization.

Root cause: notification permissions API changed in iOS 17.2
Solution: Added null safety checks and proper error handling

Tested on:
- iOS 17.2 Simulator 
- iOS 17.2 Physical device 

Fixes LEXI-500"

# Bước 3: Push hotfix
git push -u origin hotfix/LEXI-500-ios-crash-on-startup

# Bước 4: Tạo PR merge VÀO MAIN (URGENT)
# Get 2 approvals quickly
# Merge immediately

# Bước 5: Tag version
git checkout main
git pull origin main
git tag -a v1.0.1 -m "Hotfix: iOS 17.2 crash fix"
git push origin v1.0.1

# Bước 6: Merge hotfix vào develop để đồng bộ
git checkout develop
git pull origin develop
git merge hotfix/LEXI-500-ios-crash-on-startup
git push origin develop

# Bước 7: Cleanup
git branch -d hotfix/LEXI-500-ios-crash-on-startup
git push origin --delete hotfix/LEXI-500-ios-crash-on-startup

# Bước 8: Deploy hotfix to production ASAP!
```

---

## 4. Release Process

### Ví dụ: Chuẩn bị release v1.1.0

```bash
# Bước 1: Tạo release branch từ develop
git checkout develop
git pull origin develop
git checkout -b release/v1.1.0

# Bước 2: Bump version
# File: lexilingo_app/pubspec.yaml
# version: 1.1.0+11

git add lexilingo_app/pubspec.yaml
git commit -m "chore(release): bump version to 1.1.0"

# Bước 3: Update CHANGELOG
# File: CHANGELOG.md
"""
## [1.1.0] - 2026-01-10

### Added
- Word of the Day feature
- Vocabulary search functionality
- AI chat improvements

### Fixed
- Vocabulary list not updating after add
- Login crash on iOS

### Changed
- Improved vocabulary UI
- Updated dependencies
"""

git add CHANGELOG.md
git commit -m "docs(changelog): update for v1.1.0"

# Bước 4: Fix any last-minute bugs on release branch
# (Chỉ bug fixes, KHÔNG thêm features mới)

# Bước 5: Push release branch
git push -u origin release/v1.1.0

# Bước 6: Tạo PR merge vào main
# Title: Release v1.1.0
# Get approvals and merge

# Bước 7: Tag release trên main
git checkout main
git pull origin main
git tag -a v1.1.0 -m "Release version 1.1.0

Features:
- Word of the Day
- Vocabulary search
- AI chat improvements

Bug fixes:
- iOS crash fixes
- List refresh issues"

git push origin v1.1.0

# Bước 8: Merge release vào develop
git checkout develop
git merge release/v1.1.0
git push origin develop

# Bước 9: Delete release branch
git branch -d release/v1.1.0
git push origin --delete release/v1.1.0

# Bước 10: Deploy to Production! 🚀
```

---

## 5. Refactoring Code

### Ví dụ: Refactor to Clean Architecture

```bash
# Đây là những gì chúng ta đã làm!

git checkout develop
git pull origin develop
git checkout -b refactor/LEXI-400-clean-architecture

# Commit từng layer riêng biệt
git add lib/features/*/data/models/
git commit -m "refactor(data): add models for all features"

git add lib/features/*/domain/usecases/
git commit -m "refactor(domain): add use cases for all features"

git add lib/core/di/injection_container.dart
git commit -m "refactor(core): setup dependency injection with get_it"

git add lib/features/*/presentation/providers/
git commit -m "refactor(presentation): update providers to use use cases"

git add lib/main.dart lexilingo_app/pubspec.yaml
git commit -m "refactor(app): integrate DI container in main"

git add test/
git commit -m "test: update tests for clean architecture"

git push -u origin refactor/LEXI-400-clean-architecture

# Create PR with detailed explanation
```

---

## 6. Xử lý Conflicts

### Ví dụ: Merge conflict khi sync với develop

```bash
# Bạn đang trên feature branch
git checkout feature/LEXI-150-word-of-the-day

# Fetch latest develop
git fetch origin

# Attempt merge
git merge origin/develop

# ⚠️ CONFLICT! Git shows:
"""
Auto-merging lib/core/di/injection_container.dart
CONFLICT (content): Merge conflict in lib/core/di/injection_container.dart
Automatic merge failed; fix conflicts and then commit the result.
"""

# Bước 1: Xem files có conflict
git status
# Shows:
# both modified:   lib/core/di/injection_container.dart

# Bước 2: Mở file và giải quyết conflict
# File sẽ có dạng:
"""
<<<<<<< HEAD
  // Your code
  sl.registerFactory(() => DailyWordProvider(...));
=======
  // Code from develop
  sl.registerFactory(() => ChatProvider(...));
>>>>>>> origin/develop
"""

# Bước 3: Giải quyết - giữ CẢ HAI
"""
  // Resolved: keep both
  sl.registerFactory(() => ChatProvider(...));
  sl.registerFactory(() => DailyWordProvider(...));
"""

# Bước 4: Mark as resolved
git add lib/core/di/injection_container.dart

# Bước 5: Complete merge
git commit -m "merge: resolve conflicts with develop"

# Bước 6: Verify everything works
flutter test
flutter run

# Bước 7: Push
git push origin feature/LEXI-150-word-of-the-day
```

---

## 7. Stashing Changes

### Ví dụ: Cần switch branch nhưng chưa muốn commit

```bash
# Đang code trên feature/LEXI-150
# Có changes nhưng chưa sẵn sàng commit
# Cần switch sang bugfix/LEXI-201 gấp

# Bước 1: Stash changes
git stash save "WIP: daily word UI"

# Bước 2: Switch branch
git checkout bugfix/LEXI-201-vocab-list-not-updating

# ... fix bug ...
git add .
git commit -m "fix(vocabulary): fix list refresh"
git push origin bugfix/LEXI-201-vocab-list-not-updating

# Bước 3: Back to feature branch
git checkout feature/LEXI-150-word-of-the-day

# Bước 4: Restore stashed changes
git stash pop

# Continue working...
```

---

## 8. Cherry-picking Commits

### Ví dụ: Cần một commit từ branch khác

```bash
# Có một bug fix trên feature branch
# Cần apply nó vào develop luôn

# Bước 1: Find commit hash
git checkout feature/LEXI-150-word-of-the-day
git log --oneline
# Shows: abc1234 fix(vocabulary): resolve memory leak

# Bước 2: Switch to target branch
git checkout develop
git pull origin develop

# Bước 3: Cherry-pick commit
git cherry-pick abc1234

# Bước 4: Push
git push origin develop
```

---

## 9. Revert Commit

### Ví dụ: Commit gây bug, cần revert

```bash
# Commit def5678 gây ra bug nghiêm trọng

# Option 1: Revert commit (tạo commit mới)
git revert def5678
git commit -m "revert: revert buggy commit def5678

This reverts commit def5678 which caused critical bug.
Will re-implement with proper fix."
git push origin develop

# Option 2: Reset (chỉ dùng trên local branch)
git reset --hard HEAD~1  # Undo last commit
git push --force-with-lease origin feature/branch-name
```

---

## 10. Interactive Rebase (Cleanup commits)

### Ví dụ: Có nhiều WIP commits, cần cleanup trước PR

```bash
# Feature branch có commits:
# abc1 - WIP: add entity
# abc2 - WIP: fix typo
# abc3 - WIP: add use case
# abc4 - feat: complete daily word feature

# Muốn squash tất cả thành 1 commit

# Bước 1: Interactive rebase
git rebase -i HEAD~4

# Editor mở ra:
"""
pick abc1 WIP: add entity
pick abc2 WIP: fix typo
pick abc3 WIP: add use case
pick abc4 feat: complete daily word feature
"""

# Bước 2: Change to:
"""
pick abc1 WIP: add entity
squash abc2 WIP: fix typo
squash abc3 WIP: add use case
squash abc4 feat: complete daily word feature
"""

# Bước 3: Save and close editor
# New editor opens for commit message

# Bước 4: Write clean commit message:
"""
feat(vocabulary): add Word of the Day feature

- Add DailyWord entity and repository
- Implement GetDailyWord use case
- Create UI components
- Add tests

Closes LEXI-150
"""

# Bước 5: Force push (branch chưa có PR)
git push --force-with-lease origin feature/LEXI-150-word-of-the-day
```

---

## 💡 Tips and Tricks

### Quick Aliases
```bash
# Add to ~/.gitconfig or ~/.zshrc
alias gs='git status -sb'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gp='git push'
alias gl='git pull'
alias gc='git commit -m'
alias gca='git commit --amend'
alias glog='git log --oneline --graph --all'
alias gsync='git fetch origin && git merge origin/develop'
```

### Useful Commands
```bash
# See changes before commit
git diff

# See staged changes
git diff --staged

# Undo unstaged changes
git restore file.dart

# Unstage file
git restore --staged file.dart

# Show commit details
git show abc1234

# Find commit with specific change
git log -S "search term" --source --all

# List branches by date
git branch --sort=-committerdate

# Delete all merged branches
git branch --merged | grep -v '*\|main\|develop' | xargs -n 1 git branch -d
```

---

## 🎓 Learning Path

1. ✅ Hiểu Git Flow basics
2. ✅ Practice branching strategy
3. ✅ Master commit conventions
4. ✅ Handle merge conflicts
5. ✅ Use rebase effectively
6. ✅ Cherry-pick commits
7. ✅ Interactive rebase for cleanup
8. ✅ Understand when to force push

---

**Remember:** Practice makes perfect! Càng code nhiều, càng quen với Git workflow.

**For more details, see:**
- [RPT-011_GIT_WORKFLOW.md](./RPT-011_GIT_WORKFLOW.md) - Full guidelines
- [RPT-012_GIT_QUICK_REFERENCE.md](./RPT-012_GIT_QUICK_REFERENCE.md) - Quick reference
- [CONTRIBUTING.md](../../CONTRIBUTING.md) - Contributing guidelines

**Last Updated:** January 10, 2026
