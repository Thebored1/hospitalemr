import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.hospitalemr/camera',
  );
  static final ImagePicker _picker = ImagePicker();

  /// Launches the camera.
  /// On Android, uses the custom native implementation to avoid OnePlus crashes.
  /// On iOS, uses the standard image_picker package.
  static Future<XFile?> takePicture() async {
    if (Platform.isAndroid) {
      // Must request permission at runtime because we are not using image_picker which does it for us
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
        if (!status.isGranted) {
          // Permission denied
          return null;
        }
      }

      try {
        final String? path = await _channel.invokeMethod('launchCamera');
        if (path != null) {
          return XFile(path);
        }
        return null;
      } on PlatformException catch (e) {
        print("Native Camera Error: ${e.message}");
        // Fallback to image_picker if native fails?
        // Or maybe just return null to indicate failure.
        // Let's try fallback just in case, but usually we want the native fix.
        return null;
      }
    } else {
      // iOS and others
      return await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
    }
  }

  /// Checks if the native side has a recovered image from a previous process death.
  /// Call this in initState of screens that use the camera.
  static Future<XFile?> checkForLostImage() async {
    if (Platform.isAndroid) {
      try {
        final String? path = await _channel.invokeMethod('recoverImage');
        if (path != null) {
          return XFile(path);
        }
      } catch (e) {
        print("Error checking for lost image: $e");
      }
    }
    return null;
  }
}
