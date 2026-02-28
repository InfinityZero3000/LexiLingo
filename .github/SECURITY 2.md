# Security Policy

## Reporting Security Issues

**DO NOT** report security vulnerabilities through public GitHub issues.

Instead, please report them via email to: [your-security-email@example.com]

Include as much information as possible:
- Type of issue (credential leak, vulnerability, etc.)
- Affected files or components
- Steps to reproduce
- Potential impact

## Current Security Alerts

### ⚠️ Leaked Credentials Detected

GitHub Secret Scanning has detected exposed credentials in the repository history. These credentials have been:

1. **Revoked/Rotated** (action required by repository owner)
2. **Removed from current files** (completed)
3. **Added to .gitignore** (completed)

### Action Items for Repository Owner

1. **MongoDB Atlas Credentials**:
   - Go to [MongoDB Atlas](https://cloud.mongodb.com/)
   - Navigate to Database Access → Your User
   - Click "Edit" → "Edit Password"
   - Generate new secure password
   - Update local `.env` files with new credentials

2. **Google API Keys (Firebase)**:
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Navigate to APIs & Services → Credentials
   - Find the exposed API keys and click "Delete"
   - Create new API keys with proper restrictions:
     - Application restrictions: HTTP referrers (websites)
     - API restrictions: Limit to required APIs only
   - Download new `google-services.json` and `GoogleService-Info.plist`
   - Add to local project (never commit!)

3. **Git History Cleanup** (Optional but Recommended):
   ```bash
   # Use BFG Repo-Cleaner to remove secrets from git history
   # https://rtyley.github.io/bfg-repo-cleaner/
   
   # Or use git-filter-repo (recommended by GitHub)
   # https://github.com/newren/git-filter-repo
   ```

## Best Practices

### Never Commit:
- ❌ API keys
- ❌ Database passwords
- ❌ OAuth tokens
- ❌ Private keys
- ❌ Firebase config files
- ❌ `.env` files with real credentials

### Always Use:
- ✅ Environment variables (`.env.example` as template)
- ✅ GitHub Secrets for CI/CD
- ✅ Secret management services (AWS Secrets Manager, HashiCorp Vault)
- ✅ `.gitignore` for sensitive files
- ✅ Git hooks to prevent accidental commits

### Development Setup:
1. Copy `.env.example` to `.env`
2. Fill in your local credentials in `.env`
3. Never commit `.env` file
4. Use different credentials for dev/staging/production

### For Flutter/Firebase:
```dart
// firebase_options.dart should be generated locally
// Run: flutterfire configure
// Add to .gitignore: **/firebase_options.dart
```

## Security Checklist

- [ ] All exposed credentials have been rotated
- [ ] `.gitignore` updated to prevent future leaks
- [ ] GitHub Secret Scanning alerts reviewed and closed
- [ ] Team members notified about security best practices
- [ ] CI/CD updated to use GitHub Secrets
- [ ] Documentation updated with security guidelines

## Resources

- [GitHub Secret Scanning](https://docs.github.com/en/code-security/secret-scanning)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [12-Factor App Config](https://12factor.net/config)
