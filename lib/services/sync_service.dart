import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/patient_referral.dart';
import '../models/doctor.dart';
import 'api_service.dart';
import 'database_helper.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  static bool _isSyncing = false;

  factory SyncService() => _instance;

  SyncService._internal() {
    // Listen for network changes to trigger sync
    Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        syncPendingData();
      }
    });
    _kickoffSyncIfOnline();
  }

  Future<void> _kickoffSyncIfOnline() async {
    final results = await Connectivity().checkConnectivity();
    if (results.isNotEmpty && results.first != ConnectivityResult.none) {
      await syncPendingData();
    }
  }

  /// Pushes all local queued actions to the server
  Future<void> syncPendingData() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final dbHelper = DatabaseHelper();
      final queue = await dbHelper.getSyncQueue();

      if (queue.isEmpty) {
        return;
      }
      print('Syncing ${queue.length} pending items to server...');

      bool anySuccess = false;
      bool anyFailure = false;

      for (final item in queue) {
        final action = item['action'];
        final payload = item['payload'] as Map<String, dynamic>;
        final queueId = item['id'];

        bool success = false;

        try {
          if (action == 'CREATE_PATIENT') {
            final referral = PatientReferral.fromJson(payload);
            success = await ApiService.createPatientReferral(
              referral,
              isSync: true,
            );
        } else if (action == 'CREATE_DOCTOR_REFERRAL') {
          final referralData = payload['referral'];
          final tripId = int.tryParse(payload['tripId'].toString()) ?? 0;
          final imagePath = payload['imagePath']?.toString();
          final lat = payload['lat'] != null
              ? double.tryParse(payload['lat'].toString())
              : null;
          final long = payload['long'] != null
              ? double.tryParse(payload['long'].toString())
              : null;

          if (tripId >= 1000000000000) {
            // Trip is still a temp/offline id. Wait for START_TRIP to sync.
            continue;
          }

          final referral = DoctorReferral.fromJson(referralData);
          success = await ApiService.createDoctorReferral(
            referral,
            tripId,
              imagePath: imagePath,
              lat: lat,
              long: long,
              isSync: true,
            );
        } else if (action == 'UPDATE_DOCTOR_REFERRAL') {
          final id = int.tryParse(payload['id'].toString()) ?? 0;
          // Safe cast — json.decode can return LinkedHashMap which needs explicit conversion
          final rawData = payload['data'];
          final data = rawData is Map<String, dynamic>
              ? rawData
              : Map<String, dynamic>.from(rawData as Map);
          final imagePath = payload['imagePath']?.toString();

          if (id >= 1000000000000) {
            final merged = await dbHelper.mergeQueuedDoctorReferralUpdate(
              id,
              data,
              imagePath: imagePath,
            );
            if (merged) {
              await dbHelper.deleteSyncQueueItem(queueId);
              ApiService.notifyQueueUpdated();
              anySuccess = true;
              continue;
            }
            final tripIdRaw = data['trip'] ?? data['trip_id'];
            final tripId =
                tripIdRaw != null ? int.tryParse(tripIdRaw.toString()) : null;
            if (tripId != null && imagePath != null && imagePath.isNotEmpty) {
              final referral = DoctorReferral.fromJson(data);
              success = await ApiService.createDoctorReferral(
                referral,
                tripId,
                imagePath: imagePath,
                lat: data['visit_lat'] != null
                    ? double.tryParse(data['visit_lat'].toString())
                    : null,
                long: data['visit_long'] != null
                    ? double.tryParse(data['visit_long'].toString())
                    : null,
                isSync: true,
              );
              if (success) {
                await dbHelper.deleteSyncQueueItem(queueId);
                ApiService.notifyQueueUpdated();
                anySuccess = true;
                continue;
              }
            } else {
              // Temp-id update without a matching create or image can't be synced.
              await dbHelper.deleteSyncQueueItem(queueId);
              ApiService.notifyQueueUpdated();
              ApiService.reportError(
                'An offline doctor entry could not sync (missing image). Please reopen and save it again.',
              );
              anyFailure = true;
              continue;
            }
          }

          print('Syncing UPDATE_DOCTOR_REFERRAL id=$id imagePath=$imagePath');
          success = await ApiService.updateDoctorReferral(
            id,
              data,
              imagePath: imagePath,
              isSync: true,
            );
        } else if (action == 'END_TRIP') {
          final tripId = int.tryParse(payload['tripId'].toString()) ?? 0;
          if (tripId >= 1000000000000) {
            // Trip is still a temp/offline id. Wait for START_TRIP to sync.
            continue;
          }
          final kilometers =
              double.tryParse(payload['kilometers'].toString()) ?? 0.0;
          final expenses = payload['expenses']?.toString() ?? '';
            final odometerEndPath = payload['odometerEndPath']?.toString();
            final lat = payload['lat'] != null
                ? double.tryParse(payload['lat'].toString())
                : null;
            final long = payload['long'] != null
                ? double.tryParse(payload['long'].toString())
                : null;

            final updatedTrip = await ApiService.endTrip(
              tripId,
              kilometers,
              expenses,
              odometerEndPath,
              lat: lat,
              long: long,
              isSync: true,
            );
            success = updatedTrip != null;
          } else if (action == 'START_TRIP') {
            final tempTripId =
                int.tryParse(payload['tempTripId'].toString()) ?? 0;
            final odometerStartPath = payload['odometerStartPath']?.toString();
            final lat = payload['lat'] != null
                ? double.tryParse(payload['lat'].toString())
                : null;
            final long = payload['long'] != null
                ? double.tryParse(payload['long'].toString())
                : null;

            final realTrip = await ApiService.startTrip(
              odometerStartPath,
              lat: lat,
              long: long,
              isSync: true,
            );

            if (realTrip != null) {
              success = true;
              await dbHelper.updateSyncQueueTripIds(tempTripId, realTrip.id);
            }
        } else if (action == 'ADD_OVERNIGHT_STAY') {
          final tripId = int.tryParse(payload['tripId'].toString()) ?? 0;
          if (tripId >= 1000000000000) {
            // Trip is still a temp/offline id. Wait for START_TRIP to sync.
            continue;
          }
          final name = payload['name']?.toString() ?? '';
          final address = payload['address']?.toString() ?? '';
            final billPath = payload['billPath']?.toString() ?? '';
            final lat = payload['lat'] != null
                ? double.tryParse(payload['lat'].toString())
                : null;
            final long = payload['long'] != null
                ? double.tryParse(payload['long'].toString())
                : null;

            success = await ApiService.addOvernightStay(
              tripId,
              name,
              address,
              billPath,
              lat,
              long,
              isSync: true,
            );
          } else if (action == 'MARK_DOCTOR_VISITED') {
            final doctorId = int.tryParse(payload['doctorId'].toString()) ?? 0;
            final tripId = int.tryParse(payload['tripId'].toString()) ?? 0;
            if (doctorId > 0 && tripId > 0) {
              success = await ApiService.markDoctorAsVisited(
                doctorId,
                tripId,
                isSync: true,
              );
            }
          }
        } catch (e) {
          print('Error syncing item $queueId: $e');
        }

        // If successfully sent to the server, remove it from local queue
        if (success) {
          await dbHelper.deleteSyncQueueItem(queueId);
          ApiService.notifyQueueUpdated();
          print('Successfully synced item $queueId ($action)');
          anySuccess = true;
        } else {
          anyFailure = true;
        }
      }

      // If we synced anything, force a background refresh to replace optimistic fake IDs
      // with the real data from the server.
      if (anySuccess) {
        print("Sync complete. Refreshing local caches with real data...");
        try {
          await ApiService.fetchTrips();
          await ApiService.fetchDoctorReferrals();
          // Also fire off an event or let the UI know if needed,
          // but the next time the screen builds or pulls to refresh, it will use real data.
        } catch (e) {
          print('Error refreshing caches after sync: $e');
        }
      }

      if (anyFailure) {
        ApiService.reportError(
          'Some items failed to sync. Please check your connection and try again.',
        );
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Fetch latest data from server and cache locally
  Future<void> fetchAndCacheAll() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.isEmpty ||
        connectivityResult.first == ConnectivityResult.none) {
      return; // Offline, can't fetch
    }

    try {
      // Background fetch docs and patients, caching them automatically inside ApiService
      await ApiService.fetchAllDoctors();
      await ApiService.fetchPatientReferrals();
    } catch (e) {
      print('Failed to cache data: $e');
    }
  }
}
