import 'doctor.dart';

class OvernightStay {
  final int id;
  final String hotelName;
  final String hotelAddress;
  final String? billImagePath;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  OvernightStay({
    required this.id,
    required this.hotelName,
    required this.hotelAddress,
    this.billImagePath,
    this.latitude,
    this.longitude,
    required this.createdAt,
  });

  factory OvernightStay.fromJson(Map<String, dynamic> json) {
    return OvernightStay(
      id: json['id'],
      hotelName: json['hotel_name'],
      hotelAddress: json['hotel_address'],
      billImagePath: json['bill_image'],
      latitude: json['latitude'] != null
          ? double.tryParse(json['latitude'].toString())
          : null,
      longitude: json['longitude'] != null
          ? double.tryParse(json['longitude'].toString())
          : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class Trip {
  final int id;
  final int tripNumber; // Agent-specific
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // 'ONGOING', 'COMPLETED'
  final String? odometerStartImagePath;
  final String? odometerEndImagePath;
  final double totalKilometers;
  final String? additionalExpenses;
  final double? startLat;
  final double? startLong;
  final double? endLat;
  final double? endLong;
  final List<DoctorReferral> doctorReferrals;
  final List<OvernightStay> overnightStays;

  Trip({
    required this.id,
    this.tripNumber = 0,
    required this.startTime,
    this.endTime,
    required this.status,
    this.odometerStartImagePath,
    this.odometerEndImagePath,
    this.totalKilometers = 0.0,
    this.additionalExpenses,
    this.startLat,
    this.startLong,
    this.endLat,
    this.endLong,
    this.doctorReferrals = const [],
    this.overnightStays = const [],
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'],
      tripNumber: json['trip_number'] ?? json['id'],
      startTime: DateTime.parse(json['start_time']),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'])
          : null,
      status: json['status'],
      odometerStartImagePath: json['odometer_start_image'],
      odometerEndImagePath: json['odometer_end_image'],
      totalKilometers: json['total_kilometers'] ?? 0.0,
      additionalExpenses: json['additional_expenses'],
      startLat: json['start_lat'] != null
          ? double.parse(json['start_lat'].toString())
          : null,
      startLong: json['start_long'] != null
          ? double.parse(json['start_long'].toString())
          : null,
      endLat: json['end_lat'] != null
          ? double.parse(json['end_lat'].toString())
          : null,
      endLong: json['end_long'] != null
          ? double.parse(json['end_long'].toString())
          : null,
      doctorReferrals:
          (json['doctor_referrals'] as List<dynamic>?)
              ?.map((e) => DoctorReferral.fromJson(e))
              .toList() ??
          [],
      overnightStays:
          (json['overnight_stays'] as List<dynamic>?)
              ?.map((e) => OvernightStay.fromJson(e))
              .toList() ??
          [],
    );
  }
}
