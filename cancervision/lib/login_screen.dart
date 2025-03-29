import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import 'db_helper.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
    // Check if user is already logged in but not registered
    _checkAndClearInvalidAuth();
  }

  Future<void> _checkAndClearInvalidAuth() async {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      // Check if user exists in Firestore
      DocumentSnapshot userDoc = await _firestore.collection("users").doc(currentUser.uid).get();
      if (!userDoc.exists) {
        // User is authenticated but not in Firestore - sign them out
        await _auth.signOut();
      }
    }
  }

  void _loginWithEmail() async {
    if (!_validateInputs()) return;
    
    setState(() => isLoading = true);

    try {
      // Directly attempt to sign in with Firebase Auth
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      
      User? user = userCredential.user;
      
      if (user != null) {
        // Check if user exists in Firestore
        DocumentSnapshot userDoc = await _firestore.collection("users").doc(user.uid).get();
        
        if (!userDoc.exists) {
          // User exists in Auth but not in Firestore
          await _auth.signOut();
          setState(() => isLoading = false);
          _showErrorSnackbar("Account exists but is incomplete. Please sign up again.");
          return;
        }
        
        // User exists in Firestore, proceed with login
        var userData = userDoc.data() as Map<String, dynamic>;

        // Save user in SQLite for persistent login
        await DBHelper.saveUser(user.uid, user.email!, userData["username"] ?? "User");

        setState(() => isLoading = false);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              username: userData["username"] ?? "User",
              userId: user.uid,
            ),
          ),
        );
      } else {
        setState(() => isLoading = false);
        _showErrorSnackbar("Login Failed! Unknown error occurred.");
      }
    } on FirebaseAuthException catch (e) {
      setState(() => isLoading = false);
      
      if (e.code == 'user-not-found') {
        _showAccountNotExistsDialog();
      } else if (e.code == 'wrong-password') {
        _showErrorSnackbar("Incorrect password. Please try again.");
      } else if (e.code == 'invalid-credential') {
        _showErrorSnackbar("Invalid credentials. Please check your email and password.");
      } else if (e.code == 'invalid-email') {
        _showErrorSnackbar("Invalid email format. Please enter a valid email.");
      } else {
        _showErrorSnackbar("Login Error: ${e.message}");
        print("Firebase Auth Error: ${e.code} - ${e.message}");
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorSnackbar("Login Failed: ${e.toString()}");
      print("General Error: ${e.toString()}");
    }
  }

  void _showAccountNotExistsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Account Not Found"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_circle_outlined,
                size: 70,
                color: Colors.orange,
              ),
              SizedBox(height: 16),
              Text(
                "We couldn't find an account with this email address. Would you like to create a new account?",
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("CANCEL"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SignupScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text("SIGN UP"),
            ),
          ],
        );
      },
    );
  }

  bool _validateInputs() {
    if (emailController.text.trim().isEmpty || !emailController.text.contains('@')) {
      _showErrorSnackbar("Please enter a valid email");
      return false;
    }
    if (passwordController.text.isEmpty) {
      _showErrorSnackbar("Please enter your password");
      return false;
    }
    return true;
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(10),
      ),
    );
  }

  void _loginWithGoogle() async {
    setState(() => isLoading = true);

    try {
      // First sign out to clear any existing auth state
      await _auth.signOut();
      
      // Attempt Google sign-in
      User? user = await _authService.signInWithGoogle();

      if (user == null) {
        setState(() => isLoading = false);
        _showErrorSnackbar("Google Sign-In failed or was cancelled.");
        return;
      }

      // Check if this Google account is registered in Firestore
      DocumentSnapshot userDoc = await _firestore.collection("users").doc(user.uid).get();
      
      if (!userDoc.exists) {
        // This Google account is not registered
        // Sign out and show registration dialog
        await _auth.signOut();
        setState(() => isLoading = false);
        _showGoogleAccountNotRegisteredDialog(user);
        return;
      }

      // Account exists, proceed with login
      var userData = userDoc.data() as Map<String, dynamic>;
      
      // Ensure userData is never null
      String username = userData["username"] ?? user.displayName ?? "User";
      String email = userData["email"] ?? user.email!;

      // Save user in SQLite for persistent login
      await DBHelper.saveUser(user.uid, email, username);

      setState(() => isLoading = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            username: username,
            userId: user.uid,
          ),
        ),
      );
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorSnackbar("Google Sign-In Failed: ${e.toString()}");
      print("Google Sign-In Error: ${e.toString()}");
    }
  }

  void _showGoogleAccountNotRegisteredDialog(User googleUser) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Account Not Registered"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_circle_outlined,
                size: 70,
                color: Colors.orange,
              ),
              SizedBox(height: 16),
              Text(
                "This Google account (${googleUser.email}) is not registered. Would you like to create a new account?",
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("CANCEL"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _registerGoogleUser(googleUser);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text("REGISTER"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _registerGoogleUser(User googleUser) async {
    setState(() => isLoading = true);

    try {
      // Create user document in Firestore
      await _firestore.collection("users").doc(googleUser.uid).set({
        "uid": googleUser.uid,
        "email": googleUser.email,
        "username": googleUser.displayName ?? "User",
        "phone": googleUser.phoneNumber ?? "",
        "createdAt": FieldValue.serverTimestamp(),
        "authProvider": "google"
      });

      // Re-login with Google
      _loginWithGoogle();
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorSnackbar("Registration Failed: ${e.toString()}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.blue.shade800,
                  Colors.indigo.shade900,
                ],
              ),
            ),
          ),
          
          // Main content
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 60),
                    
                    // App logo or icon
                    Icon(
                      Icons.lock_outlined,
                      size: 80,
                      color: Colors.white,
                    ),
                    
                    SizedBox(height: 30),
                    
                    // Welcome text
                    Text(
                      "Welcome Back",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    SizedBox(height: 10),
                    
                    Text(
                      "Sign in to continue",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    SizedBox(height: 50),
                    
                    // Login form card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 15,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Email field
                          _buildTextField(
                            controller: emailController,
                            label: "Email",
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          
                          SizedBox(height: 16),
                          
                          // Password field
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
                          
                          SizedBox(height: 8),
                          
                          // Forgot password link
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                // Implement forgot password functionality
                              },
                              child: Text(
                                "Forgot Password?",
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size(50, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          
                          SizedBox(height: 24),
                          
                          // Login button
                          ElevatedButton(
                            onPressed: isLoading ? null : _loginWithEmail,
                            child: isLoading
                                ? SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text("LOGIN", style: TextStyle(fontSize: 16)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                              minimumSize: Size(double.infinity, 50),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: 24),
                    
                    // Divider with "OR" text
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.white54, thickness: 1)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text("OR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        ),
                        Expanded(child: Divider(color: Colors.white54, thickness: 1)),
                      ],
                    ),
                    
                    SizedBox(height: 24),
                    
                    // Google login button
                    ElevatedButton.icon(
                      onPressed: isLoading ? null : _loginWithGoogle,
                      icon: Icon(Icons.g_mobiledata, size: 24),
                      label: Text("Login with Google", style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                        minimumSize: Size(double.infinity, 50),
                      ),
                    ),
                    
                    SizedBox(height: 24),
                    
                    // Sign up link
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SignupScreen()),
                        );
                      },
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          text: "Don't have an account? ",
                          style: TextStyle(color: Colors.white70),
                          children: [
                            TextSpan(
                              text: "Sign Up",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
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
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !isPasswordVisible,
        keyboardType: keyboardType,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade700),
          prefixIcon: Icon(icon, color: Colors.blue.shade700),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey.shade600,
                  ),
                  onPressed: () {
                    if (onTogglePasswordVisibility != null) {
                      onTogglePasswordVisibility();
                    }
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
