import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import '../models/doctor.dart';
import '../services/api_service.dart';
import '../services/camera_service.dart';
import '../widgets/tap_to_call_text.dart'; // Added import

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

  @override
  void initState() {
    super.initState();
    if (widget.existingDoctor != null) {
      _populateFields(widget.existingDoctor!);
      _selectedDoctor = widget.existingDoctor;
    }
    _loadAllDoctors();
    _loadSpecializations();
    _loadQualifications();
    _loadQualifications();
    _checkLocationPermission();
    _checkLostImage();
  }

  Future<void> _checkLostImage() async {
    final lostImage = await CameraService.checkForLostImage();
    if (lostImage != null && mounted) {
      setState(() {
        _visitImage = lostImage;
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
      setState(() => _visitImage = image);
    }
  }

  void _onDoctorSelected(DoctorReferral? doctor) {
    if (doctor != null) {
      setState(() {
        _selectedDoctor = doctor;
        _visitImage = null; // Reset image when switching doctor
      });
      _populateFields(doctor);
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

    // area and pin are mandatory
    if (degree.isEmpty ||
        specialization.isEmpty ||
        contact.isEmpty ||
        email.isEmpty ||
        area.isEmpty ||
        pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all mandatory fields (*)')),
      );
      return;
    }

    // Image is mandatory
    // If it's a repeat visit, we MUST require a new image (ignore old one)
    if (_visitImage == null &&
        (widget.existingDoctor?.visitImage == null ||
            (widget.existingDoctor != null &&
                widget.existingDoctor!.status != 'Assigned'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a photo of the visit (Mandatory)'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

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
    // - If it's a fresh assignment (status == 'Assigned'), we UPDATE the record to mark it as visited.
    // - If it was already visited/referred (status == 'Referred'), we CREATE A NEW record for this new visit.
    bool isRepeatVisit =
        widget.existingDoctor != null &&
        widget.existingDoctor!.status == 'Referred';

    if (widget.existingDoctor != null && !isRepeatVisit) {
      // Update existing ASSIGNED doctor (first visit)
      success =
          await ApiService.updateDoctorReferral(widget.existingDoctor!.id!, {
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
            if (position != null) 'visit_lat': position.latitude.toString(),
            if (position != null) 'visit_long': position.longitude.toString(),
          }, imagePath: _visitImage?.path);
    } else {
      // Create new referral (New entry OR Repeat Visit)
      final referral = DoctorReferral(
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
            widget.existingDoctor != null
                ? 'Doctor visit completed successfully'
                : 'Doctor referral added successfully',
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
                  _buildTextField(
                    _emailController,
                    "Email ID *",
                    isEmail: true,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(_areaController, "Area *"),
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
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _detailsController,
                    "Additional Details",
                    maxLines: 5,
                  ),
                  const SizedBox(height: 24),

                  // Visit Image Upload (Mandatory)
                  const Text(
                    "Visit Photo *",
                    style: TextStyle(fontWeight: FontWeight.bold),
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
                          color:
                              (_visitImage == null &&
                                  (widget.existingDoctor?.visitImage == null ||
                                      widget.existingDoctor!.status !=
                                          'Assigned'))
                              ? Colors.red.shade300
                              : Colors.grey.shade400,
                          width:
                              (_visitImage == null &&
                                  (widget.existingDoctor?.visitImage == null ||
                                      widget.existingDoctor!.status !=
                                          'Assigned'))
                              ? 2
                              : 1,
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
                          : widget.existingDoctor?.visitImage != null &&
                                widget.existingDoctor!.status == 'Assigned'
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.network(
                                widget.existingDoctor!.visitImage!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(child: Icon(Icons.error));
                                },
                              ),
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
            const SizedBox(height: 30),
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
                    : Text(
                        widget.existingDoctor != null
                            ? "Save & Mark Referred"
                            : "Submit Referral",
                        style: const TextStyle(
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
