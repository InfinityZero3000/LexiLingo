# 📚 Git Workflow - Hướng dẫn Branching Strategy chuẩn Doanh nghiệp

## 📖 Mục lục
- [1. Git Flow Strategy](#1-git-flow-strategy)
- [2. Branch Naming Convention](#2-branch-naming-convention)
- [3. Quy trình làm việc](#3-quy-trình-làm-việc)
- [4. Commit Message Convention](#4-commit-message-convention)
- [5. Pull Request Guidelines](#5-pull-request-guidelines)
- [6. Code Review Process](#6-code-review-process)
- [7. Best Practices](#7-best-practices)

---

## 1. Git Flow Strategy

### 🌳 Cấu trúc Branch

```
main (production)
│
├── develop (development)
│   │
│   ├── feature/LEXI-123-add-vocabulary-feature
│   ├── feature/LEXI-124-implement-ai-chat
│   ├── feature/LEXI-125-user-authentication
│   │
│   ├── bugfix/LEXI-200-fix-login-crash
│   ├── bugfix/LEXI-201-fix-vocabulary-sync
│   │
│   └── release/v1.0.0
│
└── hotfix/LEXI-500-critical-crash-fix
```

### 📌 Mô tả các Branch chính

| Branch | Mục đích | Merge từ | Merge vào | Protected |
|--------|----------|----------|-----------|-----------|
| `main` | Production code, luôn stable | `hotfix/*`, `release/*` | - | ✅ Yes |
| `develop` | Integration branch cho development | `feature/*`, `bugfix/*` | `release/*` | ✅ Yes |
| `feature/*` | Phát triển tính năng mới | `develop` | `develop` | ❌ No |
| `bugfix/*` | Sửa lỗi trên develop | `develop` | `develop` | ❌ No |
| `hotfix/*` | Sửa lỗi khẩn cấp trên production | `main` | `main`, `develop` | ❌ No |
| `release/*` | Chuẩn bị cho production release | `develop` | `main`, `develop` | ✅ Yes |

---

## 2. Branch Naming Convention

### ✅ Quy tắc đặt tên Branch

```bash
<type>/<ticket-id>-<short-description>
```

### 📝 Types (Loại branch)

| Type | Mô tả | Ví dụ |
|------|-------|-------|
| `feature/` | Tính năng mới | `feature/LEXI-123-add-vocabulary-feature` |
| `bugfix/` | Sửa lỗi trên develop | `bugfix/LEXI-200-fix-login-crash` |
| `hotfix/` | Sửa lỗi khẩn cấp production | `hotfix/LEXI-500-critical-crash-fix` |
| `release/` | Chuẩn bị release | `release/v1.0.0` hoặc `release/1.0.0-rc.1` |
| `chore/` | Tasks không liên quan code | `chore/LEXI-300-update-dependencies` |
| `refactor/` | Refactor code | `refactor/LEXI-400-clean-architecture` |
| `docs/` | Cập nhật documentation | `docs/update-readme` |
| `test/` | Thêm/sửa tests | `test/LEXI-600-add-unit-tests` |
| `ci/` | CI/CD changes | `ci/setup-github-actions` |

### 🎯 Ví dụ thực tế

```bash
# ✅ ĐÚNG
feature/LEXI-123-add-vocabulary-feature
bugfix/LEXI-200-fix-login-crash
hotfix/LEXI-500-critical-crash-fix
release/v1.0.0

# ❌ SAI
new-feature
fix-bug
my-branch
john-working-branch
```

---

## 3. Quy trình làm việc

### 🚀 A. Bắt đầu Feature mới

```bash
# 1. Cập nhật develop branch
git checkout develop
git pull origin develop

# 2. Tạo feature branch từ develop
git checkout -b feature/LEXI-123-add-vocabulary-feature

# 3. Làm việc và commit thường xuyên
git add .
git commit -m "feat(vocabulary): add vocabulary list page"

# 4. Push lên remote
git push -u origin feature/LEXI-123-add-vocabulary-feature

# 5. Tạo Pull Request trên GitHub/GitLab
# Từ: feature/LEXI-123-add-vocabulary-feature
# Vào: develop
```

### 🐛 B. Sửa Bug trên Development

```bash
# 1. Cập nhật develop
git checkout develop
git pull origin develop

# 2. Tạo bugfix branch
git checkout -b bugfix/LEXI-200-fix-login-crash

# 3. Fix bug và commit
git add .
git commit -m "fix(auth): resolve login crash on iOS"

# 4. Push và tạo PR
git push -u origin bugfix/LEXI-200-fix-login-crash
```

### 🔥 C. Hotfix khẩn cấp trên Production

```bash
# 1. Tạo hotfix từ main
git checkout main
git pull origin main
git checkout -b hotfix/LEXI-500-critical-crash-fix

# 2. Fix và test kỹ
git add .
git commit -m "fix(critical): resolve app crash on startup"

# 3. Push
git push -u origin hotfix/LEXI-500-critical-crash-fix

# 4. Tạo PR merge vào MAIN
# 5. Sau khi merge, cũng merge vào develop để đồng bộ
```

### 📦 D. Release Process

```bash
# 1. Tạo release branch từ develop
git checkout develop
git pull origin develop
git checkout -b release/v1.0.0

# 2. Bump version, update CHANGELOG
# Chỉ fix bug nhỏ, không thêm feature mới

# 3. Commit changes
git commit -am "chore(release): bump version to 1.0.0"

# 4. Push
git push -u origin release/v1.0.0

# 5. Tạo PR merge vào main
# 6. Sau khi merge vào main, tạo tag
git checkout main
git pull origin main
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# 7. Merge lại vào develop
git checkout develop
git merge release/v1.0.0
git push origin develop

# 8. Xóa release branch
git branch -d release/v1.0.0
git push origin --delete release/v1.0.0
```

### 🔄 E. Đồng bộ code khi làm việc lâu dài

```bash
# Trên feature branch của bạn, thường xuyên sync với develop
git checkout feature/LEXI-123-add-vocabulary-feature
git fetch origin
git merge origin/develop

# Hoặc dùng rebase (nếu team dùng rebase strategy)
git fetch origin
git rebase origin/develop

# Giải quyết conflicts nếu có
# Sau đó push (với rebase cần force push)
git push origin feature/LEXI-123-add-vocabulary-feature
# Hoặc với rebase:
git push --force-with-lease origin feature/LEXI-123-add-vocabulary-feature
```

---

## 4. Commit Message Convention

### 📐 Format chuẩn (Conventional Commits)

```
<type>(<scope>): <subject>

<body>

<footer>
```

### 🏷️ Types

| Type | Mô tả | Ví dụ |
|------|-------|-------|
| `feat` | Tính năng mới | `feat(vocabulary): add word list pagination` |
| `fix` | Sửa bug | `fix(auth): resolve token refresh issue` |
| `docs` | Cập nhật docs | `docs(readme): update installation guide` |
| `style` | Format code, không đổi logic | `style(chat): format chat message UI` |
| `refactor` | Refactor code | `refactor(core): apply clean architecture` |
| `perf` | Cải thiện performance | `perf(vocabulary): optimize database query` |
| `test` | Thêm/sửa tests | `test(auth): add unit tests for login` |
| `chore` | Maintenance tasks | `chore(deps): update dependencies` |
| `ci` | CI/CD changes | `ci(github): add automated testing` |
| `build` | Build system changes | `build(gradle): update build config` |
| `revert` | Revert commit trước | `revert: revert commit abc123` |

### ✅ Ví dụ Commit Messages tốt

```bash
# Short commit
git commit -m "feat(vocabulary): add word search functionality"

# Detailed commit với body
git commit -m "feat(vocabulary): add word search functionality

- Implement search bar component
- Add debounce for search input
- Integrate with vocabulary repository
- Add unit tests for search logic

Closes LEXI-123"

# Bug fix
git commit -m "fix(auth): resolve login crash on iOS

The app was crashing when user tried to login on iOS 17.
Root cause was null safety issue in AuthProvider.

Fixes LEXI-200"

# Breaking change
git commit -m "feat(api)!: change API response format

BREAKING CHANGE: API now returns data in different structure.
Update all API clients to handle new format."
```

### ❌ Ví dụ Commit Messages tồi

```bash
# Quá chung chung
git commit -m "fix bug"
git commit -m "update code"
git commit -m "changes"

# Không mô tả gì
git commit -m "wip"
git commit -m "test"
git commit -m "asdf"

# Quá dài trong subject
git commit -m "add new feature that allows users to search for vocabulary words in the database with filters"
```

---

## 5. Pull Request Guidelines

### 📝 Template PR tốt

```markdown
## 📋 Description
Brief description of what this PR does.

## 🎯 Jira Ticket
[LEXI-123](https://jira.company.com/browse/LEXI-123)

## 🔄 Type of Change
- [ ] 🎨 New feature
- [ ] 🐛 Bug fix
- [ ] 📝 Documentation update
- [ ] ♻️ Code refactoring
- [ ] ⚡ Performance improvement
- [ ] 🧪 Test updates

## ✅ Checklist
- [ ] Code follows the project's coding standards
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] Documentation updated
- [ ] No new warnings generated
- [ ] Unit tests added/updated
- [ ] All tests passing
- [ ] No merge conflicts

## 📸 Screenshots (if applicable)
Before | After
-------|-------
![before](url) | ![after](url)

## 🧪 Testing
- [ ] Tested on iOS
- [ ] Tested on Android
- [ ] Manual testing completed
- [ ] Automated tests passing

## 📱 Platforms Tested
- iOS: 17.0+
- Android: API 24+

## 🔗 Related PRs
- #123
- #124

## 📖 Additional Notes
Any additional information that reviewers should know.
```

### 🎯 Quy tắc PR

1. **Kích thước:** PR không quá 400 dòng code (nếu lớn hơn, chia nhỏ)
2. **Self-review:** Review code của bạn trước khi tạo PR
3. **Description:** Mô tả rõ ràng những gì đã làm
4. **Screenshots:** Thêm screenshots nếu có thay đổi UI
5. **Tests:** Đảm bảo tests đều pass
6. **No WIP:** Không tạo PR khi code chưa hoàn thành
7. **Draft PR:** Dùng Draft PR nếu muốn feedback sớm

---

## 6. Code Review Process

### 👀 Quy trình Review

```
Developer → Create PR → Request Review → Reviewer(s)
                              ↓
                         Review Code
                              ↓
            ┌─────────────────┴─────────────────┐
            ↓                                   ↓
     Request Changes                        Approve
            ↓                                   ↓
    Developer fixes                      Merge to target
            ↓                                branch
    Re-request Review                          ↓
            ↓                              Delete branch
    └───────┘
```

### ✅ Checklist cho Reviewer

**Code Quality:**
- [ ] Code dễ đọc và maintain
- [ ] Tuân thủ coding standards
- [ ] Không có code duplicate
- [ ] Error handling đầy đủ
- [ ] No magic numbers/strings

**Architecture:**
- [ ] Tuân thủ Clean Architecture
- [ ] Separation of concerns rõ ràng
- [ ] Dependencies inject đúng
- [ ] Repository pattern đúng

**Testing:**
- [ ] Unit tests đầy đủ
- [ ] Edge cases được cover
- [ ] Tests có ý nghĩa, không superficial

**Performance:**
- [ ] Không có memory leaks
- [ ] Database queries tối ưu
- [ ] Không block UI thread

**Security:**
- [ ] Không hardcode sensitive data
- [ ] Input validation đầy đủ
- [ ] Authentication/Authorization đúng

### 💬 Comment Types

```dart
// ❌ MUST FIX - Blocking issue
// Critical bug hoặc security issue phải fix

// ⚠️ SHOULD FIX - Important
// Issue quan trọng nên fix nhưng không block

// 💡 SUGGESTION - Optional
// Gợi ý cải thiện, không bắt buộc

// ❓ QUESTION
// Đặt câu hỏi để hiểu rõ hơn

// 🎉 PRAISE
// Khen ngợi code tốt (quan trọng cho team morale!)
```

### 🔄 Response Time

- **First review:** Trong vòng 4 giờ làm việc
- **Follow-up review:** Trong vòng 2 giờ làm việc
- **Urgent PR:** Review ngay lập tức

---

## 7. Best Practices

### ✅ DO's

1. **Commit thường xuyên:** Commit nhỏ, thường xuyên
2. **Pull thường xuyên:** Sync với develop mỗi ngày
3. **Test before push:** Chạy tests trước khi push
4. **Meaningful names:** Đặt tên branch/commit có ý nghĩa
5. **Clean history:** Squash commits trước khi merge (nếu team dùng)
6. **Delete old branches:** Xóa branch sau khi merge
7. **Protect branches:** Protect main và develop branches
8. **Code review:** Luôn có ít nhất 1 reviewer approve
9. **CI/CD:** Đảm bảo CI pass trước khi merge
10. **Documentation:** Cập nhật docs khi cần

### ❌ DON'Ts

1. **Không commit trực tiếp vào main/develop**
2. **Không force push lên shared branches**
3. **Không commit code commented-out** (xóa đi, git sẽ track)
4. **Không commit console.log/debugPrint** (dùng proper logging)
5. **Không commit sensitive data** (API keys, passwords)
6. **Không merge PR của chính mình** (trừ hotfix khẩn cấp)
7. **Không skip CI checks**
8. **Không để merge conflicts lâu**
9. **Không rebase shared branches** (trừ khi team agreement)
10. **Không tạo PR quá lớn** (>400 lines)

---

## 8. Ví dụ thực tế cho LexiLingo

### 🎯 Scenario 1: Thêm tính năng Chat AI

```bash
# 1. Tạo branch
git checkout develop
git pull origin develop
git checkout -b feature/LEXI-101-implement-ai-chat

# 2. Implement feature (nhiều commits)
git add lib/features/chat/
git commit -m "feat(chat): add chat UI components"

git add lib/features/chat/domain/
git commit -m "feat(chat): implement chat repository and use cases"

git add lib/features/chat/data/
git commit -m "feat(chat): integrate with Gemini AI API"

git add test/
git commit -m "test(chat): add unit tests for chat feature"

# 3. Sync với develop trước khi tạo PR
git fetch origin
git merge origin/develop
# Giải quyết conflicts nếu có

# 4. Push
git push -u origin feature/LEXI-101-implement-ai-chat

# 5. Tạo PR trên GitHub
# Title: feat(chat): Implement AI Chat Feature [LEXI-101]
# Description: Detailed description with screenshots

# 6. Sau khi được approve và merge
git checkout develop
git pull origin develop
git branch -d feature/LEXI-101-implement-ai-chat
```

### 🐛 Scenario 2: Fix bug khẩn cấp

```bash
# Bug critical trên production
git checkout main
git pull origin main
git checkout -b hotfix/LEXI-999-fix-app-crash

# Fix bug
git add .
git commit -m "fix(critical): resolve app crash on startup

App was crashing on iOS 17 due to null pointer in AuthProvider.
Added null check and proper error handling.

Fixes LEXI-999"

# Push và tạo PR vào main
git push -u origin hotfix/LEXI-999-fix-app-crash

# Sau khi merge vào main, merge vào develop
git checkout develop
git pull origin develop
git merge hotfix/LEXI-999-fix-app-crash
git push origin develop

# Clean up
git branch -d hotfix/LEXI-999-fix-app-crash
git push origin --delete hotfix/LEXI-999-fix-app-crash
```

---

## 9. Git Aliases hữu ích

Thêm vào `~/.gitconfig`:

```ini
[alias]
    # Status shortcuts
    st = status
    s = status -sb

    # Branch shortcuts
    co = checkout
    cob = checkout -b
    br = branch
    brd = branch -d

    # Commit shortcuts
    cm = commit -m
    cam = commit -am

    # Log shortcuts
    lg = log --oneline --graph --decorate
    last = log -1 HEAD

    # Sync shortcuts
    sync = !git fetch origin && git merge origin/develop
    update = !git pull origin develop

    # Cleanup
    cleanup = !git branch --merged | grep -v '*\\|main\\|develop' | xargs -n 1 git branch -d

    # Undo shortcuts
    undo = reset HEAD~1 --soft
    unstage = reset HEAD --
```

Sử dụng:
```bash
git st              # Instead of git status
git cob feature/LEXI-123  # Instead of git checkout -b
git cm "feat: add feature"  # Instead of git commit -m
git lg              # Beautiful log graph
git sync            # Sync with develop
git cleanup         # Delete merged branches
```

---

## 10. CI/CD Integration

### GitHub Actions Example

Tạo `.github/workflows/pr-check.yml`:

```yaml
name: PR Checks

on:
  pull_request:
    branches: [ develop, main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'

      - name: Install dependencies
        run: flutter pub get
        working-directory: ./lexilingo_app

      - name: Analyze code
        run: flutter analyze
        working-directory: ./lexilingo_app

      - name: Run tests
        run: flutter test
        working-directory: ./lexilingo_app

      - name: Check formatting
        run: dart format --set-exit-if-changed .
        working-directory: ./lexilingo_app
```

---

## 📚 Resources

- [Git Flow](https://nvie.com/posts/a-successful-git-branching-model/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [GitHub Flow](https://docs.github.com/en/get-started/quickstart/github-flow)
- [Semantic Versioning](https://semver.org/)

---

## 🎓 Training Checklist

- [ ] Đọc và hiểu Git Flow strategy
- [ ] Thực hành tạo branch theo naming convention
- [ ] Viết commit messages theo Conventional Commits
- [ ] Tạo PR với template đầy đủ
- [ ] Thực hiện code review cho đồng nghiệp
- [ ] Xử lý merge conflicts
- [ ] Hiểu và áp dụng git aliases
- [ ] Thiết lập CI/CD workflow

---

**Lưu ý:** Tài liệu này là guideline chung. Team có thể điều chỉnh cho phù hợp với quy trình riêng.

**Updated:** January 10, 2026
**Maintainer:** Development Team
