import 'dart:convert';
import 'dart:io';
import 'dart:math' show asin, cos, sqrt;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import '../models/doctor.dart';
import '../models/patient_referral.dart';
import '../models/trip.dart';
import 'database_helper.dart';

class ApiService {
  // Use http://127.0.0.1:8000 for Windows/Web
  // Use http://10.0.2.2:8000 for Android Emulator
  // Use ngrok for physical devices
  static const String baseUrl =
      'https://definite-toucan-highly.ngrok-free.app/api';

  static String? _authToken;
  static String? _userRole; // 'advisor', 'maintenance', 'admin'
  static String? _username;

  static bool get isAuthenticated => _authToken != null;
  static String? get userRole => _userRole;
  static String? get username => _username;

  // --- Session Persistence ---
  static Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', _authToken ?? '');
    await prefs.setString('user_role', _userRole ?? '');
    await prefs.setString('auth_username', _username ?? '');
  }

  static Future<bool> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('auth_token');
    _userRole = prefs.getString('user_role');
    _username = prefs.getString('auth_username');

    // Check if token is valid (non-null and non-empty)
    if (_authToken != null && _authToken!.isNotEmpty) {
      return true;
    }
    // Clear invalid session data
    _authToken = null;
    _userRole = null;
    _username = null;
    return false;
  }

  static Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_role');
    await prefs.remove('auth_username');
  }

  // --- API Caching Helpers ---
  static Future<void> _cacheApiResponse(String key, String data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_cache_$key', data);
  }

  static Future<String?> _getCachedApiResponse(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_cache_$key');
  }

  static Future<void> _clearCachedApiResponse(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('api_cache_$key');
  }

  static Future<String> _getAppDocumentsPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// Returns true if the device has a real network connection.
  static Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result.isNotEmpty && result.first != ConnectivityResult.none;
  }

  // --- Authentication ---
  static Future<bool> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api-token-auth/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _authToken = data['token'];
        _username = data['username'] ?? username;
        _userRole = data['role']; // Role now comes from the API!
        await _saveSession();
        return true;
      }
      return false;
    } catch (e) {
      print('Login Error: $e');
      return false;
    }
  }

  static Future<void> logout() async {
    _authToken = null;
    _userRole = null;
    _username = null;
    await _clearSession();
  }

  // Role is now returned directly from the login API response

  /// Fetch all doctors from master table for dropdown selection
  static Future<List<DoctorReferral>> fetchAllDoctors() async {
    if (_authToken == null) return [];

    final dbHelper = DatabaseHelper();

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/doctor-referrals/master/'),
            headers: {
              'Authorization': 'Token $_authToken',
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final doctors = data
            .map((json) => DoctorReferral.fromJson(json))
            .toList();
        // Cache them locally
        await dbHelper.cacheDoctors(doctors);
        return doctors;
      }
    } catch (e) {
      print('Fetch All Doctors Error (Offline?): $e');
    }

    // Fallback: Return cached data
    print('Returning cached doctors fallback');
    return await dbHelper.getCachedDoctors();
  }

  /// Fetch all specializations for dropdown selection
  static Future<List<Map<String, dynamic>>> fetchSpecializations() async {
    if (_authToken == null) return [];
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/specializations/'),
            headers: {
              'Authorization': 'Token $_authToken',
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Cache the raw JSON string
        await _cacheApiResponse('specializations', response.body);

        final List<dynamic> data = json.decode(response.body);
        return data
            .map((item) => {'id': item['id'], 'name': item['name'] as String})
            .toList();
      }
    } catch (e) {
      print('Fetch Specializations Error (Offline?): $e');
    }

    // Fallback to cache
    final cached = await _getCachedApiResponse('specializations');
    if (cached != null) {
      print('Returning cached specializations fallback');
      final List<dynamic> data = json.decode(cached);
      return data
          .map((item) => {'id': item['id'], 'name': item['name'] as String})
          .toList();
    }
    return [];
  }

  /// Fetch all qualifications for dropdown selection
  static Future<List<Map<String, dynamic>>> fetchQualifications() async {
    if (_authToken == null) return [];
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/qualifications/'),
            headers: {
              'Authorization': 'Token $_authToken',
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Cache the raw JSON string
        await _cacheApiResponse('qualifications', response.body);

        final List<dynamic> data = json.decode(response.body);
        return data
            .map((item) => {'id': item['id'], 'name': item['name'] as String})
            .toList();
      }
    } catch (e) {
      print('Fetch Qualifications Error (Offline?): $e');
    }

    // Fallback to cache
    final cached = await _getCachedApiResponse('qualifications');
    if (cached != null) {
      print('Returning cached qualifications fallback');
      final List<dynamic> data = json.decode(cached);
      return data
          .map((item) => {'id': item['id'], 'name': item['name'] as String})
          .toList();
    }
    return [];
  }

  // --- Tasks ---
  static Future<List<Task>> fetchTasks() async {
    if (_authToken == null) return [];
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/tasks/'),
            headers: {
              'Authorization': 'Token $_authToken',
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await _cacheApiResponse('tasks', response.body);
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Task.fromJson(json)).toList();
      }
    } catch (e) {
      print('Fetch Tasks Error (Offline?): $e');
    }

    final cached = await _getCachedApiResponse('tasks');
    if (cached != null) {
      final List<dynamic> data = json.decode(cached);
      return data.map((json) => Task.fromJson(json)).toList();
    }
    return [];
  }

  static Future<Task?> createTask(Task task) async {
    if (_authToken == null) return null;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/tasks/'),
        headers: {
          'Authorization': 'Token $_authToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(task.toJson()),
      );
      if (response.statusCode == 201) {
        return Task.fromJson(json.decode(response.body));
      }
      return null;
    } catch (e) {
      print('Create Task Error: $e');
      return null;
    }
  }

  static Future<bool> updateTaskStatus(String taskId, String newStatus) async {
    if (_authToken == null) return false;
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/tasks/$taskId/'),
        headers: {
          'Authorization': 'Token $_authToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({'status': newStatus}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update Task Error: $e');
      return false;
    }
  }

  static Future<bool> deleteTask(String taskId) async {
    if (_authToken == null) return false;
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/tasks/$taskId/'),
        headers: {
          'Authorization': 'Token $_authToken',
          'Content-Type': 'application/json',
        },
      );
      return response.statusCode == 204;
    } catch (e) {
      print('Delete Task Error: $e');
      return false;
    }
  }

  // --- Trip Management ---
  static Future<Trip?> fetchCurrentTrip() async {
    if (_authToken == null) return null;
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/trips/current/'),
        headers: {
          'Authorization': 'Token $_authToken',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        if (response.body == 'null' || response.body.isEmpty) return null;
        await _cacheApiResponse('current_trip', response.body);
        return Trip.fromJson(json.decode(response.body));
      }
    } catch (e) {
      print('Fetch Current Trip Error (Offline?): $e');
    }

    final cached = await _getCachedApiResponse('current_trip');
    if (cached != null && cached != 'null' && cached.isNotEmpty) {
      try {
        return Trip.fromJson(json.decode(cached));
      } catch (e) {
        print("Mismatched cached format for current_trip: $e");
      }
    }
    return null;
  }

  static Future<Trip?> fetchTripById(int id) async {
    if (_authToken == null) return null;
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/trips/$id/'),
        headers: {
          'Authorization': 'Token $_authToken',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        await _cacheApiResponse('trip_$id', response.body);
        return Trip.fromJson(json.decode(response.body));
      }
    } catch (e) {
      print('Fetch Trip By ID Error (Offline?): $e');
    }

    final cached = await _getCachedApiResponse('trip_$id');
    if (cached != null) {
      return Trip.fromJson(json.decode(cached));
    }
    return null;
  }

  static Future<List<Trip>> fetchTrips() async {
    if (_authToken == null) return [];
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/trips/'),
        headers: {
          'Authorization': 'Token $_authToken',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final newTrips = data.map((j) => Trip.fromJson(j)).toList();
        final newTripIds = newTrips.map((t) => t.id).toSet();

        // Clear stale individual trip caches for deleted trips
        final oldCached = await _getCachedApiResponse('trips');
        if (oldCached != null) {
          try {
            final oldData = json.decode(oldCached) as List<dynamic>;
            for (final oldTrip in oldData) {
              final oldId = oldTrip['id'];
              if (oldId != null && !newTripIds.contains(oldId)) {
                await _clearCachedApiResponse('trip_$oldId');
                print('Cleared stale cache for deleted trip $oldId');
              }
            }
          } catch (_) {}
        }

        // If current_trip was deleted, clear it too
        final cachedCurrent = await _getCachedApiResponse('current_trip');
        if (cachedCurrent != null) {
          try {
            final currentTrip = json.decode(cachedCurrent);
            final currentId = currentTrip['id'];
            if (currentId != null && !newTripIds.contains(currentId)) {
              await _clearCachedApiResponse('current_trip');
              print('Cleared stale cache for deleted current_trip $currentId');
            }
          } catch (_) {}
        }

        await _cacheApiResponse('trips', response.body);
        return newTrips;
      }
    } catch (e) {
      print('Fetch Trips Error (Offline?): $e');
    }

    final cached = await _getCachedApiResponse('trips');
    if (cached != null) {
      final List<dynamic> data = json.decode(cached);
      return data.map((json) => Trip.fromJson(json)).toList();
    }
    return [];
  }

  static Future<Trip?> startTrip(
    String? odometerStartPath, {
    double? lat,
    double? long,
    bool isSync = false,
  }) async {
    if (_authToken == null) return null;
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/trips/'));
      request.headers['Authorization'] = 'Token $_authToken';

      if (lat != null) request.fields['start_lat'] = lat.toString();
      if (long != null) request.fields['start_long'] = long.toString();

      print('Starting Trip with Lat: $lat, Long: $long');

      if (odometerStartPath != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'odometer_start_image',
            odometerStartPath,
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        return Trip.fromJson(json.decode(response.body));
      } else {
        print('Start Trip Failed: ${response.statusCode}');
        print('Response Body: ${response.body}');
      }
    } catch (e) {
      print('Start Trip Error: $e');
      if (!isSync) {
        print('Queueing Start Trip for offline sync...');
        // Generate a temporary integer ID for the trip to be used locally
        final tempTripId = DateTime.now().millisecondsSinceEpoch % 1000000;

        final payload = {
          'tempTripId': tempTripId,
          'odometerStartPath': odometerStartPath,
          'lat': lat,
          'long': long,
        };
        await DatabaseHelper().enqueueSyncAction('START_TRIP', payload);

        // Return a dummy Trip so the UI can navigate to TripDashboardScreen
        return Trip(
          id: tempTripId,
          tripNumber: 0, // Gets overridden visually or ignored
          status: 'ONGOING',
          startTime: DateTime.now(),
        );
      }
    }
    return null;
  }

  static Future<Trip?> endTrip(
    int tripId,
    double kilometers,
    String expenses,
    String? odometerEndPath, {
    double? lat,
    double? long,
    bool isSync = false,
  }) async {
    if (_authToken == null) return null;
    try {
      var request = http.MultipartRequest(
        'PATCH',
        Uri.parse('$baseUrl/trips/$tripId/end_trip/'),
      );
      request.headers['Authorization'] = 'Token $_authToken';

      request.fields['total_kilometers'] = kilometers.toString();
      request.fields['additional_expenses'] = expenses;
      if (lat != null) request.fields['end_lat'] = lat.toString();
      if (long != null) request.fields['end_long'] = long.toString();

      print('Ending Trip with Lat: $lat, Long: $long');

      if (odometerEndPath != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'odometer_end_image',
            odometerEndPath,
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return Trip.fromJson(json.decode(response.body));
      }
    } catch (e) {
      print('End Trip Error: $e');

      if (!isSync) {
        print('Queueing End Trip for offline sync...');
        final payload = {
          'tripId': tripId,
          'kilometers': kilometers,
          'expenses': expenses,
          'odometerEndPath': odometerEndPath,
          'lat': lat,
          'long': long,
        };
        await DatabaseHelper().enqueueSyncAction('END_TRIP', payload);

        // Optimistically return a dummy updated trip to satisfy the UI
        return Trip(
          id: tripId,
          tripNumber: 0,
          status: 'COMPLETED',
          startTime: DateTime.now(),
          totalKilometers: kilometers,
        );
      }
    }
    return null;
  }

  static Future<bool> addOvernightStay(
    int tripId,
    String name,
    String address,
    String billPath,
    double? lat,
    double? long,
  ) async {
    if (_authToken == null) return false;
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/overnight-stays/'),
      );
      request.headers['Authorization'] = 'Token $_authToken';

      request.fields['trip'] = tripId.toString();
      request.fields['hotel_name'] = name;
      request.fields['hotel_address'] = address;
      if (lat != null) request.fields['latitude'] = lat.toString();
      if (long != null) request.fields['longitude'] = long.toString();
      request.files.add(
        await http.MultipartFile.fromPath('bill_image', billPath),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      return response.statusCode == 201;
    } catch (e) {
      print('Add Overnight Stay Error: $e');
      return false;
    }
  }

  // --- Doctor Referrals ---

  /// Search doctors by name for autocomplete
  static Future<List<DoctorReferral>> searchDoctors(String query) async {
    if (_authToken == null || query.isEmpty) return [];
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/doctor-referrals/?search=$query'),
        headers: {
          'Authorization': 'Token $_authToken',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => DoctorReferral.fromJson(json)).toList();
      }
    } catch (e) {
      print('Search Doctors Error: $e');
    }
    return [];
  }

  // Updated to just fetch simple list (maybe for history) or specific to trip
  static Future<List<DoctorReferral>> fetchDoctorReferrals() async {
    if (_authToken == null) return [];
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/doctor-referrals/'),
        headers: {
          'Authorization': 'Token $_authToken',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        await _cacheApiResponse('doctor_referrals', response.body);
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => DoctorReferral.fromJson(json)).toList();
      }
    } catch (e) {
      print('Fetch Doctor Referrals Error (Offline?): $e');
    }

    final cached = await _getCachedApiResponse('doctor_referrals');
    if (cached != null) {
      final List<dynamic> data = json.decode(cached);
      return data.map((json) => DoctorReferral.fromJson(json)).toList();
    }
    return [];
  }

  static Future<bool> createDoctorReferral(
    DoctorReferral referral,
    int tripId, {
    String? imagePath,
    double? lat,
    double? long,
    bool isSync = false,
  }) async {
    if (_authToken == null) return false;

    // Pre-check connectivity — skip HTTP entirely when offline (avoids long hangs)
    if (!isSync && !(await _isOnline())) {
      return _queueCreateDoctorReferral(
        referral,
        tripId,
        imagePath: imagePath,
        lat: lat,
        long: long,
      );
    }

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/doctor-referrals/'),
      );
      request.headers['Authorization'] = 'Token $_authToken';

      request.fields['trip'] = tripId.toString();
      request.fields['name'] = referral.name;
      request.fields['contact_number'] = referral.contactNumber;
      request.fields['area'] = referral.area;
      request.fields['street'] = referral.street ?? '';
      request.fields['city'] = referral.city ?? '';
      request.fields['pin'] = referral.pin;
      request.fields['specialization'] = referral.specialization;
      request.fields['degree_qualification'] = referral.degreeQualification;
      request.fields['email'] = referral.email ?? '';
      request.fields['remarks'] = referral.remarks ?? '';
      request.fields['additional_details'] = referral.additionalDetails;
      request.fields['status'] = referral.status;

      if (lat != null) request.fields['visit_lat'] = lat.toString();
      if (long != null) request.fields['visit_long'] = long.toString();

      print('Doctor Visit Lat: $lat, Long: $long');

      if (imagePath != null) {
        request.files.add(
          await http.MultipartFile.fromPath('visit_image', imagePath),
        );
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        return true;
      } else {
        print('Create Doctor Referral Failed: ${response.statusCode}');
        print('Body: ${response.body}');
        if (!isSync) {
          // Server rejected — queue for later retry rather than silently dropping
          // (e.g. temporary 500 error)
        }
        return false;
      }
    } catch (e) {
      print('Create Doctor Referral Error: $e');
      if (!isSync) {
        return _queueCreateDoctorReferral(
          referral,
          tripId,
          imagePath: imagePath,
          lat: lat,
          long: long,
        );
      }
      return false;
    }
  }

  /// Extracted offline-queue logic for createDoctorReferral.
  static Future<bool> _queueCreateDoctorReferral(
    DoctorReferral referral,
    int tripId, {
    String? imagePath,
    double? lat,
    double? long,
  }) async {
    print('Queueing doctor referral for offline sync...');

    String? persistentImagePath = imagePath;
    if (imagePath != null) {
      try {
        final appDir = await _getAppDocumentsPath();
        final fileName =
            'offline_visit_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final destPath = '$appDir/$fileName';
        await File(imagePath).copy(destPath);
        persistentImagePath = destPath;
        print('Offline image saved permanently: $destPath');
      } catch (imgErr) {
        print('Could not persist offline image: $imgErr');
      }
    }

    final payload = {
      'referral': referral.toJson(),
      'tripId': tripId,
      'imagePath': persistentImagePath,
      'lat': lat,
      'long': long,
    };
    await DatabaseHelper().enqueueSyncAction('CREATE_DOCTOR_REFERRAL', payload);

    // Optimistic UI update
    try {
      final cachedTripStr = await _getCachedApiResponse('trip_$tripId');
      if (cachedTripStr != null) {
        final tripData = json.decode(cachedTripStr);
        final refs = List<dynamic>.from(tripData['doctor_referrals'] ?? []);
        final dummyRef = referral.toJson();
        dummyRef['id'] = DateTime.now().millisecondsSinceEpoch;
        dummyRef['trip'] = tripId;
        dummyRef['status'] = 'Referred';
        dummyRef['created_at'] = DateTime.now().toIso8601String();
        refs.insert(0, dummyRef);
        tripData['doctor_referrals'] = refs;
        await _cacheApiResponse('trip_$tripId', json.encode(tripData));
      }
    } catch (e) {
      print('Optimistic cache error: $e');
    }
    return true;
  }

  static Future<bool> updateDoctorReferral(
    int id,
    Map<String, dynamic> data, {
    String? imagePath,
    bool isSync = false,
  }) async {
    if (_authToken == null) return false;

    // Pre-check connectivity — skip HTTP entirely when offline
    if (!isSync && !(await _isOnline())) {
      return _queueUpdateDoctorReferral(id, data, imagePath: imagePath);
    }

    try {
      // Use MultipartRequest for updates if image is present or to keep consistency
      var request = http.MultipartRequest(
        'PATCH',
        Uri.parse('$baseUrl/doctor-referrals/$id/'),
      );
      request.headers['Authorization'] = 'Token $_authToken';

      data.forEach((key, value) {
        if (value != null) {
          request.fields[key] = value.toString();
        }
      });

      if (imagePath != null) {
        request.files.add(
          await http.MultipartFile.fromPath('visit_image', imagePath),
        );
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        // Also update local cache so the UI refreshes immediately
        try {
          final tripIdRaw = data['trip'];
          if (tripIdRaw != null) {
            final tripId = int.tryParse(tripIdRaw.toString());
            if (tripId != null) {
              final cachedTripStr = await _getCachedApiResponse('trip_$tripId');
              if (cachedTripStr != null) {
                final tripData = json.decode(cachedTripStr);
                final refs = List<dynamic>.from(
                  tripData['doctor_referrals'] ?? [],
                );
                final idx = refs.indexWhere((r) => r['id'] == id);
                if (idx >= 0) {
                  // Merge the updated data over the existing record
                  final existing = Map<String, dynamic>.from(refs[idx]);
                  data.forEach((key, value) {
                    if (value != null) existing[key] = value;
                  });
                  if (imagePath != null) {
                    existing['visit_image'] = imagePath;
                  }
                  refs[idx] = existing;
                  tripData['doctor_referrals'] = refs;
                  await _cacheApiResponse(
                    'trip_$tripId',
                    json.encode(tripData),
                  );
                }
              }
            }
          }
        } catch (cacheErr) {
          print('Synchronous cache update error: $cacheErr');
        }
        return true;
      } else {
        print('Update Doctor Referral Failed: ${response.statusCode}');
        print('Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Update Doctor Referral Error: $e');
      if (!isSync) {
        return _queueUpdateDoctorReferral(id, data, imagePath: imagePath);
      }
      return false;
    }
  }

  /// Extracted offline-queue logic for updateDoctorReferral.
  static Future<bool> _queueUpdateDoctorReferral(
    int id,
    Map<String, dynamic> data, {
    String? imagePath,
  }) async {
    String? persistentImagePath = imagePath;
    if (imagePath != null) {
      try {
        final appDir = await _getAppDocumentsPath();
        final fileName =
            'offline_update_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final destPath = '$appDir/$fileName';
        await File(imagePath).copy(destPath);
        persistentImagePath = destPath;
        print('Offline update image saved permanently: $destPath');
      } catch (imgErr) {
        print('Could not persist offline update image: $imgErr');
      }
    }

    final payload = {'id': id, 'data': data, 'imagePath': persistentImagePath};
    await DatabaseHelper().enqueueSyncAction('UPDATE_DOCTOR_REFERRAL', payload);

    // Optimistic UI update — find and update or create the trip cache entry
    try {
      final tripIdRaw = data['trip'];
      if (tripIdRaw != null) {
        final tripId = int.tryParse(tripIdRaw.toString());
        if (tripId != null) {
          final updatedRef = {
            'id': id,
            'trip': tripId,
            'name': data['name'] ?? '',
            'degree_qualification': data['degree_qualification'] ?? '',
            'specialization': data['specialization'] ?? '',
            'contact_number': data['contact_number'] ?? '',
            'area': data['area'] ?? '',
            'street': data['street'] ?? '',
            'city': data['city'] ?? '',
            'pin': data['pin'] ?? '',
            'email': data['email'] ?? '',
            'remarks': data['remarks'] ?? '',
            'additional_details': data['additional_details'] ?? '',
            'status': 'Referred',
            'visit_image': persistentImagePath, // Keep local image proxy
            'created_at': DateTime.now().toIso8601String(),
          };

          final cachedTripStr = await _getCachedApiResponse('trip_$tripId');
          Map<String, dynamic> tripData;
          if (cachedTripStr != null) {
            tripData = json.decode(cachedTripStr);
          } else {
            // Offline trip — no cache yet. Create a skeleton so the UI shows activity.
            tripData = {
              'id': tripId,
              'trip_number': 0,
              'status': 'ongoing',
              'start_time': DateTime.now().toIso8601String(),
              'end_time': null,
              'doctor_referrals': [],
              'patient_referrals': [],
            };
          }

          final refs = List<dynamic>.from(tripData['doctor_referrals'] ?? []);
          final idx = refs.indexWhere((r) => r['id'] == id);
          if (idx >= 0) {
            refs[idx] = updatedRef;
          } else {
            refs.insert(0, updatedRef);
          }
          tripData['doctor_referrals'] = refs;
          await _cacheApiResponse('trip_$tripId', json.encode(tripData));
        }
      }
    } catch (e) {
      print('Optimistic cache error: $e');
    }
    return true;
  }

  static Future<bool> markDoctorAsVisited(int doctorId, int tripId) async {
    if (_authToken == null) return false;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/doctor-referrals/$doctorId/mark_visited/'),
        headers: {
          'Authorization': 'Token $_authToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({'trip_id': tripId}),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        print('Mark Doctor Visited Failed: ${response.statusCode}');
        print('Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Mark Doctor Visited Error: $e');
      return false;
    }
  }

  // --- Patient Referrals ---
  static Future<List<PatientReferral>> fetchPatientReferrals() async {
    if (_authToken == null) return [];

    final dbHelper = DatabaseHelper();

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/patient-referrals/'),
            headers: {
              'Authorization': 'Token $_authToken',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final patients = data
            .map((json) => PatientReferral.fromJson(json))
            .toList();
        await dbHelper.cachePatients(patients);
        return patients;
      }
    } catch (e) {
      print('Fetch Patient Referrals Error (Offline?): $e');
    }

    // Fallback: Read from Cache
    print('Returning cached patients fallback');
    return await dbHelper.getCachedPatients();
  }

  static Future<bool> createPatientReferral(
    PatientReferral referral, {
    bool isSync = false,
  }) async {
    if (_authToken == null) return false;

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/patient-referrals/'),
            headers: {
              'Authorization': 'Token $_authToken',
              'Content-Type': 'application/json',
            },
            body: json.encode(referral.toJson()),
          )
          .timeout(const Duration(seconds: 15));

      return response.statusCode == 201;
    } catch (e) {
      print('Create Patient Referral Error: $e');

      // If NOT running from SyncService, queue it for later!
      if (!isSync) {
        print('Queueing patient creation for offline sync...');
        await DatabaseHelper().enqueueSyncAction(
          'CREATE_PATIENT',
          referral.toJson(),
        );

        // Optimistically cache it locally so User sees it immediately
        final db = DatabaseHelper();
        final currentPatients = await db.getCachedPatients();
        currentPatients.insert(0, referral); // prepend to list
        await db.cachePatients(currentPatients);

        return true; // We accept it locally!
      }
      return false;
    }
  }

  // --- OpenRouteService Integration ---
  static const String _orsApiKey =
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImNhZWQ4MWU4MTlhODQ4NjFiOWY5MzQ1NjkzNTkyMmZhIiwiaCI6Im11cm11cjY0In0=';

  static Future<double> calculateRouteDistance(
    List<List<double>> coordinates,
  ) async {
    if (coordinates.length < 2) return 0.0;

    try {
      final response = await http.post(
        Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car'),
        headers: {
          'Authorization': _orsApiKey,
          'Content-Type': 'application/json',
        },
        body: json.encode({'coordinates': coordinates}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;
        if (routes.isNotEmpty) {
          final summary = routes[0]['summary'];
          final distanceMeters = summary['distance']; // in meters
          return distanceMeters / 1000.0; // Convert to km
        }
      } else {
        print('ORS API Error: ${response.statusCode} - ${response.body}');
        // Fallback to Haversine if API fails
        return _calculateTotalHaversineDistance(coordinates);
      }
    } catch (e) {
      print('Calculate Route Distance Error: $e');
      // Fallback to Haversine if Network/Exception error
      return _calculateTotalHaversineDistance(coordinates);
    }
    return 0.0;
  }

  // Fallback: Calculate straight-line distance between multiple points
  static double _calculateTotalHaversineDistance(
    List<List<double>> coordinates,
  ) {
    double totalDistance = 0.0;
    for (int i = 0; i < coordinates.length - 1; i++) {
      totalDistance += _haversine(
        coordinates[i][1],
        coordinates[i][0],
        coordinates[i + 1][1],
        coordinates[i + 1][0],
      );
    }
    return totalDistance;
  }

  // Haversine formula for distance between two points (in km)
  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final double a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }
}
