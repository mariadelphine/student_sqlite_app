import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite for Chrome.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  runApp(const StudentApp());
}

// ==================== MAIN APP ====================

class StudentApp extends StatelessWidget {
  const StudentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Student Records',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const StudentHomePage(),
    );
  }
}

// ==================== DATABASE HELPER ====================

class StudentDatabase {
  StudentDatabase._();

  static final StudentDatabase instance = StudentDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    final String dbPath;

    if (kIsWeb) {
      // The web database uses browser storage.
      dbPath = 'students.db';
    } else {
      dbPath = path.join(await getDatabasesPath(), 'students.db');
    }

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE students (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            registerNo TEXT NOT NULL UNIQUE,
            department TEXT NOT NULL
          )
        ''');
      },
    );

    return _database!;
  }

  // CREATE operation.
  Future<int> insertStudent({
    required String name,
    required String registerNo,
    required String department,
  }) async {
    final db = await database;

    return db
        .insert('students', {
          'name': name,
          'registerNo': registerNo,
          'department': department,
        }, conflictAlgorithm: ConflictAlgorithm.abort)
        .timeout(const Duration(seconds: 20));
  }

  // READ operation.
  Future<List<Map<String, Object?>>> getStudents() async {
    final db = await database;

    return db
        .query('students', orderBy: 'id DESC')
        .timeout(const Duration(seconds: 20));
  }
}

// ==================== STUDENT HOME PAGE ====================

class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _registerController = TextEditingController();
  final _departmentController = TextEditingController();

  List<Map<String, Object?>> _students = [];

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _registerController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  // READ: Load all student records.
  Future<void> _loadStudents() async {
    try {
      final records = await StudentDatabase.instance.getStudents();

      if (!mounted) return;

      setState(() {
        _students = records;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('LOAD ERROR: $e');
      debugPrint('ERROR TYPE: ${e.runtimeType}');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Unable to load students: $e');
    }
  }

  // CREATE: Save a student record.
  Future<void> _addStudent() async {
    if (_isSaving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await StudentDatabase.instance.insertStudent(
        name: _nameController.text.trim(),
        registerNo: _registerController.text.trim(),
        department: _departmentController.text.trim(),
      );

      if (!mounted) return;

      _nameController.clear();
      _registerController.clear();
      _departmentController.clear();

      await _loadStudents();

      if (mounted) {
        _showMessage('Student saved successfully!');
      }
    } on TimeoutException catch (e) {
      debugPrint('DATABASE TIMEOUT: $e');
      _showMessage('Database timed out. Check the Chrome SQLite setup.');
    } on DatabaseException catch (e) {
      debugPrint('DATABASE ERROR: $e');

      if (e.isUniqueConstraintError()) {
        _showMessage('This register number already exists.');
      } else {
        _showMessage('Database error: $e');
      }
    } catch (e, stackTrace) {
      debugPrint('SAVE ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);
      _showMessage('Unable to save student: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  // ==================== USER INTERFACE ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Record Management'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Student input form.
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Add Student',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Student Name',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter student name';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _registerController,
                        decoration: const InputDecoration(
                          labelText: 'Register Number',
                          prefixIcon: Icon(Icons.badge),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter register number';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _departmentController,
                        decoration: const InputDecoration(
                          labelText: 'Department',
                          prefixIcon: Icon(Icons.school),
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter department';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        height: 46,
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _addStudent,
                          icon: Icon(
                            _isSaving ? Icons.hourglass_top : Icons.save,
                          ),
                          label: Text(_isSaving ? 'Saving...' : 'Save Student'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Saved students heading and refresh button.
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved Students (${_students.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh records',
                  onPressed: _isLoading ? null : _loadStudents,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),

            const SizedBox(height: 8),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_students.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('No student records yet. Add one above.'),
                  ),
                ),
              )
            else
              ..._students.map((student) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${student['id']}')),
                    title: Text('${student['name']}'),
                    subtitle: Text(
                      'Register No: ${student['registerNo']}\n'
                      'Department: ${student['department']}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.storage, color: Colors.indigo),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
