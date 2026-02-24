import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/camera_service.dart';

class AddHotelScreen extends StatefulWidget {
  final int tripId;
  const AddHotelScreen({Key? key, required this.tripId}) : super(key: key);

  @override
  _AddHotelScreenState createState() => _AddHotelScreenState();
}

class _AddHotelScreenState extends State<AddHotelScreen> {
  final _hotelNameController = TextEditingController();
  final _addressController = TextEditingController();
  File? _billImage;
  // final _picker = ImagePicker(); -- removed for CameraService
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkLostImage();
  }

  Future<void> _checkLostImage() async {
    final lostImage = await CameraService.checkForLostImage();
    if (lostImage != null && mounted) {
      setState(() {
        _billImage = File(lostImage.path);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restored photo from previous session')),
      );
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    // We only support camera via Native fix for now, ignore source arg or force camera
    // The UI only shows camera icon anyway.
    final XFile? pickedFile = await CameraService.takePicture();

    if (pickedFile != null) {
      setState(() {
        _billImage = File(pickedFile.path);
      });
    }
  }

  void _submitHotel() async {
    final name = _hotelNameController.text.trim();
    final address = _addressController.text.trim();

    if (name.isEmpty || address.isEmpty || _billImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all fields and upload bill image'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Capture GPS Location
    double? lat;
    double? long;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();
      if (serviceEnabled &&
          (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse)) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        lat = position.latitude;
        long = position.longitude;
      }
    } catch (e) {
      print("Error capturing hotel location: $e");
    }

    final success = await ApiService.addOvernightStay(
      widget.tripId,
      name,
      address,
      _billImage!.path,
      lat,
      long,
    );

    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hotel added successfully')));
      Navigator.pop(
        context,
      ); // Go back to dashboard to potentially add another or view
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to add hotel')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Hotel Stay"),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Hotel Details",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(_hotelNameController, "Hotel Name *"),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _addressController,
                    "Hotel Address *",
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Bill / Receipt Image *",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _pickImage(ImageSource.camera),
                    child: Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: _billImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.file(_billImage!, fit: BoxFit.cover),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.camera_alt,
                                  size: 40,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "Tap to take photo",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitHotel,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Save Hotel Details",
                        style: TextStyle(
                          fontSize: 16,
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

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
