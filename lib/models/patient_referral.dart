class PatientReferral {
  final String id;
  final String patientName;
  final int age;
  final String gender;
  final String phone;
  final String illness;
  final String description;
  final DateTime reportedOn;
  final String status; // "Pending", "In Progress", "Resolved"
  final bool isUrgent;
  final int? referredByDoctorId;
  final int? referredToDoctorId;

  PatientReferral({
    required this.id,
    required this.patientName,
    required this.age,
    required this.gender,
    required this.phone,
    required this.illness,
    required this.description,
    required this.reportedOn,
    required this.status,
    this.isUrgent = false,
    this.referredByDoctorId,
    this.referredToDoctorId,
  });

  // Formatted date: "15/12/2005"
  String get formattedDate {
    final localTime = reportedOn.toLocal();
    return "${localTime.day.toString().padLeft(2, '0')}/${localTime.month.toString().padLeft(2, '0')}/${localTime.year}";
  }

  // Formatted time: "16:15"
  String get formattedTime {
    final localTime = reportedOn.toLocal();
    return "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}";
  }

  // JSON serialization for REST API
  factory PatientReferral.fromJson(Map<String, dynamic> json) {
    return PatientReferral(
      id: json['id'].toString(),
      patientName: json['patient_name'] ?? '',
      age: json['age'] ?? 0,
      gender: json['gender'] ?? '',
      phone: json['phone'] ?? '',
      illness: json['illness'] ?? '',
      description: json['description'] ?? '',
      reportedOn: json['reported_on'] != null
          ? DateTime.parse(json['reported_on'])
          : DateTime.now(),
      status: json['status'] ?? 'Pending',
      isUrgent: json['is_urgent'] ?? false,
      referredByDoctorId: json['referred_by_doctor'],
      referredToDoctorId: json['referred_to_doctor'],
    );
  }

  Map<String, dynamic> toJson() {
    final map = {
      'patient_name': patientName,
      'age': age,
      'gender': gender,
      'phone': phone,
      'illness': illness,
      'description': description,
      'reported_on': reportedOn.toIso8601String(),
      'status': status,
      'is_urgent': isUrgent,
    };
    if (referredByDoctorId != null)
      map['referred_by_doctor'] = referredByDoctorId!;
    if (referredToDoctorId != null)
      map['referred_to_doctor'] = referredToDoctorId!;
    return map;
  }

  // Sample data for prototype
  static List<PatientReferral> getSamplePatients() {
    final now = DateTime.now();
    return [
      PatientReferral(
        id: '1',
        patientName: 'Ravi Kumar',
        age: 45,
        gender: 'Male',
        phone: '+91 98765 43210',
        illness: 'Fever',
        description:
            'Vivamus porta ex ac tristique hendrerit. Pellentesque vitae purus elit. Vivamus non nibh ut ante convallis egestas eu ac mi. Ut gravida euismod libero eget tempor.',
        reportedOn: DateTime(2005, 12, 15, 16, 15),
        status: 'In Progress',
      ),
      PatientReferral(
        id: '2',
        patientName: 'Ravi Rao',
        age: 38,
        gender: 'Male',
        phone: '+91 98765 43211',
        illness: 'Hay Fever',
        description:
            'Vivamus porta ex ac tristique hendrerit. Pellentesque vitae purus elit. Vivamus non nibh ut ante convallis egestas eu ac mi. Ut gravida euismod libero eget tempor.',
        reportedOn: DateTime(2005, 12, 15, 16, 15),
        status: 'Resolved',
      ),
      PatientReferral(
        id: '3',
        patientName: 'Ravi Daas',
        age: 52,
        gender: 'Male',
        phone: '+91 98765 43212',
        illness: 'Hay Fever',
        description:
            'Vivamus porta ex ac tristique hendrerit. Pellentesque vitae purus elit. Vivamus non nibh ut ante convallis egestas eu ac mi. Ut gravida euismod libero eget tempor.',
        reportedOn: DateTime(2005, 12, 15, 16, 15),
        status: 'Resolved',
      ),
    ];
  }
}
