// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import 'db_helper.dart' as localdb; 

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool isLoading = false;
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _checkAndClearInvalidAuth();
  }

  // --- FUNCTIONAL METHODS ---
  Future<void> _checkAndClearInvalidAuth() async {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      DocumentSnapshot userDoc = await _firestore.collection("users").doc(currentUser.uid).get();
      if (!mounted) return;
      if (!userDoc.exists) {
        await _auth.signOut();
      }
    }
  }

  void _loginWithEmail() async {
    if (!_validateInputs()) return;
    setState(() => isLoading = true);
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      User? user = userCredential.user;
      if (!mounted) return;
      if (user != null) {
        DocumentSnapshot userDoc = await _firestore.collection("users").doc(user.uid).get();
        if (!mounted) return;
        if (!userDoc.exists) {
          await _auth.signOut();
          if (mounted) { setState(() => isLoading = false); }
          _showErrorSnackbar("Account exists but is incomplete. Please sign up again.");
          return;
        }
        var userData = userDoc.data() as Map<String, dynamic>;
        final localdb.User localUser = localdb.User(
          id: user.uid, email: user.email!, displayName: userData["username"] ?? "User", photoUrl: userData["photoURL"] ?? "",
        );
        await localdb.DatabaseHelper().insertUser(localUser);
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Login Successful! Redirecting..."), backgroundColor: Colors.green, duration: Duration(seconds: 1),));
        }
        if (!mounted) return;
        setState(() => isLoading = false);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomeScreen(username: userData["username"] ?? "User", userId: user.uid,)),);
      } else {
        if (mounted) { setState(() => isLoading = false); }
        _showErrorSnackbar("Login Failed! Unknown error occurred.");
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) { setState(() => isLoading = false); }
      if (!mounted) return;
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        _showAccountNotExistsDialog();
      } else if (e.code == 'wrong-password') {
        _showErrorSnackbar("Incorrect password. Please try again.");
      } else {
        _showErrorSnackbar("Login Error: ${e.message}");
      }
    } catch (e) {
      if (mounted) { setState(() => isLoading = false); }
      if (!mounted) return; 
      _showErrorSnackbar("Login Failed: ${e.toString()}");
    }
  }

  void _showAccountNotExistsDialog() {
    if (!mounted) return; 
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Account Not Found"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle_outlined, size: 70, color: Colors.orange,),
              const SizedBox(height: 16),
              const Text("No account was found with this email. Would you like to create a new account?", style: TextStyle(fontSize: 16), textAlign: TextAlign.center,),
            ],
          ),
          actions: [
            TextButton(onPressed: () { Navigator.of(context).pop(); }, child: const Text("CANCEL"),),
            ElevatedButton(
              onPressed: () { Navigator.of(context).pop(); Navigator.push(context, MaterialPageRoute(builder: (context) => const SignupScreen()),); },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8),),),
              child: const Text("SIGN UP"),
            ),
          ],
        );
      },
    );
  }

  bool _validateInputs() {
    if (emailController.text.trim().isEmpty || !emailController.text.contains('@')) { return false; }
    if (passwordController.text.isEmpty) { return false; }
    return true;
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return; 
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), margin: const EdgeInsets.all(10),),
    );
  }

  void _loginWithGoogle() async {
    setState(() => isLoading = true);
    try {
      await _auth.signOut();
      User? user = await _authService.signInWithGoogle();
      if (!mounted) return;
      if (user == null) {
        if (mounted) { setState(() => isLoading = false); }
        _showErrorSnackbar("Google Sign-In failed or was cancelled.");
        return;
      }
      DocumentSnapshot userDoc = await _firestore.collection("users").doc(user.uid).get();
      if (!mounted) return;
      if (!userDoc.exists) {
        await _auth.signOut();
        if (mounted) { setState(() => isLoading = false); }
        _showGoogleAccountNotRegisteredDialog(user);
        return;
      }
      var userData = userDoc.data() as Map<String, dynamic>;
      String username = userData["username"] ?? user.displayName ?? "User";
      String email = userData["email"] ?? user.email!;
      final localdb.User localUser = localdb.User(
        id: user.uid, email: email, displayName: username, photoUrl: userData["photoURL"] ?? user.photoURL ?? "",
      );
      await localdb.DatabaseHelper().insertUser(localUser);
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Login Successful with Google! Redirecting..."), backgroundColor: Colors.green, duration: Duration(seconds: 1),));
      }
      if (!mounted) return;
      setState(() => isLoading = false);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomeScreen(username: username, userId: user.uid,)),);
    } catch (e) {
      if (mounted) { setState(() => isLoading = false); }
      if (!mounted) return; 
      _showErrorSnackbar("Google Sign-In Failed: ${e.toString()}");
    }
  }

  void _showGoogleAccountNotRegisteredDialog(User googleUser) {
    if (!mounted) return; 
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Account Not Registered"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle_outlined, size: 70, color: Colors.orange,),
              const SizedBox(height: 16),
              Text("This Google account (${googleUser.email}) is not registered. Would you like to create a new account?", style: const TextStyle(fontSize: 16),),
            ],
          ),
          actions: [
            TextButton(onPressed: () { Navigator.of(context).pop(); }, child: const Text("CANCEL"),),
            ElevatedButton(
              onPressed: () { Navigator.of(context).pop(); _registerGoogleUser(googleUser); },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8),),),
              child: const Text("REGISTER"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _registerGoogleUser(User googleUser) async {
    setState(() => isLoading = true);
    try {
      await _firestore.collection("users").doc(googleUser.uid).set({
        "uid": googleUser.uid, "email": googleUser.email, "username": googleUser.displayName ?? "User",
        "phone": googleUser.phoneNumber ?? "", "photoURL": googleUser.photoURL ?? "",
        "createdAt": FieldValue.serverTimestamp(), "authProvider": "google"
      });
      if (!mounted) return;
      _loginWithGoogle();
    } catch (e) {
      if (mounted) { setState(() => isLoading = false); }
      if (!mounted) return; 
      _showErrorSnackbar("Registration Failed: ${e.toString()}");
    }
  }

  // --- BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    // 1. Detect Keyboard State
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = keyboardHeight > 0;

    // 2. Calculate Slide Offset
    // When keyboard opens, we slide the screen UP by ~160 pixels
    // This moves the top logo off-screen and centers the inputs smoothly.
    final double yOffset = isKeyboardOpen ? -160.0 : 0.0;

    return Scaffold(
      // 3. Stop OS from resizing window (Prevents Overflow & Focus Loss)
      resizeToAvoidBottomInset: false,
      
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.deepPurple.shade900, 
              Colors.purple.shade700,     
              Colors.deepPurple.shade900,
            ],
          ),
        ),
        child: SafeArea(
          // 4. Use AnimatedContainer for smooth transition
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, yOffset, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  // Standard Column, centered. No conditional widget removal!
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      
                      // --- LOGO & HEADER (Slides up/off-screen) ---
                      const Icon(Icons.lock_outlined, size: 70, color: Colors.white,),
                      const SizedBox(height: 10),
                      const Text(
                        "Welcome Back",
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 5),
                      const Text("Sign in to continue", style: TextStyle(fontSize: 14, color: Colors.white70), textAlign: TextAlign.center,),
                      
                      const SizedBox(height: 30),

                      // --- INPUT FIELDS ---
                      _buildTextField(
                        controller: emailController,
                        label: "Email",
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      
                      const SizedBox(height: 16),
                      
                      _buildTextField(
                        controller: passwordController,
                        label: "Password",
                        icon: Icons.lock_outline,
                        isPassword: true,
                        isPasswordVisible: _isPasswordVisible,
                        onTogglePasswordVisibility: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                      
                      // Forgot password
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {},
                          child: const Text("Forgot Password?", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),),
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Login Button
                      ElevatedButton(
                        onPressed: isLoading ? null : _loginWithEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.shade500,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),),
                          elevation: 4,
                          shadowColor: Colors.black45,
                        ),
                        child: isLoading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2,),)
                            : const Text("LOGIN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),

                      const SizedBox(height: 20),

                      // --- DIVIDER ---
                      const Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white54, thickness: 1)),
                          Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("OR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),),
                          Expanded(child: Divider(color: Colors.white54, thickness: 1)),
                        ],
                      ),
                      
                      const SizedBox(height: 20),

                      // --- NEW GOOGLE BUTTON DESIGN ---
                      // A white pill-shaped button with shadow and full Google visual
                      ElevatedButton(
                        onPressed: isLoading ? null : _loginWithGoogle,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30),),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // You can use an asset image here if you have the official Google logo
                            // For now, we use the colored icon which is standard practice if assets are missing
                            const Icon(Icons.g_mobiledata, size: 32, color: Colors.redAccent), 
                            const SizedBox(width: 10),
                            Text(
                              "Continue with Google",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),

                      // --- SIGN UP LINK (Slides behind keyboard) ---
                      TextButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const SignupScreen()),);
                        },
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: const TextSpan(
                            text: "Don't have an account? ",
                            style: TextStyle(color: Colors.white70),
                            children: [
                              TextSpan(text: "Sign Up", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, decoration: TextDecoration.underline,),),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isPasswordVisible = false,
    Function? onTogglePasswordVisibility,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !isPasswordVisible,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 16, color: Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade600),
          prefixIcon: Icon(icon, color: Colors.purple.shade700),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(isPasswordVisible ? Icons.visibility_off : Icons.visibility, color: Colors.grey.shade600,),
                  onPressed: () { if (onTogglePasswordVisibility != null) { onTogglePasswordVisibility(); } },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
    );
  }
}