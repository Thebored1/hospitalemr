import '../models/doctor.dart';
import '../models/trip.dart';

class TripQueueProcessor {
  static Trip mergeTripWithQueue(
    Trip trip,
    List<Map<String, dynamic>> queueItems,
  ) {
    if (queueItems.isEmpty) return trip;

    final newDoctors = <DoctorReferral>[];
    final updatesById = <int, DoctorReferral>{};
    final queuedStays = <OvernightStay>[];
    bool queuedEndTrip = false;
    Trip updatedTrip = trip;
    final seenDoctorIds = <int>{};

    for (final doc in updatedTrip.doctorReferrals) {
      if (doc.id != null) {
        seenDoctorIds.add(doc.id!);
      }
    }

    for (final item in queueItems) {
      final action = item['action']?.toString() ?? '';
      final payload = item['payload'] as Map<String, dynamic>;
      final createdAtStr = item['created_at'] as String?;
      final createdAt =
          DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now();

      if (action == 'CREATE_DOCTOR_REFERRAL') {
        final queuedDoctor =
            _doctorFromQueueCreation(payload, trip.id, createdAt);
        final queuedId = queuedDoctor.id;
        if (queuedId != null && seenDoctorIds.contains(queuedId)) {
          continue;
        }
        if (queuedId != null) {
          seenDoctorIds.add(queuedId);
        }
        newDoctors.add(queuedDoctor);
      } else if (action == 'UPDATE_DOCTOR_REFERRAL') {
        final doc = _doctorFromQueueUpdate(payload, trip.id, createdAt);
        if (doc.id != null) {
          updatesById[doc.id!] = doc;
        }
      } else if (action == 'ADD_OVERNIGHT_STAY') {
        queuedStays.add(_overnightStayFromQueue(payload, createdAt));
      } else if (action == 'END_TRIP') {
        queuedEndTrip = true;
        updatedTrip = _applyQueuedEndTrip(updatedTrip, payload, createdAt);
      }
    }

    final mergedDoctors = [
      for (final doc in updatedTrip.doctorReferrals)
        if (doc.id != null && updatesById.containsKey(doc.id))
          _mergeDoctorReferral(doc, updatesById[doc.id!]!)
        else
          doc,
      ...newDoctors,
    ];

    final mergedStays = [
      ...updatedTrip.overnightStays,
      ...queuedStays,
    ];

    return updatedTrip.copyWith(
      doctorReferrals: mergedDoctors,
      overnightStays: mergedStays,
      status: queuedEndTrip ? 'COMPLETED' : updatedTrip.status,
    );
  }

  static DoctorReferral _mergeDoctorReferral(
    DoctorReferral base,
    DoctorReferral update,
  ) {
    String pickRequired(String updated, String original) =>
        updated.trim().isNotEmpty ? updated : original;

    String? pickOptional(String? updated, String? original) {
      if (updated == null) return original;
      // Allow explicit clears only when a non-null value is provided; keep original otherwise.
      return updated;
    }

    String? pickImage(String? updated, String? original) {
      final updatedVal = updated?.trim() ?? '';
      if (updatedVal.isNotEmpty) return updatedVal;
      final originalVal = original?.trim() ?? '';
      return originalVal.isNotEmpty ? originalVal : null;
    }

    return DoctorReferral(
      id: base.id,
      tripId: base.tripId,
      name: pickRequired(update.name, base.name),
      contactNumber: pickRequired(update.contactNumber, base.contactNumber),
      area: pickRequired(update.area, base.area),
      street: pickOptional(update.street, base.street),
      city: pickOptional(update.city, base.city),
      pin: pickRequired(update.pin, base.pin),
      specialization: pickRequired(update.specialization, base.specialization),
      degreeQualification:
          pickRequired(update.degreeQualification, base.degreeQualification),
      email: pickOptional(update.email, base.email),
      remarks: pickOptional(update.remarks, base.remarks),
      additionalDetails:
          pickRequired(update.additionalDetails, base.additionalDetails),
      additionalExpenses: pickOptional(update.additionalExpenses, base.additionalExpenses),
      visitImage: pickImage(update.visitImage, base.visitImage),
      visitLat: update.visitLat ?? base.visitLat,
      visitLong: update.visitLong ?? base.visitLong,
      createdAt: base.createdAt,
      status: pickRequired(update.status, base.status),
      isInternal: update.isInternal,
    );
  }

  static DoctorReferral _doctorFromQueueCreation(
    Map<String, dynamic> payload,
    int tripId,
    DateTime createdAt,
  ) {
    final referral = Map<String, dynamic>.from(
      (payload['referral'] as Map<String, dynamic>?) ?? {},
    );
    referral['trip'] = tripId;
    referral['created_at'] ??= createdAt.toIso8601String();
    if ((referral['visit_image'] ?? '').toString().isEmpty &&
        (payload['imagePath'] ?? '').toString().isNotEmpty) {
      referral['visit_image'] = payload['imagePath'];
    }
    referral['visit_lat'] ??= payload['lat'];
    referral['visit_long'] ??= payload['long'];
    return DoctorReferral.fromJson(referral);
  }

  static DoctorReferral _doctorFromQueueUpdate(
    Map<String, dynamic> payload,
    int tripId,
    DateTime createdAt,
  ) {
    final data = Map<String, dynamic>.from(
      (payload['data'] as Map<String, dynamic>?) ?? {},
    );
    data['id'] = payload['id'];
    data['trip'] = data['trip'] ?? tripId;
    data['created_at'] ??= createdAt.toIso8601String();
    if ((data['visit_image'] ?? '').toString().isEmpty &&
        (payload['imagePath'] ?? '').toString().isNotEmpty) {
      data['visit_image'] = payload['imagePath'];
    }
    data['visit_lat'] ??= payload['lat'];
    data['visit_long'] ??= payload['long'];
    return DoctorReferral.fromJson(data);
  }

  static OvernightStay _overnightStayFromQueue(
    Map<String, dynamic> payload,
    DateTime createdAt,
  ) {
    return OvernightStay(
      id: -(createdAt.millisecondsSinceEpoch),
      hotelName: payload['name']?.toString() ?? 'Hotel Stay (Queued)',
      hotelAddress: payload['address']?.toString() ?? '',
      billImagePath: payload['billPath']?.toString(),
      latitude: _toDouble(payload['lat']),
      longitude: _toDouble(payload['long']),
      createdAt: createdAt,
    );
  }

  static Trip _applyQueuedEndTrip(
    Trip trip,
    Map<String, dynamic> payload,
    DateTime createdAt,
  ) {
    final kilometers = _toDouble(payload['kilometers']) ?? trip.totalKilometers;
    final expenses = payload['expenses']?.toString() ?? trip.additionalExpenses;
    final odometerEnd =
        payload['odometerEndPath']?.toString() ?? trip.odometerEndImagePath;
    final lat = _toDouble(payload['lat']) ?? trip.endLat;
    final long = _toDouble(payload['long']) ?? trip.endLong;

    return trip.copyWith(
      status: 'COMPLETED',
      endTime: createdAt,
      totalKilometers: kilometers,
      additionalExpenses: expenses,
      odometerEndImagePath: odometerEnd,
      endLat: lat,
      endLong: long,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
