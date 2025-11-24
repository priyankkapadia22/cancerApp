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
// FIX: Import db_helper with a prefix
import 'db_helper.dart' as localdb;
import 'chatbot_screen.dart';


class HomeScreen extends StatefulWidget {
  final String username;
  final String userId;

  const HomeScreen({super.key, required this.username, required this.userId});

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
      'color': const Color(0xFFE57373),
    },
    {
      'title': 'Breast Cancer',
      'description': 'Regular screening and early detection of breast cancer are crucial for successful treatment.',
      'image': 'assets/images/breast cancer.jpg',
      'color': const Color(0xFF81C784),
    },
    {
      'title': 'Lung Cancer',
      'description': 'Lung cancer is a leading cause of cancer deaths. Early detection can improve survival rates.',
      'image': 'assets/images/lung cancer.jpg',
      'color': const Color(0xFF64B5F6),
    },
    {
      'title': 'Colon Cancer',
      'description': 'Colorectal cancer can be detected early through screening.',
      'image': 'assets/images/colon cancer.jpg',
      'color': const Color(0xFFFFB74D),
    },
  ];

  // Stats data
  int _totalScans = 0;
  String _lastScanDate = "No scans yet";
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
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
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Gallery Access Required"),
        content: Text(
          "CancerVision needs access to your photo gallery to analyze images for cancer detection. Please enable this permission in your device settings.",
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("LATER"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
            ),
            child: const Text("OPEN SETTINGS"),
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
      QuerySnapshot predictionsSnapshot = await FirebaseFirestore.instance
          .collection("predictions")
          .where("userId", isEqualTo: widget.userId)
          .get();

      if (predictionsSnapshot.docs.isNotEmpty) {
        _totalScans = predictionsSnapshot.docs.length;

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
      } else {
        _totalScans = 0;
        _lastScanDate = "No scans yet";
      }
    } catch (e) {
      print("Error loading user stats: $e");
    } finally {
      if(mounted) {
        setState(() {
          _isLoadingStats = false;
        });
      }
    }
  }

  /// Handles user sign-out with Modern UI
  Future<void> _signOut() async {
    try {
      // Modern UI Confirmation Dialog
      bool confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), // Modern rounded corners
          ),
          backgroundColor: Colors.white,
          elevation: 5,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Sign Out',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to end your session?',
            style: GoogleFonts.poppins(
              color: Colors.black54,
              fontSize: 14,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          actions: [
            // Modern CANCEL Button (Outlined, Theme Color)
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Theme.of(context).primaryColor, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              ),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Modern SIGN OUT Button (Filled, Theme Color)
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor, // Purple Theme
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              ),
              child: Text(
                'Sign Out',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ) ?? false;

      if (!confirm) return;

      // Clear user data from SQLite
      await localdb.DatabaseHelper().clearTable();

      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();

      // Navigate back to Login Screen
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      print("❌ Sign-out error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Error signing out!"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
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
          IconButton(
            icon: const Icon(
              Icons.notifications,
              color: Colors.white,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("No new notifications"),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(
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
            MaterialPageRoute(builder: (context) => const ChatbotScreen()),
          );
        },
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(
          Icons.chat_bubble_outline_rounded,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildHomeContent(Size screenSize, BuildContext context, User? user) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildQuickActions(context, user),
          _buildCancerTypesSection(),
          _buildHealthTipsSection(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: const BorderRadius.only(
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
          const SizedBox(height: 5),
          Text(
            "Welcome to your cancer detection assistant",
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 20),
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
              const SizedBox(width: 15),
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
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 10),
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
      padding: const EdgeInsets.all(20),
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
          const SizedBox(height: 15),
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
                onTap: _showAboutDialog,
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
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withOpacity(0.3), width: 1),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              "Cancer Types We Detect",
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 250,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: _cancerTypes.length,
              itemBuilder: (context, index) {
                final item = _cancerTypes[index];
                return Container(
                  width: 250,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                        child: _buildCancerTypeImage(item),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(15),
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
                              const SizedBox(height: 5),
                              Expanded(
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

  Widget _buildCancerTypeImage(Map<String, dynamic> item) {
    try {
      return Image.asset(
        item['image'],
        height: 120,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print("Error loading image: $error");
          return Container(
            height: 120,
            width: double.infinity,
            color: item['color'],
            child: const Center(
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
      return Container(
        height: 120,
        width: double.infinity,
        color: item['color'],
        child: const Center(
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
      padding: const EdgeInsets.all(20),
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
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  const Color(0xFF1565C0),
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
                    const Icon(
                      Icons.tips_and_updates,
                      color: Colors.white,
                      size: 30,
                    ),
                    const SizedBox(width: 10),
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
                const SizedBox(height: 15),
                Text(
                  "Regular screenings are essential for early cancer detection. Talk to your doctor about which cancer screening tests are right for you based on your age, gender, and family history.",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 15),
                OutlinedButton(
                  onPressed: _showHealthTipsDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text("Learn More"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("About CancerVision"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Our app uses advanced AI technology to help detect various types of cancer from medical images. This tool is designed to assist healthcare professionals and should not replace professional medical advice.",
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            const SizedBox(height: 15),
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
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }

  void _showHealthTipsDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancer Prevention Tips"),
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
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }

  Widget _buildTipItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
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
          const SizedBox(height: 5),
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