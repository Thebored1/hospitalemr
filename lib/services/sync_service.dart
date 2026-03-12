import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/patient_referral.dart';
import '../models/doctor.dart';
import '../models/trip.dart';
import 'api_service.dart';
import 'database_helper.dart';
import 'log_service.dart';

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
  Future<void> syncPendingData({bool showErrors = false}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final dbHelper = DatabaseHelper();
      final queue = await dbHelper.getSyncQueue();

      if (queue.isEmpty) {
        return;
      }
      print('Syncing ${queue.length} pending items to server...');
      LogService.log(
        'INFO',
        'Sync started',
        logger: 'sync',
        context: {'queueSize': queue.length},
      );

      bool anySuccess = false;
      bool anyFailure = false;
      final startedWithQueue = queue.isNotEmpty;

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

      // Always reconcile after a sync run so we can clear stale queued flags
      // (e.g. END_TRIP already completed on the server).
      if (startedWithQueue) {
        try {
          await ApiService.fetchTrips();
          if (anySuccess) {
            await ApiService.fetchDoctorReferrals();
          }
          await _reconcileQueueWithServer();
        } catch (e) {
          print('Error reconciling caches after sync: $e');
        }
      }

      if (anyFailure && showErrors) {
        ApiService.reportError(
          'Some items failed to sync. Please check your connection and try again.',
        );
      }
      if (anySuccess || anyFailure) {
        LogService.log(
          'INFO',
          'Sync finished',
          logger: 'sync',
          context: {'anySuccess': anySuccess, 'anyFailure': anyFailure},
        );
      }
      await _cleanupInvalidQueueItems();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _reconcileQueueWithServer() async {
    // Best-effort: if server already has the effect of a queued action (often
    // due to retries/duplicates), drop the local queue item so UI doesn't show
    // "Queued for sync" forever.
    final dbHelper = DatabaseHelper();
    final queue = await dbHelper.getSyncQueue();
    if (queue.isEmpty) return;

    final tripIds = <int>{};
    for (final item in queue) {
      final payload = item['payload'] as Map<String, dynamic>;
      final tripId = int.tryParse(payload['tripId']?.toString() ?? '') ??
          int.tryParse(payload['trip_id']?.toString() ?? '') ??
          int.tryParse((payload['data'] is Map ? payload['data']['trip']?.toString() : '') ?? '');
      if (tripId != null && tripId > 0) {
        tripIds.add(tripId);
      }
    }
    if (tripIds.isEmpty) return;

    final tripsById = <int, Trip>{};
    for (final id in tripIds) {
      final trip = await ApiService.fetchTripById(id);
      if (trip != null) {
        tripsById[id] = trip;
      }
    }

    int removed = 0;
    for (final item in queue) {
      final action = item['action']?.toString() ?? '';
      final payload = item['payload'] as Map<String, dynamic>;
      final queueId = item['id'] as int;

      final tripId = int.tryParse(payload['tripId']?.toString() ?? '') ??
          int.tryParse(payload['trip_id']?.toString() ?? '') ??
          int.tryParse((payload['data'] is Map ? payload['data']['trip']?.toString() : '') ?? '');
      if (tripId == null) continue;
      final trip = tripsById[tripId];
      if (trip == null) continue;

      bool alreadyApplied = false;
      if (action == 'END_TRIP') {
        alreadyApplied = trip.status == 'COMPLETED';
      } else if (action == 'MARK_DOCTOR_VISITED') {
        final doctorId = int.tryParse(payload['doctorId']?.toString() ?? '');
        if (doctorId != null) {
          alreadyApplied = trip.doctorReferrals.any((d) => d.id == doctorId);
        }
      } else if (action == 'CREATE_DOCTOR_REFERRAL') {
        final ref = payload['referral'];
        final name = (ref is Map ? (ref['name'] ?? '') : '').toString().trim().toLowerCase();
        if (name.isNotEmpty) {
          alreadyApplied = trip.doctorReferrals.any(
            (d) => d.name.trim().toLowerCase() == name,
          );
        }
      } else if (action == 'UPDATE_DOCTOR_REFERRAL') {
        final id = int.tryParse(payload['id']?.toString() ?? '');
        final data = payload['data'];
        final name = (data is Map ? (data['name'] ?? '') : '').toString().trim().toLowerCase();
        if (id != null) {
          alreadyApplied = trip.doctorReferrals.any((d) => d.id == id);
        }
        if (!alreadyApplied && name.isNotEmpty) {
          alreadyApplied = trip.doctorReferrals.any(
            (d) => d.name.trim().toLowerCase() == name,
          );
        }
      } else if (action == 'ADD_OVERNIGHT_STAY') {
        final name = (payload['name'] ?? '').toString().trim().toLowerCase();
        final address = (payload['address'] ?? '').toString().trim().toLowerCase();
        if (name.isNotEmpty && address.isNotEmpty) {
          alreadyApplied = trip.overnightStays.any(
            (s) =>
                s.hotelName.trim().toLowerCase() == name &&
                s.hotelAddress.trim().toLowerCase() == address,
          );
        }
      }

      if (alreadyApplied) {
        await dbHelper.deleteSyncQueueItem(queueId);
        removed += 1;
      }
    }

    if (removed > 0) {
      ApiService.notifyQueueUpdated();
      LogService.log(
        'WARN',
        'Reconciled and removed stale queue items',
        logger: 'sync',
        context: {'removedCount': removed},
      );
    }
  }

  Future<void> _cleanupInvalidQueueItems() async {
    final dbHelper = DatabaseHelper();
    final queue = await dbHelper.getSyncQueue();
    if (queue.isEmpty) return;

    bool removedAny = false;
    int removedCount = 0;
    for (final item in queue) {
      final action = item['action'];
      final payload = item['payload'] as Map<String, dynamic>;
      final queueId = item['id'] as int;

      String? filePath;
      if (action == 'START_TRIP') {
        filePath = payload['odometerStartPath']?.toString();
      } else if (action == 'END_TRIP') {
        filePath = payload['odometerEndPath']?.toString();
      } else if (action == 'CREATE_DOCTOR_REFERRAL') {
        filePath = payload['imagePath']?.toString();
      } else if (action == 'UPDATE_DOCTOR_REFERRAL') {
        filePath = payload['imagePath']?.toString();
      } else if (action == 'ADD_OVERNIGHT_STAY') {
        filePath = payload['billPath']?.toString();
      } else {
        continue;
      }

      if (filePath == null || filePath.trim().isEmpty) {
        if (action == 'CREATE_DOCTOR_REFERRAL' || action == 'ADD_OVERNIGHT_STAY') {
          await dbHelper.deleteSyncQueueItem(queueId);
          removedAny = true;
          removedCount += 1;
        }
        continue;
      }

      if (!File(filePath).existsSync()) {
        await dbHelper.deleteSyncQueueItem(queueId);
        removedAny = true;
        removedCount += 1;
      }
    }

    if (removedAny) {
      ApiService.notifyQueueUpdated();
      LogService.log(
        'WARN',
        'Removed invalid queued sync items',
        logger: 'sync',
        context: {'removedCount': removedCount},
      );
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
