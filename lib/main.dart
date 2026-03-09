import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb
import 'screens/login_screen.dart';
import 'widgets/role_switcher.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set highest refresh rate available
  // Set highest refresh rate available
  try {
    if (!kIsWeb && Platform.isAndroid) {
      await FlutterDisplayMode.setHighRefreshRate();
    }
  } catch (e) {
    // High refresh rate not supported on this device
    debugPrint('Failed to set high refresh rate: $e');
  }

  // Initialize SyncService singleton so its connectivity listener is registered.
  // This is what triggers syncPendingData() when the device regains network.
  SyncService();

  runApp(const StaffApp());
}

class StaffApp extends StatefulWidget {
  const StaffApp({super.key});

  @override
  State<StaffApp> createState() => _StaffAppState();
}

class _StaffAppState extends State<StaffApp> {
  StreamSubscription<String>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _errorSubscription = ApiService.errorStream.listen((message) {
      final messenger = scaffoldMessengerKey.currentState;
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Hospital EMR',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        primaryColor: Colors.black,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: FutureBuilder<bool>(
        future: ApiService.loadSession(),
        builder: (context, snapshot) {
          // Show a loading indicator while checking session
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          // If session exists, go to RoleSwitcher; otherwise, LoginScreen
          if (snapshot.data == true) {
            return const RoleSwitcher();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
