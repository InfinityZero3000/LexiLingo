# 🔐 Firebase Setup Guide - LexiLingo

> **⚠️ SECURITY NOTICE**: Firebase credentials are now removed from git for security. Follow this guide to set up your local environment.

## 📋 Quick Setup

### 1. Copy Template Files

```bash
# Android
cp flutter-app/android/app/google-services.json.example \
   flutter-app/android/app/google-services.json

# iOS
cp flutter-app/ios/Runner/GoogleService-Info.plist.example \
   flutter-app/ios/Runner/GoogleService-Info.plist

# Flutter
cp flutter-app/lib/firebase_options.dart.example \
   flutter-app/lib/firebase_options.dart
```

### 2. Get Your Firebase Credentials

#### Method 1: Using FlutterFire CLI (Recommended)

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure Firebase
cd flutter-app
flutterfire configure
```

This will automatically:
- Create/update `google-services.json`
- Create/update `GoogleService-Info.plist`
- Create/update `firebase_options.dart`

#### Method 2: Manual Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: **lexilingo-88492**
3. Go to **Project Settings** > **General**

**For Android:**
- Scroll to "Your apps" section
- Click Android app
- Download `google-services.json`
- Place in: `flutter-app/android/app/`

**For iOS:**
- Click iOS app
- Download `GoogleService-Info.plist`
- Place in: `flutter-app/ios/Runner/`

**For Flutter:**
- Copy config values from each platform
- Update `flutter-app/lib/firebase_options.dart`

### 3. Configure Google Sign-In (Web)

1. Go to [Google Cloud Console](https://console.cloud.google.com/apis/credentials?project=lexilingo-88492)
2. Find OAuth 2.0 Client ID for Web
3. Add **Authorized JavaScript origins**:
   ```
   http://localhost:8080
   http://localhost:3000
   https://your-production-domain.com
   ```
4. Add **Authorized redirect URIs**:
   ```
   http://localhost:8080/__/auth/handler
   http://localhost:3000/__/auth/handler
   https://your-production-domain.com/__/auth/handler
   ```
5. Click **Save**

### 4. Test Your Setup

```bash
cd flutter-app
flutter clean
flutter pub get

# Test on web
./run_web.sh

# Test on mobile
flutter run
```

---

## 📂 File Structure

```
flutter-app/
├── android/app/
│   ├── google-services.json          # ❌ NOT in git (gitignored)
│   └── google-services.json.example  # ✅ Template in git
├── ios/Runner/
│   ├── GoogleService-Info.plist      # ❌ NOT in git (gitignored)
│   └── GoogleService-Info.plist.example  # ✅ Template in git
└── lib/
    ├── firebase_options.dart         # ❌ NOT in git (gitignored)
    └── firebase_options.dart.example # ✅ Template in git
```

---

## 🔑 Current Project Info

- **Project ID**: `lexilingo-88492`
- **Project Number**: `432329288238`
- **Storage Bucket**: `lexilingo-88492.firebasestorage.app`

---

## 🚨 Important Security Notes

1. **NEVER commit** real credentials to git
2. Template files (`.example`) are safe to commit
3. Real credential files are in `.gitignore`
4. Each developer needs their own local setup
5. Use environment variables for CI/CD

---

## 🆘 Troubleshooting

### "Firebase not configured" error
- Make sure you copied all 3 files
- Run `flutter clean && flutter pub get`
- Restart your IDE

### Google Sign-In not working
- Check OAuth Client ID in Google Cloud Console
- Verify authorized origins match your URL
- Clear browser cache and try again

### iOS build fails
- Open `ios/Runner.xcworkspace` in Xcode
- Verify `GoogleService-Info.plist` is in project
- Clean build folder (Cmd+Shift+K)

---

## 📞 Contact

Need access to the Firebase project? Contact project admin for invitation.

---

**Last Updated**: 2026-01-14
projectId: 'lexilingo-demo'  // WRONG!
authDomain: 'lexilingo-demo.firebaseapp.com'  // WRONG!
```

Đây là lý do **Google Sign-In bị CORS errors** và authentication không hoạt động!

## Giải pháp - Lấy Real Credentials

### Bước 1: Vào Firebase Console

1. Mở: https://console.firebase.google.com/
2. Chọn project: **lexilingo-88492**

### Bước 2: Lấy Web App Config

1. Click vào **⚙️ Settings** (góc trên bên trái)
2. Chọn **Project settings**
3. Scroll xuống **Your apps**
4. Tìm **Web app** (icon `</>`), nếu chưa có thì:
   - Click **Add app** > chọn **Web**
   - Đặt tên: `flutter-app (web)`
   - Click **Register app**
5. Bạn sẽ thấy **Firebase SDK snippet** với config object như:

```javascript
const firebaseConfig = {
  apiKey: "AIzaSy...",
  authDomain: "lexilingo-88492.firebaseapp.com",
  projectId: "lexilingo-88492",
  storageBucket: "lexilingo-88492.firebasestorage.app",
  messagingSenderId: "...",
  appId: "1:...:web:...",
  measurementId: "G-..."
};
```

### Bước 3: Lấy Web OAuth Client ID

1. Vẫn trong Firebase Console
2. Click **Authentication** (menu bên trái)
3. Tab **Sign-in method**
4. Enable **Google** provider nếu chưa enable
5. Click vào **Google** provider
6. Bạn sẽ thấy:
   - **Web SDK configuration**
   - **Web client ID**: `123456789012-abcdefghijk.apps.googleusercontent.com`
   - **Web client secret**: `GOCSPX-...`
7. **Copy Web client ID** này

### Bước 4: Update Code với Real Credentials

Gửi cho tôi:
1. Web app config từ Firebase Console (apiKey, authDomain, projectId, etc.)
2. Web OAuth Client ID từ Google Sign-In provider settings

Tôi sẽ update:
- `lib/firebase_options.dart` với real Firebase config
- `lib/features/auth/data/datasources/auth_remote_data_source.dart` với real OAuth Client ID
- `web/index.html` với real OAuth Client ID

## 🎯 Expected Values

Sau khi lấy đúng, bạn sẽ có:

```dart
// lib/firebase_options.dart
static const FirebaseOptions web = FirebaseOptions(
  apiKey: 'AIzaSy...',  // Real API key
  appId: '1:...:web:...',  // Real app ID
  messagingSenderId: '...',  // Real sender ID
  projectId: 'lexilingo-88492',  // Correct!
  authDomain: 'lexilingo-88492.firebaseapp.com',  // Correct!
  storageBucket: 'lexilingo-88492.firebasestorage.app',  // Correct!
  measurementId: 'G-...',
);
```

```dart
// auth_remote_data_source.dart
final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: ['email'],
  clientId: kIsWeb 
      ? 'YOUR_REAL_WEB_CLIENT_ID.apps.googleusercontent.com'  // From Firebase Auth > Google > Web client ID
      : null,
);
```

## Security Note

**KHÔNG commit real credentials vào Git nếu repo là public!**

Cách bảo mật:
1. Add `lib/firebase_options.dart` vào `.gitignore`
2. Tạo `lib/firebase_options.example.dart` với fake values để example
3. Hoặc dùng environment variables

## Quick Test

Sau khi update credentials, test:

```bash
cd flutter-app
flutter clean
flutter pub get
./run_web.sh
```

Mở http://localhost:8080, không còn CORS errors nữa! ✅
