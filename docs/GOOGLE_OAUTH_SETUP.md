# Hướng dẫn cấu hình Google OAuth cho LexiLingo

## 📋 Tổng quan

LexiLingo sử dụng Google OAuth để cho phép người dùng đăng nhập bằng tài khoản Google. Bạn cần tạo OAuth 2.0 Client IDs trên Google Cloud Console.

## 🔑 Thông tin cần thiết

- **Firebase Project ID**: `lexilingo-88492`
- **iOS Bundle ID**: `com.lexilingo.lexilingoApp`
- **Android Package Name**: `com.lexilingo.lexilingo_app` (nếu có)
- **Web Client ID**: Cần tạo từ Google Cloud Console

## 📝 Các bước cấu hình

### 1. Truy cập Google Cloud Console

1. Đi đến: https://console.cloud.google.com/
2. Chọn project: `lexilingo-88492` hoặc project Firebase của bạn
3. Vào **APIs & Services** → **Credentials**

### 2. Tạo OAuth 2.0 Client ID cho iOS

#### Bước 1: Nhấn "CREATE CREDENTIALS" → "OAuth client ID"

#### Bước 2: Chọn "iOS" làm Application type

#### Bước 3: Điền thông tin:
- **Name**: `iOS client 1` (hoặc tên bạn muốn)
- **Bundle ID**: `com.lexilingo.lexilingoApp`
- **App Store ID**: (để trống nếu chưa publish)
- **Team ID**: (lấy từ Apple Developer Account)

#### Bước 4: Nhấn "CREATE"

Bạn sẽ nhận được:
- **iOS Client ID**: `432329288238-xxxxx.apps.googleusercontent.com`

### 3. Tạo OAuth 2.0 Client ID cho Web (Backend)

#### Bước 1: Nhấn "CREATE CREDENTIALS" → "OAuth client ID"

#### Bước 2: Chọn "Web application"

#### Bước 3: Điền thông tin:
- **Name**: `Web client 1` (hoặc tên bạn muốn)
- **Authorized JavaScript origins**: 
  - `http://localhost:8080`
  - `http://localhost:3000`
- **Authorized redirect URIs**: (để trống cho backend verification)

#### Bước 4: Nhấn "CREATE"

Bạn sẽ nhận được:
- **Web Client ID**: `432329288238-xxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com`
- **Client Secret**: `GOCSPX-xxxxxxxxxxxxxxxxxxxxx`

### 4. Cấu hình Backend Service

Mở file `/backend-service/.env` và cập nhật:

```env
# Google OAuth (for Google Sign In)
# Sử dụng WEB Client ID ở đây
GOOGLE_CLIENT_ID=432329288238-xxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com
```

**Lưu ý quan trọng**: Backend cần **WEB Client ID**, không phải iOS Client ID!

### 5. Cấu hình Flutter App

Mở file `/flutter-app/lib/core/services/google_sign_in_service.dart` và cập nhật dòng 16:

```dart
serverClientId: '432329288238-xxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com',
```

**Sử dụng WEB Client ID**, không phải iOS Client ID!

### 6. Lấy Team ID từ Apple Developer (cho iOS)

1. Đăng nhập vào https://developer.apple.com/account
2. Vào **Membership**
3. Copy **Team ID** (10 ký tự)
4. Quay lại Google Cloud Console và điền vào form tạo iOS Client ID

## ✅ Kiểm tra cấu hình

### 1. Kiểm tra Backend

```bash
cd backend-service
source venv/bin/activate  # hoặc activate venv của bạn
python -c "from app.core.config import settings; print(f'Google Client ID: {settings.GOOGLE_CLIENT_ID}')"
```

### 2. Kiểm tra Flutter

```bash
cd flutter-app
grep -n "serverClientId" lib/core/services/google_sign_in_service.dart
```

### 3. Test đăng nhập Google

1. Khởi động backend: `bash scripts/start-backend.sh`
2. Khởi động Flutter web: `bash scripts/run-flutter-web.sh`
3. Truy cập `http://localhost:8080`
4. Nhấn nút "Sign in with Google"
5. Chọn tài khoản Google
6. Kiểm tra console log

