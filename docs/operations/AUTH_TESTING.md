# Testing sign-in and account merging with fake accounts

The Firebase Auth emulator gives unlimited fake Google and Facebook accounts, so
the sign-in and merge flows can be exercised without real ones. Everything stays on
this machine. The backend refuses every Firebase token if the emulator is
configured with `APP_ENV=production`, and the app ignores the emulator in a
release build or for a host other than `localhost`/`127.0.0.1`.

## Start

```bash
# 1. Emulator (any empty folder)
echo '{"emulators":{"auth":{"port":9099},"ui":{"enabled":true,"port":4400}}}' > firebase.json
firebase emulators:start --only auth --project lexilingo-88492

# 2. Backend, against a local database
cd backend-service
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 FIREBASE_PROJECT_ID=lexilingo-88492 \
  uvicorn app.main:app --port 8000

# 3. App
cd flutter-app
flutter run -d chrome --dart-define=FIREBASE_AUTH_EMULATOR=127.0.0.1:9099
```

In the emulator popup choose **Add new account** and type any email. The emulator
UI (`http://127.0.0.1:4400/auth`) lists the users; **Clear all data** resets them.

**One difference from real Firebase, and it matters.** The emulator's popup marks
every email as verified, Facebook's included. Real Facebook emails are not, and
that is what raises the "account exists" conflict. Left alone, the emulator just
signs in and merges without asking. Before submitting a **Facebook** popup, paste
this into that popup's DevTools console:

```js
const make = window.createFakeClaims;
window.createFakeClaims = (info) => {
  const claims = JSON.parse(decodeURIComponent(make(info)));
  claims.email_verified = false;
  return encodeURIComponent(JSON.stringify(claims));
};
```

The two-step variant (Firebase returning no pending credential) cannot be produced
by the emulator; `facebook_account_linking_test.dart` covers it.

## Cases to walk

| Set up | Then | Expected |
|---|---|---|
| Sign in with Google as `a@test.com` | Sign out, sign in with Facebook as `a@test.com` | Asked to merge → confirm with Google → signed in (a second Facebook tap if Firebase gave no credential) |
| Register `b@test.com` with a password | Sign in with Facebook as `b@test.com` | Asked to merge → sign in with the password → "merged" notice; Facebook works next time |
| Facebook as `c@test.com` (new) | Sign out, sign in with Google as `c@test.com` | Signed in; using Facebook again asks to merge |
| Any popup | Close it | No error shown |
| `b@test.com` waiting to merge | Look at the login form | The email is filled in and a hint says what to do |
| Sign-up page opened from the login page | Sign in with Google or Facebook | The app opens; the sign-up page does not stay on top |
| `#/verify-email?token=broken` | Back to login, then sign in | The app opens |

With the emulator configured, the app sends Google's sign-in as a Firebase token:
the emulator's Google credential is not signed by Google and the backend would
reject it.

## With real accounts

Real Facebook sign-in is only needed to check the Meta app itself (Live mode,
redirect URI). One real account is enough: run the cases above in the emulator.
