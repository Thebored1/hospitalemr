package com.example.hospitalemr

import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import android.util.Log

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.hospitalemr/camera"
    private val REQUEST_IMAGE_CAPTURE = 1
    private var currentPhotoPath: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchCamera" -> {
                    if (pendingResult != null) {
                        result.error("CAMERA_BUSY", "Camera is already active", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    try {
                        dispatchTakePictureIntent()
                    } catch (e: Exception) {
                        Log.e("Camera", "Fatal error launching camera", e)
                        pendingResult?.error("FATAL_ERROR", e.message, null)
                        pendingResult = null
                    }
                }
                "recoverImage" -> {
                    // Check SharedPreferences for a recovered image
                    val prefs = getSharedPreferences("FlutterCamera", Context.MODE_PRIVATE)
                    val recoveredPath = prefs.getString("recovered_image_path", null)
                    
                    if (recoveredPath != null) {
                        // Return it and clear it
                        result.success(recoveredPath)
                        prefs.edit().remove("recovered_image_path").apply()
                    } else {
                        result.success(null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun dispatchTakePictureIntent() {
        val cameraIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        
        val photoFile: File? = try {
            createImageFile()
        } catch (ex: IOException) {
            Log.e("Camera", "Error creating image file", ex)
            pendingResult?.error("IO_ERROR", "Error creating file: ${ex.message}", null)
            pendingResult = null
            null
        }

        photoFile?.also {
            // Persist the pending path to SharedPreferences immediately
            getSharedPreferences("FlutterCamera", Context.MODE_PRIVATE)
                .edit()
                .putString("pending_photo_path", currentPhotoPath)
                .apply()

            try {
                // Use dynamic package name for FileProvider authority
                val authority = "${context.packageName}.fileprovider"
                val photoURI: Uri = FileProvider.getUriForFile(
                    this,
                    authority,
                    it
                )
                cameraIntent.putExtra(MediaStore.EXTRA_OUTPUT, photoURI)
                
                // CRITICAL FIX: Add ClipData for Android 11+ compliance
                cameraIntent.clipData = ClipData.newRawUri("", photoURI)
                
                // Grant URI permissions explicitly
                cameraIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                cameraIntent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                
                startActivityForResult(cameraIntent, REQUEST_IMAGE_CAPTURE)
            } catch (e: Exception) {
                Log.e("Camera", "Error starting camera activity", e)
                pendingResult?.error("LAUNCH_ERROR", "Failed to launch camera: ${e.message}", null)
                pendingResult = null
            }
        }
    }

    private fun createImageFile(): File {
        val timeStamp: String = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        // Use standard directory to ensure visibility
        val storageDir: File? = getExternalFilesDir(Environment.DIRECTORY_PICTURES)
        if (storageDir == null) {
            throw IOException("ExternalFilesDir is null")
        }
        return File.createTempFile(
            "JPEG_${timeStamp}_",
            ".jpg",
            storageDir
        ).apply {
            currentPhotoPath = absolutePath
        }
    }
    
    // We can keep onSaveInstanceState as a backup, but Prefs is primary now
    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("currentPhotoPath", currentPhotoPath)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Pass null to super.onCreate to prevent the FlutterEngine from trying to restore 
        // a potentially dead state. This forces a fresh app start, which is safer.
        super.onCreate(null)
        
        // Restore pending path from Prefs if not null (more reliable than Bundle sometimes)
        val prefs = getSharedPreferences("FlutterCamera", Context.MODE_PRIVATE)
        val pendingPath = prefs.getString("pending_photo_path", null)
        if (pendingPath != null) {
            currentPhotoPath = pendingPath
        } else if (savedInstanceState != null) {
            currentPhotoPath = savedInstanceState.getString("currentPhotoPath")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        try {
            if (requestCode == REQUEST_IMAGE_CAPTURE) {
                val prefs = getSharedPreferences("FlutterCamera", Context.MODE_PRIVATE)
                
                if (resultCode == Activity.RESULT_OK) {
                    if (currentPhotoPath != null) {
                        if (pendingResult != null) {
                            // Normal case
                            pendingResult?.success(currentPhotoPath)
                            // Clear pending path since we consumed it
                            prefs.edit().remove("pending_photo_path").apply()
                        } else {
                            // Recovery case: App was killed.
                            // Promote "pending" to "recovered"
                            prefs.edit()
                                .putString("recovered_image_path", currentPhotoPath)
                                .remove("pending_photo_path")
                                .apply()
                        }
                    } else {
                        pendingResult?.error("PATH_ERROR", "Photo path is null", null)
                    }
                } else {
                    // User canceled or error
                    pendingResult?.success(null)
                    // Clear pending path since operation finished (canceled)
                    prefs.edit().remove("pending_photo_path").apply()
                }
                pendingResult = null
            }
        } catch (e: Exception) {
            Log.e("Camera", "Error in onActivityResult", e)
            pendingResult?.success(null) // Fail gracefully
            pendingResult = null
        }
    }
}
