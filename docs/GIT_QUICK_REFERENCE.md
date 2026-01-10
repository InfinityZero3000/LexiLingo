# 🚀 Git Quick Reference - LexiLingo Project

## 📋 Branch Naming Cheat Sheet

```bash
feature/LEXI-[number]-[description]    # New features
bugfix/LEXI-[number]-[description]     # Bug fixes on develop
hotfix/LEXI-[number]-[description]     # Critical fixes on production
release/v[version]                     # Release preparation
chore/[description]                    # Maintenance tasks
refactor/[description]                 # Code refactoring
docs/[description]                     # Documentation
test/[description]                     # Testing
```

## 🎯 Common Workflows

### Start New Feature
```bash
git checkout develop
git pull origin develop
git checkout -b feature/LEXI-123-your-feature
# ... work ...
git add .
git commit -m "feat(scope): your message"
git push -u origin feature/LEXI-123-your-feature
# Create PR on GitHub
```

### Fix Bug
```bash
git checkout develop
git pull origin develop
git checkout -b bugfix/LEXI-200-bug-name
# ... fix ...
git commit -m "fix(scope): your message"
git push -u origin bugfix/LEXI-200-bug-name
# Create PR
```

### Hotfix Production
```bash
git checkout main
git pull origin main
git checkout -b hotfix/LEXI-500-critical-fix
# ... fix ...
git commit -m "fix(critical): your message"
git push -u origin hotfix/LEXI-500-critical-fix
# Create PR to main, then also merge to develop
```

### Sync with Develop
```bash
# On your feature branch
git fetch origin
git merge origin/develop
# Resolve conflicts if any
git push origin your-branch-name
```

## 💬 Commit Message Types

```
feat:      New feature
fix:       Bug fix
docs:      Documentation
style:     Formatting
refactor:  Code restructuring
perf:      Performance improvement
test:      Testing
chore:     Maintenance
ci:        CI/CD changes
build:     Build system
revert:    Revert previous commit
```

## 📝 Commit Message Format

```bash
<type>(<scope>): <subject>

# Examples:
git commit -m "feat(vocabulary): add word search"
git commit -m "fix(auth): resolve login crash"
git commit -m "docs(readme): update setup guide"
git commit -m "refactor(core): apply clean architecture"
```

## ✅ PR Checklist

Before creating PR:
- [ ] Code follows project standards
- [ ] Self-review completed
- [ ] Tests added/updated
- [ ] All tests passing
- [ ] No console.log/debugPrint
- [ ] No commented code
- [ ] Documentation updated
- [ ] No merge conflicts

## 🔧 Useful Git Commands

```bash
# Status
git status -sb                         # Short status

# Branch
git branch -a                          # List all branches
git branch -d branch-name              # Delete local branch
git push origin --delete branch-name   # Delete remote branch

# Commit
git commit --amend                     # Amend last commit
git reset HEAD~1 --soft                # Undo last commit (keep changes)
git reset HEAD~1 --hard                # Undo last commit (discard changes)

# Sync
git fetch origin                       # Fetch updates
git pull origin develop                # Pull develop
git merge origin/develop               # Merge develop into current branch

# Stash
git stash                              # Stash changes
git stash pop                          # Apply stash
git stash list                         # List stashes

# Log
git log --oneline --graph              # Pretty log
git log -5                             # Last 5 commits
git show HEAD                          # Show last commit

# Cleanup
git remote prune origin                # Clean remote refs
git gc --aggressive                    # Garbage collection
```

## 🎨 Branch Protection Rules (GitHub Settings)

**For `main` branch:**
- Require pull request before merging
- Require approvals: 2
- Dismiss stale approvals
- Require status checks to pass
- Require conversation resolution
- No force pushes
- No deletions

**For `develop` branch:**
- Require pull request before merging
- Require approvals: 1
- Require status checks to pass
- No force pushes

## ⚡ Quick Tips

1. **Commit often:** Small commits are better than large ones
2. **Pull daily:** Sync with develop at least once per day
3. **Test before push:** Always run tests locally
4. **Clean branches:** Delete merged branches immediately
5. **Review first:** Always self-review before creating PR
6. **Clear messages:** Write descriptive commit messages
7. **No direct commits:** Never commit directly to main/develop
8. **Ask for help:** Don't hesitate to ask if stuck

## 🚨 Emergency Commands

```bash
# Undo last commit but keep changes
git reset --soft HEAD~1

# Discard all local changes
git reset --hard HEAD
git clean -fd

# Abort merge
git merge --abort

# Abort rebase
git rebase --abort

# Force sync with remote (CAREFUL!)
git fetch origin
git reset --hard origin/develop
```

## 📊 Project Structure

```
main (production)
  ↓
develop (development)
  ↓
feature/LEXI-xxx
bugfix/LEXI-xxx
```

## 🔗 Important Links

- **Jira Board:** [Project Tickets]
- **Documentation:** See GIT_WORKFLOW.md for detailed guide
- **Code Style:** See CONTRIBUTING.md
- **CI/CD:** GitHub Actions

---

**Remember:** When in doubt, ask the team! Better to ask than to break something.

**Last Updated:** January 10, 2026
