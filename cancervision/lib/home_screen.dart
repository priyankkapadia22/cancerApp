import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'upload_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'db_helper.dart';
import 'chatbot_screen.dart';


class HomeScreen extends StatefulWidget {
  final String username;
  final String userId;

  HomeScreen({required this.username, required this.userId});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // List of cancer types for informational cards
  final List<Map<String, dynamic>> _cancerTypes = [
    {
      'title': 'Skin Cancer',
      'description': 'Early detection of skin cancer significantly improves treatment outcomes.',
      'image': 'assets/images/skin cancer.webp',
      'color': Color(0xFFE57373),
    },
    {
      'title': 'Breast Cancer',
      'description': 'Regular screening and early detection of breast cancer are crucial for successful treatment.',
      'image': 'assets/images/breast cancer.jpg',
      'color': Color(0xFF81C784),
    },
    {
      'title': 'Lung Cancer',
      'description': 'Lung cancer is a leading cause of cancer deaths. Early detection can improve survival rates.',
      'image': 'assets/images/lung cancer.jpg',
      'color': Color(0xFF64B5F6),
    },
    {
      'title': 'Colon Cancer',
      'description': 'Colorectal cancer can be detected early through screening.',
      'image': 'assets/images/colon cancer.jpg',
      'color': Color(0xFFFFB74D),
    },
  ];
  
