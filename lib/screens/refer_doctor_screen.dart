import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import '../models/doctor.dart';
import '../services/api_service.dart';
import '../services/camera_service.dart';
import '../widgets/network_indicator.dart';

class DoctorReferralForm extends StatefulWidget {
  final int tripId;
  final DoctorReferral? existingDoctor;

  const DoctorReferralForm({
    Key? key,
    required this.tripId,
    this.existingDoctor,
  }) : super(key: key);

  @override
  _DoctorReferralFormState createState() => _DoctorReferralFormState();
}

class _DoctorReferralFormState extends State<DoctorReferralForm> {
  final _contactController = TextEditingController();
  final _areaController = TextEditingController();
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _pinController = TextEditingController();
  final _emailController = TextEditingController();
  final _remarksController = TextEditingController();
  final _detailsController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingDoctors = true;
  bool _isLoadingSpecializations = true;
  bool _isLoadingQualifications = true;
  List<DoctorReferral> _allDoctors = [];
  List<Map<String, dynamic>> _specializations = [];
  List<Map<String, dynamic>> _qualifications = [];
  String? _selectedSpecialization;
  String? _selectedQualification;
  DoctorReferral? _selectedDoctor;

  // Image Picking
  // final ImagePicker _picker = ImagePicker(); -- removed for CameraService
  XFile? _visitImage;
  bool _hasExistingVisitImage = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingDoctor != null) {
      final isEditingCurrentTripVisit =
          widget.existingDoctor!.tripId == widget.tripId;

      if (isEditingCurrentTripVisit) {
        // Editing an existing visit in this trip (e.g. continuing a partial draft)
        _populateFields(widget.existingDoctor!);
      } else {
        // Starting a new visit for a pending/assigned doctor from a previous trip
        _populateFields(widget.existingDoctor!);
        _remarksController.clear();
        _detailsController.clear();
      }

      // Existing image is only valid when editing the same trip record.
      _hasExistingVisitImage =
          isEditingCurrentTripVisit &&
          (widget.existingDoctor!.visitImage?.trim().isNotEmpty ?? false);
      _selectedDoctor = widget.existingDoctor;
    }
    _loadAllDoctors();
    _loadSpecializations();
    _loadQualifications();
    _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location services are disabled. Please enable them.',
            ),
          ),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission denied. Cannot track visit.'),
            ),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permissions are permanently denied, we cannot request permissions.',
            ),
          ),
        );
      }
      return;
    }
  }

  Future<void> _loadAllDoctors() async {
    final doctors = await ApiService.fetchAllDoctors();
    setState(() {
      _allDoctors = doctors;
      _isLoadingDoctors = false;

      // Fix reference mismatch: if we have a pre-selected doctor, find its matching instance
      // in the newly loaded list so the dropdown doesn't reset.
      if (_selectedDoctor != null) {
        try {
          _selectedDoctor = _allDoctors.firstWhere(
            (d) => d.id == _selectedDoctor!.id,
          );
        } catch (_) {
          // If not found in the new list, keep the old reference (handled by the fallback DropdownMenuItem)
        }
      }
    });
  }

  Future<void> _loadSpecializations() async {
    final specs = await ApiService.fetchSpecializations();
    setState(() {
      _specializations = specs;
      _isLoadingSpecializations = false;
    });
  }

  Future<void> _loadQualifications() async {
    final quals = await ApiService.fetchQualifications();
    setState(() {
      _qualifications = quals;
      _isLoadingQualifications = false;
    });
  }

  void _populateFields(DoctorReferral doc) {
    _contactController.text = doc.contactNumber;
    _areaController.text = doc.area;
    _streetController.text = doc.street ?? '';
    _cityController.text = doc.city ?? '';
    _pinController.text = doc.pin;
    _selectedSpecialization = doc.specialization.isNotEmpty
        ? doc.specialization
        : null;
    _selectedQualification = doc.degreeQualification.isNotEmpty
        ? doc.degreeQualification
        : null;
    _emailController.text = doc.email ?? '';
    _remarksController.text = doc.remarks ?? '';
    _detailsController.text = doc.additionalDetails;
  }

  @override
  void dispose() {
    _contactController.dispose();
    _areaController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _pinController.dispose();
    _emailController.dispose();
    _remarksController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

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
      setState(() {
        _visitImage = image;
        _hasExistingVisitImage = true;
      });
    }
  }

  void _onDoctorSelected(DoctorReferral? doctor) {
    if (doctor != null && widget.existingDoctor == null) {
      setState(() {
        _selectedDoctor = doctor;
        _visitImage =
            null; // Reset image only when switching doctor on New referral
        _hasExistingVisitImage = false;
      });
      // The user wants all fields EXCEPT contact number to be auto-filled if the doctor exists.
      // And Area should NOT be editable.

      _populateFields(doctor);
      _remarksController.clear();
      _detailsController.clear();
    }
  }

  Future<void> _submitReferral() async {
    // Validate doctor selection
    if (_selectedDoctor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a doctor from the list')),
      );
      return;
    }

    final hasVisitImage = _visitImage != null || _hasExistingVisitImage;
    if (!hasVisitImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Visit photo is mandatory, even for partial draft save.',
          ),
        ),
      );
      return;
    }

    // Check if entry is complete
    final isComplete =
        _contactController.text.trim().isNotEmpty &&
        (_selectedSpecialization?.trim().isNotEmpty ?? false) &&
        (_selectedQualification?.trim().isNotEmpty ?? false) &&
        _areaController.text.trim().isNotEmpty &&
        _pinController.text.trim().isNotEmpty &&
        hasVisitImage;

    if (!isComplete) {
      // Show confirmation dialog before saving partially
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save Partial Entry?'),
          content: const Text(
            'Some mandatory fields are missing. '
            'You can save this as an incomplete draft, but you must complete it before ending the trip.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Draft'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    setState(() => _isLoading = true);

    final name = _selectedDoctor!.name;
    final degree = _selectedQualification ?? '';
    final specialization = _selectedSpecialization ?? '';
    final contact = _contactController.text.trim();
    final email = _emailController.text.trim();
    final area = _areaController.text.trim();
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    final pin = _pinController.text.trim();
    final remarks = _remarksController.text.trim();
    final details = _detailsController.text.trim();

    // Capture Location
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print("Error getting location: $e");
    }

    bool success;

    // Logic:
    // We should only UPDATE if we are editing a draft that is ALREADY part of THIS trip.
    // If the existingDoctor belongs to a different trip, or is a pending "Assigned" doctor,
    // it means we are starting a NEW visit for this trip, so we must CREATE a new record.
    bool isEditingCurrentTripVisit =
        widget.existingDoctor != null &&
        widget.existingDoctor!.tripId == widget.tripId;

    if (isEditingCurrentTripVisit) {
      // Update existing draft for THIS trip
      success = await ApiService.updateDoctorReferral(widget.existingDoctor!.id!, {
        'trip': widget.tripId,
        'name': name,
        'degree_qualification': degree,
        'specialization': specialization,
        'contact_number': contact,
        'email': email,
        'area': area,
        'street': street,
        'city': city,
        'pin': pin,
        'remarks': remarks,
        'additional_details': details,
        'status': 'Referred',
        // If location was captured, update it. If not, it means the user saved partial without triggering location?
        if (position != null) 'visit_lat': position.latitude.toString(),
        if (position != null) 'visit_long': position.longitude.toString(),
        // Empty image string signals to backend we cleared it, or just omit if no new image.
        // Wait, if we cleared the image, _visitImage is null.
        // In ApiService, imagePath: null means it ignores updating the image, it does NOT clear it.
        // That's fine for now. We mostly care about new records not taking old images.
      }, imagePath: _visitImage?.path);
    } else {
      // Create new referral (New entry OR Repeat Visit)
      final referral = DoctorReferral(
        id: _selectedDoctor!.id,
        name: name,
        contactNumber: contact,
        area: area,
        street: street,
        city: city,
        pin: pin,
        specialization: specialization,
        degreeQualification: degree,
        email: email,
        remarks: remarks,
        additionalDetails: details,
        createdAt: DateTime.now(),
        status: "Referred",
      );

      success = await ApiService.createDoctorReferral(
        referral,
        widget.tripId,
        imagePath: _visitImage?.path,
        lat: position?.latitude,
        long: position?.longitude,
      );
    }

    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isComplete
                ? 'Doctor visit completed successfully'
                : 'Doctor partial draft saved successfully',
          ),
        ),
      );
      Navigator.pop(context, true); // Return true to signal refresh needed
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save details')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingDoctor != null
              ? "Complete Doctor Visit"
              : "Add Doctor Referral",
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: const [
          Center(
            child: Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: NetworkIndicator(),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.white, // Ensure white background
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                // Changed from Color(0xFFD9D9D9) to Colors.white with border
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Doctor Details",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Doctor Name Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: widget.existingDoctor != null
                          ? Colors.grey.shade100
                          : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _isLoadingDoctors
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        : DropdownButtonFormField<DoctorReferral>(
                            value: _selectedDoctor,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              hintText: "Select Doctor *",
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                            items: [
                              ..._allDoctors.map((doctor) {
                                return DropdownMenuItem<DoctorReferral>(
                                  value: doctor,
                                  child: Text(
                                    "${doctor.name} - ${doctor.specialization}",
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                              if (_selectedDoctor != null &&
                                  !_allDoctors.contains(_selectedDoctor))
                                DropdownMenuItem<DoctorReferral>(
                                  value: _selectedDoctor,
                                  child: Text(
                                    "${_selectedDoctor!.name} - ${_selectedDoctor!.specialization}",
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ].toList(),
                            onChanged: widget.existingDoctor != null
                                ? null // Disable if editing existing
                                : _onDoctorSelected,
                          ),
                  ),
                  const SizedBox(height: 16),
                  // Qualification Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isLoadingQualifications
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : DropdownButtonFormField<String>(
                            value: _selectedQualification,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              hintText: "Degree & Qualification *",
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                            items: [
                              ..._qualifications.map((qual) {
                                return DropdownMenuItem<String>(
                                  value: qual['name'] as String,
                                  child: Text(qual['name'] as String),
                                );
                              }),
                              if (_selectedQualification != null &&
                                  !_qualifications.any(
                                    (q) => q['name'] == _selectedQualification,
                                  ))
                                DropdownMenuItem<String>(
                                  value: _selectedQualification,
                                  child: Text(_selectedQualification!),
                                ),
                            ].toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedQualification = value;
                              });
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  // Specialization Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isLoadingSpecializations
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : DropdownButtonFormField<String>(
                            value: _selectedSpecialization,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              hintText: "Specialization *",
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                            items: [
                              ..._specializations.map((spec) {
                                return DropdownMenuItem<String>(
                                  value: spec['name'] as String,
                                  child: Text(spec['name'] as String),
                                );
                              }),
                              if (_selectedSpecialization != null &&
                                  !_specializations.any(
                                    (s) => s['name'] == _selectedSpecialization,
                                  ))
                                DropdownMenuItem<String>(
                                  value: _selectedSpecialization,
                                  child: Text(_selectedSpecialization!),
                                ),
                            ].toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedSpecialization = value;
                              });
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _contactController,
                    "Contact Number *",
                    isPhone: true,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(_emailController, "Email ID", isEmail: true),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _areaController,
                    "Area *",
                    readOnly:
                        _selectedDoctor !=
                        null, // Make area permanent/read-only if doctor exists
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(_streetController, "Street"),
                  const SizedBox(height: 16),
                  _buildTextField(_cityController, "City"),
                  const SizedBox(height: 16),
                  _buildTextField(_pinController, "PIN *"),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _remarksController,
                    "Remarks / Feedback",
                    maxLines: 6, // Make it bigger as requested
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _detailsController,
                    "Additional Details",
                    maxLines: 5,
                  ),
                  const SizedBox(height: 24),

                  // Visit Image Upload
                  Row(
                    children: [
                      const Text(
                        "Visit Photo *",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "(Required for Draft & End Trip)",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: (_visitImage != null || _hasExistingVisitImage)
                              ? Colors.grey.shade400
                              : Colors.red.shade300,
                          width: (_visitImage != null || _hasExistingVisitImage)
                              ? 1
                              : 2,
                        ),
                      ),
                      child: _visitImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.file(
                                File(_visitImage!.path),
                                fit: BoxFit.cover,
                              ),
                            )
                          : _hasExistingVisitImage
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.check_circle,
                                  size: 36,
                                  color: Colors.green,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "Existing visit photo attached",
                                  style: TextStyle(color: Colors.grey),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Tap to retake photo",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.camera_alt,
                                  size: 40,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "Tap to take visit photo",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitReferral,
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
                    : Builder(
                        builder: (context) {
                          final hasVisitImage =
                              _visitImage != null || _hasExistingVisitImage;
                          bool isComplete =
                              _contactController.text.trim().isNotEmpty &&
                              (_selectedSpecialization?.trim().isNotEmpty ??
                                  false) &&
                              (_selectedQualification?.trim().isNotEmpty ??
                                  false) &&
                              _areaController.text.trim().isNotEmpty &&
                              _pinController.text.trim().isNotEmpty &&
                              hasVisitImage;
                          if (!hasVisitImage) {
                            return const Text(
                              "Add Visit Photo to Continue",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }
                          return Text(
                            isComplete
                                ? (widget.existingDoctor != null
                                      ? "Complete Doctor Visit"
                                      : "Submit Referral")
                                : "Save Partial Draft",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
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
    bool isPhone = false,
    bool isEmail = false,
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: readOnly ? Colors.grey.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.grey.shade300,
        ), // Added border for visibility on white
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: isPhone
            ? TextInputType.phone
            : (isEmail ? TextInputType.emailAddress : TextInputType.text),
        inputFormatters: isPhone
            ? [
                LengthLimitingTextInputFormatter(10),
                FilteringTextInputFormatter.digitsOnly,
              ]
            : null,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
