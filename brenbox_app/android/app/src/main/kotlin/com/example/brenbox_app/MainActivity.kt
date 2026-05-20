package com.example.brenbox_app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.brenbox/file_saver"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveToDownloads") {
                    val tempPath  = call.argument<String>("tempPath")
                    val fileName  = call.argument<String>("fileName") ?: "file"
                    val subfolder = call.argument<String>("subfolder") ?: "PDFs"
                    val mimeType  = call.argument<String>("mimeType") ?: "application/pdf"

                    if (tempPath == null) {
                        result.error("INVALID_ARGS", "tempPath is null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val path = saveToDownloads(tempPath, fileName, subfolder, mimeType)
                        result.success(path)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message ?: "Unknown error", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun saveToDownloads(
        tempPath: String,
        fileName: String,
        subfolder: String,
        mimeType: String,
    ): String {
        val src = File(tempPath)

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ — MediaStore, no storage permission required
            val relPath = "${Environment.DIRECTORY_DOWNLOADS}/Brenbox/$subfolder"
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, relPath)
            }
            val uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: throw Exception("MediaStore insert failed")

            contentResolver.openOutputStream(uri)?.use { out ->
                src.inputStream().use { inp -> inp.copyTo(out) }
            } ?: throw Exception("Could not open output stream for uri=$uri")

            "${Environment.DIRECTORY_DOWNLOADS}/Brenbox/$subfolder/$fileName"
        } else {
            // Android 9 and below — direct path
            val base = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            val dir  = File(base, "Brenbox/$subfolder")
            dir.mkdirs()
            val dest = File(dir, fileName)
            src.copyTo(dest, overwrite = true)
            dest.absolutePath
        }
    }
}
