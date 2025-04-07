import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatbotScreen extends StatefulWidget {
  @override
  _ChatbotScreenState createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _isConnected = false;

  // API URL - Use your PC's actual IP address
  final String apiUrl = "https://cancer-chatbot-ij32.onrender.com/chat";

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _testConnection(); // Test connection on startup
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Test connection to server
  Future<void> _testConnection() async {
    try {
      final baseUrl = apiUrl.substring(0, apiUrl.lastIndexOf('/'));
      final response = await http.get(
        Uri.parse(baseUrl),
      ).timeout(Duration(seconds: 5));
      
      setState(() {
        _isConnected = response.statusCode == 200;
      });
      
      print("Connection test to $baseUrl: ${response.statusCode}");
      
      if (_isConnected) {
        print("✅ Connection successful!");
      } else {
        print("⚠️ Server returned status: ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
      });
      print("❌ Connection test failed: $e");
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatHistory = prefs.getStringList('chat_history') ?? [];
      
      if (chatHistory.isNotEmpty) {
        setState(() {
          for (String message in chatHistory) {
            final Map<String, dynamic> messageData = json.decode(message);
            _messages.add(ChatMessage(
              text: messageData['text'],
              isUser: messageData['isUser'],
              timestamp: DateTime.parse(messageData['timestamp']),
            ));
          }
        });
        _scrollToBottom();
      } else {
        // Only add the welcome message if there's no chat history
        _addBotMessage(
          "Hello! I'm your CancerVision AI assistant. How can I help you today?",
        );
      }
    } catch (e) {
      print("Error loading chat history: $e");
      // If there's an error loading chat history, add the welcome message
      if (_messages.isEmpty) {
        _addBotMessage(
          "Hello! I'm your CancerVision AI assistant. How can I help you today?",
        );
      }
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> chatHistory = [];
      
      // Limit history size to prevent excessive storage use
      final messagesToSave = _messages.length > 100 
          ? _messages.sublist(_messages.length - 100) 
          : _messages;
      
      for (ChatMessage message in messagesToSave) {
        chatHistory.add(json.encode({
          'text': message.text,
          'isUser': message.isUser,
          'timestamp': message.timestamp.toIso8601String(),
        }));
      }
      
      await prefs.setStringList('chat_history', chatHistory);
    } catch (e) {
      print("Error saving chat history: $e");
    }
  }

  void _addUserMessage(String message) {
    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isUser: true,
        timestamp: DateTime.now(),
      ));
    });
    _saveChatHistory();
    _scrollToBottom();
  }

  void _addBotMessage(String message) {
    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
    _saveChatHistory();
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final userMessage = _messageController.text.trim();
    _addUserMessage(userMessage);
    _messageController.clear();

    // Set typing indicator
    setState(() {
      _isTyping = true;
    });

    print("Sending request to: $apiUrl");
    print("Request body: ${json.encode({"query": userMessage})}");

    try {
      // Call your backend API with increased timeout
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "query": userMessage,  
        }),
      ).timeout(Duration(seconds: 60)); // Longer timeout for LLM processing

      // Debug log
      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");

      setState(() {
        _isTyping = false;
        _isConnected = true; // Connection worked
      });

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          if (data.containsKey('response')) {
            _addBotMessage(data['response']);
          } else {
            print("Unexpected response format: $data");
            _addBotMessage("I received a response but couldn't understand it. Please try again.");
          }
        } catch (e) {
          print("JSON parsing error: $e");
          _addBotMessage("I received a response but couldn't parse it properly. Please try again.");
        }
      } else {
        // More specific error message based on status code
        if (response.statusCode == 503) {
          _addBotMessage(
            "The service is temporarily unavailable. Please try again later.",
          );
        } else {
          _addBotMessage(
            "I encountered an error (${response.statusCode}). Please try again later.",
          );
        }
        print("API Error: Status ${response.statusCode}, Body: ${response.body}");
      }
    } catch (e) {
      setState(() {
        _isTyping = false;
        _isConnected = false; // Connection failed
      });
      
      String errorMessage = "I'm having trouble connecting to my servers. Please try again later.";
      
      if (e.toString().contains("SocketException")) {
        errorMessage = "Network connection error. Please check that your device and the server (192.168.231.90) are on the same network.";
      } else if (e.toString().contains("TimeoutException")) {
        errorMessage = "The server took too long to respond. This might be due to high processing demand or connection issues.";
      } else if (e.toString().contains("FormatException")) {
        errorMessage = "I received a response but couldn't understand it. Please try again.";
      }
      
      _addBotMessage(errorMessage);
      print("API Error: $e");
    }
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              radius: 16,
              child: Icon(
                Icons.medical_services_outlined,
                color: Theme.of(context).primaryColor,
                size: 18,
              ),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "CancerVision AI",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: const Color.fromARGB(255, 204, 195, 195)
                  ),
                ),
                Text(
                  _isConnected ? "Connected" : "Disconnected",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: _isConnected 
                        ? Colors.white.withOpacity(0.8) 
                        : Colors.red.shade300,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        actions: [
          // Add a test connection button
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _testConnection,
            color: Colors.grey.shade100,
            tooltip: "Test connection",
          ),
          IconButton(
            
            icon: Icon(Icons.delete_outline),
            onPressed: _showClearChatDialog,
            tooltip: "Clear chat",
            color: Colors.grey.shade100
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
        ),
        child: Column(
          children: [
            // Connection status banner
            if (!_isConnected)
              Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: Colors.red.shade100,
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Not connected to server at 192.168.231.90. Make sure both devices are on the same network.",
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _testConnection,
                      child: Text("RETRY"),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade900,
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size(0, 0),
                      ),
                    )
                  ],
                ),
              ),
              
            // Chat messages area
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return _buildMessageBubble(message);
                },
              ),
            ),
            
            // Typing indicator
            if (_isTyping)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    _buildTypingIndicator(),
                    SizedBox(width: 10),
                    Text(
                      "AI is typing...",
                      style: GoogleFonts.poppins(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            
            // Input area
            Container(
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
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: "Type a message...",
                            hintStyle: GoogleFonts.poppins(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                          ),
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              _sendMessage();
                            }
                          },
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(Icons.send_rounded),
                        color: Colors.white,
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    final time = DateFormat('h:mm a').format(message.timestamp);
    
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              radius: 16,
              child: Icon(
                Icons.medical_services_outlined,
                color: Colors.white,
                size: 16,
              ),
            ),
            SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser 
                    ? Theme.of(context).primaryColor
                    : Colors.white,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomLeft: isUser ? Radius.circular(20) : Radius.circular(0),
                  bottomRight: isUser ? Radius.circular(0) : Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(  // Changed to SelectableText for copy functionality
                    message.text,
                    style: GoogleFonts.poppins(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    time,
                    style: GoogleFonts.poppins(
                      color: isUser 
                          ? Colors.white.withOpacity(0.7) 
                          : Colors.grey.shade500,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
          ),
          
          if (isUser) ...[
            SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.grey.shade300,
              radius: 16,
              child: Icon(
                Icons.person,
                color: Colors.grey.shade700,
                size: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildTypingIndicator() {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (index) => Container(
            margin: EdgeInsets.symmetric(horizontal: 2),
            height: 8,
            width: 8,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: _buildPulseAnimation(
              duration: Duration(milliseconds: 1000 + (index * 200)),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildPulseAnimation({required Duration duration}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: duration,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
  
  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Clear Chat History"),
        content: Text(
          "Are you sure you want to clear all chat messages? This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _messages.clear();
                _addBotMessage(
                  "Hello! I'm your CancerVision AI assistant. How can I help you today?",
                );
              });
              _saveChatHistory();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text("CLEAR"),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}
