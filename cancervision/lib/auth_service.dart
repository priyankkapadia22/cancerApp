import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'db_helper.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  //final GoogleSignIn _googleSignIn = GoogleSignIn();

  // 🔹 SIGNUP with Email, Password, Username, and Phone Number
  Future<User?> signUpWithEmail(String email, String password, String username, String phone) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      User? user = userCredential.user;

      if (user != null) {
        // Save user details in Firestore
        await _firestore.collection("users").doc(user.uid).set({
          "uid": user.uid,
          "email": email,
          "username": username,
          "phone": phone,
        });
      }
      return user;
    } catch (e) {
      print("Signup Error: $e");
      return null;
    }
  }

  // 🔹 LOGIN with Email & Password
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(email: email, password: password);
      return userCredential.user;
    } catch (e) {
      print("Login Error: $e");
      return null;
    }
  }

  // 🔹 SIGN-IN with Google
  // 🔹 SIGN-IN with Google (Forces Account Selection)
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


  // 🔹 LOGOUT FUNCTION
  Future<void> signOut() async {
    await _auth.signOut(); // ✅ Logs out from Firebase
    await GoogleSignIn().signOut(); // ✅ Logs out from Google (if signed in)
    await DBHelper.deleteUser(); // ✅ Clear user from SQLite
  }

  // 🔹 FETCH USER DATA
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection("users").doc(uid).get();
      if (userDoc.exists) {
        return userDoc.data() as Map<String, dynamic>;
      }
    } catch (e) {
      print("Error fetching user data: $e");
    }
    return null;
  }

  // 🔹 REAUTHENTICATION BEFORE PASSWORD CHANGE
  Future<bool> reauthenticateUser(String currentPassword) async {
    try {
      User? user = _auth.currentUser;
      if (user == null) return false;

      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      return true; // ✅ Reauthentication successful
    } catch (e) {
      print("Reauthentication Error: $e");
      return false; // ❌ Reauthentication failed
    }
  }

  // 🔹 UPDATE PROFILE & PASSWORD WITH REAUTHENTICATION
  Future<bool> updateUserProfile({
    required String uid,
    String? newName,
    String? newPhone,
    String? newPassword,
    String? currentPassword,
  }) async {
    try {
      User? user = _auth.currentUser;
      if (user == null) return false;

      // If user is updating password, reauthenticate first
      if (newPassword != null && newPassword.isNotEmpty) {
        bool reauthenticated = await reauthenticateUser(currentPassword!);
        if (!reauthenticated) {
          print("Reauthentication failed. Cannot update password.");
          return false;
        }
        await user.updatePassword(newPassword);
      }

      // Update Firestore user details if provided
      Map<String, dynamic> updateData = {};
      if (newName != null) updateData["username"] = newName;
      if (newPhone != null) updateData["phone"] = newPhone;

      if (updateData.isNotEmpty) {
        await _firestore.collection("users").doc(uid).update(updateData);
      }

      return true; // ✅ Update successful
    } catch (e) {
      print("Error updating profile: $e");
      return false;
    }
  }
}