## 🔧 Troubleshooting

### Lỗi "Invalid ID token"

**Nguyên nhân**: Backend không có GOOGLE_CLIENT_ID hoặc sai Client ID

**Giải pháp**:
- Kiểm tra file `.env` có GOOGLE_CLIENT_ID chưa
- Đảm bảo sử dụng **WEB Client ID**, không phải iOS Client ID
- Restart backend service sau khi thay đổi .env

### Lỗi "401 Unauthorized"

**Nguyên nhân**: Token Google không được verify đúng

**Giải pháp**:
- Kiểm tra `google-auth` đã được cài đặt: `pip list | grep google-auth`
- Kiểm tra backend logs để xem chi tiết lỗi

### Lỗi "Google Sign In cancelled"

**Nguyên nhân**: User hủy đăng nhập hoặc serverClientId sai

**Giải pháp**:
- Kiểm tra `serverClientId` trong `google_sign_in_service.dart`
- Đảm bảo đã điền đúng WEB Client ID
- Kiểm tra Google Cloud Console đã enable Google Sign-In API

### iOS không hiện màn hình chọn tài khoản

**Nguyên nhân**: iOS Client ID chưa được tạo hoặc Bundle ID không khớp

**Giải pháp**:
- Tạo iOS Client ID trên Google Cloud Console
- Đảm bảo Bundle ID là `com.lexilingo.lexilingoApp`
- Thêm URL Scheme vào Info.plist (xem phần dưới)

## 📱 Cấu hình thêm cho iOS

### Thêm URL Scheme vào Info.plist

Mở `/flutter-app/ios/Runner/Info.plist` và thêm:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <!-- Đảo ngược iOS Client ID của bạn -->
            <string>com.googleusercontent.apps.432329288238-xxxxx</string>
        </array>
    </dict>
</array>
```

**Lấy URL Scheme**: Lấy iOS Client ID và đảo ngược domain:
- iOS Client ID: `432329288238-xxxxx.apps.googleusercontent.com`
- URL Scheme: `com.googleusercontent.apps.432329288238-xxxxx`

## 🌐 Cấu hình cho Web

Không cần cấu hình thêm gì, Google Sign-In sẽ tự động hoạt động với Web Client ID.

## 📱 Cấu hình cho Android

### 1. Tạo OAuth Client ID cho Android

1. Vào Google Cloud Console → Credentials → Create OAuth Client ID
2. Chọn "Android"
3. Điền:
   - **Package name**: `com.lexilingo.lexilingo_app`
   - **SHA-1 certificate fingerprint**: Lấy từ keystore

### 2. Lấy SHA-1 fingerprint

```bash
cd flutter-app/android
./gradlew signingReport
# Hoặc từ debug keystore:
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

## 📚 Tài liệu tham khảo

- [Google Sign-In for Flutter](https://pub.dev/packages/google_sign_in)
- [Google OAuth 2.0 Setup](https://developers.google.com/identity/protocols/oauth2)
- [Firebase Auth with Google](https://firebase.google.com/docs/auth/web/google-signin)

## 🎯 Checklist cuối cùng

- [ ] Đã tạo iOS Client ID trên Google Cloud Console
- [ ] Đã tạo Web Client ID trên Google Cloud Console
- [ ] Đã cập nhật GOOGLE_CLIENT_ID trong `/backend-service/.env` (dùng WEB Client ID)
- [ ] Đã cập nhật serverClientId trong `/flutter-app/lib/core/services/google_sign_in_service.dart` (dùng WEB Client ID)
- [ ] Đã cài đặt `google-auth`: `pip install google-auth`
- [ ] Đã restart backend service
- [ ] Đã test đăng nhập Google trên web
- [ ] (Optional) Đã thêm URL Scheme vào Info.plist cho iOS
- [ ] (Optional) Đã tạo Android Client ID và thêm SHA-1

---

**Lưu ý**: Mỗi platform (iOS, Android, Web) cần có Client ID riêng, nhưng backend chỉ cần WEB Client ID để verify token.
