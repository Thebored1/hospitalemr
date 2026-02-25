class DoctorReferral {
  final int? id;
  final int? tripId; // null means pending (not visited), non-null means visited
  final String name;
  final String contactNumber;
  // Address fields
  final String area;
  final String? street;
  final String? city;
  final String pin;
  final String specialization;
  final String degreeQualification;
  final String? email;
  final String? remarks;
  final String additionalDetails;
  final DateTime createdAt;
  final String status;
  final String? additionalExpenses;

  final String? visitImage;
  final double? visitLat;
  final double? visitLong;
  final bool isInternal;

  // Constructor
  DoctorReferral({
    this.id,
    this.tripId,
    required this.name,
    required this.contactNumber,
    required this.area,
    this.street,
    this.city,
    required this.pin,
    required this.specialization,
    this.degreeQualification = "MBBS",
    this.email,
    this.remarks,
    required this.additionalDetails,
    this.additionalExpenses,
    this.visitImage,
    this.visitLat,
    this.visitLong,
    required this.createdAt,
    this.status = "Assigned",
    this.isInternal = false,
  });

  // Whether this doctor has been visited (linked to a trip)
  bool get isVisited => tripId != null;

  // Formatted full address for display
  String get fullAddress {
    final parts = <String>[];
    if (area.isNotEmpty) parts.add(area);
    if (street != null && street!.isNotEmpty) parts.add(street!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (pin.isNotEmpty) parts.add(pin);
    return parts.join(', ');
  }

  factory DoctorReferral.fromJson(Map<String, dynamic> json) {
    // Parse address from address_details only (legacy fields removed from backend)
    final addressDetails = json['address_details'] as Map<String, dynamic>?;
    final areaDetails =
        addressDetails?['area_details'] as Map<String, dynamic>?;

    // Extract address data from address_details structure
    String area = '';
    String? street;
    String? city;
    String pin = '';

    if (addressDetails != null) {
      street = addressDetails['street'];

      // Get area info from area_details within address_details
      if (areaDetails != null) {
        area = areaDetails['name'] ?? '';
        city = areaDetails['city'];
        pin = areaDetails['pincode'] ?? ''; // Moved to area in backend
      } else {
        pin =
            addressDetails['pincode'] ??
            ''; // Fallback for older data structure
      }
    }

    return DoctorReferral(
      id: json['id'],
      tripId: json['trip'],
      name: json['name'] ?? '',
      contactNumber: json['contact_number'] ?? '',
      area: area,
      street: street,
      city: city,
      pin: pin,
      specialization: json['specialization'] ?? '',
      degreeQualification: json['degree_qualification'] ?? "MBBS",
      email: json['email'],
      remarks: json['remarks'],
      additionalDetails: json['additional_details'] ?? '',
      additionalExpenses: json['additional_expenses'],
      visitImage: json['visit_image'],
      visitLat: json['visit_lat'] != null
          ? double.parse(json['visit_lat'].toString())
          : null,
      visitLong: json['visit_long'] != null
          ? double.parse(json['visit_long'].toString())
          : null,
      createdAt: DateTime.parse(json['created_at']),
      status: json['status'] ?? 'Assigned',
      isInternal: json['is_internal'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'contact_number': contactNumber,
      'area': area,
      'street': street,
      'city': city,
      'pin': pin,
      'specialization': specialization,
      'degree_qualification': degreeQualification,
      'email': email,
      'remarks': remarks,
      'additional_details': additionalDetails,
      'additional_expenses': additionalExpenses,
      'visit_image': visitImage,
      'visit_lat': visitLat,
      'visit_long': visitLong,
      'created_at': createdAt.toIso8601String(),
      'status': status,
    };
  }

  String get formattedDate {
    final localTime = createdAt.toLocal();
    return "${localTime.day.toString().padLeft(2, '0')}/${localTime.month.toString().padLeft(2, '0')}/${localTime.year}";
  }

  String get formattedTime {
    final localTime = createdAt.toLocal();
    return "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}";
  }

  static List<DoctorReferral> getSampleReferrals() {
    return [
      DoctorReferral(
        name: "Dr. Sarah Johnson",
        contactNumber: "+1 555-0123",
        area: "Medical Center",
        street: "123 Main St",
        city: "New York",
        pin: "10001",
        specialization: "Cardiologist",
        additionalDetails:
            "Referred for cardiac arrhythmia consultation. Patient has history of palpitations.",
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      DoctorReferral(
        name: "Dr. Michael Chen",
        contactNumber: "+1 555-0198",
        area: "Health Ave",
        city: "City Hospital",
        pin: "10002",
        specialization: "Neurologist",
        additionalDetails: "Consultation required for chronic migraines.",
        additionalExpenses: "Parking fee: \$10",
        createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 4)),
      ),
      DoctorReferral(
        name: "Dr. Emily Davis",
        contactNumber: "+1 555-0256",
        area: "Wellness Blvd",
        pin: "10003",
        specialization: "Dermatologist",
        additionalDetails: "Skin rash persistent for 2 weeks.",
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DoctorReferral && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
