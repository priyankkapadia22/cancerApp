import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

class UploadScreen extends StatefulWidget {
  final User user;

  UploadScreen({required this.user});

  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> with SingleTickerProviderStateMixin {
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  String? finalPredictionClass;
  double? finalConfidenceScore;
  List<Map<String, dynamic>> individualPredictions = [];
  bool _isUploading = false;
  bool _isAnalyzing = false;
  late AnimationController _animationController;
  
  // Result colors based on prediction
  final Map<String, Color> _resultColors = {
    'benign': Color(0xFF4CAF50),      // Green
    'malignant': Color(0xFFF44336),   // Red
    'normal': Color(0xFF2196F3),      // Blue
    'pre-malignant': Color(0xFFFF9800) // Orange
  };
  
  // Default color if prediction doesn't match any of the above
  final Color _defaultResultColor = Color(0xFF2196F3); // Blue

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80, // Compress image for faster upload
    );
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        finalPredictionClass = null;
        finalConfidenceScore = null;
        individualPredictions.clear();
      });
    }
  }

  Future<String?> uploadImageToFirebase(File imageFile) async {
    try {
      setState(() {
        _isUploading = true;
      });
      
      String fileName = "uploads/${widget.user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg";
      Reference ref = FirebaseStorage.instance.ref().child(fileName);
      UploadTask uploadTask = ref.putFile(imageFile);
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print("❌ Error uploading image: $e");
      return null;
    } finally {
      setState(() {
        _isUploading = false;
        _isAnalyzing = true;
      });
    }
  }

  Future<void> classifyImage() async {
    if (_selectedImage == null) {
      _showErrorSnackbar("Please select an image first!");
      return;
    }

    try {
      // Start the loading animation
      _animationController.repeat();
      
      // First upload to Firebase
      String? imageUrl = await uploadImageToFirebase(_selectedImage!);
      if (imageUrl == null) {
        _showErrorSnackbar("Failed to upload image. Please try again.");
        setState(() {
          _isAnalyzing = false;
        });
        _animationController.stop();
        return;
      }

      // Then send to classification API
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api-wj6u.onrender.com/predict'),
      );
      request.files.add(
        await http.MultipartFile.fromPath('file', _selectedImage!.path),
      );

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var jsonResponse = jsonDecode(responseData);

      print("✅ API Response: $jsonResponse");

      setState(() {
        finalPredictionClass = jsonResponse['final_prediction']['final_predicted_class'];
        finalConfidenceScore = (jsonResponse['final_prediction']['final_confidence'] as num?)?.toDouble() ?? -1;
        individualPredictions = List<Map<String, dynamic>>.from(jsonResponse['individual_model_predictions']);
        _isAnalyzing = false;
      });

      // Save the prediction to Firestore
      await FirebaseFirestore.instance.collection("predictions").add({
        "userId": widget.user.uid,
        "imageUrl": imageUrl,
        "finalPrediction": finalPredictionClass,
        "finalConfidence": finalConfidenceScore,
        "date": DateTime.now().toLocal().toString().split(" ")[0], // Extract date
        "time": DateTime.now().toLocal().toString().split(" ")[1], // Extract time
        "timestamp": FieldValue.serverTimestamp(),
      });
      
      // Show success message
      _showSuccessSnackbar("Image classified successfully!");
    } catch (e) {
      print("❌ Error: $e");
      _showErrorSnackbar("Failed to classify image. Please try again.");
      setState(() {
        _isAnalyzing = false;
      });
    } finally {
      _animationController.stop();
    }
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
  
  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(10),
      ),
    );
  }

  Color _getResultColor() {
    if (finalPredictionClass == null) return _defaultResultColor;
    
    String lowerCasePrediction = finalPredictionClass!.toLowerCase();
    
    // Check if the prediction contains any of our key terms
    for (String key in _resultColors.keys) {
      if (lowerCasePrediction.contains(key)) {
        return _resultColors[key]!;
      }
    }
    
    return _defaultResultColor;
  }

  @override
  Widget build(BuildContext context) {
    final Color resultColor = _getResultColor();
    
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "Cancer Detection",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Theme.of(context).primaryColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
        body: Stack(
          children: [
            // Main content
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Image selection area
                  _buildImageSelectionArea(),
                  
                  // Result area
                  if (finalPredictionClass != null && finalConfidenceScore != null)
                    _buildResultsArea(resultColor),
                  
                  SizedBox(height: 100), // Space for bottom buttons
                ],
              ),
            ),
            
            // Bottom action buttons
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomActionButtons(),
            ),
            
            // Loading overlay
            if (_isUploading || _isAnalyzing)
              _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSelectionArea() {
    return Container(
      margin: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Image container with shadow
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _selectedImage != null
                  ? Image.file(
                      _selectedImage!,
                      height: 300,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      height: 300,
                      width: double.infinity,
                      color: Colors.grey.shade200,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 80,
                            color: Colors.grey.shade400,
                          ),
                          SizedBox(height: 16),
                          Text(
                            "Select an image to classify",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Choose an image from gallery",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          
          SizedBox(height: 16),
          
          // Gallery button only
          ElevatedButton.icon(
            onPressed: pickImage,
            icon: Icon(Icons.photo_library_outlined),
            label: Text(
              "Select from Gallery",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsArea(Color resultColor) {
    return Container(
      margin: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Final prediction card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: resultColor.withOpacity(0.3), width: 1),
            ),
            color: resultColor.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: resultColor.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.biotech_outlined,
                          color: resultColor,
                          size: 28,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Final Prediction",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            Text(
                              finalPredictionClass ?? "Unknown",
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: resultColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: resultColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "${finalConfidenceScore!.toStringAsFixed(2)}", // Removed % symbol, showing raw score (0-1)
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: resultColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: finalConfidenceScore!, // Using raw score (0-1) directly
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(resultColor),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          SizedBox(height: 24),
          
          // Individual predictions section
          Text(
            "Model Predictions",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 12),
          
          // Individual prediction cards
          ...individualPredictions.map((model) => _buildModelPredictionCard(model)).toList(),
        ],
      ),
    );
  }
  
  Widget _buildModelPredictionCard(Map<String, dynamic> model) {
    final double confidence = model['confidence'] as double;
    final String predictedClass = model['predicted_class'] as String;
    
    // Determine color based on prediction
    Color cardColor = _defaultResultColor;
    for (String key in _resultColors.keys) {
      if (predictedClass.toLowerCase().contains(key)) {
        cardColor = _resultColors[key]!;
        break;
      }
    }
    
    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Model: ${model['model']}",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cardColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${confidence.toStringAsFixed(2)}", // Removed % symbol, showing raw score (0-1)
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cardColor,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              "Prediction: $predictedClass",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: confidence, // Using raw score (0-1) directly
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(cardColor),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionButtons() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: (_isUploading || _isAnalyzing || _selectedImage == null) 
              ? null 
              : classifyImage,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor, // Always blue
            padding: EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: Text(
            finalPredictionClass != null ? "Analyze Again" : "Analyze Image",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 100,
                  width: 100,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                    strokeWidth: 3,
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  _isUploading 
                      ? "Uploading Image..." 
                      : "Analyzing Image...",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  _isUploading 
                      ? "Please wait while we upload your image."
                      : "Our AI is analyzing your image for cancer detection.",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}