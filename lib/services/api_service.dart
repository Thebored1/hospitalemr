import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' show asin, cos, sqrt;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';
import '../models/task.dart';
import '../models/doctor.dart';
import '../models/patient_referral.dart';
import '../models/trip.dart';
import 'database_helper.dart';

class ApiService {

  static const String baseUrl =
      'https://shenmupsp.pythonanywhere.com/api';

  static String? _authToken;
  static String? _userRole; // 'advisor', 'maintenance', 'admin'
  static String? _username;

  static final StreamController<void> _queueUpdateController =
      StreamController<void>.broadcast();
  static Stream<void> get queueStream => _queueUpdateController.stream;
  static void notifyQueueUpdated() {
    if (!_queueUpdateController.isClosed) {
      _queueUpdateController.add(null);
    }
  }

  static final StreamController<void> _dataUpdateController =
      StreamController<void>.broadcast();
  static Stream<void> get dataStream => _dataUpdateController.stream;
  static void notifyDataUpdated() {
    if (!_dataUpdateController.isClosed) {
      _dataUpdateController.add(null);
    }
  }

  static bool get isAuthenticated => _authToken != null;
  static String? get userRole => _userRole;
  static String? get username => _username;
  static String? get authToken => _authToken;

  static final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  static Stream<String> get errorStream => _errorController.stream;
  static String? lastErrorMessage;

  static void _reportError(String message) {
    lastErrorMessage = message;
    _errorController.add(message);
  }

  static void reportError(String message) {
    _reportError(message);
  }

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

  static Future<bool> tripHasQueuedSync(int tripId) async {
    return await DatabaseHelper().hasQueuedActionsForTrip(tripId);
  }

  static Future<Map<int, List<Map<String, dynamic>>>>
      queuedActionsGroupedByTrip() async {
    return await DatabaseHelper().queuedActionsGroupedByTrip();
  }

