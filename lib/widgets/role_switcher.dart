import 'package:flutter/material.dart';
import '../screens/dashboard_screen.dart';
import '../screens/advisor_dashboard_screen.dart';
import '../services/api_service.dart';

class RoleSwitcher extends StatefulWidget {
  const RoleSwitcher({super.key});

  @override
  State<RoleSwitcher> createState() => _RoleSwitcherState();
}

class _RoleSwitcherState extends State<RoleSwitcher> {
  String _currentRole = 'advisor'; // 'advisor' or 'maintenance'

  @override
  void initState() {
    super.initState();
    if (ApiService.userRole == 'maintenance') {
      _currentRole = 'maintenance';
    }
    // Admin or Advisor defaults to advisor view initially (but admin can switch)
  }

  void _switchRole() {
    setState(() {
      _currentRole = _currentRole == 'advisor' ? 'maintenance' : 'advisor';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentRole == 'advisor'
          ? AdvisorDashboardScreen(onProfileTap: _switchRole)
          : DashboardScreen(onProfileTap: _switchRole),
    );
  }
}
