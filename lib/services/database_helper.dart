import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../models/doctor.dart';
import '../models/patient_referral.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'hospital_emr.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    // --- Cached Doctors ---
    await db.execute('''
      CREATE TABLE doctors (
        id INTEGER PRIMARY KEY,
        trip_id INTEGER,
        name TEXT NOT NULL,
        contact_number TEXT,
        area TEXT,
        street TEXT,
        city TEXT,
        pin TEXT,
        specialization TEXT,
        degree_qualification TEXT,
        email TEXT,
        remarks TEXT,
        additional_details TEXT,
        additional_expenses TEXT,
        visit_image TEXT,
        visit_lat REAL,
        visit_long REAL,
        created_at TEXT,
        status TEXT,
        is_internal INTEGER DEFAULT 0
      )
    ''');

    // --- Cached Patients (Read-only list caching) ---
    await db.execute('''
      CREATE TABLE patients (
        id TEXT PRIMARY KEY,
        patient_name TEXT,
        age INTEGER,
        gender TEXT,
        phone TEXT,
        illness TEXT,
        description TEXT,
        reported_on TEXT,
        status TEXT,
        is_urgent INTEGER DEFAULT 0,
        referred_by_doctor INTEGER,
        referred_to_doctor INTEGER
      )
    ''');

    // --- Sync Queue (For Offline Submissions) ---
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL, -- e.g., 'CREATE_PATIENT', 'SUBMIT_VISIT'
        payload TEXT NOT NULL, -- JSON formatted data
        created_at TEXT NOT NULL
      )
    ''');
  }

  // ----------------------------------------------------
  // DOCTOR METHODS
  // ----------------------------------------------------

  Future<void> cacheDoctors(List<DoctorReferral> doctors) async {
    final db = await database;
    Batch batch = db.batch();

    // Clear old cache before inserting new ones
    batch.delete('doctors');

    for (var doc in doctors) {
      batch.insert('doctors', {
        'id': doc.id,
        'trip_id': doc.tripId,
        'name': doc.name,
        'contact_number': doc.contactNumber,
        'area': doc.area,
        'street': doc.street,
        'city': doc.city,
        'pin': doc.pin,
        'specialization': doc.specialization,
        'degree_qualification': doc.degreeQualification,
        'email': doc.email,
        'remarks': doc.remarks,
        'additional_details': doc.additionalDetails,
        'additional_expenses': doc.additionalExpenses,
        'visit_image': doc.visitImage,
        'visit_lat': doc.visitLat,
        'visit_long': doc.visitLong,
        'created_at': doc.createdAt.toIso8601String(),
        'status': doc.status,
        'is_internal': doc.isInternal ? 1 : 0,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<DoctorReferral>> getCachedDoctors() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('doctors');

    return maps.map((map) {
      return DoctorReferral(
        id: map['id'],
        tripId: map['trip_id'],
        name: map['name'] ?? '',
        contactNumber: map['contact_number'] ?? '',
        area: map['area'] ?? '',
        street: map['street'],
        city: map['city'],
        pin: map['pin'] ?? '',
        specialization: map['specialization'] ?? '',
        degreeQualification: map['degree_qualification'] ?? "MBBS",
        email: map['email'],
        remarks: map['remarks'],
        additionalDetails: map['additional_details'] ?? '',
        additionalExpenses: map['additional_expenses'],
        visitImage: map['visit_image'],
        visitLat: map['visit_lat'],
        visitLong: map['visit_long'],
        createdAt: DateTime.parse(map['created_at']),
        status: map['status'] ?? 'Assigned',
        isInternal: map['is_internal'] == 1,
      );
    }).toList();
  }

  // ----------------------------------------------------
  // PATIENT METHODS
  // ----------------------------------------------------

  Future<void> cachePatients(List<PatientReferral> patients) async {
    final db = await database;
    Batch batch = db.batch();

    batch.delete('patients');

    for (var p in patients) {
      batch.insert('patients', {
        'id': p.id,
        'patient_name': p.patientName,
        'age': p.age,
        'gender': p.gender,
        'phone': p.phone,
        'illness': p.illness,
        'description': p.description,
        'reported_on': p.reportedOn.toIso8601String(),
        'status': p.status,
        'is_urgent': p.isUrgent ? 1 : 0,
        'referred_by_doctor': p.referredByDoctorId,
        'referred_to_doctor': p.referredToDoctorId,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<PatientReferral>> getCachedPatients() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('patients');

    return maps.map((map) {
      return PatientReferral(
        id: map['id'],
        patientName: map['patient_name'] ?? '',
        age: map['age'] ?? 0,
        gender: map['gender'] ?? '',
        phone: map['phone'] ?? '',
        illness: map['illness'] ?? '',
        description: map['description'] ?? '',
        reportedOn: DateTime.parse(map['reported_on']),
        status: map['status'] ?? 'Pending',
        isUrgent: map['is_urgent'] == 1,
        referredByDoctorId: map['referred_by_doctor'],
        referredToDoctorId: map['referred_to_doctor'],
      );
    }).toList();
  }

  // ----------------------------------------------------
  // SYNC QUEUE METHODS
  // ----------------------------------------------------

  Future<int> enqueueSyncAction(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final db = await database;
    return await db.insert('sync_queue', {
      'action': action,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final db = await database;
    final maps = await db.query('sync_queue', orderBy: 'created_at ASC');
    // Decode JSON strings back to Maps
    return maps.map((row) {
      final map = Map<String, dynamic>.from(row);
      map['payload'] = jsonDecode(row['payload'] as String);
      return map;
    }).toList();
  }

  Future<void> deleteSyncQueueItem(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateSyncQueueTripIds(int tempTripId, int realTripId) async {
    final db = await database;
    final maps = await db.query('sync_queue');
    for (var row in maps) {
      final payloadStr = row['payload'] as String;
      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
      bool changed = false;

      // CREATE_DOCTOR_REFERRAL stores tripId at top level
      if (payload.containsKey('tripId') && payload['tripId'] == tempTripId) {
        payload['tripId'] = realTripId;
        changed = true;
      }

      // UPDATE_DOCTOR_REFERRAL stores trip inside payload['data']['trip']
      if (payload.containsKey('data') && payload['data'] is Map) {
        final data = Map<String, dynamic>.from(payload['data'] as Map);
        final storedTrip = data['trip'];
        if (storedTrip != null &&
            int.tryParse(storedTrip.toString()) == tempTripId) {
          data['trip'] = realTripId;
          payload['data'] = data;
          changed = true;
        }
      }

      if (changed) {
        await db.update(
          'sync_queue',
          {'payload': jsonEncode(payload)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }
}
