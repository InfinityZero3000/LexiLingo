// File: firebase_options.dart.example
// This is a template file. Copy to firebase_options.dart and replace with your Firebase config.
//
// To get your Firebase configuration:
// 1. Go to Firebase Console: https://console.firebase.google.com/
// 2. Select your project
// 3. Go to Project Settings > General
// 4. Scroll down to "Your apps" section
// 5. Click on the Flutter app
// 6. Copy the configuration values
//
// OR run: flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDxb89kPDmWalE3fx8Jlo45pNYMfpe-Q5I',
    appId: '1:432329288238:web:f34e2fdf685d5b8a718dbf',
    messagingSenderId: '432329288238',
    projectId: 'lexilingo-88492',
    authDomain: 'lexilingo-88492.firebaseapp.com',
    storageBucket: 'lexilingo-88492.firebasestorage.app',
    measurementId: 'G-M8B2FXYJ42',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA88sCxpBNL-__EPTzL5EfotfV7isaZZ_A',
    appId: '1:432329288238:android:27021651b0302784718dbf',
    messagingSenderId: '432329288238',
    projectId: 'lexilingo-88492',
    storageBucket: 'lexilingo-88492.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDnGOEn-S0gI75ZsznWAE8KZslFbXZVhx4',
    appId: '1:432329288238:ios:982737f02386c9ac718dbf',
    messagingSenderId: '432329288238',
    projectId: 'lexilingo-88492',
    storageBucket: 'lexilingo-88492.firebasestorage.app',
    iosBundleId: 'com.lexilingo.lexilingoApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDnGOEn-S0gI75ZsznWAE8KZslFbXZVhx4',
    appId: '1:432329288238:ios:982737f02386c9ac718dbf',
    messagingSenderId: '432329288238',
    projectId: 'lexilingo-88492',
    storageBucket: 'lexilingo-88492.firebasestorage.app',
    iosBundleId: 'com.lexilingo.lexilingoApp',
  );
}