  static Future<List<Map<String, dynamic>>> queuedActionsForTrip(int tripId) async {
    return await DatabaseHelper().queuedActionsForTrip(tripId);
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
        LogService.log(
          'INFO',
          'Login success',
          logger: 'auth',
          context: {'username': _username, 'role': _userRole},
        );
        return true;
      }
      LogService.log(
        'WARN',
        'Login failed',
        logger: 'auth',
        context: {
          'username': username,
          'status': response.statusCode,
          'body': response.body,
        },
      );
      return false;
    } catch (e) {
      print('Login Error: $e');
      LogService.log(
        'ERROR',
        'Login error',
        logger: 'auth',
        context: {'username': username, 'error': e.toString()},
      );
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
        final serverTripMaps = List<Map<String, dynamic>>.from(
          data.map((e) => Map<String, dynamic>.from(e as Map)),
        );
        final newTrips = serverTripMaps.map((j) => Trip.fromJson(j)).toList();
        // If the server already considers a trip completed, any queued END_TRIP
        // actions for that trip are stale and should be cleared.
        try {
          int removed = 0;
          for (final t in newTrips) {
            if (t.status == 'COMPLETED') {
              removed += await DatabaseHelper().deleteQueuedActionsForTrip(
                t.id,
                action: 'END_TRIP',
              );
            }
          }
          if (removed > 0) {
            notifyQueueUpdated();
          }
        } catch (_) {}
        final newTripIds = newTrips.map((t) => t.id).toSet();
        final pendingStartTripIds = await _getPendingStartTripIds();

        // Clear stale individual trip caches for deleted trips
        final oldCached = await _getCachedApiResponse('trips');
        if (oldCached != null) {
          try {
            final oldData = json.decode(oldCached) as List<dynamic>;
            for (final oldTrip in oldData) {
              final oldId = oldTrip['id'];
              if (oldId != null &&
                  !newTripIds.contains(oldId) &&
                  !pendingStartTripIds.contains(oldId)) {
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
            if (currentId != null &&
                !newTripIds.contains(currentId) &&
                !pendingStartTripIds.contains(currentId)) {
              await _clearCachedApiResponse('current_trip');
              print('Cleared stale cache for deleted current_trip $currentId');
            }
          } catch (_) {}
        }

        // Preserve offline START_TRIP items in list/cache until they sync.
        final mergedTripMaps = List<Map<String, dynamic>>.from(serverTripMaps);
        final mergedTrips = List<Trip>.from(newTrips);
        for (final tempId in pendingStartTripIds) {
          if (newTripIds.contains(tempId)) continue;
          final cachedTempTrip = await _getCachedApiResponse('trip_$tempId');
          if (cachedTempTrip == null || cachedTempTrip.isEmpty) continue;
          try {
            final tempMap = Map<String, dynamic>.from(
              json.decode(cachedTempTrip),
            );
            mergedTripMaps.insert(0, tempMap);
            mergedTrips.insert(0, Trip.fromJson(tempMap));
          } catch (_) {}
        }

        await _cacheApiResponse('trips', json.encode(mergedTripMaps));
        return mergedTrips;
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

  static Future<Set<int>> _getPendingStartTripIds() async {
    try {
      final queue = await DatabaseHelper().getSyncQueue();
      return queue
          .where((item) => item['action'] == 'START_TRIP')
          .map((item) {
            final payload = item['payload'] as Map<String, dynamic>;
            return int.tryParse(payload['tempTripId'].toString());
          })
          .whereType<int>()
          .toSet();
    } catch (_) {
      return <int>{};
    }
  }

  static Future<Trip?> startTrip(
    String? odometerStartPath, {
    double? lat,
    double? long,
    bool isSync = false,
  }) async {
    if (_authToken == null) return null;
    if (!isSync && !(await _isOnline())) {
      return _queueStartTripOffline(odometerStartPath, lat: lat, long: long);
    }
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
        final trip = Trip.fromJson(json.decode(response.body));
        // Keep local cache fresh so trip survives app restart even before
        // dashboard refetch happens.
        await _cacheStartedTripLocally(trip);
        notifyDataUpdated();
        return trip;
      } else {
        print('Start Trip Failed: ${response.statusCode}');
        print('Response Body: ${response.body}');
      }
    } catch (e) {
      print('Start Trip Error: $e');
      if (!isSync) {
        return _queueStartTripOffline(odometerStartPath, lat: lat, long: long);
      }
    }
    return null;
  }

  static Future<Trip> _queueStartTripOffline(
    String? odometerStartPath, {
    double? lat,
    double? long,
  }) async {
    print('Queueing Start Trip for offline sync...');
    final tempTripId = DateTime.now().millisecondsSinceEpoch % 1000000;
    final nextTripNumber = await _getNextLocalTripNumber();

    String? persistentOdometerPath = odometerStartPath;
    if (odometerStartPath != null && odometerStartPath.trim().isNotEmpty) {
      try {
        final appDir = await _getAppDocumentsPath();
        final fileName =
            'offline_trip_start_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final destPath = '$appDir/$fileName';
        await File(odometerStartPath).copy(destPath);
        persistentOdometerPath = destPath;
      } catch (e) {
        print('Could not persist offline start trip image: $e');
      }
    }

    final payload = {
      'tempTripId': tempTripId,
      'odometerStartPath': persistentOdometerPath,
      'lat': lat,
      'long': long,
    };
    await DatabaseHelper().enqueueSyncAction('START_TRIP', payload);
    notifyQueueUpdated();
    notifyDataUpdated();

    final offlineTrip = Trip(
      id: tempTripId,
      tripNumber: nextTripNumber,
      status: 'ONGOING',
      startTime: DateTime.now(),
      odometerStartImagePath: persistentOdometerPath,
      startLat: lat,
      startLong: long,
    );
    await _cacheStartedTripLocally(offlineTrip);
    notifyDataUpdated();
    return offlineTrip;
  }

  static Future<int> _getNextLocalTripNumber() async {
    final cachedTrips = await _getCachedApiResponse('trips');
    if (cachedTrips == null || cachedTrips.isEmpty) return 1;
    try {
      final tripsData = json.decode(cachedTrips) as List<dynamic>;
      int maxTripNumber = 0;
      for (final item in tripsData) {
        if (item is! Map) continue;
        final tripNumberRaw = item['trip_number'] ?? item['tripNumber'] ?? 0;
        final tripNumber = int.tryParse(tripNumberRaw.toString()) ?? 0;
        if (tripNumber > maxTripNumber) {
          maxTripNumber = tripNumber;
        }
      }
      return maxTripNumber + 1;
    } catch (_) {
      return 1;
    }
  }

  static Map<String, dynamic> _tripToCacheJson(Trip trip) {
    return {
      'id': trip.id,
      'trip_number': trip.tripNumber,
      'start_time': trip.startTime.toIso8601String(),
      'end_time': trip.endTime?.toIso8601String(),
      'status': trip.status,
      'odometer_start_image': trip.odometerStartImagePath,
      'odometer_end_image': trip.odometerEndImagePath,
      'total_kilometers': trip.totalKilometers,
      'additional_expenses': trip.additionalExpenses,
      'start_lat': trip.startLat,
      'start_long': trip.startLong,
      'end_lat': trip.endLat,
      'end_long': trip.endLong,
      'doctor_referrals': const [],
      'overnight_stays': const [],
    };
  }

  static Future<void> _cacheStartedTripLocally(Trip trip) async {
    final tripJson = _tripToCacheJson(trip);
    await _cacheApiResponse('trip_${trip.id}', json.encode(tripJson));
    await _cacheApiResponse('current_trip', json.encode(tripJson));

    final cachedTrips = await _getCachedApiResponse('trips');
    List<dynamic> tripsList = [];
    if (cachedTrips != null && cachedTrips.isNotEmpty) {
      try {
        tripsList = List<dynamic>.from(json.decode(cachedTrips));
      } catch (_) {
        tripsList = [];
      }
    }

    tripsList.removeWhere((t) => (t is Map) && t['id'] == trip.id);
    tripsList.insert(0, tripJson);
    await _cacheApiResponse('trips', json.encode(tripsList));
  }

  static Future<void> _cacheTripLocally(Trip trip) async {
    final tripJson = _tripToCacheJson(trip);
    await _cacheApiResponse('trip_${trip.id}', json.encode(tripJson));

    final currentTripStr = await _getCachedApiResponse('current_trip');
    if (currentTripStr != null) {
      try {
        final currentTrip = Map<String, dynamic>.from(json.decode(currentTripStr));
        if (currentTrip['id'] == trip.id) {
          await _cacheApiResponse('current_trip', json.encode(tripJson));
        }
      } catch (_) {}
    }

    final tripsStr = await _getCachedApiResponse('trips');
    List<dynamic> tripsList = [];
    if (tripsStr != null && tripsStr.isNotEmpty) {
      try {
        tripsList = List<dynamic>.from(json.decode(tripsStr));
      } catch (_) {
        tripsList = [];
      }
    }
    bool updated = false;
    for (int i = 0; i < tripsList.length; i++) {
      final entry = tripsList[i];
      if (entry is Map<String, dynamic> && entry['id'] == trip.id) {
        tripsList[i] = tripJson;
        updated = true;
        break;
      }
    }
    if (!updated) {
      tripsList.insert(0, tripJson);
    }
    await _cacheApiResponse('trips', json.encode(tripsList));
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
    if (!isSync && !(await _isOnline())) {
      return _queueEndTripOffline(
        tripId,
        kilometers,
        expenses,
        odometerEndPath,
        lat: lat,
        long: long,
      );
    }
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
        final trip = Trip.fromJson(json.decode(response.body));
        await _cacheTripLocally(trip);
        try {
          final removed = await DatabaseHelper().deleteQueuedActionsForTrip(
            tripId,
            action: 'END_TRIP',
          );
          if (removed > 0) {
            notifyQueueUpdated();
          }
        } catch (_) {}
        notifyDataUpdated();
        return trip;
      } else {
        if (!isSync) {
          _reportError(
            'Failed to end trip (${response.statusCode}). Please try again.',
          );
        }
        LogService.log(
          'ERROR',
          'End trip failed',
          logger: 'trip',
          context: {
            'tripId': tripId,
            'status': response.statusCode,
            'body': response.body,
            'isSync': isSync,
          },
        );
      }
    } catch (e) {
      print('End Trip Error: $e');
      if (!isSync) {
        _reportError('End Trip Error: $e');
      }
      LogService.log(
        'ERROR',
        'End trip error',
        logger: 'trip',
        context: {'tripId': tripId, 'error': e.toString(), 'isSync': isSync},
      );
      if (!isSync) {
        return _queueEndTripOffline(
          tripId,
          kilometers,
          expenses,
          odometerEndPath,
          lat: lat,
          long: long,
        );
      }
    }
    return null;
  }

  static Future<Trip?> _queueEndTripOffline(
    int tripId,
    double kilometers,
    String expenses,
    String? odometerEndPath, {
    double? lat,
    double? long,
  }) async {
    print('Queueing End Trip for offline sync...');
    _reportError(
      'You are offline—this trip end has been queued and will sync when the network is available.',
    );
    final payload = {
      'tripId': tripId,
      'kilometers': kilometers,
      'expenses': expenses,
      'odometerEndPath': odometerEndPath,
      'lat': lat,
      'long': long,
    };
    await DatabaseHelper().enqueueSyncAction('END_TRIP', payload);
    notifyQueueUpdated();
    notifyDataUpdated();
    final tripData = await _cacheTripEndLocally(
      tripId: tripId,
      kilometers: kilometers,
      expenses: expenses,
      odometerEndPath: odometerEndPath,
      lat: lat,
      long: long,
    );
    final startTimeStr = tripData['start_time'] as String? ??
        DateTime.now().toIso8601String();
    final tripNumberRaw = tripData['trip_number'];
    final tripNumber = tripNumberRaw is int
        ? tripNumberRaw
        : int.tryParse(tripNumberRaw?.toString() ?? '') ?? 0;
    return Trip(
      id: tripId,
      tripNumber: tripNumber,
      startTime: DateTime.parse(startTimeStr),
      endTime: DateTime.parse(tripData['end_time'] as String),
      status: 'COMPLETED',
      totalKilometers: kilometers,
      additionalExpenses: expenses,
      odometerEndImagePath: odometerEndPath,
      endLat: lat,
      endLong: long,
    );
  }

  static Future<Map<String, dynamic>> _cacheTripEndLocally({
    required int tripId,
    required double kilometers,
    required String expenses,
    String? odometerEndPath,
    double? lat,
    double? long,
  }) async {
    final nowStr = DateTime.now().toIso8601String();
    Map<String, dynamic> tripData = {};
    final cachedTripStr = await _getCachedApiResponse('trip_$tripId');
    if (cachedTripStr != null) {
      tripData = Map<String, dynamic>.from(json.decode(cachedTripStr));
    } else {
      tripData = _tripToCacheJson(
        Trip(
          id: tripId,
          tripNumber: 0,
          status: 'ONGOING',
          startTime: DateTime.now(),
        ),
      );
    }

    tripData['status'] = 'COMPLETED';
    tripData['total_kilometers'] = kilometers;
    tripData['additional_expenses'] = expenses;
    if (odometerEndPath != null && odometerEndPath.trim().isNotEmpty) {
      tripData['odometer_end_image'] = odometerEndPath;
    }
    if (lat != null) tripData['end_lat'] = lat;
    if (long != null) tripData['end_long'] = long;
    tripData['end_time'] = nowStr;

    await _cacheApiResponse('trip_$tripId', json.encode(tripData));

    final currentTripStr = await _getCachedApiResponse('current_trip');
    if (currentTripStr != null) {
      final currentTrip = Map<String, dynamic>.from(json.decode(currentTripStr));
      if (currentTrip['id'] == tripId) {
        currentTrip.addAll(tripData);
        await _cacheApiResponse('current_trip', json.encode(currentTrip));
      }
    }

    final tripsStr = await _getCachedApiResponse('trips');
    if (tripsStr != null) {
      final tripsList = List<dynamic>.from(json.decode(tripsStr));
      bool updated = false;
      for (int i = 0; i < tripsList.length; i++) {
        final entry = tripsList[i];
        if (entry is Map<String, dynamic> && entry['id'] == tripId) {
          tripsList[i] = {...entry, ...tripData};
          updated = true;
          break;
        }
      }
      if (updated) {
        await _cacheApiResponse('trips', json.encode(tripsList));
      }
    }

    return tripData;
  }

  static Future<bool> addOvernightStay(
    int tripId,
    String name,
    String address,
    String billPath,
    double? lat,
    double? long,
    {bool isSync = false}
  ) async {
    if (_authToken == null) return false;
    if (!isSync && !(await _isOnline())) {
      return _queueAddOvernightStay(
        tripId,
        name,
        address,
        billPath,
        lat,
        long,
      );
    }
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
        if (!isSync) {
          _reportError('Add Overnight Stay Error: $e');
        }
        LogService.log(
          'ERROR',
          'Overnight stay error',
          logger: 'overnight_stay',
          context: {'tripId': tripId, 'error': e.toString(), 'isSync': isSync},
        );
        if (!isSync) {
          return _queueAddOvernightStay(
            tripId,
            name,
            address,
            billPath,
            lat,
            long,
          );
        }
        return false;
      }
    }

  static Future<bool> _queueAddOvernightStay(
    int tripId,
    String name,
    String address,
    String billPath,
    double? lat,
    double? long,
  ) async {
    print('Queueing overnight stay for offline sync...');
    _reportError(
      'You are offline—this hotel stay has been queued and will sync when the network returns.',
    );
    String? persistentBillPath = billPath;
    if (billPath.trim().isNotEmpty) {
      try {
        final appDir = await _getAppDocumentsPath();
        final fileName =
            'offline_overnight_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final destPath = '$appDir/$fileName';
        await File(billPath).copy(destPath);
        persistentBillPath = destPath;
      } catch (e) {
        print('Could not persist offline overnight stay image: $e');
      }
    }

    final payload = {
      'tripId': tripId,
      'name': name,
      'address': address,
      'billPath': persistentBillPath,
      'lat': lat,
      'long': long,
    };
    await DatabaseHelper().enqueueSyncAction('ADD_OVERNIGHT_STAY', payload);
    notifyQueueUpdated();
    return true;
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
    if (imagePath == null || imagePath.trim().isEmpty) {
      if (!isSync) {
        _reportError('Cannot sync doctor visit: missing visit image.');
      }
      LogService.log(
        'WARN',
        'Doctor visit missing image',
        logger: 'doctor_visit',
        context: {'tripId': tripId, 'isSync': isSync},
      );
      return false;
    }

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
      if (!File(imagePath).existsSync()) {
        if (!isSync) {
          _reportError('Cannot sync doctor visit: image file not found.');
        }
        LogService.log(
          'ERROR',
          'Doctor visit image file not found',
          logger: 'doctor_visit',
          context: {'tripId': tripId, 'path': imagePath, 'isSync': isSync},
        );
        return false;
      }
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/doctor-referrals/'),
      );
      request.headers['Authorization'] = 'Token $_authToken';

      request.fields['trip'] = tripId.toString();
      if (referral.id != null) {
        request.fields['doctor_id'] = referral.id.toString();
      }
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

      request.files.add(
        await http.MultipartFile.fromPath('visit_image', imagePath),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201 || response.statusCode == 200) {
        notifyDataUpdated();
        return true;
      } else {
        print('Create Doctor Referral Failed: ${response.statusCode}');
        print('Body: ${response.body}');
        if (!isSync) {
          _reportError(
            'Failed to sync doctor visit (${response.statusCode}).',
          );
        }
        LogService.log(
          'ERROR',
          'Doctor visit sync failed',
          logger: 'doctor_visit',
          context: {
            'tripId': tripId,
            'status': response.statusCode,
            'body': response.body,
            'isSync': isSync,
          },
        );
        if (!isSync) {
          // Server rejected — queue for later retry rather than silently dropping
          // (e.g. temporary 500 error)
        }
        return false;
      }
    } catch (e) {
      print('Create Doctor Referral Error: $e');
      if (!isSync) {
        _reportError('Failed to sync doctor visit: $e');
      }
      LogService.log(
        'ERROR',
        'Doctor visit sync error',
        logger: 'doctor_visit',
        context: {'tripId': tripId, 'error': e.toString(), 'isSync': isSync},
      );
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

    // IMPORTANT:
    // `DoctorReferral.id` is overloaded in parts of the app to carry `doctor_id`
    // when creating a visit (see createDoctorReferral -> request.fields['doctor_id']).
    // For offline-created visits we must generate a *temporary visit id* that:
    // - is unique per queued visit
    // - is >= 1e12 so updateDoctorReferral() treats it as temp/offline and queues
    //   updates instead of attempting PATCH on the server (which would 404)
    final optimisticId = DateTime.now().microsecondsSinceEpoch;
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
      'tempId': optimisticId,
    };
    await DatabaseHelper().enqueueSyncAction('CREATE_DOCTOR_REFERRAL', payload);
    notifyQueueUpdated();
    notifyDataUpdated();

    // Optimistic UI update
    try {
      final cachedTripStr = await _getCachedApiResponse('trip_$tripId');
      Map<String, dynamic> tripData;
      if (cachedTripStr != null) {
        tripData = json.decode(cachedTripStr);
      } else {
        // Offline trip fallback — ensure timeline still renders queued actions.
        tripData = {
          'id': tripId,
          'trip_number': 0,
          'status': 'ONGOING',
          'start_time': DateTime.now().toIso8601String(),
          'end_time': null,
          'doctor_referrals': [],
          'overnight_stays': [],
        };
      }

      final refs = List<dynamic>.from(tripData['doctor_referrals'] ?? []);
      final optimisticRef = {
        // Keep stable id for same-doctor edits while offline; fallback for brand-new doctors.
        'id': optimisticId,
        'trip': tripId,
        'name': referral.name,
        'contact_number': referral.contactNumber,
        'specialization': referral.specialization,
        'degree_qualification': referral.degreeQualification,
        'email': referral.email,
        'remarks': referral.remarks,
        'additional_details': referral.additionalDetails,
        'status': 'Referred',
        'visit_image': persistentImagePath,
        if (lat != null) 'visit_lat': lat.toString(),
        if (long != null) 'visit_long': long.toString(),
        'created_at': DateTime.now().toIso8601String(),
        // Keep address in nested shape expected by DoctorReferral.fromJson.
        'address_details': {
          'street': referral.street ?? '',
          'pincode': referral.pin,
          'area_details': {
            'name': referral.area,
            'city': referral.city ?? '',
            'pincode': referral.pin,
          },
        },
      };
      refs.insert(0, optimisticRef);
      tripData['doctor_referrals'] = refs;
      await _cacheApiResponse('trip_$tripId', json.encode(tripData));
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

    // Temp/offline IDs can never exist on the server, even if we're online.
    // Always merge into queued offline updates.
    if (id >= 1000000000000) {
      return _queueUpdateDoctorReferral(id, data, imagePath: imagePath);
    }

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
        notifyDataUpdated();
        return true;
      } else {
        print('Update Doctor Referral Failed: ${response.statusCode}');
        print('Body: ${response.body}');

        // Compatibility fallback:
        // Some backends/mobile payloads treat a doctor "visit" as an upsert keyed by (doctor_id, trip)
        // at the POST endpoint. If PATCH returns 404 (not found), retry as POST so users can still
        // complete a saved draft without getting stuck.
        if (response.statusCode == 404) {
          final upserted = await _upsertDoctorVisitViaPost(
            doctorId: id,
            data: data,
            imagePath: imagePath,
            isSync: isSync,
          );
          if (upserted) {
            notifyDataUpdated();
            return true;
          }
        }

        if (!isSync) {
          _reportError(
            'Failed to save doctor visit (${response.statusCode}). Please try again.',
          );
        }
        LogService.log(
          'ERROR',
          'Update doctor referral failed',
          logger: 'doctor_visit',
          context: {
            'id': id,
            'status': response.statusCode,
            'body': response.body,
            'isSync': isSync,
          },
        );
        return false;
      }
    } catch (e) {
      print('Update Doctor Referral Error: $e');
      if (!isSync) {
        _reportError('Failed to save doctor visit: $e');
      }
      LogService.log(
        'ERROR',
        'Update doctor referral error',
        logger: 'doctor_visit',
        context: {'id': id, 'error': e.toString(), 'isSync': isSync},
      );
      if (!isSync) {
        return _queueUpdateDoctorReferral(id, data, imagePath: imagePath);
      }
      return false;
    }
  }

  static Future<bool> _upsertDoctorVisitViaPost({
    required int doctorId,
    required Map<String, dynamic> data,
    required String? imagePath,
    required bool isSync,
  }) async {
    if (_authToken == null) return false;
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/doctor-referrals/'),
      );
      request.headers['Authorization'] = 'Token $_authToken';

      // Ensure we resolve the same doctor row when possible.
      request.fields['doctor_id'] = doctorId.toString();

      data.forEach((key, value) {
        if (value != null) {
          request.fields[key] = value.toString();
        }
      });

      if (imagePath != null && imagePath.trim().isNotEmpty) {
        if (File(imagePath).existsSync()) {
          request.files.add(
            await http.MultipartFile.fromPath('visit_image', imagePath),
          );
        }
      }

      final streamed = await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return true;
      }
      print('Upsert Doctor Visit via POST Failed: ${response.statusCode}');
      print('Body: ${response.body}');
      return false;
    } catch (e) {
      print('Upsert Doctor Visit via POST Error: $e');
      if (!isSync) {
        // Don't show a second UI error; caller handles reporting.
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

    final db = DatabaseHelper();
    final merged = await db.mergeQueuedDoctorReferralUpdate(
      id,
      data,
      imagePath: persistentImagePath,
    );
    if (!merged) {
      final payload = {
        'id': id,
        'data': data,
        'imagePath': persistentImagePath,
        'tempId': id,
      };
      await db.enqueueSyncAction('UPDATE_DOCTOR_REFERRAL', payload);
    }
    notifyQueueUpdated();

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
            'created_at': DateTime.now().toIso8601String(),
            'address_details': {
              'street': data['street'] ?? '',
              'pincode': data['pin'] ?? '',
              'area_details': {
                'name': data['area'] ?? '',
                'city': data['city'] ?? '',
                'pincode': data['pin'] ?? '',
              },
            },
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
              'overnight_stays': [],
            };
          }

          final refs = List<dynamic>.from(tripData['doctor_referrals'] ?? []);
          final idx = refs.indexWhere((r) => r['id'] == id);
          if (idx >= 0) {
            final existing = Map<String, dynamic>.from(refs[idx]);
            existing.addAll(updatedRef);
            // Preserve existing image unless a new one was supplied.
            if (persistentImagePath != null && persistentImagePath.isNotEmpty) {
              existing['visit_image'] = persistentImagePath;
            }
            refs[idx] = existing;
          } else {
            if (persistentImagePath != null && persistentImagePath.isNotEmpty) {
              updatedRef['visit_image'] = persistentImagePath;
            }
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

  static Future<bool> markDoctorAsVisited(int doctorId, int tripId,
      {bool isSync = false}) async {
    if (_authToken == null) return false;
    if (!isSync && !(await _isOnline())) {
      return _queueMarkDoctorVisited(doctorId, tripId);
    }
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
        if (!isSync) {
          _reportError(
            'Failed to mark doctor as visited (${response.statusCode}).',
          );
        }
        LogService.log(
          'ERROR',
          'Mark doctor visited failed',
          logger: 'doctor_visit',
          context: {
            'doctorId': doctorId,
            'tripId': tripId,
            'status': response.statusCode,
            'body': response.body,
            'isSync': isSync,
          },
        );
        return false;
      }
    } catch (e) {
      print('Mark Doctor Visited Error: $e');
      if (!isSync) {
        _reportError('Mark Doctor Visited Error: $e');
      }
      LogService.log(
        'ERROR',
        'Mark doctor visited error',
        logger: 'doctor_visit',
        context: {
          'doctorId': doctorId,
          'tripId': tripId,
          'error': e.toString(),
          'isSync': isSync,
        },
      );
      if (!isSync) {
        return _queueMarkDoctorVisited(doctorId, tripId);
      }
      return false;
    }
  }

  static Future<bool> _queueMarkDoctorVisited(int doctorId, int tripId) async {
    print('Queueing doctor visited mark for offline sync...');
    _reportError(
      'You are offline—doctor visit completion will sync once you reconnect.',
    );
    final payload = {'doctorId': doctorId, 'tripId': tripId};
    await DatabaseHelper().enqueueSyncAction('MARK_DOCTOR_VISITED', payload);
    notifyQueueUpdated();
    return true;
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
        notifyQueueUpdated();

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
