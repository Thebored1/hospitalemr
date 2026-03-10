import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LogService {
  static String? _baseUrl;
  static String? Function()? _tokenProvider;
  static String? _deviceId;

  static void configure({
    required String baseUrl,
    String? Function()? tokenProvider,
  }) {
    _baseUrl = baseUrl;
    _tokenProvider = tokenProvider;
  }

  static Future<void> log(
    String level,
    String message, {
    String? logger,
    Map<String, dynamic>? context,
  }) async {
    if (_baseUrl == null || _baseUrl!.isEmpty) return;

    final payload = {
      'level': level,
      'message': message,
      'logger': logger,
      'context': context ?? {},
      'device_id': await _getDeviceId(),
      'platform': Platform.operatingSystem,
      'build_mode': _buildMode(),
      'client_time': DateTime.now().toIso8601String(),
    };

    final token = _tokenProvider?.call();
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Token $token';
    }

    try {
      await http.post(
        Uri.parse('${_baseUrl!}/logs/'),
        headers: headers,
        body: json.encode(payload),
      );
    } catch (_) {
      // Best-effort logging only; never throw.
    }
  }

  static String _buildMode() {
    if (kReleaseMode) return 'release';
    if (kProfileMode) return 'profile';
    return 'debug';
  }

  static Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('device_id');
    if (existing != null && existing.isNotEmpty) {
      _deviceId = existing;
      return existing;
    }
    final newId = const Uuid().v4();
    await prefs.setString('device_id', newId);
    _deviceId = newId;
    return newId;
  }
}
