import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class CertificateService {
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;
  final _firestore = FirebaseFirestore.instance;

  static const _channel = MethodChannel('com.brenbox/file_saver');

  static String _mimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png'           => 'image/png',
      'gif'           => 'image/gif',
      'webp'          => 'image/webp',
      'doc'           => 'application/msword',
      'docx'          => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      _               => 'application/pdf',
    };
  }

  // ── Step 1: Just pick a PDF and return its bytes + name ───────────────────
  Future<({Uint8List bytes, String name})?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;

    return (bytes: bytes, name: file.name);
  }

  // ── Pick PDF, DOC, or DOCX ────────────────────────────────────────────────
  Future<({Uint8List bytes, String name})?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;

    return (bytes: bytes, name: file.name);
  }

  // ── Step 2: Upload already-picked bytes to Firebase ───────────────────────
  Future<Map<String, dynamic>?> uploadCertificate({
    required Uint8List bytes,
    required String fileName,
    required String title,
    required String year,
    required List<String> tags,
    required Function(double) onProgress,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'certificates/$uid/${timestamp}_$fileName';
    final ref = _storage.ref().child(storagePath);

    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(contentType: 'application/pdf'),
    );

    uploadTask.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });

    await uploadTask;

    final downloadUrl = await ref.getDownloadURL();
    final sizeKB = bytes.lengthInBytes / 1024;

    final docRef = await _firestore
        .collection('certificates')
        .doc(uid)
        .collection('userCerts')
        .add({
      'title': title,
      'year': year,
      'tags': tags,
      'fileName': fileName,
      'fileSizeKB': double.parse(sizeKB.toStringAsFixed(1)),
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'uploadedAt': FieldValue.serverTimestamp(),
    });

    return {'docId': docRef.id, 'downloadUrl': downloadUrl};
  }

  // ── Combined helper (kept for backward compat if needed) ──────────────────
  Future<Map<String, dynamic>?> pickAndUpload({
    required String title,
    required String year,
    required List<String> tags,
    required Function(double) onProgress,
  }) async {
    final picked = await pickPdf();
    if (picked == null) return null;
    return uploadCertificate(
      bytes: picked.bytes,
      fileName: picked.name,
      title: title,
      year: year,
      tags: tags,
      onProgress: onProgress,
    );
  }

  // ── Update metadata only ──────────────────────────────────────────────────
  Future<void> updateCertificate({
    required String docId,
    required String title,
    required String year,
    required List<String> tags,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _firestore
        .collection('certificates')
        .doc(uid)
        .collection('userCerts')
        .doc(docId)
        .update({
      'title': title,
      'year': year,
      'tags': tags,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Delete cert from storage + Firestore ─────────────────────────────────
  Future<void> deleteCertificate({
    required String docId,
    required String storagePath,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    if (storagePath.isNotEmpty) {
      try {
        await _storage.ref().child(storagePath).delete();
      } catch (_) {}
    }

    await _firestore
        .collection('certificates')
        .doc(uid)
        .collection('userCerts')
        .doc(docId)
        .delete();
  }

  // ── Stream certs — all filtering/sorting done client-side ─────────────────
  // Returns unfiltered stream; filtering is handled in the screen widget
  // to avoid composite index requirements and fix tag-filter reactivity.
  Stream<QuerySnapshot<Map<String, dynamic>>> getCertificates({
    String? filterYear,
    String? filterTag,
  }) {
    final uid = _auth.currentUser?.uid ?? '';

    // Only orderBy uploadedAt — no where clauses to avoid index issues
    return _firestore
        .collection('certificates')
        .doc(uid)
        .collection('userCerts')
        .orderBy('uploadedAt', descending: true)
        .snapshots();
  }

  // ── Download bytes for PDF viewer ─────────────────────────────────────────
  Future<Uint8List?> downloadCertificateBytes(String storagePath) async {
    try {
      return await _storage.ref().child(storagePath).getData(20 * 1024 * 1024);
    } catch (_) {
      return null;
    }
  }

  // ── Save file to Download/Brenbox/{subfolder}/ ───────────────────────────
  // Android: /storage/emulated/0/Download/Brenbox/<subfolder>/
  // iOS:     <AppDocuments>/Brenbox/<subfolder>/
  //
  // Returns null if permission is denied, the saved path on success.
  // Returns the saved path on success, throws on failure.
  Future<String> savePdfToDevice({
    required String storagePath,
    required String fileName,
    String subfolder = 'PDFs',
  }) async {
    final bytes = await downloadCertificateBytes(storagePath);
    if (bytes == null) throw Exception('Failed to download file from storage.');

    final safe = fileName.replaceAll(RegExp(r'[^\w\-.]'), '_');

    if (Platform.isAndroid) {
      // Write to temp file first — avoids passing large byte arrays over IPC
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$safe');
      await tempFile.writeAsBytes(bytes);
      try {
        final result = await _channel.invokeMethod<String>('saveToDownloads', {
          'tempPath':  tempFile.path,
          'fileName':  safe,
          'subfolder': subfolder,
          'mimeType':  _mimeType(fileName),
        });
        if (result == null) throw Exception('Native save returned null.');
        return result;
      } finally {
        try { await tempFile.delete(); } catch (_) {}
      }
    } else {
      // iOS: app documents directory
      final appDocs = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDocs.path}/Brenbox/$subfolder');
      if (!await dir.exists()) await dir.create(recursive: true);
      final filePath = '${dir.path}/$safe';
      await File(filePath).writeAsBytes(bytes);
      return filePath;
    }
  }
  static Reference storageRef(String path) =>
    FirebaseStorage.instance.ref().child(path);

}