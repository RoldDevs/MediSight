// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
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
        return windows;
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
    apiKey: 'AIzaSyDmuJf-OjS2JKQUNKeQ96SsfuvuGpF75hE',
    appId: '1:538955764944:web:2a8c02bcb0cc8c9debfad5',
    messagingSenderId: '538955764944',
    projectId: 'medisight-5a189',
    authDomain: 'medisight-5a189.firebaseapp.com',
    storageBucket: 'medisight-5a189.firebasestorage.app',
    measurementId: 'G-R9YVCERN5X',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAn1WwFetdiYN7PudOP7HHd7yOb2ICm4Sc',
    appId: '1:538955764944:android:4e3182495abdaaeeebfad5',
    messagingSenderId: '538955764944',
    projectId: 'medisight-5a189',
    storageBucket: 'medisight-5a189.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDJ-IPSECKdbvTw3J8Zwk2t-PSRnqTJmt8',
    appId: '1:538955764944:ios:b8771410c8bcba84ebfad5',
    messagingSenderId: '538955764944',
    projectId: 'medisight-5a189',
    storageBucket: 'medisight-5a189.firebasestorage.app',
    iosBundleId: 'app.medisight.medisight',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDJ-IPSECKdbvTw3J8Zwk2t-PSRnqTJmt8',
    appId: '1:538955764944:ios:b8771410c8bcba84ebfad5',
    messagingSenderId: '538955764944',
    projectId: 'medisight-5a189',
    storageBucket: 'medisight-5a189.firebasestorage.app',
    iosBundleId: 'app.medisight.medisight',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDmuJf-OjS2JKQUNKeQ96SsfuvuGpF75hE',
    appId: '1:538955764944:web:4a69b81739223b89ebfad5',
    messagingSenderId: '538955764944',
    projectId: 'medisight-5a189',
    authDomain: 'medisight-5a189.firebaseapp.com',
    storageBucket: 'medisight-5a189.firebasestorage.app',
    measurementId: 'G-P5LSJL4PJT',
  );
}
