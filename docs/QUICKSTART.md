# 🎯 QUICK START - LexiLingo Development

## ⚡ TL;DR - Bắt đầu ngay trong 5 phút

```bash
# 1. Clone & Setup
git clone https://github.com/InfinityZero3000/LexiLingo.git
cd LexiLingo/lexilingo_app
flutter pub get

# 2. Run app
flutter run

# 3. Tạo feature branch
git checkout develop
git pull origin develop
git checkout -b feature/LEXI-XXX-your-feature

# 4. Code & Commit
git add .
git commit -m "feat(scope): your changes"

# 5. Push & PR
git push -u origin feature/LEXI-XXX-your-feature
# Tạo PR trên GitHub
```

## 📚 Essential Reading (20 minutes)

1. **[README.md](./README.md)** (5 min) - Documentation index
2. **[lexilingo_app/README.md](./lexilingo_app/README.md)** (10 min) - Architecture
3. **[GIT_QUICK_REFERENCE.md](./GIT_QUICK_REFERENCE.md)** (5 min) - Git commands

## 🌳 Branch Naming

```bash
feature/LEXI-123-add-vocabulary    # ✅ Correct
bugfix/LEXI-200-fix-crash         # ✅ Correct
hotfix/LEXI-500-critical-fix      # ✅ Correct

new-feature                        # ❌ Wrong
fix-bug                           # ❌ Wrong
```

## 💬 Commit Messages

```bash
feat(vocabulary): add search feature         # ✅
fix(auth): resolve login crash             # ✅
docs(readme): update setup guide            # ✅

update code                                 # ❌
fix bug                                     # ❌
```

## 📝 Before Every PR

- [ ] Code follows standards
- [ ] Tests added/updated
- [ ] All tests passing
- [ ] No console.log
- [ ] No merge conflicts
- [ ] Synced with develop

## 🆘 Need Help?

- **Git commands**: [GIT_QUICK_REFERENCE.md](./GIT_QUICK_REFERENCE.md)
- **Examples**: [GIT_EXAMPLES.md](./GIT_EXAMPLES.md)
- **Full guide**: [GIT_WORKFLOW.md](./GIT_WORKFLOW.md)
- **Issues**: Create GitHub Issue

## 🚀 Daily Workflow

```bash
# Morning: Sync với develop
git checkout develop && git pull origin develop

# Start feature
git checkout -b feature/LEXI-XXX-name

# During development
git add .
git commit -m "type(scope): message"

# Before PR: Sync again
git fetch origin
git merge origin/develop

# Push
git push origin feature/LEXI-XXX-name
```

## 📱 Architecture

```
Domain (Business Logic)
   ↓
Data (Implementation)
   ↓
Presentation (UI)
```

All dependencies injected via GetIt.

---

**That's it! Happy coding! 🎉**

For details: [README.md](./README.md)
