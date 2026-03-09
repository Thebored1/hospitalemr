import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; // Added for distance calc
import '../models/patient_referral.dart';
import '../models/doctor.dart';
import '../services/api_service.dart';
import '../utils/trip_queue_processor.dart';
import '../widgets/tap_to_call_text.dart'; // Added import
import 'add_patient_screen.dart';
import 'trip_dashboard_screen.dart';
import 'start_trip_screen.dart';
import '../models/trip.dart';
import 'package:intl/intl.dart';
import 'login_screen.dart';

class AdvisorDashboardScreen extends StatefulWidget {
  final VoidCallback? onProfileTap;

  const AdvisorDashboardScreen({super.key, this.onProfileTap});

  @override
  State<AdvisorDashboardScreen> createState() => _AdvisorDashboardScreenState();
}

class _AdvisorDashboardScreenState extends State<AdvisorDashboardScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  List<PatientReferral> _patients = [];
  List<Trip> _trips = [];
  List<DoctorReferral> _assignedDoctors = []; // Doctors assigned by admin
  Set<String> _visitedDoctorNames = {};
  bool _isLoading = true;
  TabController? _tabController;
  String _searchQuery = '';
  Map<int, bool> _queuedTripMap = {};
  StreamSubscription<void>? _queueSubscription;
  StreamSubscription<void>? _dataSubscription;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _fetchData();
    _queueSubscription = ApiService.queueStream.listen((_) => _fetchData());
    _dataSubscription = ApiService.dataStream.listen((_) => _fetchData());
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final patients = await ApiService.fetchPatientReferrals();
      final trips = await ApiService.fetchTrips();
      final doctors = await ApiService.fetchDoctorReferrals();
      // Sort trips by start time descending
      trips.sort((a, b) => b.startTime.compareTo(a.startTime));
      final queuedMapRaw =
          await ApiService.queuedActionsGroupedByTrip();
      final processedTrips = trips
          .map((trip) => TripQueueProcessor.mergeTripWithQueue(
                trip,
                queuedMapRaw[trip.id] ?? [],
              ))
          .toList();
      final visitedNames = <String>{};
      for (final trip in processedTrips) {
        for (final doc in trip.doctorReferrals) {
          final nameKey = doc.name.trim().toLowerCase();
          if (nameKey.isNotEmpty) {
            visitedNames.add(nameKey);
          }
        }
      }
      final queuedMap = <int, bool>{};
      queuedMapRaw.forEach((key, value) {
        queuedMap[key] = value.isNotEmpty;
      });

      if (mounted) {
        setState(() {
          _patients = patients;
          _trips = processedTrips;
          _assignedDoctors = doctors;
          _visitedDoctorNames = visitedNames;
          _queuedTripMap = queuedMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching dashboard data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController?.dispose();
    _queueSubscription?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  void _initTabController() {
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(() {
      setState(() {}); // Rebuild to update UI based on tab selection
    });
  }

  List<PatientReferral> _getFilteredPatients() {
    if (_searchQuery.isEmpty) {
      return _patients;
    }
    return _patients.where((patient) {
      return patient.patientName.toLowerCase().contains(_searchQuery) ||
          patient.illness.toLowerCase().contains(_searchQuery) ||
          patient.status.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  List<Trip> _getFilteredTrips() {
    if (_searchQuery.isEmpty) {
      return _trips;
    }
    return _trips.where((trip) {
      final dateStr = DateFormat('MMM dd, yyyy').format(trip.startTime);
      return trip.status.toLowerCase().contains(_searchQuery) ||
          dateStr.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  // Get doctors that are assigned (show all, so agent knows who is in their area)
  // Deduplicate by name to prevent showing multiple copies for each visit
  List<DoctorReferral> get _pendingDoctors {
    final seen = <String>{};
    return _assignedDoctors
    // Backend already filters by current assignment + visited/disabled state.
    // Do not rely on global doctor.status here.
    .where((doc) {
      final key = doc.name.trim().toLowerCase();
      return key.isNotEmpty &&
          !_visitedDoctorNames.contains(key) &&
          seen.add(key);
    }) // First occurrence (Newest) wins
    .toList();
  }

  Widget _buildAssignedDoctorsNotification() {
    final pending = _pendingDoctors;
    if (pending.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_add, color: Colors.blue.shade700, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  pending.length == 1
                      ? 'New Doctor Assigned to You'
                      : '${pending.length} New Doctors Assigned to You',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.blue.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...pending
              .take(3)
              .map(
                (doc) => GestureDetector(
                  onTap: () => _showDoctorDetails(doc),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${doc.name}${doc.specialization.isNotEmpty ? ' - ${doc.specialization}' : ''}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (doc.fullAddress.isNotEmpty)
                                Text(
                                  doc.fullAddress,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Colors.blue.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          if (pending.length > 3)
            GestureDetector(
              onTap: () => _showAllPendingDoctors(),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '...and ${pending.length - 3} more (tap to view)',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Tap a doctor to make connections',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  void _showDoctorDetails(DoctorReferral doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person,
                      size: 32,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (doc.specialization.isNotEmpty)
                          Text(
                            doc.specialization,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Pending Visit',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Details
              _buildDetailRow(
                Icons.school,
                'Qualification',
                doc.degreeQualification.isNotEmpty
                    ? doc.degreeQualification
                    : 'Not specified',
              ),
              _buildDetailRow(
                Icons.phone,
                'Contact',
                doc.contactNumber.isNotEmpty
                    ? doc.contactNumber
                    : 'Not provided',
              ),
              if (doc.email != null && doc.email!.isNotEmpty)
                _buildDetailRow(Icons.email, 'Email', doc.email!),
              _buildDetailRow(
                Icons.location_on,
                'Address',
                doc.fullAddress.isNotEmpty ? doc.fullAddress : 'Not provided',
              ),
              if (doc.remarks != null && doc.remarks!.isNotEmpty)
                _buildDetailRow(Icons.note, 'Remarks', doc.remarks!),
              if (doc.additionalDetails.isNotEmpty)
                _buildDetailRow(
                  Icons.info_outline,
                  'Additional Details',
                  doc.additionalDetails,
                ),
              const SizedBox(height: 16),
              // Added on date
              Text(
                'Assigned on: ${doc.formattedDate}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TapToCallText(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 2),
                TapToCallText(value, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAllPendingDoctors() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar and title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'All Pending Doctors (${_pendingDoctors.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // List of doctors
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _pendingDoctors.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final doc = _pendingDoctors[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: Icon(Icons.person, color: Colors.blue.shade700),
                    ),
                    title: Text(
                      doc.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${doc.fullAddress.isNotEmpty ? doc.fullAddress : ''}${doc.specialization.isNotEmpty ? ' (${doc.specialization})' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      _showDoctorDetails(doc);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController == null) {
      _initTabController();
    }

    final filteredPatients = _getFilteredPatients();
    final filteredTrips = _getFilteredTrips();
    final tripsCount = _trips.length;
    final lastTrip = _trips.isNotEmpty ? _trips.first : null;

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 20.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Header Section ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Dashboard",
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  // Logout logic
                                  await ApiService.logout();
                                  if (mounted) {
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const LoginScreen(),
                                      ),
                                      (route) => false,
                                    );
                                  }
                                },
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFD9D9D9),
                                  ),
                                  child: const Icon(Icons.logout, size: 20),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: widget.onProfileTap,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFD9D9D9),
                                  ),
                                  child: const Icon(Icons.swap_horiz, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),

                      // --- Referred Patients Card ---
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- Left Column: Info ---
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Trips Taken",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  Text(
                                    tripsCount.toString().padLeft(2, '0'),
                                    style: const TextStyle(
                                      fontSize: 64,
                                      fontWeight: FontWeight.bold,
                                      height: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (lastTrip != null)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Last Entry",
                                          style: TextStyle(
                                            color: Colors.black87,
                                            fontSize: 14,
                                          ),
                                        ),
                                        RichText(
                                          text: TextSpan(
                                            style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 14,
                                            ),
                                            children: [
                                              TextSpan(
                                                text:
                                                    "${DateFormat('MMM dd, yyyy').format(lastTrip.startTime.toLocal())}, ",
                                              ),
                                              TextSpan(
                                                text: DateFormat('hh:mm a')
                                                    .format(
                                                      lastTrip.startTime
                                                          .toLocal(),
                                                    ),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),

                            // --- Right Column: Buttons ---
                            Column(
                              children: [
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const AddPatientScreen(),
                                      ),
                                    ).then((_) => _fetchData());
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    elevation: 0,
                                    minimumSize: const Size(140, 50),
                                  ),
                                  child: const Text(
                                    "Add New\nPatient",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, height: 1.2),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: () {
                                    // Always start a new trip
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const StartTripScreen(),
                                      ),
                                    ).then((_) => _fetchData());
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    elevation: 0,
                                    minimumSize: const Size(140, 50),
                                  ),
                                  child: const Text(
                                    "Start \nTrip",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, height: 1.2),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- Assigned Doctors Notification ---
                      _buildAssignedDoctorsNotification(),

                      // --- Search Bar ---
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: _tabController!.index == 0
                                ? "Search trips..."
                                : "Search patients...",
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),

                      const SizedBox(height: 30),

                      // --- Tabs Header ---
                      Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          indicator: BoxDecoration(
                            borderRadius: BorderRadius.circular(25),
                            color: Colors.black,
                          ),
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.black54,
                          tabs: const [
                            Tab(text: "Trips"),
                            Tab(text: "Patients"),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- Tab Content ---
                      if (_tabController!.index == 0) ...[
                        // Trips List
                        if (filteredTrips.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(40.0),
                              child: Text(
                                _searchQuery.isEmpty
                                    ? "No trips yet"
                                    : "No trips found for '$_searchQuery'",
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          )
                        else
                          ...filteredTrips.map(
                            (trip) => Padding(
                              padding: const EdgeInsets.only(bottom: 30.0),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TripDashboardScreen(trip: trip),
                                    ),
                                  ).then((_) => _fetchData());
                                },
                                child: TripCard(
                                  trip: trip,
                                  hasQueuedSync: _queuedTripMap[trip.id] ?? false,
                                ),
                              ),
                            ),
                          ),
                      ] else ...[
                        // Patients List
                        if (filteredPatients.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(40.0),
                              child: Text(
                                _searchQuery.isEmpty
                                    ? "No patients yet"
                                    : "No patients found for '$_searchQuery'",
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          )
                        else
                          ...filteredPatients.map(
                            (patient) => Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: PatientCard(patient: patient),
                            ),
                          ),
                      ],

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// --- Patient Card Widget ---
class PatientCard extends StatelessWidget {
  final PatientReferral patient;

  const PatientCard({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name and Date Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.patientName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Illness: ${patient.illness}",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    "Reported on",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black, fontSize: 13),
                      children: [
                        TextSpan(text: "${patient.formattedDate}, "),
                        TextSpan(
                          text: patient.formattedTime,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Description Text
          Text(
            patient.description,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              height: 1.4,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 20),

          // Status Badge (Read-only - controlled by admin)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                patient.status,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TripCard extends StatelessWidget {
  final Trip trip;
  final bool hasQueuedSync;

  const TripCard({
    super.key,
    required this.trip,
    this.hasQueuedSync = false,
  });

  @override
  Widget build(BuildContext context) {
    final localStartTime = trip.startTime.toLocal();
    final dateStr = DateFormat('MMM dd, yyyy').format(localStartTime);
    final timeStr = DateFormat('hh:mm a').format(localStartTime);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.directions_car, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    "Trip #${trip.tripNumber}",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: trip.status == 'ONGOING'
                      ? const Color(0xFFE3F2FD) // Light Blue
                      : const Color(0xFFF5F5F5), // Light Grey
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: trip.status == 'ONGOING'
                        ? const Color(0xFF2196F3)
                        : Colors.grey.shade400,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: trip.status == 'ONGOING'
                            ? const Color(0xFF2196F3)
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      trip.status == 'ONGOING' ? 'Ongoing' : 'Completed',
                      style: TextStyle(
                        color: trip.status == 'ONGOING'
                            ? const Color(0xFF1565C0)
                            : Colors.grey.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasQueuedSync)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.sync, size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    'Queued for sync',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: Colors.black54),
              const SizedBox(width: 8),
              Text(
                "$dateStr at $timeStr",
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (trip.totalKilometers > 0)
            Row(
              children: [
                const Icon(Icons.speed, size: 16, color: Colors.black54),
                const SizedBox(width: 8),
                Text(
                  "${trip.totalKilometers} km",
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ],
            )
          else if (trip.status == 'ONGOING' &&
              trip.startLat != null &&
              trip.startLong != null)
            // Calculate approximate distance so far
            Builder(
              builder: (context) {
                double totalDistMeters = 0;
                // Filter doctors with visits
                final visited = trip.doctorReferrals
                    .where((d) => d.visitLat != null && d.visitLong != null)
                    .toList();
                // Sort by created
                visited.sort((a, b) => a.createdAt.compareTo(b.createdAt));

                if (visited.isNotEmpty) {
                  // Start to First
                  totalDistMeters += Geolocator.distanceBetween(
                    trip.startLat!,
                    trip.startLong!,
                    visited.first.visitLat!,
                    visited.first.visitLong!,
                  );

                  // Between visits
                  for (int i = 0; i < visited.length - 1; i++) {
                    totalDistMeters += Geolocator.distanceBetween(
                      visited[i].visitLat!,
                      visited[i].visitLong!,
                      visited[i + 1].visitLat!,
                      visited[i + 1].visitLong!,
                    );
                  }
                }

                if (totalDistMeters > 0) {
                  return Row(
                    children: [
                      const Icon(Icons.speed, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        "${(totalDistMeters / 1000).toStringAsFixed(1)} km so far",
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),

          const SizedBox(height: 20),

          Align(
            alignment: Alignment.centerRight,
            child: Text(
              trip.status == 'ONGOING' ? "Tap to Manage >" : "Tap to View >",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