  // Stats data
  int _totalScans = 0;
  String _lastScanDate = "No scans yet";
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _loadUserStats();
    _requestGalleryPermission();
  }
  
  // Request gallery permissions when the user logs in
  Future<void> _requestGalleryPermission() async {
    try {
      if (Platform.isAndroid) {
        // For Android 13+ (API level 33+)
        if (await Permission.photos.isGranted) {
          return;
        } else {
          final status = await Permission.photos.request();
          if (status.isDenied || status.isPermanentlyDenied) {
            _showPermissionDeniedDialog();
          }
        }
        
        // For older Android versions
        if (await Permission.storage.isGranted) {
          return;
        } else {
          final status = await Permission.storage.request();
          if (status.isDenied || status.isPermanentlyDenied) {
            _showPermissionDeniedDialog();
          }
        }
      } 
      // For iOS
      else if (Platform.isIOS) {
        if (await Permission.photos.isGranted) {
          return;
        } else {
          final status = await Permission.photos.request();
          if (status.isDenied || status.isPermanentlyDenied) {
            _showPermissionDeniedDialog();
          }
        }
      }
    } catch (e) {
      print("Error requesting permissions: $e");
    }
  }
  
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Gallery Access Required"),
        content: Text(
          "CancerVision needs access to your photo gallery to analyze images for cancer detection. Please enable this permission in your device settings.",
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("LATER"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text("OPEN SETTINGS"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _loadUserStats() async {
    setState(() {
      _isLoadingStats = true;
    });
    
    try {
      // Get total scans count
      QuerySnapshot predictionsSnapshot = await FirebaseFirestore.instance
          .collection("predictions")
          .where("userId", isEqualTo: widget.userId)
          .get();
      
      if (predictionsSnapshot.docs.isNotEmpty) {
        // Get total count
        _totalScans = predictionsSnapshot.docs.length;
        
        // Find the most recent scan
        Timestamp? mostRecentTimestamp;
        for (var doc in predictionsSnapshot.docs) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          Timestamp? timestamp = data['timestamp'] as Timestamp?;
          
          if (timestamp != null && (mostRecentTimestamp == null || timestamp.compareTo(mostRecentTimestamp) > 0)) {
            mostRecentTimestamp = timestamp;
          }
        }
        
        if (mostRecentTimestamp != null) {
          DateTime dateTime = mostRecentTimestamp.toDate();
          DateTime now = DateTime.now();
          
          if (dateTime.year == now.year && dateTime.month == now.month && dateTime.day == now.day) {
            _lastScanDate = "Today";
          } else if (dateTime.year == now.year && dateTime.month == now.month && dateTime.day == now.day - 1) {
            _lastScanDate = "Yesterday";
          } else {
            int daysDifference = now.difference(dateTime).inDays;
            if (daysDifference < 7) {
              _lastScanDate = "$daysDifference days ago";
            } else {
              _lastScanDate = DateFormat('MMM d, yyyy').format(dateTime);
            }
          }
        }
      }
    } catch (e) {
      print("Error loading user stats: $e");
    } finally {
      setState(() {
        _isLoadingStats = false;
      });
    }
  }

  /// Handles user sign-out
  Future<void> _signOut() async {
    try {
      // Show confirmation dialog
      bool confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Sign Out'),
          content: Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('SIGN OUT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
            ),
          ],
        ),
      ) ?? false;
      
      if (!confirm) return;
      
      // Clear user data from SQLite
      await DBHelper.deleteUser();

      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();

      // Navigate back to Login Screen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      print("❌ Sign-out error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error signing out!"),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  void _navigateToScreen(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    ).then((_) {
      // Refresh data when returning from other screens
      _loadUserStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "CancerVision",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        actions: [
          // Updated notification button with filled icon and white color
          IconButton(
            icon: Icon(
              Icons.notifications,
              color: Colors.white,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("No new notifications"),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          // Updated logout button with filled icon and white color
          IconButton(
            icon: Icon(
              Icons.logout,
              color: Colors.white,
            ),
            onPressed: _signOut,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadUserStats();
        },
        child: _buildHomeContent(screenSize, context, user),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatbotScreen()),
          );
        },
        backgroundColor: Theme.of(context).primaryColor,
        child: Icon(
          Icons.chat_bubble_outline_rounded,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildHomeContent(Size screenSize, BuildContext context, User? user) {
    return SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with greeting and quick stats
          _buildHeader(),
          
          // Quick action buttons
          _buildQuickActions(context, user),
          
          // Cancer types information
          _buildCancerTypesSection(),
          
          // Health tips section
          _buildHealthTipsSection(),
          
          SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Hello, ${widget.username}",
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 5),
          Text(
            "Welcome to your cancer detection assistant",
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: "Total Scans",
                  value: _isLoadingStats ? "Loading..." : "$_totalScans",
                  icon: Icons.image_search_outlined,
                  color: Colors.white.withOpacity(0.2),
                ),
              ),
              SizedBox(width: 15),
              Expanded(
                child: _buildStatCard(
                  title: "Last Scan",
                  value: _isLoadingStats ? "Loading..." : _lastScanDate,
                  icon: Icons.calendar_today_outlined,
                  color: Colors.white.withOpacity(0.2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 15, horizontal: 15),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuickActions(BuildContext context, User? user) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Quick Actions",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildActionButton(
                icon: Icons.add_a_photo,
                label: "New Scan",
                onTap: () {
                  if (user != null) {
                    _navigateToScreen(
                      context, 
                      UploadScreen(user: user)
                    );
                  }
                },
                color: Theme.of(context).primaryColor,
              ),
              _buildActionButton(
                icon: Icons.history,
                label: "History",
                onTap: () {
                  _navigateToScreen(
                    context, 
                    HistoryScreen(userId: widget.userId)
                  );
                },
                color: Colors.orange,
              ),
              _buildActionButton(
                icon: Icons.person,
                label: "Profile",
                onTap: () {
                  _navigateToScreen(
                    context, 
                    ProfileScreen(userId: widget.userId)
                  );
                },
                color: Colors.purple,
              ),
              _buildActionButton(
                icon: Icons.info,
                label: "About",
                onTap: () {
                  _showAboutDialog();
                },
                color: Colors.teal,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withOpacity(0.3), width: 1),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCancerTypesSection() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              "Cancer Types We Detect",
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 10),
          SizedBox(  // Changed from Container to SizedBox
            height: 250,  // Increased height to accommodate content
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 15),
              itemCount: _cancerTypes.length,
              itemBuilder: (context, index) {
                final item = _cancerTypes[index];
                return Container(
                  width: 250,
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Actual image loading with fallback
                      ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                        child: _buildCancerTypeImage(item),
                      ),
                      Expanded(  // Added Expanded to prevent overflow
                        child: Padding(
                          padding: EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['title'],
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 5),
                              Expanded(  // Added Expanded to allow text to fill available space
                                child: Text(
                                  item['description'],
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // New method to handle image loading with fallback
  Widget _buildCancerTypeImage(Map<String, dynamic> item) {
    try {
      return Image.asset(
        item['image'],
        height: 120,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print("Error loading image: $error");
          // Fallback to colored container with icon if image fails to load
          return Container(
            height: 120,
            width: double.infinity,
            color: item['color'],
            child: Center(
              child: Icon(
                Icons.image,
                color: Colors.white,
                size: 40,
              ),
            ),
          );
        },
      );
    } catch (e) {
      print("Exception loading image: $e");
      // Fallback for any other exceptions
      return Container(
        height: 120,
        width: double.infinity,
        color: item['color'],
        child: Center(
          child: Icon(
            Icons.image,
            color: Colors.white,
            size: 40,
          ),
        ),
      );
    }
  }
  
  Widget _buildHealthTipsSection() {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Health Tips",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 15),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Color(0xFF1565C0),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.tips_and_updates,
                      color: Colors.white,
                      size: 30,
                    ),
                    SizedBox(width: 10),
                    Text(
                      "Tip of the Day",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 15),
                Text(
                  "Regular screenings are essential for early cancer detection. Talk to your doctor about which cancer screening tests are right for you based on your age, gender, and family history.",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                SizedBox(height: 15),
                OutlinedButton(
                  onPressed: () {
                    // Show more health tips
                    _showHealthTipsDialog();
                  },
                  child: Text("Learn More"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("About CancerVision"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Our app uses advanced AI technology to help detect various types of cancer from medical images. This tool is designed to assist healthcare professionals and should not replace professional medical advice.",
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            SizedBox(height: 15),
            Text(
              "Version: 1.0.0",
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CLOSE"),
          ),
        ],
      ),
    );
  }
  
  void _showHealthTipsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Cancer Prevention Tips"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTipItem(
                "Avoid Tobacco",
                "Using any type of tobacco puts you on a collision course with cancer.",
              ),
              _buildTipItem(
                "Eat a Healthy Diet",
                "Eat plenty of fruits and vegetables, limit processed meats, and consider Mediterranean diet patterns.",
              ),
              _buildTipItem(
                "Maintain a Healthy Weight",
                "Being overweight or obese may increase your risk of cancer.",
              ),
              _buildTipItem(
                "Physical Activity",
                "Regular physical activity can help you maintain a healthy weight and reduce your risk of several types of cancer.",
              ),
              _buildTipItem(
                "Protect Yourself from the Sun",
                "Skin cancer is one of the most common kinds of cancer and one of the most preventable.",
              ),
              _buildTipItem(
                "Get Vaccinated",
                "Cancer prevention includes protection from certain viral infections like Hepatitis B and HPV.",
              ),
              _buildTipItem(
                "Regular Medical Care",
                "Regular self-exams and screenings for various types of cancer can increase your chances of discovering cancer early.",
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CLOSE"),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTipItem(String title, String description) {
    return Padding(
      padding: EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          SizedBox(height: 5),
          Text(
            description,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}