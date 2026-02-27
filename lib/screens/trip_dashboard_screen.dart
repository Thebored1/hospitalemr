import 'package:flutter/material.dart';
import '../models/trip.dart';
import '../models/doctor.dart';
import '../services/api_service.dart';
import 'refer_doctor_screen.dart'; // DoctorReferralForm is defined here now
import 'add_hotel_screen.dart';
import 'end_trip_screen.dart'; // We'll create this next
import 'doctor_referral_details_screen.dart';
import 'hotel_stay_details_screen.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart'; // Added for distance calc
import '../widgets/network_indicator.dart';

class TripDashboardScreen extends StatefulWidget {
  final Trip trip;
  const TripDashboardScreen({Key? key, required this.trip}) : super(key: key);

  @override
  _TripDashboardScreenState createState() => _TripDashboardScreenState();
}

class _TripDashboardScreenState extends State<TripDashboardScreen> {
  late Trip _trip;
  bool _isLoading = false;
  List<DoctorReferral> _pendingDoctors =
      []; // Doctors assigned by admin but not visited yet

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _refreshTrip();
  }

  Future<void> _refreshTrip() async {
    setState(() => _isLoading = true);
    try {
      final updatedTrip = await ApiService.fetchTripById(_trip.id);
      final allDoctors = await ApiService.fetchDoctorReferrals();

      // Merge server trip with local optimistic visits so offline entries
      // aren't lost when the server data arrives before the sync completes.
      Trip currentTrip = _trip;
      if (updatedTrip != null) {
        final serverRefIds = updatedTrip.doctorReferrals
            .map((d) => d.id)
            .toSet();
        final localOnly = _trip.doctorReferrals
            .where((d) => !serverRefIds.contains(d.id))
            .toList();
        // Keep server data as base, but inject any local-only optimistic visits
        final mergedRefs = [...updatedTrip.doctorReferrals, ...localOnly];
        currentTrip = updatedTrip.copyWith(doctorReferrals: mergedRefs);
      }

      final visitedInThisTripNames = currentTrip.doctorReferrals
          .map((d) => d.name.trim().toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();

      final uniquePending = <String, DoctorReferral>{};
      final seenNames = <String>{};

      for (var doc in allDoctors) {
        final nameKey = doc.name.trim().toLowerCase();
        if (nameKey.isEmpty) continue;
        if (visitedInThisTripNames.contains(nameKey)) continue;
        if (seenNames.contains(nameKey)) continue;
        seenNames.add(nameKey);
        uniquePending[nameKey] = doc;
      }

      final pending = uniquePending.values.toList();

      if (!mounted) return;
      setState(() {
        _trip = currentTrip;
        _pendingDoctors = pending;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error refreshing trip: $e");
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _navigateToAddDoctor() {
    if (_pendingDoctors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No assigned doctors available to visit.'),
        ),
      );
      return;
    }

    // Show bottom sheet with pending doctors to select from
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.person_add, color: Colors.blue),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Select Doctor to Visit',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Removed "Add New" button to force selection from assigned list
                ],
              ),
            ),
            const Divider(height: 1),
            // Pending doctors list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _pendingDoctors.length,
                itemBuilder: (context, index) {
                  final doc = _pendingDoctors[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: Icon(Icons.person, color: Colors.blue.shade700),
                    ),
                    title: Text(
                      doc.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (doc.specialization.isNotEmpty)
                          Text(doc.specialization),
                        if (doc.fullAddress.isNotEmpty)
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 12,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  doc.fullAddress,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    trailing: const Icon(
                      Icons.check_circle_outline,
                      color: Colors.green,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      // Navigate to form with existing doctor
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DoctorReferralForm(
                            tripId: _trip.id,
                            existingDoctor: doc,
                          ),
                        ),
                      ).then((refresh) {
                        if (refresh == true) {
                          _refreshTrip();
                        }
                      });
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

  /// Returns true if the doctor visit is missing any mandatory fields.
  bool _isIncomplete(DoctorReferral d) {
    return d.contactNumber.trim().isEmpty ||
        d.specialization.trim().isEmpty ||
        d.degreeQualification.trim().isEmpty ||
        d.area.trim().isEmpty ||
        d.pin.trim().isEmpty ||
        (d.visitImage == null || d.visitImage!.trim().isEmpty);
  }

  void _endTrip() {
    // Hard block — use _isIncomplete helper
    final incompleteCount = _trip.doctorReferrals
        .where((d) => _isIncomplete(d))
        .length;
    if (incompleteCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$incompleteCount doctor visit${incompleteCount > 1 ? 's have' : ' has'} incomplete mandatory fields. Tap the ⚠ entry to complete it.',
          ),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EndTripScreen(tripId: _trip.id)),
    ).then((result) {
      if (result == true) {
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    });
  }

  void _viewImageFullScreen(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(child: Image.network(imageUrl)),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Combine DoctorReferrals and OvernightStays into single timeline list
    final List<dynamic> timelineItems = [
      ..._trip.doctorReferrals,
      ..._trip.overnightStays,
    ];
    // Sort by created time
    timelineItems.sort((a, b) {
      DateTime timeA = a is DoctorReferral
          ? a.createdAt
          : (a as OvernightStay).createdAt;
      DateTime timeB = b is DoctorReferral
          ? b.createdAt
          : (b as OvernightStay).createdAt;
      return timeA.compareTo(timeB); // Ascending
    });

    return Scaffold(
      appBar: AppBar(
        title: Text("Trip #${_trip.tripNumber}"),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          const Center(
            child: Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: NetworkIndicator(),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color:
                      Colors.black, // Changed to black to be visible on white
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshTrip,
            ),
        ],
      ),
      body: Column(
        children: [
          // Trip Info Card
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_car, color: Colors.blue),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Trip Started",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          DateFormat(
                            'MMM dd, hh:mm a',
                          ).format(_trip.startTime.toLocal()),
                        ),
                        if (_trip.endTime != null) ...[
                          const SizedBox(height: 4),
                          const Text(
                            "Trip Ended",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            DateFormat(
                              'MMM dd, hh:mm a',
                            ).format(_trip.endTime!.toLocal()),
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _trip.status == 'ONGOING'
                            ? Colors.green.shade100
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _trip.status,
                        style: TextStyle(
                          color: _trip.status == 'ONGOING'
                              ? Colors.green.shade800
                              : Colors.grey.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_trip.additionalExpenses != null &&
                        _trip.additionalExpenses!.isNotEmpty ||
                    _trip.totalKilometers > 0) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (_trip.totalKilometers > 0)
                    Row(
                      children: [
                        const Icon(Icons.speed, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          "Distance: ${_trip.totalKilometers} km",
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  if (_trip.totalKilometers > 0 &&
                      _trip.additionalExpenses != null)
                    const SizedBox(height: 8),
                  if (_trip.additionalExpenses != null &&
                      _trip.additionalExpenses!.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.attach_money,
                          size: 16,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Expenses: ${_trip.additionalExpenses}",
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                ],
                if ((_trip.odometerStartImagePath != null ||
                        _trip.odometerEndImagePath != null) &&
                    _trip.status != 'ONGOING') ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Odometer Photos",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_trip.odometerStartImagePath != null)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _viewImageFullScreen(
                              _trip.odometerStartImagePath!,
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  "Start",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    _trip.odometerStartImagePath!,
                                    height: 80,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(Icons.broken_image),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_trip.odometerStartImagePath != null &&
                          _trip.odometerEndImagePath != null)
                        const SizedBox(width: 12),
                      if (_trip.odometerEndImagePath != null)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _viewImageFullScreen(
                              _trip.odometerEndImagePath!,
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  "End",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    _trip.odometerEndImagePath!,
                                    height: 80,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(Icons.broken_image),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Pending Doctors Section
          if (_pendingDoctors.isNotEmpty && _trip.status != 'COMPLETED')
            _buildPendingDoctorsSection(),

          Expanded(
            child: timelineItems.isEmpty
                ? const Center(child: Text("No activities added yet."))
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: timelineItems.length,
                    itemBuilder: (context, index) {
                      final item = timelineItems[index];
                      return _buildTimelineItem(
                        item,
                        index == timelineItems.length - 1,
                      );
                    },
                  ),
          ),

          // Actions
          if (_trip.status != 'COMPLETED')
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.person_add),
                          label: const Text("Add Doctor"),
                          onPressed: _navigateToAddDoctor,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.hotel),
                          label: const Text("Add Hotel"),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    AddHotelScreen(tripId: _trip.id),
                              ),
                            ).then((_) => _refreshTrip());
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            side: const BorderSide(color: Colors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _endTrip,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text("End Trip"),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPendingDoctorsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_add, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Doctors to Visit (${_pendingDoctors.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 85,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pendingDoctors.length,
              itemBuilder: (context, index) {
                final doc = _pendingDoctors[index];
                return GestureDetector(
                  onTap: () {
                    // Navigate to form with existing doctor to complete visit
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DoctorReferralForm(
                          tripId: _trip.id,
                          existingDoctor: doc,
                        ),
                      ),
                    ).then((refresh) {
                      if (refresh == true) {
                        _refreshTrip();
                      }
                    });
                  },
                  child: Container(
                    width: 180,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (doc.specialization.isNotEmpty)
                          Text(
                            doc.specialization,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const Spacer(),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 10,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                doc.fullAddress.isNotEmpty
                                    ? doc.fullAddress
                                    : 'No address',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(dynamic item, bool isLast) {
    bool isDoctor = item is DoctorReferral;
    String title = isDoctor ? item.name : (item as OvernightStay).hotelName;
    String subtitle = isDoctor
        ? item.specialization
        : (item as OvernightStay).hotelAddress;
    DateTime time = isDoctor
        ? item.createdAt
        : (item as OvernightStay).createdAt;
    IconData icon = isDoctor ? Icons.person : Icons.hotel;

    // Calculate distance from start if coordinates exist
    String? distanceText;
    if (isDoctor && _trip.startLat != null && _trip.startLong != null) {
      final doc = item as DoctorReferral;
      if (doc.visitLat != null && doc.visitLong != null) {
        final distMeters = Geolocator.distanceBetween(
          _trip.startLat!,
          _trip.startLong!,
          doc.visitLat!,
          doc.visitLong!,
        );
        distanceText =
            "${(distMeters / 1000).toStringAsFixed(1)} km from start";
      }
    }

    // For doctor timeline entries, show warning badge if incomplete
    final bool incompleteEntry = isDoctor && _isIncomplete(item);

    return GestureDetector(
      onTap: () {
        if (isDoctor) {
          final doc = item as DoctorReferral;
          if (incompleteEntry) {
            // Open edit form so the agent can complete the missing fields
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    DoctorReferralForm(tripId: _trip.id, existingDoctor: doc),
              ),
            ).then((refresh) {
              if (refresh == true) _refreshTrip();
            });
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DoctorReferralDetailsScreen(referral: doc),
              ),
            ).then((_) => _refreshTrip());
          }
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  HotelStayDetailsScreen(stay: item as OvernightStay),
            ),
          );
        }
      },
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: incompleteEntry
                            ? Colors.orange.shade50
                            : Colors.white,
                        border: Border.all(
                          color: incompleteEntry
                              ? Colors.orange.shade400
                              : Colors.grey.shade300,
                          width: incompleteEntry ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: incompleteEntry ? Colors.orange : Colors.black,
                      ),
                    ),
                    if (incompleteEntry)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.orange,
                          ),
                          child: const Icon(
                            Icons.priority_high,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: Colors.grey.shade200),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (distanceText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Text(
                              distanceText,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(subtitle, style: const TextStyle(color: Colors.grey)),
                    if (incompleteEntry)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "Incomplete Draft - Tap to complete",
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      DateFormat('hh:mm a').format(time.toLocal()),
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
