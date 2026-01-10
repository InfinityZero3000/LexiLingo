---
name: Pull Request
about: Template cho Pull Request
title: '[TYPE](SCOPE): Brief description'
labels: ''
assignees: ''
---

## 📋 Description
<!-- Describe what this PR does in a few sentences -->


## 🎯 Jira/Issue Ticket
<!-- Link to Jira ticket or GitHub Issue -->
Closes [LEXI-XXX](https://jira.company.com/browse/LEXI-XXX)

## 🔄 Type of Change
<!-- Mark the relevant option with an 'x' -->
- [ ] 🎨 New feature (non-breaking change which adds functionality)
- [ ] 🐛 Bug fix (non-breaking change which fixes an issue)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] 📝 Documentation update
- [ ] ♻️ Code refactoring (no functional changes)
- [ ] ⚡ Performance improvement
- [ ] 🧪 Test updates
- [ ] 🔧 Build/CI configuration changes

## 🎯 Scope
<!-- What area of the codebase does this affect? -->
- [ ] Auth
- [ ] Vocabulary
- [ ] Chat
- [ ] Course
- [ ] Profile
- [ ] Notifications
- [ ] Core/Infrastructure
- [ ] UI/UX
- [ ] Other: ___________

## ✅ Checklist
<!-- Mark completed items with an 'x' -->
### Code Quality
- [ ] Code follows the project's coding standards
- [ ] Self-review of code completed
- [ ] Comments added in hard-to-understand areas
- [ ] No commented-out code included
- [ ] No console.log / debugPrint statements (use proper logging)
- [ ] No hardcoded values (use constants)

### Clean Architecture
- [ ] Follows Clean Architecture principles
- [ ] Proper separation of concerns (Domain/Data/Presentation)
- [ ] Dependencies injected properly
- [ ] Repository pattern followed
- [ ] Use Cases implemented correctly

### Testing
- [ ] New unit tests added
- [ ] Existing tests updated (if needed)
- [ ] All unit tests passing locally
- [ ] Manual testing completed
- [ ] Edge cases covered

### Documentation
- [ ] README updated (if needed)
- [ ] API documentation updated (if applicable)
- [ ] Comments added for complex logic
- [ ] CHANGELOG updated

### Git
- [ ] Branch name follows convention (feature/LEXI-XXX-description)
- [ ] Commit messages follow Conventional Commits
- [ ] No merge conflicts
- [ ] Synced with latest develop branch

### CI/CD
- [ ] All CI checks passing
- [ ] No new warnings or errors
- [ ] Build successful on all platforms

## 📸 Screenshots / Recordings
<!-- If this PR includes UI changes, add before/after screenshots or recordings -->

### Before
<!-- Screenshot or description of current state -->

### After
<!-- Screenshot or description after changes -->

## 🧪 Testing Performed
<!-- Describe the testing you've done -->

### Platforms Tested
- [ ] iOS Simulator
- [ ] iOS Device (version: ___)
- [ ] Android Emulator
- [ ] Android Device (version: ___)
- [ ] Web
- [ ] Desktop (macOS/Windows/Linux)

### Test Cases
<!-- List the test cases you've verified -->
1. 
2. 
3. 

### Test Data
<!-- Describe test data used if applicable -->

## 🔗 Related PRs
<!-- Link any related pull requests -->
- #XXX
- #YYY

## 📝 Migration Guide
<!-- If this includes breaking changes, provide migration guide -->
<!-- N/A if not applicable -->

## 🎯 Performance Impact
<!-- Describe any performance implications -->
- [ ] No performance impact
- [ ] Performance improved
- [ ] Performance impact analyzed and acceptable
- [ ] Performance degradation (explain why acceptable)

## 🔒 Security Considerations
<!-- Any security implications? -->
- [ ] No security implications
- [ ] Security reviewed
- [ ] Security impact documented

## 📊 Metrics/Analytics
<!-- Any new metrics or analytics events? -->

## 🚀 Deployment Notes
<!-- Any special deployment considerations? -->
- [ ] No special deployment needed
- [ ] Requires database migration
- [ ] Requires environment variable updates
- [ ] Requires feature flag
- [ ] Other: ___________

## 📖 Additional Notes
<!-- Any additional information that reviewers should know -->

## 🙋 Questions for Reviewers
<!-- Any specific areas you want feedback on? -->

---

## 👀 Reviewer Guidelines

**Please check:**
- [ ] Code quality and readability
- [ ] Architecture adherence
- [ ] Test coverage
- [ ] Performance implications
- [ ] Security considerations
- [ ] Documentation completeness

**Review focus areas:**
- Look for potential bugs
- Verify error handling
- Check for memory leaks
- Validate UI/UX changes
- Ensure backward compatibility
