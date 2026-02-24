import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../services/camera_service.dart';

class EndTripScreen extends StatefulWidget {
  final int tripId;
  const EndTripScreen({Key? key, required this.tripId}) : super(key: key);

  @override
  _EndTripScreenState createState() => _EndTripScreenState();
}

class _EndTripScreenState extends State<EndTripScreen> {
  final TextEditingController _kilometersController = TextEditingController();
  final TextEditingController _expensesController = TextEditingController();
  // final ImagePicker -- removed for CameraService
  XFile? _endImage;
  bool _isLoading = false;

  Future<void> _pickImage() async {
    // Check location first
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable Location Services to take photo.'),
        ),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required to take photo.'),
        ),
      );
      return;
    }

    final XFile? image = await CameraService.takePicture();
    if (image != null) {
      setState(() => _endImage = image);
    }
  }

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    _checkLocationPermission();
    _calculateTotalDistance();
    _checkLostImage();
  }

  Future<void> _checkLostImage() async {
    final lostImage = await CameraService.checkForLostImage();
    if (lostImage != null && mounted) {
      setState(() {
        _endImage = lostImage;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restored photo from previous session')),
      );
    }
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Handle disabled service
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
  }

  Future<void> _calculateTotalDistance() async {
    setState(() => _isLoading = true);
    try {
      // 1. Get current location (End Point)
      Position? endPosition;
      try {
        endPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (e) {
        print("Error getting end location: $e");
      }

      // 2. Fetch Trip Details (Start Point)
      final trip = await ApiService.fetchTripById(widget.tripId);
      if (trip == null) return;

      // 3. Fetch Visited Doctors (Waypoints)
      // Note: In a real app we might need a specific API to get doctors for a trip
      // For now, let's assume we can filter the local list or fetch all and filter
      final allDoctors = await ApiService.fetchDoctorReferrals();
      final visitedDoctors = allDoctors
          .where((d) => d.tripId == widget.tripId)
          .toList();

      // 4. Construct Coordinate Sequence
      List<List<double>> coordinates = [];

      // Start
      if (trip.startLat != null && trip.startLong != null) {
        coordinates.add([trip.startLong!, trip.startLat!]);
      } else {
        // Fallback: If no start location, maybe skip or use first doctor?
        // Let's assume start is required for calc
      }

      // Visits (sorted by creation time roughly approximates route)
      visitedDoctors.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (var doc in visitedDoctors) {
        if (doc.visitLat != null && doc.visitLong != null) {
          coordinates.add([doc.visitLong!, doc.visitLat!]);
        }
      }

      // End
      if (endPosition != null) {
        coordinates.add([endPosition.longitude, endPosition.latitude]);
      }

      // 5. Call API
      if (coordinates.length >= 2) {
        final distance = await ApiService.calculateRouteDistance(coordinates);
        _kilometersController.text = distance.toStringAsFixed(2);
      }
    } catch (e) {
      print("Error calculating distance: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to calculate distance automatically.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitEndTrip() async {
    final kmStr = _kilometersController.text.trim();
    if (kmStr.isEmpty || _endImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter total kilometers and take end odometer photo.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Capture End Location again just in case valid one wasn't found earlier
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print("Error getting location: $e");
    }

    final successTrip = await ApiService.endTrip(
      widget.tripId,
      double.tryParse(kmStr) ?? 0.0,
      _expensesController.text.trim(),
      _endImage!.path,
      lat: position?.latitude,
      long: position?.longitude,
    );
    setState(() => _isLoading = false);

    if (successTrip != null) {
      if (!mounted) return;
      Navigator.pop(context, true); // Return to Dashboard with success signal
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to end trip.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("End Trip"),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Trip Summary",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Kilometers
            TextField(
              controller: _kilometersController,
              readOnly: true, // User cannot edit this manually
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Total Kilometers Traveled (Calculated)",
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(
                  0xFFEEEEEE,
                ), // Light grey to indicate read-only
              ),
            ),
            const SizedBox(height: 16),

            // Note about calculation
            const Text(
              "Distance is automatically calculated based on your route.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Expenses
            TextField(
              controller: _expensesController,
              decoration: const InputDecoration(
                labelText: "Additional Expenses (Food, Toll, etc.)",
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // End Odometer
            const Text(
              "End Odometer Reading",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: _endImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.file(
                          File(_endImage!.path),
                          fit: BoxFit.cover,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.camera_alt, size: 50, color: Colors.grey),
                          Text("Tap to take photo"),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitEndTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "End Trip",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
