// ignore_for_file: avoid_print

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';

import 'login_screen.dart';
import 'home_screen.dart';
import 'db_helper.dart' as localdb;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  /* ---------- App-Check 0.4.0 syntax ---------- */
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
        webProvider: kIsWeb ? ReCaptchaV3Provider('RECAPTCHA_ID') : null,
      // providerIOS: AppleProvider.debug,      // uncomment for iOS
      // providerMacOS: AppleProvider.debug,    // uncomment for macOS
    );
  } catch (e) {
    print('AppCheck Error: $e');
  }

  /* ---------- Local user ---------- */
  localdb.User? savedUser;
  try {
    savedUser = await localdb.DatabaseHelper().getSingleUser();
  } catch (e) {
    print('Local DB Error: $e');
    savedUser = null;
  }

  /* ---------- Firebase user ---------- */
  final User? firebaseUser = FirebaseAuth.instance.currentUser;
  final bool hasValidSession = firebaseUser != null && savedUser != null;

  final initialUser = hasValidSession
      ? {'id': savedUser.id, 'username': savedUser.displayName}
      : null;

  if (initialUser == null && savedUser != null) {
    print('Firebase expired → Clearing local DB');
    await localdb.DatabaseHelper().clearTable();
  }

  runApp(MyApp(user: initialUser));
}

class MyApp extends StatelessWidget {
  final Map<String, String>? user;
  const MyApp({super.key, this.user});

  @override
  Widget build(BuildContext context) {
    final initialScreen =
    (user != null && user!.containsKey('username') && user!.containsKey('id'))
        ? HomeScreen(
      username: user!['username']!,
      userId: user!['id']!,
    )
        : const LoginScreen();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: initialScreen,
    );
  }
}