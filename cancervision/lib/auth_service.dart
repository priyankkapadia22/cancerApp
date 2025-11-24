// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// We import the local model with a prefix to avoid conflict with firebase_auth.User
import 'package:cancervision/db_helper.dart' as localdb;

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Utility to Save User Data to Local DB ---
  Future<void> _saveUserToLocalDb(User user) async {
    final localdb.User localUser = localdb.User(
      id: user.uid,
      email: user.email ?? "",
      displayName: user.displayName ?? user.email?.split('@').first ?? 'User',
      photoUrl: user.photoURL ?? "",
    );
    await localdb.DatabaseHelper().insertUser(localUser);
    print("✅ User data saved/updated in local database.");
  }
  // ---------------------------------------------

  // 🔹 SIGNUP with Email, Password, Username, and Phone Number
  Future<User?> signUpWithEmail(
      String email, String password, String username, String phone) async {
    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
              email: email, password: password);
      User? user = userCredential.user;

      if (user != null) {
        // 1. Save data to Firestore
        await _firestore.collection("users").doc(user.uid).set({
          "uid": user.uid,
          "email": email,
          "username": username,
          "phone": phone,
          "createdAt": FieldValue.serverTimestamp(),
        });
        print("✅ User registered successfully in Firebase");

        // 2. Save data to Local DB
        await _saveUserToLocalDb(user);
      }
      return user;
    } on FirebaseAuthException catch (e) {
      print("🔴 Signup Error: ${e.code} - ${e.message}");
      return null;
    } catch (e) {
      print("🔴 Signup Error: $e");
      return null;
    }
  }

  // 🔹 LOGIN with Email & Password
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      User? user = userCredential.user;

      if (user != null) {
        print("✅ User signed in: ${user.email}");
        // Save data to Local DB
        await _saveUserToLocalDb(user);
      }
      return user;
    } on FirebaseAuthException catch (e) {
      print("🔴 Login Error: ${e.code} - ${e.message}");
      return null;
    } catch (e) {
      print("🔴 Login Error: $e");
      return null;
    }
  }

  Future<User?> signInWithGoogle() async {
  try {
    // 🔹 Ensure user always sees the account chooser
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();

    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // User canceled sign-in

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    UserCredential userCredential = await _auth.signInWithCredential(credential);
    User? user = userCredential.user;
    print (user);

    if (user != null) {
      // ✅ Check if user exists in Firestore
      DocumentSnapshot userDoc = await _firestore.collection("users").doc(user.uid).get();

      if (!userDoc.exists) {
        // 🔹 Create new user if not found
        await _firestore.collection("users").doc(user.uid).set({
          "uid": user.uid,
          "email": user.email,
          "username": user.displayName ?? "User",
          "phone": "",
        });
      }
    }
    return user;
  } catch (e) {
    print("Google Sign-In Error: $e");
    return null;
  }
}


  // 🔹 LOGOUT FUNCTION (UPDATED)
  Future<void> signOut() async {
    try {
      // 1. Sign out from Google if signed in with Google
      if (!kIsWeb) {
        try {
          final GoogleSignIn googleSignIn = GoogleSignIn();
          await googleSignIn.signOut();
          print("✅ Signed out from Google");
        } catch (e) {
          // This catch block handles cases where the user wasn't signed in via Google
          print("⚠️ Google sign-out error (safe to ignore): $e");
        }
      }

      // 2. Sign out from Firebase
      await _auth.signOut();

      // 3. Clear local database (CORRECTED NAME AND METHOD)
      try {
        // Use the correct class name and the clearTable method we defined
        await localdb.DatabaseHelper().clearTable();
        print("✅ Local data cleared.");
      } catch (e) {
        print("⚠️ Local DB clear error: $e");
      }

      print("✅ User signed out successfully");
    } catch (e) {
      print("🔴 Error during sign out: $e");
    }
  }

  // 🔹 FETCH USER DATA from Firestore
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection("users").doc(uid).get();
      if (userDoc.exists) {
        return userDoc.data() as Map<String, dynamic>;
      } else {
        print("⚠️ User document not found");
      }
    } catch (e) {
      print("🔴 Error fetching user data: $e");
    }
    return null;
  }

  // 🔹 REAUTHENTICATION BEFORE PASSWORD CHANGE
  Future<bool> reauthenticateUser(String currentPassword) async {
    try {
      User? user = _auth.currentUser;
      if (user == null) {
        print("⚠️ No user currently signed in");
        return false;
      }

      // Check if user signed in with Google
      bool isGoogleUser =
          user.providerData.any((info) => info.providerId == 'google.com');

      if (isGoogleUser) {
        print("⚠️ Cannot reauthenticate Google user with password");
        return await _reauthenticateGoogleUser();
      }

      // Reauthenticate with email/password
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);
      print("✅ Reauthentication successful");
      return true;
    } on FirebaseAuthException catch (e) {
      print("🔴 Reauthentication Error: ${e.code} - ${e.message}");
      return false;
    } catch (e) {
      print("🔴 Reauthentication Error: $e");
      return false;
    }
  }

  // ✅ GOOGLE REAUTHENTICATION
  Future<bool> _reauthenticateGoogleUser() async {
    try {
      if (kIsWeb) {
        // Web: Use popup for reauthentication
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        await _auth.currentUser?.reauthenticateWithPopup(googleProvider);
      } else {
        // Mobile: Use google_sign_in package
        final GoogleSignIn googleSignIn = GoogleSignIn();

        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

        if (googleUser == null) {
          print("⚠️ Google reauthentication cancelled");
          return false;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await _auth.currentUser?.reauthenticateWithCredential(credential);
      }

      print("✅ Google reauthentication successful");
      return true;
    } catch (e) {
      print("🔴 Google reauthentication error: $e");
      return false;
    }
  }

  // 🔹 UPDATE USER PROFILE & PASSWORD WITH REAUTHENTICATION
  Future<bool> updateUserProfile({
    required String uid,
    String? newName,
    String? newPhone,
    String? newPassword,
    String? currentPassword,
  }) async {
    try {
      User? user = _auth.currentUser;
      if (user == null) {
        print("⚠️ No user currently signed in");
        return false;
      }

      // Check if user is Google-authenticated
      bool isGoogleUser =
          user.providerData.any((info) => info.providerId == 'google.com');

      // Prevent password update for Google users
      if (newPassword != null && newPassword.isNotEmpty && isGoogleUser) {
        print("⚠️ Cannot update password for Google-authenticated users");
        return false;
      }

      // Update password for email/password users
      if (newPassword != null && newPassword.isNotEmpty && !isGoogleUser) {
        if (currentPassword == null || currentPassword.isEmpty) {
          print("⚠️ Current password required for password update");
          return false;
        }

        // Reauthenticate before password change
        bool reauthenticated = await reauthenticateUser(currentPassword);
        if (!reauthenticated) {
          print("🔴 Reauthentication failed. Cannot update password.");
          return false;
        }

        await user.updatePassword(newPassword);
        print("✅ Password updated successfully");
      }

      // Update Firestore user data
      Map<String, dynamic> updateData = {};
      if (newName != null && newName.isNotEmpty) updateData["username"] = newName;
      if (newPhone != null && newPhone.isNotEmpty) updateData["phone"] = newPhone;
      updateData["updatedAt"] = FieldValue.serverTimestamp();

      if (updateData.isNotEmpty) {
        await _firestore.collection("users").doc(uid).update(updateData);
        print("✅ User profile updated successfully in Firestore");

        // Update local DB after successful Firestore update
        final currentLocalUser = await localdb.DatabaseHelper().getSingleUser();
        if (currentLocalUser != null) {
            final updatedLocalUser = localdb.User(
                id: uid,
                email: currentLocalUser.email,
                displayName: newName ?? currentLocalUser.displayName,
                photoUrl: currentLocalUser.photoUrl,
            );
            await localdb.DatabaseHelper().updateUser(updatedLocalUser);
            print("✅ User profile updated successfully in local DB");
        }
      }

      return true;
    } on FirebaseAuthException catch (e) {
      print("🔴 Error updating profile: ${e.code} - ${e.message}");
      return false;
    } catch (e) {
      print("🔴 Error updating profile: $e");
      return false;
    }
  }

  // 🔹 CHECK CURRENT USER AUTHENTICATION STATE
  User? get currentUser => _auth.currentUser;

  // 🔹 STREAM FOR AUTHENTICATION STATE CHANGES
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 🔹 CHECK IF USER IS SIGNED IN WITH GOOGLE
  bool isGoogleUser() {
    User? user = _auth.currentUser;
    if (user == null) return false;
    return user.providerData.any((info) => info.providerId == 'google.com');
  }

  // 🔹 GET USER SIGN-IN METHOD
  String? getSignInMethod() {
    User? user = _auth.currentUser;
    if (user == null) return null;

    if (user.providerData.isEmpty) return 'unknown';
    return user.providerData.first.providerId;
  }
}
