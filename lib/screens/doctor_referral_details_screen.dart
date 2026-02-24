import 'package:flutter/material.dart';
import '../models/doctor.dart';
import 'package:intl/intl.dart';

class DoctorReferralDetailsScreen extends StatelessWidget {
  final DoctorReferral referral;

  const DoctorReferralDetailsScreen({Key? key, required this.referral})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Doctor Referral Details"),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildDetailCard([
              _buildDetailItem("Doctor Name", referral.name),
              _buildDetailItem(
                "Degree & Qualification",
                referral.degreeQualification,
              ),
              _buildDetailItem("Specialization", referral.specialization),
              _buildDetailItem(
                "Contact Number",
                referral.contactNumber.isNotEmpty
                    ? referral.contactNumber
                    : "N/A",
              ),
              _buildDetailItem("Email ID", referral.email ?? "N/A"),
              _buildDetailItem("Street", referral.street ?? "N/A"),
              _buildDetailItem(
                "Area",
                referral.area.isNotEmpty ? referral.area : "N/A",
              ),
              _buildDetailItem("City", referral.city ?? "N/A"),
              _buildDetailItem(
                "Pincode",
                referral.pin.isNotEmpty ? referral.pin : "N/A",
              ),
              _buildDetailItem("Remarks", referral.remarks ?? "N/A"),
              _buildDetailItem(
                "Additional Details",
                referral.additionalDetails.isNotEmpty
                    ? referral.additionalDetails
                    : "N/A",
              ),
              _buildDetailItem(
                "Created At",
                DateFormat(
                  'dd MMM yyyy, hh:mm a',
                ).format(referral.createdAt.toLocal()),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}
