import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;

  ProfileScreen({required this.userId});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();

  String _email = "";
  String _username = "";
  String _avatarText = "";
  bool _isLoading = false;
  bool _isGoogleUser = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _obscureCurrentPassword = true;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _currentPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _email = user.email ?? "No email available";
      _isGoogleUser = user.providerData.any((info) => info.providerId == 'google.com');
    });

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection("users").doc(user.uid).get();
      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _nameController.text = userData["username"] ?? "";
          _username = userData["username"] ?? "User";
          _phoneController.text = userData["phone"] ?? "";
          
          // Create avatar text from username
          if (_username.isNotEmpty) {
            List<String> nameParts = _username.split(" ");
            if (nameParts.length > 1) {
              _avatarText = nameParts[0][0] + nameParts[1][0];
            } else {
              _avatarText = _username.substring(0, _username.length > 1 ? 2 : 1);
            }
            _avatarText = _avatarText.toUpperCase();
          }
        });
      }
    } catch (e) {
      print("Error loading user data: $e");
      _showErrorSnackbar("Failed to load profile data");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }

    // Listen for changes to detect unsaved modifications
    _nameController.addListener(_checkForChanges);
    _phoneController.addListener(_checkForChanges);
    _passwordController.addListener(_checkForChanges);
    _confirmPasswordController.addListener(_checkForChanges);
  }

  void _checkForChanges() {
    if (!mounted) return;
    
    setState(() {
      _hasUnsavedChanges = 
          _nameController.text != _username ||
          _phoneController.text.isNotEmpty ||
          _passwordController.text.isNotEmpty ||
          _confirmPasswordController.text.isNotEmpty;
    });
  }

  Future<void> _reauthenticate() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_isGoogleUser) {
      // Reauthenticate Google user
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) throw Exception("Google sign-in cancelled");
      
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
    } else {
      // Reauthenticate Email/Password user
      if (_currentPasswordController.text.isEmpty) {
        throw Exception("Current password is required");
      }
      
      AuthCredential credential = EmailAuthProvider.credential(
        email: _email,
        password: _currentPasswordController.text.trim(),
      );
      await user.reauthenticateWithCredential(credential);
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (!_hasUnsavedChanges) {
      _showInfoSnackbar("No changes to save");
      return;
    }
    
    // Verify password match if changing password
    if (_passwordController.text.isNotEmpty && 
        _passwordController.text != _confirmPasswordController.text) {
      _showErrorSnackbar("Passwords do not match");
      return;
    }

    // Show confirmation dialog
    bool confirmUpdate = await _showConfirmationDialog(
      "Update Profile",
      "Are you sure you want to update your profile information?",
      "CANCEL",
      "UPDATE"
    );
    
    if (!confirmUpdate) return;

    setState(() {
      _isLoading = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not found");

      // Only update fields that have changed
      Map<String, dynamic> updateData = {};
      if (_nameController.text != _username && _nameController.text.isNotEmpty) {
        updateData["username"] = _nameController.text;
      }
      
      if (_phoneController.text.isNotEmpty) {
        updateData["phone"] = _phoneController.text;
      }

      // Update Firestore data if there are changes
      if (updateData.isNotEmpty) {
        await FirebaseFirestore.instance.collection("users").doc(user.uid).update(updateData);
      }

      // Update password if provided (requires reauthentication)
      if (_passwordController.text.isNotEmpty) {
        await _reauthenticate();
        await user.updatePassword(_passwordController.text);
      }

      // Clear password fields
      _passwordController.clear();
      _confirmPasswordController.clear();
      _currentPasswordController.clear();
      
      setState(() {
        _hasUnsavedChanges = false;
        if (updateData.containsKey("username")) {
          _username = updateData["username"];
          
          // Update avatar text
          if (_username.isNotEmpty) {
            List<String> nameParts = _username.split(" ");
            if (nameParts.length > 1) {
              _avatarText = nameParts[0][0] + nameParts[1][0];
            } else {
              _avatarText = _username.substring(0, _username.length > 1 ? 2 : 1);
            }
            _avatarText = _avatarText.toUpperCase();
          }
        }
      });

      _showSuccessSnackbar("Profile updated successfully");
    } catch (e) {
      print("Error updating profile: $e");
      String errorMessage = "Failed to update profile";
      
      if (e.toString().contains("weak-password")) {
        errorMessage = "Password is too weak. Please use a stronger password.";
      } else if (e.toString().contains("requires-recent-login")) {
        errorMessage = "Please re-login before changing your password.";
      } else if (e.toString().contains("wrong-password")) {
        errorMessage = "Current password is incorrect.";
      }
      
      _showErrorSnackbar(errorMessage);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAccount() async {
    bool confirmDelete = await _showConfirmationDialog(
      "Delete Account",
      "This action will permanently delete your account and all associated data. This cannot be undone. Are you sure?",
      "CANCEL",
      "DELETE",
      isDestructive: true
    );
    
    if (!confirmDelete) return;

    setState(() {
      _isLoading = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not found");

      await _reauthenticate();

      // Delete user data from Firestore
      await FirebaseFirestore.instance.collection("users").doc(user.uid).delete();
      
      // Delete predictions associated with this user
      QuerySnapshot predictionsSnapshot = await FirebaseFirestore.instance
          .collection("predictions")
          .where("userId", isEqualTo: user.uid)
          .get();
          
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in predictionsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Delete account from Firebase Authentication
      await user.delete();

      // Sign out from Google (if Google user)
      if (_isGoogleUser) {
        await GoogleSignIn().signOut();
      }

      _showSuccessSnackbar("Account deleted successfully");
      
      // Navigate to login screen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      print("Error deleting account: $e");
      String errorMessage = "Failed to delete account";
      
      if (e.toString().contains("requires-recent-login")) {
        errorMessage = "Please re-login before deleting your account.";
      } else if (e.toString().contains("wrong-password")) {
        errorMessage = "Current password is incorrect.";
      }
      
      _showErrorSnackbar(errorMessage);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _showConfirmationDialog(
    String title, 
    String message, 
    String cancelText, 
    String confirmText, 
    {bool isDestructive = false}
  ) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                ),
              ),
              if (!_isGoogleUser && (title == "Delete Account" || _passwordController.text.isNotEmpty)) ...[
                SizedBox(height: 20),
                Text(
                  "Please enter your current password to continue:",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 10),
                TextFormField(
                  controller: _currentPasswordController,
                  decoration: InputDecoration(
                    labelText: "Current Password",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureCurrentPassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureCurrentPassword = !_obscureCurrentPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureCurrentPassword,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              cancelText,
              style: GoogleFonts.poppins(
                color: Colors.grey.shade700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              confirmText,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ) ?? false;
  }
  
  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(10),
      ),
    );
  }
  
  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(10),
      ),
    );
  }
  
  void _showInfoSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_hasUnsavedChanges) {
          bool shouldDiscard = await _showConfirmationDialog(
            "Discard Changes",
            "You have unsaved changes. Are you sure you want to discard them?",
            "STAY",
            "DISCARD"
          );
          return shouldDiscard;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "Edit Profile",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Theme.of(context).primaryColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () async {
              if (_hasUnsavedChanges) {
                bool shouldDiscard = await _showConfirmationDialog(
                  "Discard Changes",
                  "You have unsaved changes. Are you sure you want to discard them?",
                  "STAY",
                  "DISCARD"
                );
                if (shouldDiscard) {
                  Navigator.pop(context);
                }
              } else {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            if (_hasUnsavedChanges)
              TextButton(
                onPressed: _updateProfile,
                child: Text(
                  "SAVE",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        body: _isLoading ? 
          Center(child: CircularProgressIndicator()) : 
          _buildProfileForm(),
      ),
    );
  }

  Widget _buildProfileForm() {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Profile header with avatar
            Container(
              padding: EdgeInsets.only(top: 30, bottom: 30),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white,
                    child: Text(
                      _avatarText,
                      style: GoogleFonts.poppins(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  // Email
                  Text(
                    _email,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  // Account type badge
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isGoogleUser ? Icons.g_mobiledata : Icons.email_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          _isGoogleUser ? "Google Account" : "Email Account",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Form fields
            Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section title
                  Text(
                    "Personal Information",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 20),
                  
                  // Name field
                  _buildTextField(
                    controller: _nameController,
                    label: "Display Name",
                    icon: Icons.person_outline,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Please enter your name";
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),
                  
                  // Phone field
                  _buildTextField(
                    controller: _phoneController,
                    label: "Phone Number",
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  
                  // Password section (only for email users)
                  if (!_isGoogleUser) ...[
                    SizedBox(height: 30),
                    Text(
                      "Security",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20),
                    
                    // New password field
                    _buildTextField(
                      controller: _passwordController,
                      label: "New Password",
                      icon: Icons.lock_outline,
                      isPassword: true,
                      isPasswordVisible: !_obscurePassword,
                      onTogglePasswordVisibility: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                      validator: (value) {
                        if (value != null && value.isNotEmpty && value.length < 6) {
                          return "Password must be at least 6 characters";
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    
                    // Confirm password field
                    _buildTextField(
                      controller: _confirmPasswordController,
                      label: "Confirm Password",
                      icon: Icons.lock_outline,
                      isPassword: true,
                      isPasswordVisible: !_obscureConfirmPassword,
                      onTogglePasswordVisibility: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                      validator: (value) {
                        if (_passwordController.text.isNotEmpty && value != _passwordController.text) {
                          return "Passwords do not match";
                        }
                        return null;
                      },
                    ),
                  ],
                  
                  SizedBox(height: 40),
                  
                  // Update button
                  ElevatedButton(
                    onPressed: _hasUnsavedChanges ? _updateProfile : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: Size(double.infinity, 50),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: Text(
                      "UPDATE PROFILE",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Delete account button
                  OutlinedButton(
                    onPressed: _deleteAccount,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: Size(double.infinity, 50),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "DELETE ACCOUNT",
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !isPasswordVisible,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Theme.of(context).primaryColor),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red, width: 1),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}