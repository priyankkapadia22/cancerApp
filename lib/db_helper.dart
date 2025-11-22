import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Define your User model structure
class User {
  final String id;
  final String email;
  final String displayName;
  final String photoUrl;

  User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.photoUrl,
  });

  // Convert a User object into a Map for the database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
    };
  }

  // Extract a User object from a Map from the database
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      email: map['email'],
      displayName: map['displayName'],
      photoUrl: map['photoUrl'],
    );
  }
}

class DatabaseHelper {
  // --- Singleton Setup ---
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  // --- Database Initialization ---
  static Database? _database;
  final String tableName = 'users';


  Future<Database?> get database async {
    if (kIsWeb) {
      return null;
    }
    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'app_database.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      // You might use onUpgrade for schema changes in future versions
    );
  }

  // --- Table Creation ---
  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id TEXT PRIMARY KEY,
        email TEXT,
        displayName TEXT,
        photoUrl TEXT
      )
    ''');
  }

  // --- CRUD Operations ---

  // Insert a new user or replace existing one (useful for sign-in/update)
  Future<void> insertUser(User user) async {
    final db = await database;
    if (db == null) return;
    await db.insert(
      tableName,
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get the current user (assuming only one user is logged in locally)
  Future<User?> getSingleUser() async {
    final db = await database;
    if (db == null) return null;
    final List<Map<String, dynamic>> maps = await db!.query(tableName, limit: 1);

    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  // Update a user's details
  Future<int> updateUser(User user) async {
    final db = await database;
    if (db == null) return 0;
    return await db!.update(
      tableName,
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  // Delete all users (useful for sign-out)
  Future<void> deleteUser(String id) async {
    final db = await database;
    if (db == null) return;
    await db!.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  // Optional: Delete ALL data from the table (useful for full logout/reset)
  Future<void> clearTable() async {
    final db = await database;
    if (db == null) return;
    await db!.delete(tableName);
  }
}