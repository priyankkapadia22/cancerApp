import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _database;

  // ✅ Initialize Database
  static Future<Database> getDatabase() async {
    if (_database != null) return _database!;

    _database = await openDatabase(
      join(await getDatabasesPath(), 'user.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          "CREATE TABLE user(id TEXT PRIMARY KEY, email TEXT, username TEXT)",
        );
      },
    );

    return _database!;
  }

  // ✅ Save User Data in SQLite
  static Future<void> saveUser(String id, String email, String username) async {
    try {
      final db = await getDatabase();
      await db.insert(
        'user',
        {'id': id, 'email': email, 'username': username},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print("Error saving user: $e");
    }
  }

  // ✅ Get Logged-in User
  static Future<Map<String, String>?> getUser() async {
    try {
      final db = await getDatabase();
      List<Map<String, dynamic>> users = await db.query('user');

      if (users.isNotEmpty) {
        return {
          "id": users.first["id"],
          "email": users.first["email"],
          "username": users.first["username"],
        };
      }
    } catch (e) {
      print("Error fetching user: $e");
    }
    return null;
  }

  // ✅ Clear User Data (Logout)
  static Future<void> deleteUser() async {
    try {
      final db = await getDatabase();
      await db.delete('user');
      await db.close(); // ✅ Close database to free up resources
      _database = null; // ✅ Reset _database to force reinitialization on next login
    } catch (e) {
      print("Error deleting user: $e");
    }
  }
}