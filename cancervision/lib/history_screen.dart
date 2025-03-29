import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

class HistoryScreen extends StatefulWidget {
  final String userId;

  HistoryScreen({required this.userId});

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Stream<QuerySnapshot> _predictionsStream;
  String _filterType = "All";
  final List<String> _filterOptions = ["All", "Benign", "Malignant", "Normal", "Pre-malignant"];
  
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
    _initializeStream();
  }
  
  void _initializeStream() {
    _predictionsStream = FirebaseFirestore.instance
        .collection("predictions")
        .where("userId", isEqualTo: widget.userId)
        .orderBy("timestamp", descending: true) // Use timestamp field for better sorting
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Records",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          _buildFilterChips(),
          
          // Results list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _predictionsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState();
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }

                // Filter results based on selected filter
                var docs = snapshot.data!.docs;
                if (_filterType != "All") {
                  docs = docs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>? ?? {};
                    String prediction = (data['finalPrediction'] ?? "").toLowerCase();
                    return prediction.contains(_filterType.toLowerCase());
                  }).toList();
                  
                  if (docs.isEmpty) {
                    return _buildEmptyFilterState();
                  }
                }

                return _buildResultsList(docs);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFilterChips() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filterOptions.map((filter) {
            bool isSelected = _filterType == filter;
            Color chipColor = _defaultResultColor;
            
            // Set color based on filter type
            if (filter != "All") {
              for (var entry in _resultColors.entries) {
                if (filter.toLowerCase() == entry.key) {
                  chipColor = entry.value;
                  break;
                }
              }
            }
            
            return Padding(
              padding: EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(
                  filter,
                  style: GoogleFonts.poppins(
                    color: isSelected ? Colors.white : chipColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _filterType = filter;
                  });
                },
                backgroundColor: Colors.white,
                selectedColor: chipColor,
                checkmarkColor: Colors.white,
                side: BorderSide(
                  color: isSelected ? Colors.transparent : chipColor.withOpacity(0.5),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
  
  Widget _buildLoadingState() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView.builder(
        itemCount: 5,
        itemBuilder: (context, index) {
          return Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(
              height: 200,
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: 16),
          Text(
            "No Records Found",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Your cancer detection history will appear here",
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyFilterState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_list,
            size: 80,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: 16),
          Text(
            "No $_filterType Results",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Try selecting a different filter",
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _filterType = "All";
              });
            },
            child: Text("Show All Records"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).primaryColor,
              side: BorderSide(color: Theme.of(context).primaryColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildResultsList(List<QueryDocumentSnapshot> docs) {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var doc = docs[index];
        var data = doc.data() as Map<String, dynamic>? ?? {};

        String finalPrediction = data['finalPrediction'] ?? "Unknown";
        double finalConfidence = (data['finalConfidence'] as num?)?.toDouble() ?? 0.0;
        
        // Format the date and time
        String dateStr = data['date'] ?? "";
        String timeStr = data['time'] ?? "";
        String formattedDate = "";
        
        try {
          if (data['timestamp'] != null) {
            // If we have a Firestore timestamp, use that
            Timestamp timestamp = data['timestamp'] as Timestamp;
            DateTime dateTime = timestamp.toDate();
            formattedDate = DateFormat('MMM d, yyyy • h:mm a').format(dateTime);
          } else if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
            // Otherwise use the separate date and time fields
            formattedDate = "$dateStr • $timeStr";
          }
        } catch (e) {
          formattedDate = "$dateStr • $timeStr";
        }
        
        String imageUrl = data['imageUrl'] ?? "";
        
        // Determine card color based on prediction
        Color cardColor = _defaultResultColor;
        for (var entry in _resultColors.entries) {
          if (finalPrediction.toLowerCase().contains(entry.key)) {
            cardColor = entry.value;
            break;
          }
        }

        return GestureDetector(
          onTap: () => _showDetailDialog(data),
          child: Container(
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image section
                if (imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    child: Stack(
                      children: [
                        // Image with shimmer loading effect
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: double.infinity,
                          height: 180,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Shimmer.fromColors(
                            baseColor: Colors.grey.shade300,
                            highlightColor: Colors.grey.shade100,
                            child: Container(
                              width: double.infinity,
                              height: 180,
                              color: Colors.white,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: double.infinity,
                            height: 180,
                            color: Colors.grey.shade200,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Colors.grey.shade400,
                              size: 40,
                            ),
                          ),
                        ),
                        
                        // Date overlay
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withOpacity(0.7),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: Text(
                              formattedDate,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // Content section
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  finalPrediction,
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: cardColor,
                                  ),
                                ),
                                if (formattedDate.isEmpty)
                                  Text(
                                    formattedDate,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: cardColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              finalConfidence.toStringAsFixed(2), // Raw score without %
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: cardColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: finalConfidence, // Raw score (0-1)
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(cardColor),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Filter Records",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _filterOptions.map((filter) {
            return RadioListTile<String>(
              title: Text(
                filter,
                style: GoogleFonts.poppins(),
              ),
              value: filter,
              groupValue: _filterType,
              onChanged: (value) {
                setState(() {
                  _filterType = value!;
                });
                Navigator.pop(context);
              },
              activeColor: Theme.of(context).primaryColor,
              dense: true,
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CANCEL"),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
  
  void _showDetailDialog(Map<String, dynamic> data) {
    String finalPrediction = data['finalPrediction'] ?? "Unknown";
    double finalConfidence = (data['finalConfidence'] as num?)?.toDouble() ?? 0.0;
    String imageUrl = data['imageUrl'] ?? "";
    
    // Determine color based on prediction
    Color resultColor = _defaultResultColor;
    for (var entry in _resultColors.entries) {
      if (finalPrediction.toLowerCase().contains(entry.key)) {
        resultColor = entry.value;
        break;
      }
    }
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: double.infinity,
                  height: 250,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 250,
                    color: Colors.grey.shade200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 250,
                    color: Colors.grey.shade200,
                    child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
                  ),
                ),
              ),
            
            // Content
            Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Prediction Result",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    finalPrediction,
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: resultColor,
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Confidence Score",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              finalConfidence.toStringAsFixed(2), // Raw score without %
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: resultColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Date",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              data['date'] ?? "Unknown",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: finalConfidence, // Raw score (0-1)
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(resultColor),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
            
            // Button
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("CLOSE"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
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
}
