import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class CertificateService {
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;
  final _firestore = FirebaseFirestore.instance;

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
  Future<String?> savePdfToDevice({
    required String storagePath,
    required String fileName,
    String subfolder = 'PDFs',
  }) async {
    try {
      // Request storage permission on Android (system dialog, same as notifications).
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (status.isPermanentlyDenied) {
          await openAppSettings();
          return null;
        }
        if (!status.isGranted) return null;
      }

      final bytes = await downloadCertificateBytes(storagePath);
      if (bytes == null) return null;

      final Directory dir;
      if (Platform.isAndroid) {
        final downloads = Directory('/storage/emulated/0/Download');
        final base = await downloads.exists()
            ? downloads
            : await getApplicationDocumentsDirectory();
        dir = Directory('${base.path}/Brenbox/$subfolder');
      } else {
        final appDocs = await getApplicationDocumentsDirectory();
        dir = Directory('${appDocs.path}/Brenbox/$subfolder');
      }
      if (!await dir.exists()) await dir.create(recursive: true);

      final safe = fileName.replaceAll(RegExp(r'[^\w\-.]'), '_');
      final filePath = '${dir.path}/$safe';
      await File(filePath).writeAsBytes(bytes);
      return filePath;
    } catch (_) {
      return null;
    }
  }
  static Reference storageRef(String path) =>
    FirebaseStorage.instance.ref().child(path);

}