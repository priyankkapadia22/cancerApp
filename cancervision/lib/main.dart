import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'db_helper.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  var savedUser = await DBHelper.getUser(); // ✅ Check SQLite for saved user
  var firebaseUser = FirebaseAuth.instance.currentUser; // ✅ Check Firebase Authentication
  // ✅ Only allow auto-login if Firebase user is also authenticated
  // 🚀 Disable Firebase App Check completely
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug, // Forces debug mode, skipping checks
    webProvider: ReCaptchaV3Provider(''), // Bypass App Check for web
  );

  runApp(MyApp(user: (firebaseUser != null && savedUser != null) ? savedUser : null));
}

class MyApp extends StatelessWidget {
  final Map<String, String>? user;

  MyApp({this.user});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: user != null
          ? HomeScreen(username: user!["username"]!, userId: user!["id"]!)
          : LoginScreen(),
    );
  }
}
