import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/patient_referral.dart';
import '../models/doctor.dart';
import '../services/api_service.dart';
import '../widgets/network_indicator.dart';

class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final TextEditingController _patientNameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _illnessController = TextEditingController();
  final TextEditingController _conditionController = TextEditingController();

  String _selectedGender = 'Male';
  bool _isUrgent = false;

  // Doctor dropdowns
  List<DoctorReferral> _externalDoctors = [];
  List<DoctorReferral> _internalDoctors = [];
  DoctorReferral? _selectedReferredByDoctor;
  DoctorReferral? _selectedReferredToDoctor;
  bool _loadingDoctors = true;

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    final allDoctors = await ApiService.fetchAllDoctors();
    if (mounted) {
      setState(() {
        _externalDoctors = allDoctors
            .where((d) => d.isInternal == false)
            .toList();
        _internalDoctors = allDoctors
            .where((d) => d.isInternal == true)
            .toList();
        _loadingDoctors = false;
      });
    }
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _illnessController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  Future<void> _submitPatient() async {
    final name = _patientNameController.text.trim();
    final ageStr = _ageController.text.trim();
    final phone = _phoneController.text.trim();
    final illness = _illnessController.text.trim();
    final description = _conditionController.text.trim();

    if (name.isEmpty || ageStr.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    final referral = PatientReferral(
      id: '',
      patientName: name,
      age: int.tryParse(ageStr) ?? 0,
      gender: _selectedGender,
      phone: phone,
      illness: illness.isNotEmpty ? illness : 'General',
      description: description,
      reportedOn: DateTime.now(),
      status: 'In Progress',
      isUrgent: _isUrgent,
      referredByDoctorId: _selectedReferredByDoctor?.id,
      referredToDoctorId: _selectedReferredToDoctor?.id,
    );

    final success = await ApiService.createPatientReferral(referral);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient added successfully')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to add patient')));
    }
  }

  Future<void> _showDoctorPicker({
    required String title,
    required List<DoctorReferral> doctors,
    required DoctorReferral? selectedDoctor,
    required ValueChanged<DoctorReferral?> onSelected,
  }) async {
    if (_loadingDoctors) return;

    final searchController = TextEditingController();
    List<DoctorReferral> filtered = List.from(doctors);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          void applyFilter(String query) {
            final q = query.trim().toLowerCase();
            if (q.isEmpty) {
              filtered = List.from(doctors);
            } else {
              filtered = doctors.where((doc) {
                final name = doc.name.toLowerCase();
                final spec = doc.specialization.toLowerCase();
                final address = doc.fullAddress.toLowerCase();
                return name.contains(q) ||
                    spec.contains(q) ||
                    address.contains(q);
              }).toList();
            }
            setModalState(() {});
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.black54),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (selectedDoctor != null)
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onSelected(null);
                          },
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: searchController,
                    onChanged: applyFilter,
                    decoration: InputDecoration(
                      hintText: 'Search by name, specialization, or area',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ListTile(
                          title: const Text('— None —'),
                          onTap: () {
                            Navigator.pop(context);
                            onSelected(null);
                          },
                        );
                      }
                      final doc = filtered[index - 1];
                      return ListTile(
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
                              Text(
                                doc.fullAddress,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                        trailing: selectedDoctor?.id == doc.id
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          onSelected(doc);
                        },
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: filtered.length + 1,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDoctorSearchDropdown({
    required String hint,
    required List<DoctorReferral> doctors,
    required DoctorReferral? selectedDoctor,
    required ValueChanged<DoctorReferral?> onSelected,
    IconData icon = Icons.person_search,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: _loadingDoctors
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Loading doctors...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () => _showDoctorPicker(
                title: hint,
                doctors: doctors,
                selectedDoctor: selectedDoctor,
                onSelected: onSelected,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedDoctor?.name ?? hint,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selectedDoctor == null
                              ? Colors.grey
                              : Colors.black,
                        ),
                      ),
                    ),
                    if (selectedDoctor != null)
                      GestureDetector(
                        onTap: () => onSelected(null),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.clear, size: 16, color: Colors.grey),
                        ),
                      ),
                    const Icon(Icons.expand_more),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header Section ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      "Patient Entry",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const NetworkIndicator(),
                  const SizedBox(width: 8),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFD9D9D9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- Status Badge ---
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  "In Progress",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // --- Form Card ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D9D9),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Raised on info
                    const Text(
                      "Raised on",
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    Text(
                      "${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}",
                      style: const TextStyle(color: Colors.black, fontSize: 14),
                    ),

                    const SizedBox(height: 24),

                    // Section Title
                    const Text(
                      "Patient Details",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Patient Name and Submit Row
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: TextField(
                              controller: _patientNameController,
                              decoration: const InputDecoration(
                                hintText: "Patient Name",
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _submitPatient,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            "Submit",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Age and Gender Row
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: TextField(
                              controller: _ageController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: "Age",
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedGender,
                                isExpanded: true,
                                dropdownColor: Colors.white,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Male',
                                    child: Text('Male'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Female',
                                    child: Text('Female'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Other',
                                    child: Text('Other'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedGender = value!);
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Phone Field
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(10),
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          hintText: "Phone Number",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Illness Field
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TextField(
                        controller: _illnessController,
                        decoration: const InputDecoration(
                          hintText: "Illness / Complaint",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // --- Referral Section ---
                    const Text(
                      "Referral Details",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Referred By (external doctors)
                    const Text(
                      "Referred By (External Doctor)",
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    _buildDoctorSearchDropdown(
                      hint: "Select referring doctor",
                      doctors: _externalDoctors,
                      selectedDoctor: _selectedReferredByDoctor,
                      icon: Icons.person_pin_outlined,
                      onSelected: (doc) =>
                          setState(() => _selectedReferredByDoctor = doc),
                    ),

                    const SizedBox(height: 12),

                    // Referred To (internal doctors)
                    const Text(
                      "Referred To (Internal Doctor)",
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    _buildDoctorSearchDropdown(
                      hint: "Select internal doctor",
                      doctors: _internalDoctors,
                      selectedDoctor: _selectedReferredToDoctor,
                      icon: Icons.local_hospital_outlined,
                      onSelected: (doc) =>
                          setState(() => _selectedReferredToDoctor = doc),
                    ),

                    const SizedBox(height: 16),

                    // Condition Description
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TextField(
                        controller: _conditionController,
                        decoration: const InputDecoration(
                          hintText: "Describe their Condition",
                          border: InputBorder.none,
                        ),
                        maxLines: 6,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Urgent Switch
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: SwitchListTile(
                        title: const Text(
                          "Urgent Case?",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        value: _isUrgent,
                        onChanged: (bool value) {
                          setState(() => _isUrgent = value);
                        },
                        secondary: const Icon(
                          Icons.flash_on,
                          color: Colors.orange,
                        ),
                        activeColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
