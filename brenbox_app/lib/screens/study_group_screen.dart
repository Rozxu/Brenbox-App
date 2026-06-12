import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:image/image.dart' as img;
import 'package:cached_network_image/cached_network_image.dart';
import '../services/certificate_service.dart';
import '../services/notification_scheduler.dart';
import '../app_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour constants
// ─────────────────────────────────────────────────────────────────────────────
const _kBlue  = Color(0xFF3859FF);
const _kRed   = Color(0xFFB90000);
const _kGreen = Color(0xFF34A853);
const _kYellow = Color(0xFFFBBC05);
const _kGroup = Color(0xFF7C3AED);

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HELPER WIDGETS (defined at top level so all tabs can use them)
// ─────────────────────────────────────────────────────────────────────────────

Widget _field(BuildContext context, TextEditingController ctrl, String hint,
    {int lines = 1, bool autofocus = false}) {
  return TextField(
    controller: ctrl,
    maxLines: lines,
    autofocus: autofocus,
    style: GoogleFonts.dmMono(fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.dmMono(color: AppColors.subtext(context), fontSize: 14),
      filled: true,
      fillColor: AppColors.input(context),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border(context))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border(context))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBlue, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

Widget _pickerTile(BuildContext context, {
  required IconData icon,
  required String label,
  required bool active,
  Color color = _kBlue,
  bool showArrow = false,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      color: active ? color.withValues(alpha: 0.06) : AppColors.card(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: active ? color : AppColors.border(context), width: active ? 2 : 1),
    ),
    child: Row(children: [
      Icon(icon, size: 18, color: active ? color : AppColors.subtext(context)),
      const SizedBox(width: 10),
      Expanded(child: Text(label,
          style: GoogleFonts.dmMono(fontSize: 13, color: active ? color : AppColors.subtext(context)))),
      if (showArrow) Icon(Icons.chevron_right, size: 18, color: AppColors.subtext(context)),
    ]),
  );
}

Widget _emptyState(BuildContext context, IconData icon, String title, String sub) {
  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
          color: _kBlue.withValues(alpha: 0.08), shape: BoxShape.circle),
      child: Icon(icon, size: 52, color: _kBlue),
    ),
    const SizedBox(height: 18),
    Text(title, style: GoogleFonts.dmMono(
        fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text(context))),
    const SizedBox(height: 6),
    Text(sub, style: GoogleFonts.dmMono(fontSize: 13, color: AppColors.subtext(context))),
  ]));
}

Widget _newMsgSepRow(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [
      const Expanded(child: Divider(color: Color(0xFFFF7043), thickness: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'New Messages',
          style: GoogleFonts.dmMono(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFF7043),
          ),
        ),
      ),
      const Expanded(child: Divider(color: Color(0xFFFF7043), thickness: 1)),
    ]),
  );
}

Widget _dateSepRow(BuildContext context, String label) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(children: [
      Expanded(child: Divider(color: AppColors.border(context))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(label, style: GoogleFonts.dmMono(
            fontSize: 11, color: AppColors.subtext(context))),
      ),
      Expanded(child: Divider(color: AppColors.border(context))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// GROUP PDF VIEWER SCREEN  (new — reused in Chat + Updates)
// ─────────────────────────────────────────────────────────────────────────────

class _GroupPdfViewerScreen extends StatefulWidget {
  final String title;
  final String storagePath;
  final String fileName;

  const _GroupPdfViewerScreen({
    required this.title,
    required this.storagePath,
    required this.fileName,
  });

  @override
  State<_GroupPdfViewerScreen> createState() => _GroupPdfViewerScreenState();
}

class _GroupPdfViewerScreenState extends State<_GroupPdfViewerScreen> {
  final _certSvc = CertificateService();

  String? _localPath;
  bool _loading = true;
  String? _error;
  bool _downloading = false;
  int _currentPage = 0;
  int _totalPages  = 0;

  static const _tan  = Color(0xFFD4B896);

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final bytes =
          await _certSvc.downloadCertificateBytes(widget.storagePath);
      if (bytes == null) {
        setState(() { _loading = false; _error = 'Failed to load PDF.'; });
        return;
      }
      final dir  = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/grp_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);
      if (mounted) setState(() { _localPath = file.path; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Error: $e'; });
    }
  }

  Future<void> _downloadToDevice() async {
    setState(() => _downloading = true);
    try {
      final savedPath = await _certSvc.savePdfToDevice(
        storagePath: widget.storagePath,
        fileName:    widget.fileName,
        subfolder:   'PDFs',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saved to Downloads/Brenbox/PDFs!',
                style: GoogleFonts.dmMono(
                    fontSize: 12, fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text(savedPath,
                style: GoogleFonts.dmMono(fontSize: 10, color: Colors.white70),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        backgroundColor: _kGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Download failed: $e',
            style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 5),
      ));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.chipBg(context),
      appBar: AppBar(
        backgroundColor: AppColors.chipBg(context),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.only(left: 12),
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: GoogleFonts.dmMono(
                    fontSize: 14, fontWeight: FontWeight.bold,
                    color: Colors.white),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_totalPages > 0)
              Text('Page ${_currentPage + 1} of $_totalPages',
                  style: GoogleFonts.dmMono(
                      fontSize: 10, color: Colors.white54)),
          ],
        ),
        actions: [
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _downloading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Color(0xFFD4B896), strokeWidth: 2),
                      ),
                    )
                  : GestureDetector(
                      onTap: _downloadToDevice,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _tan.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _tan.withOpacity(0.55), width: 1.2),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.download_outlined,
                              color: _tan, size: 16),
                          const SizedBox(width: 5),
                          Text('Download',
                              style: GoogleFonts.dmMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _tan)),
                        ]),
                      ),
                    ),
            ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                      color: _tan, strokeWidth: 2.5),
                  const SizedBox(height: 16),
                  Text('Loading PDF…',
                      style: GoogleFonts.dmMono(
                          fontSize: 12, color: Colors.white54)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.redAccent.withOpacity(0.8), size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: GoogleFonts.dmMono(
                              fontSize: 12, color: Colors.white54)),
                    ],
                  ),
                )
              : PDFView(
                  filePath: _localPath!,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                  onPageChanged: (page, total) {
                    if (mounted) {
                      setState(() {
                        _currentPage = page ?? 0;
                        _totalPages  = total ?? 0;
                      });
                    }
                  },
                  onRender: (pages) {
                    if (mounted) setState(() => _totalPages = pages ?? 0);
                  },
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMAGE VIEWER SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class _GroupImageViewerScreen extends StatefulWidget {
  final String title;
  final String imageUrl;
  final String storagePath;
  final String fileName;

  const _GroupImageViewerScreen({
    required this.title,
    required this.imageUrl,
    required this.storagePath,
    required this.fileName,
  });

  @override
  State<_GroupImageViewerScreen> createState() =>
      _GroupImageViewerScreenState();
}

class _GroupImageViewerScreenState extends State<_GroupImageViewerScreen> {
  bool _downloading = false;

  Future<void> _downloadToDevice() async {
    setState(() => _downloading = true);
    try {
      final savedPath = await CertificateService().savePdfToDevice(
        storagePath: widget.storagePath,
        fileName:    widget.fileName,
        subfolder:   'Images',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saved to Downloads/Brenbox/Images!',
                style: GoogleFonts.dmMono(
                    fontSize: 12, fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text(savedPath,
                style: GoogleFonts.dmMono(fontSize: 10, color: Colors.white70),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        backgroundColor: _kGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Download failed: $e',
            style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 5),
      ));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.only(left: 12),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        title: Text(widget.title,
            style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _downloading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    ),
                  )
                : GestureDetector(
                    onTap: _downloadToDevice,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.download_outlined,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 5),
                        Text('Save',
                            style: GoogleFonts.dmMono(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ]),
                    ),
                  ),
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorWidget: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class StudyGroupScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String subject;
  final int initialTab;

  const StudyGroupScreen({
    Key? key,
    required this.groupId,
    required this.groupName,
    required this.subject,
    this.initialTab = 0,
  }) : super(key: key);

  @override
  State<StudyGroupScreen> createState() => _StudyGroupScreenState();
}

class _StudyGroupScreenState extends State<StudyGroupScreen>
    with SingleTickerProviderStateMixin {
  final _auth      = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late final TabController _tabController;
  StreamSubscription<DocumentSnapshot>? _membershipSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
    _startMembershipWatch();
  }

  // Watches the group document in real-time. If this user is no longer in
  // memberIds (kicked) or the group is deleted, navigates them out immediately.
  void _startMembershipWatch() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _membershipSub = _firestore
        .collection('study_groups')
        .doc(widget.groupId)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;

          // Group was deleted
          if (!snap.exists) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('This group no longer exists.',
                  style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
              backgroundColor: _kRed,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 3),
            ));
            Navigator.pop(context);
            return;
          }

          final data      = snap.data() ?? {};
          final memberIds = List<String>.from(data['memberIds'] ?? []);

          // User was kicked
          if (!memberIds.contains(uid)) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('You have been removed from this group.',
                  style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
              backgroundColor: _kRed,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            ));
            Navigator.pop(context);
          }
        }, onError: (_) {});
  }

  @override
  void dispose() {
    _membershipSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<String> _getMyUsername() async {
    final user = _auth.currentUser;
    if (user == null) return 'Unknown';
    final doc = await _firestore.collection('users').doc(user.uid).get();
    return doc.data()?['username'] ?? user.email ?? 'Unknown';
  }

  void _showMembersSheet() {
    final myUid = _auth.currentUser?.uid ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StreamBuilder<DocumentSnapshot>(
        stream: _firestore
            .collection('study_groups')
            .doc(widget.groupId)
            .snapshots(),
        builder: (ctx, snap) {
          final data       = snap.data?.data() as Map<String, dynamic>? ?? {};
          final members    = List<Map<String, dynamic>>.from(data['members'] ?? []);
          final createdBy  = data['createdBy'] as String? ?? '';
          final adminIds   = List<String>.from(data['adminIds'] ?? []);
          final myIsHost   = myUid == createdBy;
          final myIsAdmin  = adminIds.contains(myUid);

          return Container(
            decoration: BoxDecoration(
              color: AppColors.card(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top:   BorderSide(color: AppColors.border(ctx), width: 2),
                left:  BorderSide(color: AppColors.border(ctx), width: 2),
                right: BorderSide(color: AppColors.border(ctx), width: 2),
              ),
            ),
            child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.border(ctx),
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(children: [
                    Text('Members', style: GoogleFonts.dmMono(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: _kBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('${members.length}', style: GoogleFonts.dmMono(
                          fontSize: 12, fontWeight: FontWeight.bold, color: _kBlue)),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: members.length,
                    itemBuilder: (ctx, i) {
                      final m       = members[i];
                      final uid     = m['uid'] as String? ?? '';
                      final uname   = m['username'] as String? ?? 'Unknown';
                      final isHost  = uid == createdBy;
                      final isAdmin = adminIds.contains(uid);
                      final isMe    = uid == myUid;

                      Widget? trailing;
                      if (!isMe && (myIsHost || myIsAdmin)) {
                        trailing = PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded,
                              color: AppColors.subtext(ctx), size: 20),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: AppColors.border(ctx))),
                          color: AppColors.card(ctx),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'admin',
                              child: Row(children: [
                                Icon(
                                  isAdmin ? Icons.shield_outlined : Icons.shield_rounded,
                                  size: 18, color: _kBlue,
                                ),
                                const SizedBox(width: 10),
                                Text(isAdmin ? 'Remove Admin' : 'Make Admin',
                                    style: GoogleFonts.dmMono(fontSize: 13)),
                              ]),
                            ),
                            PopupMenuItem(
                              value: 'kick',
                              child: Row(children: [
                                const Icon(Icons.person_remove_outlined,
                                    size: 18, color: Color(0xFFB90000)),
                                const SizedBox(width: 10),
                                Text('Kick', style: GoogleFonts.dmMono(
                                    fontSize: 13, color: const Color(0xFFB90000))),
                              ]),
                            ),
                          ],
                          onSelected: (val) {
                            if (val == 'admin') {
                              _toggleAdmin(uid, adminIds);
                            } else if (val == 'kick') {
                              _kickMember(ctx, uid, uname);
                            }
                          },
                        );
                      }

                      String? roleLabel;
                      const roleLabelColor = _kBlue;
                      if (isHost || isAdmin) roleLabel = 'Admin';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: _kBlue.withOpacity(0.1),
                          child: Text(
                            uname.isNotEmpty ? uname[0].toUpperCase() : '?',
                            style: GoogleFonts.dmMono(
                                fontWeight: FontWeight.bold, color: _kBlue),
                          ),
                        ),
                        title: Text(
                          '$uname${isMe ? ' (You)' : ''}',
                          style: GoogleFonts.dmMono(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        subtitle: roleLabel != null
                            ? Text(roleLabel, style: GoogleFonts.dmMono(
                                fontSize: 11, color: roleLabelColor))
                            : null,
                        trailing: trailing,
                      );
                    },
                  ),
                ),
                if (myIsHost || myIsAdmin) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteGroup();
                        },
                        icon: const Icon(Icons.delete_forever_rounded, size: 18),
                        label: Text('Delete Group',
                            style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB90000),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(ctx),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFB90000), width: 2)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB90000), size: 22),
          const SizedBox(width: 8),
          Text('Delete Group', style: GoogleFonts.dmMono(
              fontSize: 18, fontWeight: FontWeight.bold,
              color: const Color(0xFFB90000))),
        ]),
        content: Text(
          'This will permanently delete the group and all its events for every member. This cannot be undone.',
          style: GoogleFonts.dmMono(fontSize: 13, color: AppColors.subtext(ctx), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.dmMono(color: AppColors.subtext(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB90000),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text('Delete', style: GoogleFonts.dmMono(
                color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final myUid = _auth.currentUser?.uid;
    // Only delete the current user's event copies — Firestore rules prevent
    // reading/deleting other users' documents, and orphaned copies are harmless
    // once the group document is gone.
    final batch = _firestore.batch();
    if (myUid != null) {
      final eventsSnap = await _firestore
          .collection('user_group_events')
          .where('groupId', isEqualTo: widget.groupId)
          .where('userId', isEqualTo: myUid)
          .get();
      for (final doc in eventsSnap.docs) {
        batch.delete(doc.reference);
      }
    }
    batch.delete(_firestore.collection('study_groups').doc(widget.groupId));
    await batch.commit();

    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleAdmin(String uid, List<String> currentAdminIds) async {
    final updatedAdminIds = List<String>.from(currentAdminIds);
    if (updatedAdminIds.contains(uid)) {
      updatedAdminIds.remove(uid);
    } else {
      updatedAdminIds.add(uid);
    }
    await _firestore
        .collection('study_groups')
        .doc(widget.groupId)
        .update({'adminIds': updatedAdminIds});
  }

  Future<void> _kickMember(BuildContext ctx, String uid, String uname) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card(ctx),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.border(ctx), width: 2)),
        title: Text('Kick $uname?',
            style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
        content: Text('Remove $uname from the group?',
            style: GoogleFonts.dmMono(
                fontSize: 13, color: AppColors.subtext(ctx))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.dmMono(color: AppColors.subtext(ctx)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            child: Text('Kick',
                style: GoogleFonts.dmMono(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final snap = await _firestore.collection('study_groups').doc(widget.groupId).get();
    if (!snap.exists) return;
    final d = snap.data() as Map<String, dynamic>;
    final updIds = List<String>.from(d['memberIds'] ?? [])..remove(uid);
    final updMem = List<Map<String, dynamic>>.from(d['members'] ?? [])
      ..removeWhere((x) => x['uid'] == uid);
    final updAdminIds = List<String>.from(d['adminIds'] ?? [])..remove(uid);
    await _firestore
        .collection('study_groups')
        .doc(widget.groupId)
        .update({'memberIds': updIds, 'members': updMem, 'adminIds': updAdminIds});
    // Cancel any pending invitations so the kicked user cannot re-enter via an old invite.
    // Wrapped in try-catch: a permission failure here must not abort the kick itself.
    try {
      final pending = await _firestore
          .collection('group_invitations')
          .where('groupId', isEqualTo: widget.groupId)
          .where('inviteeId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .get();
      await Future.wait(
          pending.docs.map((d) => d.reference.update({'status': 'cancelled'})));
    } catch (_) {}
  }

  Future<void> _leaveGroup() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(ctx),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.border(ctx), width: 2)),
        title: Text('Leave Group', style: GoogleFonts.dmMono(
            fontSize: 18, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to leave this group?',
            style: GoogleFonts.dmMono(fontSize: 14, color: AppColors.subtext(ctx))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.dmMono(color: AppColors.subtext(ctx)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kRed,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text('Leave', style: GoogleFonts.dmMono(
                color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final d = (await _firestore
        .collection('study_groups').doc(widget.groupId).get()).data();
    if (d == null) return;
    final ids      = List<String>.from(d['memberIds'] ?? [])..remove(user.uid);
    final mems     = List<Map<String, dynamic>>.from(d['members'] ?? [])
      ..removeWhere((m) => m['uid'] == user.uid);
    final adminIds = List<String>.from(d['adminIds'] ?? [])..remove(user.uid);
    if (ids.isEmpty) {
      await _firestore.collection('study_groups').doc(widget.groupId).delete();
    } else {
      await _firestore.collection('study_groups').doc(widget.groupId)
          .update({'memberIds': ids, 'members': mems, 'adminIds': adminIds});
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.card(context),
        elevation: 0,
        toolbarHeight: 70,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: AppColors.chipBg(context), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.groupName, style: GoogleFonts.dmMono(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text(context))),
            const SizedBox(height: 2),
            Text(widget.subject, style: GoogleFonts.dmMono(fontSize: 12, color: AppColors.subtext(context))),
          ],
        ),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: _firestore
                .collection('study_groups').doc(widget.groupId).snapshots(),
            builder: (ctx, snap) {
              final count = ((snap.data?.data()
                      as Map<String, dynamic>?)?['memberIds'] as List?)?.length ?? 0;
              return GestureDetector(
                onTap: _showMembersSheet,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kBlue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kBlue),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.people, size: 16,
                        color: AppColors.isDark(context) ? const Color(0xFF82B4FF) : _kBlue),
                    const SizedBox(width: 5),
                    Text('$count', style: GoogleFonts.dmMono(
                        fontSize: 13, fontWeight: FontWeight.bold,
                        color: AppColors.isDark(context) ? const Color(0xFF82B4FF) : _kBlue)),
                  ]),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _leaveGroup,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _kRed.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kRed),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.logout, size: 16,
                      color: AppColors.isDark(context) ? const Color(0xFFFF6B6B) : _kRed),
                  const SizedBox(width: 5),
                  Text('Leave', style: GoogleFonts.dmMono(
                      fontSize: 13, fontWeight: FontWeight.bold,
                      color: AppColors.isDark(context) ? const Color(0xFFFF6B6B) : _kRed)),
                ]),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: AppColors.card(context),
            child: TabBar(
              controller: _tabController,
              labelColor: _kBlue,
              unselectedLabelColor: AppColors.subtext(context),
              indicatorColor: _kBlue,
              indicatorWeight: 3,
              labelStyle: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold),
              unselectedLabelStyle: GoogleFonts.dmMono(fontSize: 12),
              tabs: const [
                Tab(icon: Icon(Icons.chat_bubble_outline, size: 20), text: 'Chat'),
                Tab(icon: Icon(Icons.checklist_rtl, size: 20), text: 'Tasks'),
                Tab(icon: Icon(Icons.bolt_outlined, size: 20), text: 'Updates'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ChatTab(groupId: widget.groupId, groupName: widget.groupName, subject: widget.subject,
              getUsername: _getMyUsername),
          _MilestonesTab(groupId: widget.groupId, getUsername: _getMyUsername),
          _UpdatesTab(groupId: widget.groupId, getUsername: _getMyUsername),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHAT TAB
// ─────────────────────────────────────────────────────────────────────────────

class _ChatTab extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String subject;
  final Future<String> Function() getUsername;

  const _ChatTab({
    required this.groupId,
    required this.groupName,
    required this.subject,
    required this.getUsername,
  });

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final _ctrl    = TextEditingController();
  final _scroll  = ScrollController();
  final _auth    = FirebaseAuth.instance;
  final _db      = FirebaseFirestore.instance;
  final _certSvc = CertificateService();

  String? _cachedUsername;
  String  _groupCreatedBy = '';
  List<Map<String, dynamic>> _cachedMembers = [];
  List<String> _cachedAdminIds = [];
  Timestamp? _unreadSeparatorAt;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final results = await Future.wait([
      _db.collection('users').doc(user.uid).get(),
      _db.collection('study_groups').doc(widget.groupId).get(),
    ]);
    if (!mounted) return;
    final groupData = results[1].data();
    setState(() {
      _cachedUsername = results[0].data()?['username'] as String?
          ?? user.email ?? 'Unknown';
      _groupCreatedBy = groupData?['createdBy'] as String? ?? '';
      _cachedMembers  = List<Map<String, dynamic>>.from(
          (groupData?['members'] as List? ?? []).map((m) => Map<String, dynamic>.from(m as Map)));
      _cachedAdminIds = List<String>.from(groupData?['adminIds'] ?? []);
    });
    // Capture unread separator BEFORE marking as read so the divider shows
    // messages the user hasn't seen yet. Cleared when they leave and return.
    final lastReadAtMap = groupData?['lastReadAt'] as Map<String, dynamic>?;
    final myLastReadAt = lastReadAtMap?[user.uid] as Timestamp?;
    final lastMsgAt = groupData?['lastMessageAt'] as Timestamp?;
    if (lastMsgAt != null &&
        (myLastReadAt == null || lastMsgAt.compareTo(myLastReadAt) > 0)) {
      setState(() => _unreadSeparatorAt =
          myLastReadAt ?? Timestamp.fromMillisecondsSinceEpoch(0));
    } else {
      setState(() => _unreadSeparatorAt = null);
    }

    // Backfill lastMessageAt for groups that existed before this feature was added.
    // This ensures dots appear for members who haven't opened the chat yet.
    if (groupData?['lastMessageAt'] == null) {
      final latest = await _msgs
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (latest.docs.isNotEmpty) {
        final msgData = latest.docs.first.data() as Map<String, dynamic>?;
        final ts = msgData?['createdAt'] as Timestamp?;
        if (ts != null) {
          await _db
              .collection('study_groups')
              .doc(widget.groupId)
              .update({'lastMessageAt': ts});
        }
      }
    }
    _markReadByMe();
  }

  void _markLastMessage() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _db.collection('study_groups').doc(widget.groupId).update({
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastReadAt.$uid': FieldValue.serverTimestamp(),
    });
  }

  void _markReadByMe() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _db.collection('study_groups').doc(widget.groupId).update({
      'lastReadAt.$uid': FieldValue.serverTimestamp(),
    });
  }

  String _uidToName(String uid) {
    for (final m in _cachedMembers) {
      if (m['uid'] == uid) return m['username'] as String? ?? uid;
    }
    return uid;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  CollectionReference get _msgs =>
      _db.collection('study_groups').doc(widget.groupId).collection('messages');

  Future<String> get _uname async =>
      _cachedUsername ?? await widget.getUsername();

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final user = _auth.currentUser;
    if (user == null) return;
    _ctrl.clear();
    await _msgs.add({
      'type':           'text',
      'text':           text,
      'senderId':       user.uid,
      'senderUsername': await _uname,
      'createdAt':      FieldValue.serverTimestamp(),
    });
    _markLastMessage();
    _scrollToBottom();
  }

  Future<void> _sendFile() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final picked = await _certSvc.pickPdf();
    if (picked == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploading file…'),
              duration: Duration(seconds: 60)));
    }
    try {
      final ts   = DateTime.now().millisecondsSinceEpoch;
      final path = 'group_files/${widget.groupId}/${ts}_${picked.name}';
      final ref  = CertificateService.storageRef(path);
      await ref.putData(picked.bytes);
      final url    = await ref.getDownloadURL();
      final sizeKB = (picked.bytes.lengthInBytes / 1024).toStringAsFixed(0);
      await _msgs.add({
        'type':           'file',
        'fileName':       picked.name,
        'fileUrl':        url,
        'storagePath':    path,
        'fileSizeKB':     sizeKB,
        'senderId':       user.uid,
        'senderUsername': await _uname,
        'createdAt':      FieldValue.serverTimestamp(),
      });
      _markLastMessage();
      _scrollToBottom();
    } finally {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    }
  }

  Future<void> _sendImage() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // image_picker routes through the native Android/iOS image pipeline,
    // which automatically applies EXIF rotation before returning bytes.
    final xfile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (xfile == null) return;
    Uint8List bytes = await xfile.readAsBytes();

    // On web the native pipeline doesn't run, so fix EXIF orientation manually.
    // Skip this on mobile — image_picker already handled it; re-encoding here
    // would decode the whole photo on the main thread and freeze the UI.
    if (kIsWeb) {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        bytes = Uint8List.fromList(
            img.encodeJpg(img.bakeOrientation(decoded), quality: 88));
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Uploading image…'),
              duration: Duration(seconds: 60)));
    }
    try {
      final ts   = DateTime.now().millisecondsSinceEpoch;
      final name = xfile.name.isNotEmpty ? xfile.name : 'image.jpg';
      final path = 'group_files/${widget.groupId}/${ts}_$name';
      final ref  = CertificateService.storageRef(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url    = await ref.getDownloadURL();
      final sizeKB = (bytes.lengthInBytes / 1024).toStringAsFixed(0);
      await _msgs.add({
        'type':           'image',
        'fileName':       name,
        'imageUrl':       url,
        'storagePath':    path,
        'fileSizeKB':     sizeKB,
        'senderId':       user.uid,
        'senderUsername': await _uname,
        'createdAt':      FieldValue.serverTimestamp(),
      });
      _markLastMessage();
      _scrollToBottom();
    } finally {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    }
  }

  Future<void> _scheduleEvent() async {
    final titleCtrl  = TextEditingController();
    final detailCtrl = TextEditingController();
    DateTime? evDate;
    TimeOfDay? evTime;
    String evType = 'Meeting';
    const types = ['Meeting', 'Presentation', 'Deadline', 'Study Session', 'Other'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top:   BorderSide(color: AppColors.border(ctx), width: 2),
                left:  BorderSide(color: AppColors.border(ctx), width: 2),
                right: BorderSide(color: AppColors.border(ctx), width: 2),
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: _kGroup.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.event, color: _kGroup, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Schedule Group Event',
                          style: GoogleFonts.dmMono(
                              fontSize: 17, fontWeight: FontWeight.bold))),
                      GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Icon(Icons.close, color: AppColors.subtext(ctx))),
                    ]),
                    const SizedBox(height: 16),
                    Text('Event Type', style: GoogleFonts.dmMono(
                        fontSize: 12, color: AppColors.subtext(ctx), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6,
                      children: types.map((t) => GestureDetector(
                        onTap: () => setS(() => evType = t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: evType == t ? _kGroup : AppColors.card(ctx),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: evType == t ? _kGroup : AppColors.border(ctx),
                                width: evType == t ? 2 : 1),
                          ),
                          child: Text(t, style: GoogleFonts.dmMono(
                              fontSize: 12, fontWeight: FontWeight.bold,
                              color: evType == t ? Colors.white : AppColors.subtext(ctx))),
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 14),
                    Text('Title *', style: GoogleFonts.dmMono(
                        fontSize: 12, color: AppColors.subtext(ctx), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    _field(ctx, titleCtrl, 'e.g. Week 3 Presentation', autofocus: true),
                    const SizedBox(height: 10),
                    _field(ctx, detailCtrl, 'Location, notes… (optional)', lines: 2),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () async {
                        final isDark = AppColors.isDark(ctx);
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2030),
                          builder: (_, ch) => Theme(
                            data: isDark
                                ? ThemeData.dark().copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: _kGroup,
                                      onPrimary: Colors.white,
                                      surface: Color(0xFF252D47),
                                      onSurface: Colors.white,
                                    ),
                                  )
                                : ThemeData.light().copyWith(
                                    colorScheme: const ColorScheme.light(
                                      primary: _kGroup,
                                    ),
                                  ),
                            child: ch!,
                          ),
                        );
                        if (p != null) setS(() => evDate = p);
                      },
                      child: _pickerTile(ctx,
                        icon: Icons.calendar_today,
                        label: evDate != null
                            ? DateFormat('EEE, dd MMM yyyy').format(evDate!)
                            : 'Select date *',
                        active: evDate != null,
                        color: _kGroup,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        final p = await showDialog<TimeOfDay>(
                          context: ctx,
                          builder: (_) => _SgsCustomTimePickerDialog(
                              initialTime: evTime),
                        );
                        if (p != null) setS(() => evTime = p);
                      },
                      child: _pickerTile(ctx,
                        icon: Icons.access_time,
                        label: evTime != null ? evTime!.format(ctx) : 'Select time *',
                        active: evTime != null,
                        color: _kGroup,
                        showArrow: true,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (titleCtrl.text.trim().isEmpty ||
                              evDate == null || evTime == null) return;
                          final user = _auth.currentUser;
                          if (user == null) return;
                          final dt = DateTime(evDate!.year, evDate!.month,
                              evDate!.day, evTime!.hour, evTime!.minute);
                          final gSnap = await _db
                              .collection('study_groups')
                              .doc(widget.groupId)
                              .get();
                          final mIds = List<String>.from(
                              gSnap.data()?['memberIds'] ?? []);
                          await _msgs.add({
                            'type':           'event',
                            'eventType':      evType,
                            'title':          titleCtrl.text.trim(),
                            'details':        detailCtrl.text.trim(),
                            'eventDate':      Timestamp.fromDate(dt),
                            'senderId':       user.uid,
                            'senderUsername': await _uname,
                            'subject':        widget.subject,
                            'memberIds':      mIds,
                            'accepted':       [],
                            'declined':       [],
                            'createdAt':      FieldValue.serverTimestamp(),
                          });
                          _markLastMessage();
                          if (ctx.mounted) Navigator.pop(ctx);
                          _scrollToBottom();
                        },
                        icon: const Icon(Icons.send, size: 18),
                        label: Text('Send to Group', style: GoogleFonts.dmMono(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGroup,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createPoll() async {
    final qCtrl = TextEditingController();
    final List<TextEditingController> oCtrls = [
      TextEditingController(), TextEditingController(),
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top:   BorderSide(color: AppColors.border(ctx), width: 2),
                left:  BorderSide(color: AppColors.border(ctx), width: 2),
                right: BorderSide(color: AppColors.border(ctx), width: 2),
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: _kYellow.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.poll_outlined,
                            color: _kYellow, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Create Poll', style: GoogleFonts.dmMono(
                          fontSize: 17, fontWeight: FontWeight.bold))),
                      GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Icon(Icons.close, color: AppColors.subtext(ctx))),
                    ]),
                    const SizedBox(height: 16),
                    Text('Question *', style: GoogleFonts.dmMono(
                        fontSize: 12, color: AppColors.subtext(ctx), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    _field(ctx, qCtrl, 'Ask the group something…', autofocus: true),
                    const SizedBox(height: 14),
                    Text('Options', style: GoogleFonts.dmMono(
                        fontSize: 12, color: AppColors.subtext(ctx), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...oCtrls.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(child: _field(ctx, e.value, 'Option ${e.key + 1}')),
                        if (oCtrls.length > 2) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setS(() => oCtrls.removeAt(e.key)),
                            child: const Icon(Icons.remove_circle_outline,
                                color: _kRed, size: 22),
                          ),
                        ],
                      ]),
                    )),
                    if (oCtrls.length < 6)
                      TextButton.icon(
                        onPressed: () =>
                            setS(() => oCtrls.add(TextEditingController())),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('Add option',
                            style: GoogleFonts.dmMono(fontSize: 13)),
                        style: TextButton.styleFrom(foregroundColor: _kBlue),
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final q = qCtrl.text.trim();
                          final opts = oCtrls
                              .map((c) => c.text.trim())
                              .where((s) => s.isNotEmpty)
                              .toList();
                          if (q.isEmpty || opts.length < 2) return;
                          final user = _auth.currentUser;
                          if (user == null) return;
                          final votes = {for (final o in opts) o: <String>[]};
                          await _msgs.add({
                            'type':           'poll',
                            'question':       q,
                            'options':        opts,
                            'votes':          votes,
                            'senderId':       user.uid,
                            'senderUsername': await _uname,
                            'createdAt':      FieldValue.serverTimestamp(),
                          });
                          _markLastMessage();
                          if (ctx.mounted) Navigator.pop(ctx);
                          _scrollToBottom();
                        },
                        icon: const Icon(Icons.poll_outlined, size: 18),
                        label: Text('Post Poll', style: GoogleFonts.dmMono(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kYellow,
                          foregroundColor: AppColors.text(ctx),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteSheet(DocumentSnapshot doc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top:   BorderSide(color: AppColors.border(context), width: 2),
            left:  BorderSide(color: AppColors.border(context), width: 2),
            right: BorderSide(color: AppColors.border(context), width: 2),
          ),
        ),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border(context),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: _kRed),
              title: Text('Delete Message',
                  style: GoogleFonts.dmMono(fontSize: 14, color: _kRed)),
              onTap: () async {
                Navigator.pop(context);
                await confirmAndDeleteDialog(
                  context,
                  title: 'Delete Message',
                  message: 'Are you sure you want to delete this message? This cannot be undone.',
                  onDelete: () => doc.reference.delete(),
                );
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _kickMember(BuildContext ctx, String uid, String uname) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card(ctx),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.border(ctx), width: 2)),
        title: Text('Kick $uname?',
            style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
        content: Text('Remove $uname from the group?',
            style: GoogleFonts.dmMono(
                fontSize: 13, color: AppColors.subtext(ctx))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.dmMono(color: AppColors.subtext(ctx)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            child: Text('Kick',
                style: GoogleFonts.dmMono(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final snap = await _db.collection('study_groups').doc(widget.groupId).get();
    if (!snap.exists) return;
    final d = snap.data() as Map<String, dynamic>;
    final updIds = List<String>.from(d['memberIds'] ?? [])..remove(uid);
    final updMem = List<Map<String, dynamic>>.from(d['members'] ?? [])
      ..removeWhere((x) => x['uid'] == uid);
    final updAdminIds = List<String>.from(d['adminIds'] ?? [])..remove(uid);
    await _db
        .collection('study_groups')
        .doc(widget.groupId)
        .update({'memberIds': updIds, 'members': updMem, 'adminIds': updAdminIds});
    try {
      final pending = await _db
          .collection('group_invitations')
          .where('groupId', isEqualTo: widget.groupId)
          .where('inviteeId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .get();
      await Future.wait(
          pending.docs.map((doc) => doc.reference.update({'status': 'cancelled'})));
    } catch (_) {}
  }

  void _showOtherMsgOptions(
      DocumentSnapshot doc, String senderUid, String senderUsername) {
    final myUid = _auth.currentUser?.uid ?? '';
    final amHost = myUid == _groupCreatedBy;
    final amAdmin = _cachedAdminIds.contains(myUid);
    final senderIsHost = senderUid == _groupCreatedBy;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top:   BorderSide(color: AppColors.border(context), width: 2),
            left:  BorderSide(color: AppColors.border(context), width: 2),
            right: BorderSide(color: AppColors.border(context), width: 2),
          ),
        ),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border(context),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            // Both host and admin can delete any message
            if (amHost || amAdmin)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: _kRed),
                title: Text('Delete Message',
                    style: GoogleFonts.dmMono(fontSize: 14, color: _kRed)),
                onTap: () async {
                  Navigator.pop(context);
                  await confirmAndDeleteDialog(
                    context,
                    title: 'Delete Message',
                    message: 'Are you sure you want to delete this message? This cannot be undone.',
                    onDelete: () => doc.reference.delete(),
                  );
                },
              ),
            // Can kick anyone except the group creator
            if ((amHost || amAdmin) && !senderIsHost)
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: _kRed),
                title: Text('Kick $senderUsername',
                    style: GoogleFonts.dmMono(fontSize: 14, color: _kRed)),
                onTap: () {
                  Navigator.pop(context);
                  _kickMember(context, senderUid, senderUsername);
                },
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  void _showMsgOptions(DocumentSnapshot doc, String currentText) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top:   BorderSide(color: AppColors.border(context), width: 2),
            left:  BorderSide(color: AppColors.border(context), width: 2),
            right: BorderSide(color: AppColors.border(context), width: 2),
          ),
        ),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border(context),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: _kBlue),
              title: Text('Edit Message',
                  style: GoogleFonts.dmMono(fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _editMessage(doc, currentText);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: _kRed),
              title: Text('Delete Message',
                  style: GoogleFonts.dmMono(fontSize: 14, color: _kRed)),
              onTap: () async {
                Navigator.pop(context);
                await confirmAndDeleteDialog(
                  context,
                  title: 'Delete Message',
                  message: 'Are you sure you want to delete this message? This cannot be undone.',
                  onDelete: () => doc.reference.delete(),
                );
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  void _editMessage(DocumentSnapshot doc, String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(ctx),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.border(ctx), width: 2)),
        title: Text('Edit Message',
            style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          style: GoogleFonts.dmMono(fontSize: 14),
          maxLines: null,
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.input(ctx),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border(ctx))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border(ctx))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBlue, width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.dmMono(color: AppColors.subtext(ctx))),
          ),
          ElevatedButton(
            onPressed: () async {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) {
                await doc.reference.update({'text': t, 'edited': true});
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: Text('Save', style: GoogleFonts.dmMono(
                color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final myUid = _auth.currentUser?.uid ?? '';

    return Column(children: [
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: _msgs.orderBy('createdAt').snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: _kBlue));
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return _emptyState(ctx, Icons.chat_bubble_outline,
                  'No messages yet', 'Say hello to your group!');
            }

            final List<Widget> items = [];
            String? lastLabel;
            bool sepInserted = false;
            for (final doc in docs) {
              final data    = doc.data() as Map<String, dynamic>;
              final ts      = (data['createdAt'] as Timestamp?)?.toDate();
              final label   = ts != null ? _dateLabel(ts) : null;
              final msgType = data['type'] as String? ?? 'text';
              final isMe    = data['senderId'] == myUid;
              final createdAtTs = data['createdAt'] as Timestamp?;

              // Insert "New Messages" divider before the first unread message.
              if (!sepInserted &&
                  _unreadSeparatorAt != null &&
                  createdAtTs != null &&
                  createdAtTs.compareTo(_unreadSeparatorAt!) > 0) {
                sepInserted = true;
                items.add(_newMsgSepRow(ctx));
              }

              if (label != null && label != lastLabel) {
                lastLabel = label;
                items.add(_dateSepRow(context, label));
              }

              if (msgType == 'file') {
                items.add(_buildFileMsg(doc, data, isMe));
              } else if (msgType == 'image') {
                items.add(_buildImageMsg(doc, data, isMe));
              } else if (msgType == 'event') {
                items.add(_buildEventMsg(doc, data, myUid));
              } else if (msgType == 'poll') {
                items.add(_buildPollMsg(doc, data, myUid));
              } else {
                items.add(_buildTextBubble(doc, data, isMe));
              }
            }

            final reversed = items.reversed.toList();
            return ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: reversed.length,
              itemBuilder: (_, i) => reversed[i],
            );
          },
        ),
      ),

      // Input bar
      Container(
        color: AppColors.card(context),
        padding: EdgeInsets.fromLTRB(
            8, 10, 8, MediaQuery.of(context).padding.bottom + 10),
        child: Row(children: [
          _inputBtn(Icons.attach_file, _sendFile, tooltip: 'Attach file'),
          _inputBtn(Icons.image_outlined, _sendImage,
              color: _kBlue, tooltip: 'Send image'),
          _inputBtn(Icons.event_outlined, _scheduleEvent,
              color: _kGreen, tooltip: 'Schedule event'),
          _inputBtn(Icons.poll_outlined, _createPoll,
              color: _kYellow, tooltip: 'Create poll'),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: GoogleFonts.dmMono(fontSize: 15),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendText(),
              decoration: InputDecoration(
                hintText: 'Type a message…',
                hintStyle: GoogleFonts.dmMono(color: AppColors.subtext(context), fontSize: 15),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: AppColors.fieldBg(context),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendText,
            child: Container(
              width: 48, height: 48,
              decoration: const BoxDecoration(
                  color: _kBlue, shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 22),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _inputBtn(IconData icon, VoidCallback onTap,
      {Color? color, String? tooltip}) {
    color ??= AppColors.subtext(context);
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 36, height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  String _dateLabel(DateTime dt) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day   = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('EEE, dd MMM yyyy').format(dt);
  }

  Widget _buildTextBubble(
      DocumentSnapshot doc, Map<String, dynamic> data, bool isMe) {
    final text       = data['text'] as String? ?? '';
    final uname      = data['senderUsername'] as String? ?? 'Unknown';
    final senderUid  = data['senderId'] as String? ?? '';
    final ts         = (data['createdAt'] as Timestamp?)?.toDate();
    final edited     = data['edited'] == true;

    final myUid  = _auth.currentUser?.uid ?? '';
    final amHost  = myUid == _groupCreatedBy;
    final amAdmin = _cachedAdminIds.contains(myUid);
    final canAct  = isMe || amHost || amAdmin;

    return GestureDetector(
      onLongPress: canAct
          ? () {
              HapticFeedback.mediumImpact();
              if (isMe) {
                _showMsgOptions(doc, text);
              } else {
                _showOtherMsgOptions(doc, senderUid, uname);
              }
            }
          : null,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
              bottom: 10, left: isMe ? 60 : 0, right: isMe ? 0 : 60),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 3),
                  child: Text(uname, style: GoogleFonts.dmMono(
                      fontSize: 11, fontWeight: FontWeight.bold,
                      color: AppColors.isDark(context) ? const Color(0xFF82B4FF) : _kBlue)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isMe ? _kBlue : AppColors.card(context),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: isMe
                        ? const Radius.circular(18)
                        : const Radius.circular(4),
                    bottomRight: isMe
                        ? const Radius.circular(4)
                        : const Radius.circular(18),
                  ),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: GoogleFonts.dmMono(
                        fontSize: 14,
                        color: isMe ? Colors.white : AppColors.text(context),
                        height: 1.4)),
                    if (edited)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('edited', style: GoogleFonts.dmMono(
                            fontSize: 9,
                            color: isMe ? Colors.white54 : AppColors.subtext(context))),
                      ),
                  ],
                ),
              ),
              if (ts != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
                  child: Text(DateFormat('h:mm a').format(ts),
                      style: GoogleFonts.dmMono(
                          fontSize: 10, color: AppColors.subtext(context))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── File message — tap to PREVIEW, no inline download button ───────────────
  Widget _buildFileMsg(
      DocumentSnapshot doc, Map<String, dynamic> data, bool isMe) {
    final myUid     = _auth.currentUser?.uid ?? '';
    final amHost    = myUid == _groupCreatedBy;
    final amAdmin   = _cachedAdminIds.contains(myUid);
    final canAct    = isMe || amHost || amAdmin;
    final senderUid = data['senderId'] as String? ?? '';
    final uname     = data['senderUsername'] as String? ?? 'Unknown';
    final fileName = data['fileName'] as String? ?? 'File';
    final sizeKB   = data['fileSizeKB']?.toString() ?? '';
    final ts       = (data['createdAt'] as Timestamp?)?.toDate();
    final sp       = data['storagePath'] as String? ?? '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
            bottom: 10, left: isMe ? 40 : 0, right: isMe ? 0 : 40),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 3),
                child: Text(uname, style: GoogleFonts.dmMono(
                    fontSize: 11, fontWeight: FontWeight.bold,
                    color: AppColors.isDark(context) ? const Color(0xFF82B4FF) : _kBlue)),
              ),
            // Tappable card → opens full PDF viewer; long press → delete
            GestureDetector(
              onTap: sp.isEmpty ? null : () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _GroupPdfViewerScreen(
                    title: fileName,
                    storagePath: sp,
                    fileName: fileName,
                  ),
                ));
              },
              onLongPress: canAct
                  ? () {
                      HapticFeedback.mediumImpact();
                      if (isMe) {
                        _showDeleteSheet(doc);
                      } else {
                        _showOtherMsgOptions(doc, senderUid, uname);
                      }
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMe ? _kBlue.withValues(alpha: 0.1) : AppColors.card(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isMe ? _kBlue : AppColors.border(context), width: 1.5),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                        color: _kRed,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.picture_as_pdf_outlined,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fileName, style: GoogleFonts.dmMono(
                          fontSize: 12, fontWeight: FontWeight.bold),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (sizeKB.isNotEmpty)
                        Text('$sizeKB KB', style: GoogleFonts.dmMono(
                            fontSize: 10, color: AppColors.subtext(context))),
                    ],
                  )),
                  const SizedBox(width: 10),
                  // "Tap to preview" hint
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                        color: _kBlue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.visibility_outlined,
                          color: _kBlue, size: 14),
                      const SizedBox(width: 4),
                      Text('Preview',
                          style: GoogleFonts.dmMono(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _kBlue)),
                    ]),
                  ),
                ]),
              ),
            ),
            if (ts != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
                child: Text(DateFormat('h:mm a').format(ts),
                    style: GoogleFonts.dmMono(
                        fontSize: 10, color: AppColors.subtext(context))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageMsg(
      DocumentSnapshot doc, Map<String, dynamic> data, bool isMe) {
    final myUid     = _auth.currentUser?.uid ?? '';
    final amHost    = myUid == _groupCreatedBy;
    final amAdmin   = _cachedAdminIds.contains(myUid);
    final canAct    = isMe || amHost || amAdmin;
    final senderUid = data['senderId'] as String? ?? '';
    final uname     = data['senderUsername'] as String? ?? 'Unknown';
    final fileName = data['fileName'] as String? ?? 'image.jpg';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final sp       = data['storagePath'] as String? ?? '';
    final ts       = (data['createdAt'] as Timestamp?)?.toDate();

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
            bottom: 10, left: isMe ? 60 : 0, right: isMe ? 0 : 60),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 3),
                child: Text(uname,
                    style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.isDark(context)
                            ? const Color(0xFF82B4FF)
                            : _kBlue)),
              ),
            GestureDetector(
              onTap: imageUrl.isEmpty
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _GroupImageViewerScreen(
                            title: fileName,
                            imageUrl: imageUrl,
                            storagePath: sp,
                            fileName: fileName,
                          ),
                        ),
                      ),
              onLongPress: canAct
                  ? () {
                      HapticFeedback.mediumImpact();
                      if (isMe) {
                        _showDeleteSheet(doc);
                      } else {
                        _showOtherMsgOptions(doc, senderUid, uname);
                      }
                    }
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: imageUrl.isEmpty
                    ? Container(
                        width: 220,
                        height: 150,
                        color: AppColors.card(context),
                        child: const Center(
                            child: Icon(Icons.broken_image_outlined, size: 40)),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 220,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 220,
                          height: 150,
                          decoration: BoxDecoration(
                            color: isMe
                                ? _kBlue.withValues(alpha: 0.1)
                                : AppColors.card(context),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                                color: _kBlue, strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 220,
                          height: 150,
                          decoration: BoxDecoration(
                            color: AppColors.card(context),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                              child: Icon(Icons.broken_image_outlined, size: 40)),
                        ),
                      ),
              ),
            ),
            if (ts != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
                child: Text(DateFormat('h:mm a').format(ts),
                    style: GoogleFonts.dmMono(
                        fontSize: 10, color: AppColors.subtext(context))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventMsg(
      DocumentSnapshot doc, Map<String, dynamic> data, String myUid) {
    final title    = data['title'] as String? ?? 'Event';
    final eType    = data['eventType'] as String? ?? 'Meeting';
    final details  = data['details'] as String? ?? '';
    final sender    = data['senderUsername'] as String? ?? 'Someone';
    final senderUid = data['senderId'] as String? ?? '';
    final evTs      = (data['eventDate'] as Timestamp?)?.toDate();
    final msgTs     = (data['createdAt'] as Timestamp?)?.toDate();
    final accepted  = List<String>.from(data['accepted'] ?? []);
    final myAcc     = accepted.contains(myUid);
    final isMe      = data['senderId'] == myUid;
    final amHost    = myUid == _groupCreatedBy;
    final amAdmin   = _cachedAdminIds.contains(myUid);
    final canAct    = isMe || amHost || amAdmin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMe)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 3),
            child: Text(sender, style: GoogleFonts.dmMono(
                fontSize: 11, fontWeight: FontWeight.bold,
                color: AppColors.isDark(context) ? const Color(0xFF82B4FF) : _kBlue)),
          ),
        GestureDetector(
          onLongPress: canAct
              ? () {
                  HapticFeedback.mediumImpact();
                  if (isMe) {
                    _showDeleteSheet(doc);
                  } else {
                    _showOtherMsgOptions(doc, senderUid, sender);
                  }
                }
              : null,
          child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kGreen, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.07),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(children: [
                const Icon(Icons.event, color: _kGreen, size: 18),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _kGreen, borderRadius: BorderRadius.circular(6)),
                  child: Text(eType.toUpperCase(), style: GoogleFonts.dmMono(
                      fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const Spacer(),
                if (msgTs != null)
                  Text(DateFormat('dd MMM, h:mm a').format(msgTs),
                      style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.subtext(context))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: GoogleFonts.dmMono(
                    fontSize: 16, fontWeight: FontWeight.bold)),
                if (evTs != null) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.calendar_today, size: 13, color: AppColors.subtext(context)),
                    const SizedBox(width: 5),
                    Text(DateFormat('EEE, dd MMM yyyy  •  h:mm a').format(evTs),
                        style: GoogleFonts.dmMono(fontSize: 12, color: AppColors.subtext(context))),
                  ]),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(details, style: GoogleFonts.dmMono(
                      fontSize: 12, color: AppColors.text(context))),
                ],
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.person_outline, size: 13, color: _kBlue),
                  const SizedBox(width: 4),
                  Text('Scheduled by $sender',
                      style: GoogleFonts.dmMono(fontSize: 11,
                          color: AppColors.isDark(context) ? const Color(0xFF82B4FF) : _kBlue)),
                ]),
                const SizedBox(height: 10),
                // Accepted members list
                if (accepted.isNotEmpty) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_circle, size: 14, color: _kGreen),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        accepted.map(_uidToName).join(', '),
                        style: GoogleFonts.dmMono(
                            fontSize: 11,
                            color: _kGreen,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                ],
                // Accept button (full width)
                GestureDetector(
                  onTap: myAcc ? null : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.card(ctx),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: Text('Accept Event',
                            style: GoogleFonts.dmMono(
                                fontWeight: FontWeight.bold)),
                        content: Text(
                          'Are you sure you want to accept and add "$title" to your schedule?',
                          style: GoogleFonts.dmMono(fontSize: 13),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('CANCEL',
                                style: GoogleFonts.dmMono(
                                    color: AppColors.subtext(ctx),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kGreen,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text('YES, ACCEPT',
                                style: GoogleFonts.dmMono(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    await doc.reference.update({
                      'accepted': FieldValue.arrayUnion([myUid]),
                    });
                    final personalDocId = '${myUid}__${doc.id}';
                    await FirebaseFirestore.instance
                        .collection('user_group_events')
                        .doc(personalDocId)
                        .set({
                      'userId': myUid,
                      'messageId': doc.id,
                      'groupId': widget.groupId,
                      'groupName': widget.groupName,
                      'subject': widget.subject,
                      'title': data['title'] ?? 'Group Event',
                      'details': data['details'] ?? '',
                      'eventType': data['eventType'] ?? 'Meeting',
                      'eventDate': data['eventDate'],
                      'senderUsername': data['senderUsername'] ?? '',
                      'senderId': data['senderId'] ?? '',
                      'isCompleted': false,
                      'createdAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: false));
                    NotificationScheduler().scheduleGroupEventsOnly().catchError((_) {});
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          'You accepted "$title"!',
                          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        backgroundColor: _kGreen,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        duration: const Duration(seconds: 2),
                      ));
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: myAcc ? _kGreen : AppColors.card(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kGreen, width: myAcc ? 0 : 2),
                    ),
                    child: Center(child: Text(
                      myAcc ? '✓ Accepted' : 'Accept',
                      style: GoogleFonts.dmMono(fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: myAcc ? Colors.white : _kGreen),
                    )),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        ),
      ],
    );
  }


  Widget _buildPollMsg(
      DocumentSnapshot doc, Map<String, dynamic> data, String myUid) {
    final question = data['question'] as String? ?? 'Poll';
    final options  = List<String>.from(data['options'] ?? []);
    final sender    = data['senderUsername'] as String? ?? 'Someone';
    final senderUid = data['senderId'] as String? ?? '';
    final ts        = (data['createdAt'] as Timestamp?)?.toDate();
    final rawVotes  = data['votes'] as Map<String, dynamic>? ?? {};
    final votes     = rawVotes.map(
        (k, v) => MapEntry(k, List<String>.from(v as List)));
    final total     = votes.values.fold(0, (s, l) => s + l.length);
    final myVote    = votes.entries
        .where((e) => e.value.contains(myUid))
        .map((e) => e.key)
        .firstOrNull;
    final isMe      = data['senderId'] == myUid;
    final amHost    = myUid == _groupCreatedBy;
    final amAdmin   = _cachedAdminIds.contains(myUid);
    final canAct    = isMe || amHost || amAdmin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMe)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 3),
            child: Text(sender, style: GoogleFonts.dmMono(
                fontSize: 11, fontWeight: FontWeight.bold,
                color: AppColors.isDark(context) ? const Color(0xFF82B4FF) : _kBlue)),
          ),
        GestureDetector(
          onLongPress: canAct
              ? () {
                  HapticFeedback.mediumImpact();
                  if (isMe) {
                    _showDeleteSheet(doc);
                  } else {
                    _showOtherMsgOptions(doc, senderUid, sender);
                  }
                }
              : null,
          child: Container(
          margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kYellow, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _kYellow.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            const Icon(Icons.poll_outlined, color: _kYellow, size: 18),
            const SizedBox(width: 8),
            Text('POLL', style: GoogleFonts.dmMono(fontSize: 10,
                fontWeight: FontWeight.bold, color: _kYellow)),
            const Spacer(),
            if (ts != null) Text(DateFormat('dd MMM, h:mm a').format(ts),
                style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.subtext(context))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(question, style: GoogleFonts.dmMono(
                fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.person_outline, size: 12, color: _kBlue),
              const SizedBox(width: 4),
              Text('by $sender', style: GoogleFonts.dmMono(
                  fontSize: 10, color: _kBlue)),
            ]),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final count   = votes[opt]?.length ?? 0;
              final pct     = total > 0 ? count / total : 0.0;
              final isVoted = myVote == opt;
              return GestureDetector(
                onTap: isVoted ? null : () async {
                  final upd = Map<String, dynamic>.from(rawVotes);
                  // Remove from previously voted option if changing vote
                  if (myVote != null) {
                    final oldList = List<String>.from(upd[myVote] ?? []);
                    oldList.remove(myUid);
                    upd[myVote] = oldList;
                  }
                  final lst = List<String>.from(upd[opt] ?? []);
                  lst.add(myUid);
                  upd[opt] = lst;
                  await doc.reference.update({'votes': upd});
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isVoted
                        ? _kYellow.withOpacity(0.1)
                        : AppColors.input(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isVoted ? _kYellow : AppColors.border(context),
                        width: isVoted ? 2 : 1),
                  ),
                  child: Stack(children: [
                    if (myVote != null)
                      Positioned.fill(
                        child: FractionallySizedBox(
                          widthFactor: pct,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _kYellow.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      child: Row(children: [
                        if (isVoted)
                          const Icon(Icons.check_circle,
                              size: 16, color: _kYellow)
                        else if (myVote == null)
                          Container(width: 16, height: 16,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.border(context), width: 2))),
                        const SizedBox(width: 10),
                        Expanded(child: Text(opt, style: GoogleFonts.dmMono(
                            fontSize: 13,
                            fontWeight: isVoted
                                ? FontWeight.bold : FontWeight.normal))),
                        if (myVote != null)
                          Text(
                            '$count (${(pct * 100).toStringAsFixed(0)}%)',
                            style: GoogleFonts.dmMono(
                                fontSize: 11, color: AppColors.subtext(context)),
                          ),
                      ]),
                    ),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 4),
            Text('$total vote${total == 1 ? '' : 's'}',
                style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.subtext(context))),
          ]),
        ),
      ]),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MILESTONES TAB
// ─────────────────────────────────────────────────────────────────────────────

class _MilestonesTab extends StatefulWidget {
  final String groupId;
  final Future<String> Function() getUsername;
  const _MilestonesTab({required this.groupId, required this.getUsername});
  @override
  State<_MilestonesTab> createState() => _MilestonesTabState();
}

class _MilestonesTabState extends State<_MilestonesTab> {
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  CollectionReference get _col =>
      _db.collection('study_groups').doc(widget.groupId).collection('milestones');

  Future<void> _add() async {
    final titleCtrl = TextEditingController();
    final descCtrl  = TextEditingController();
    DateTime? dueDate;
    TimeOfDay? dueTime;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.card(ctx),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.border(ctx), width: 2)),
          title: Text('Add Task', style: GoogleFonts.dmMono(
              fontSize: 18, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(ctx, titleCtrl, 'Task title', autofocus: true),
              const SizedBox(height: 12),
              _field(ctx, descCtrl, 'Description (optional)', lines: 3),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () async {
                  final isDark = AppColors.isDark(ctx);
                  final p = await showDatePicker(
                    context: ctx,
                    initialDate: dueDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    builder: (_, ch) => Theme(
                      data: isDark
                          ? ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: _kBlue,
                                onPrimary: Colors.white,
                                surface: Color(0xFF252D47),
                                onSurface: Colors.white,
                              ),
                            )
                          : ThemeData.light().copyWith(
                              colorScheme: const ColorScheme.light(
                                primary: _kBlue,
                              ),
                            ),
                      child: ch!,
                    ),
                  );
                  if (p != null) setS(() => dueDate = p);
                },
                child: _pickerTile(ctx,
                  icon: Icons.calendar_today,
                  label: dueDate != null
                      ? DateFormat('EEE, dd MMM yyyy').format(dueDate!)
                      : 'Set due date (optional)',
                  active: dueDate != null,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final p = await showDialog<TimeOfDay>(
                    context: ctx,
                    builder: (_) => _SgsCustomTimePickerDialog(
                        initialTime: dueTime ?? TimeOfDay.now()),
                  );
                  if (p != null) setS(() => dueTime = p);
                },
                child: _pickerTile(ctx,
                  icon: Icons.access_time,
                  label: dueTime != null
                      ? dueTime!.format(ctx)
                      : 'Set due time (optional)',
                  active: dueTime != null,
                  showArrow: true,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.dmMono(
                  fontSize: 14, color: AppColors.subtext(ctx))),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                final username = await widget.getUsername();
                DateTime? dueDt;
                if (dueDate != null) {
                  final t = dueTime ?? const TimeOfDay(hour: 23, minute: 59);
                  dueDt = DateTime(dueDate!.year, dueDate!.month, dueDate!.day,
                      t.hour, t.minute);
                }
                await _col.add({
                  'title':             titleCtrl.text.trim(),
                  'description':       descCtrl.text.trim(),
                  'done':              false,
                  'createdBy':         _auth.currentUser?.uid ?? '',
                  'createdByUsername': username,
                  'createdAt':         FieldValue.serverTimestamp(),
                  'dueAt':             dueDt != null
                      ? Timestamp.fromDate(dueDt) : null,
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text('Add', style: GoogleFonts.dmMono(
                  fontSize: 14, color: Colors.white,
                  fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: _kBlue,
        elevation: 3,
        icon: const Icon(Icons.add, color: Colors.white, size: 24),
        label: Text('Add Task', style: GoogleFonts.dmMono(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _col.orderBy('createdAt').snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _kBlue));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return _emptyState(ctx, Icons.checklist_rtl,
                'No milestones yet', 'Add tasks your group needs to complete');
          }
          final pending = docs.where((d) =>
              (d.data() as Map)['done'] != true).toList();
          final done = docs.where((d) =>
              (d.data() as Map)['done'] == true).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (pending.isNotEmpty) ...[
                _sectionChip('Pending', pending.length, _kBlue),
                const SizedBox(height: 10),
                ...pending.map(_milestoneCard),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionChip('Completed', done.length, _kGreen),
                const SizedBox(height: 10),
                ...done.map(_milestoneCard),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionChip(String label, int count, Color color) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text('$label  $count', style: GoogleFonts.dmMono(
            fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ),
    ]);
  }

  Widget _milestoneCard(DocumentSnapshot doc) {
    final data      = doc.data() as Map<String, dynamic>;
    final done      = data['done'] == true;
    final dueTs     = data['dueAt'] as Timestamp?;
    final dueDate   = dueTs?.toDate();
    final isOverdue = dueDate != null && !done &&
        dueDate.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: done
              ? _kGreen.withOpacity(0.5)
              : isOverdue
                  ? _kRed.withOpacity(0.5)
                  : AppColors.border(context),
          width: done || isOverdue ? 2 : 1.5,
        ),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => doc.reference.update({'done': !done}),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28, height: 28,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: done ? _kGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: done ? _kGreen : AppColors.border(context), width: 2.5),
              ),
              child: done
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data['title'] ?? '', style: GoogleFonts.dmMono(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done ? AppColors.subtext(context) : AppColors.text(context))),
              if ((data['description'] ?? '').isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(data['description'], style: GoogleFonts.dmMono(
                    fontSize: 13, color: AppColors.subtext(context), height: 1.4)),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _infoChip(Icons.person_outline,
                    data['createdByUsername'] ?? 'Unknown', _kBlue,
                    textColor: AppColors.isDark(context) ? const Color(0xFF82B4FF) : _kBlue),
                if (dueDate != null)
                  _infoChip(
                      Icons.schedule,
                      DateFormat('dd MMM, h:mm a').format(dueDate),
                      (!done && isOverdue) ? _kRed : _kGreen,
                      bold: true,
                      solid: !done && isOverdue,
                      textColor: AppColors.isDark(context)
                          ? const Color(0xFF4ADE80)
                          : _kGreen),
              ]),
            ],
          )),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: _kRed, size: 22),
            onPressed: () => confirmAndDeleteDialog(
              context,
              title: 'Delete Task',
              message: 'Are you sure you want to delete this task? This cannot be undone.',
              onDelete: () => doc.reference.delete(),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color,
      {bool bold = false, Color? textColor, bool solid = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: solid ? color : color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: solid ? Colors.white : color),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.dmMono(
            fontSize: 11,
            color: solid ? Colors.white : (textColor ?? color),
            fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UPDATES TAB
// ─────────────────────────────────────────────────────────────────────────────

class _UpdatesTab extends StatefulWidget {
  final String groupId;
  final Future<String> Function() getUsername;
  const _UpdatesTab({required this.groupId, required this.getUsername});
  @override
  State<_UpdatesTab> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends State<_UpdatesTab> {
  final _auth    = FirebaseAuth.instance;
  final _db      = FirebaseFirestore.instance;
  final _certSvc = CertificateService();

  CollectionReference get _col =>
      _db.collection('study_groups').doc(widget.groupId).collection('updates');

  Future<void> _postNote() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl  = TextEditingController();
    final files     = <({Uint8List bytes, String name})>[];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.card(ctx),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.border(ctx), width: 2)),
          title: Text('Post Note', style: GoogleFonts.dmMono(
              fontSize: 18, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(ctx, titleCtrl, 'Title', autofocus: true),
              const SizedBox(height: 12),
              _field(ctx, bodyCtrl, 'Notes / description (optional)', lines: 4),
              const SizedBox(height: 14),

              // ── Attachment list ──────────────────────────────────────
              if (files.isNotEmpty) ...[
                ...files.asMap().entries.map((e) {
                  final idx  = e.key;
                  final file = e.value;
                  final isWord = file.name.toLowerCase().endsWith('.doc') ||
                      file.name.toLowerCase().endsWith('.docx');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kGreen.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kGreen, width: 1.5),
                    ),
                    child: Row(children: [
                      Icon(
                        isWord
                            ? Icons.description_outlined
                            : Icons.picture_as_pdf_outlined,
                        size: 18,
                        color: isWord
                            ? const Color(0xFF2B579A)
                            : _kRed,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        file.name,
                        style: GoogleFonts.dmMono(
                            fontSize: 12, color: _kGreen),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )),
                      GestureDetector(
                        onTap: () => setS(() => files.removeAt(idx)),
                        child: const Icon(Icons.close,
                            size: 18, color: _kRed),
                      ),
                    ]),
                  );
                }),
                const SizedBox(height: 4),
              ],

              // ── Add file button ──────────────────────────────────────
              GestureDetector(
                onTap: () async {
                  final p = await _certSvc.pickDocument();
                  if (p != null) setS(() => files.add(p));
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.input(ctx),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border(ctx)),
                  ),
                  child: Row(children: [
                    Icon(Icons.attach_file,
                        color: AppColors.subtext(ctx), size: 18),
                    const SizedBox(width: 8),
                    Text('Add PDF / DOC file',
                        style: GoogleFonts.dmMono(
                            fontSize: 12,
                            color: AppColors.subtext(ctx))),
                  ]),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.dmMono(
                    fontSize: 14, color: AppColors.subtext(ctx)))),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                if (files.isNotEmpty) {
                  messenger.showSnackBar(const SnackBar(
                    content: Text('Uploading…'),
                    duration: Duration(seconds: 60),
                  ));
                }
                try {
                  final username = await widget.getUsername();
                  final attachments = <Map<String, dynamic>>[];
                  for (final f in files) {
                    final ts   = DateTime.now().millisecondsSinceEpoch;
                    final path =
                        'group_updates/${widget.groupId}/${ts}_${f.name}';
                    final ref  = CertificateService.storageRef(path);
                    await ref.putData(f.bytes);
                    final url    = await ref.getDownloadURL();
                    final sizeKB =
                        (f.bytes.lengthInBytes / 1024).toStringAsFixed(0);
                    attachments.add({
                      'fileName':   f.name,
                      'fileUrl':    url,
                      'storagePath': path,
                      'fileSizeKB': sizeKB,
                    });
                  }
                  await _col.add({
                    'updateType':       'note',
                    'title':            titleCtrl.text.trim(),
                    'body':             bodyCtrl.text.trim(),
                    'attachments':      attachments,
                    'postedBy':         _auth.currentUser?.uid ?? '',
                    'postedByUsername': username,
                    'createdAt':        FieldValue.serverTimestamp(),
                  });
                } finally {
                  if (mounted) messenger.clearSnackBars();
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text('Post', style: GoogleFonts.dmMono(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _auth.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'post_note_fab',
        onPressed: _postNote,
        backgroundColor: _kBlue,
        elevation: 3,
        icon: const Icon(Icons.add, color: Colors.white, size: 24),
        label: Text('Post Note', style: GoogleFonts.dmMono(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _col.orderBy('createdAt', descending: true).snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _kBlue));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return _emptyState(ctx, Icons.bolt_outlined,
                'No updates yet', 'Post an update or upload a file');
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc   = docs[i];
              final data  = doc.data() as Map<String, dynamic>;
              final ts    = (data['createdAt'] as Timestamp?)?.toDate();
              final isMe  = data['postedBy'] == myUid;
              final uType = data['updateType'] as String? ?? 'text';

              // Badge label + colour per type
              final badgeLabel = uType == 'file' ? 'FILE'
                  : uType == 'note' ? 'NOTE' : 'UPDATE';
              final badgeColor = uType == 'file' ? _kGreen : _kBlue;

              // Attachments for 'note' type
              final attachments = (data['attachments'] as List? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.card(ctx),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header bar ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.06),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(badgeLabel,
                              style: GoogleFonts.dmMono(
                                  fontSize: 10, fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ),
                        const Spacer(),
                        if (ts != null)
                          Text(DateFormat('dd MMM, h:mm a').format(ts),
                              style: GoogleFonts.dmMono(
                                  fontSize: 11, color: AppColors.subtext(ctx))),
                        if (isMe) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => confirmAndDeleteDialog(
                              context,
                              title: 'Delete Note',
                              message: 'Are you sure you want to delete this note? This cannot be undone.',
                              onDelete: () => doc.reference.delete(),
                            ),
                            child: const Icon(Icons.delete_outline,
                                color: _kRed, size: 20),
                          ),
                        ],
                      ]),
                    ),

                    // ── Body ────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['title'] ?? '', style: GoogleFonts.dmMono(
                              fontSize: 16, fontWeight: FontWeight.bold)),

                          // Body text (text + note types)
                          if ((data['body'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(data['body'], style: GoogleFonts.dmMono(
                                fontSize: 14,
                                color: AppColors.text(ctx),
                                height: 1.5)),
                          ],

                          // Legacy single-file (updateType == 'file')
                          if (uType == 'file') ...[
                            const SizedBox(height: 10),
                            _fileCard(ctx, {
                              'fileName':   data['fileName'],
                              'storagePath': data['storagePath'],
                              'fileSizeKB': data['fileSizeKB'],
                              'title':      data['title'],
                            }),
                          ],

                          // Multi-attachment (updateType == 'note')
                          if (uType == 'note' && attachments.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ...attachments.map((a) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _fileCard(ctx, a),
                            )),
                          ],

                          const SizedBox(height: 12),
                          Row(children: [
                            const Icon(Icons.person_outline,
                                size: 14, color: _kBlue),
                            const SizedBox(width: 5),
                            Text(data['postedByUsername'] ?? 'Unknown',
                                style: GoogleFonts.dmMono(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _kBlue)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _fileCard(BuildContext ctx, Map<String, dynamic> file) {
    final fileName  = (file['fileName'] as String? ?? '').toLowerCase();
    final isWord    = fileName.endsWith('.doc') || fileName.endsWith('.docx');
    final rawName   = file['fileName'] as String? ?? 'file';
    final storagePath = file['storagePath'] as String? ?? '';
    final sizeKB    = (file['fileSizeKB'] ?? '').toString();

    return GestureDetector(
      onTap: () async {
        if (isWord) {
          if (storagePath.isEmpty) return;
          final messenger = ScaffoldMessenger.of(context);
          messenger.showSnackBar(const SnackBar(
            content: Text('Downloading…'),
            duration: Duration(seconds: 60),
          ));
          try {
            await CertificateService().savePdfToDevice(
              storagePath: storagePath,
              fileName: rawName,
              subfolder: 'Documents',
            );
            messenger.clearSnackBars();
            messenger.showSnackBar(SnackBar(
              content: Text('$rawName saved to Downloads/Brenbox/Documents'),
              duration: const Duration(seconds: 3),
            ));
          } catch (e) {
            messenger.clearSnackBars();
            messenger.showSnackBar(SnackBar(
              content: Text('Download failed: $e'),
              duration: const Duration(seconds: 3),
            ));
          }
          return;
        }
        if (storagePath.isEmpty) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _GroupPdfViewerScreen(
            title: file['title'] as String? ?? rawName,
            storagePath: storagePath,
            fileName: rawName,
          ),
        ));
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.input(ctx),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border(ctx)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
                color: isWord ? const Color(0xFF2B579A) : _kRed,
                borderRadius: BorderRadius.circular(8)),
            child: Icon(
                isWord
                    ? Icons.description_outlined
                    : Icons.picture_as_pdf_outlined,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rawName,
                  style: GoogleFonts.dmMono(
                      fontSize: 12, fontWeight: FontWeight.bold),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              if (sizeKB.isNotEmpty)
                Text('$sizeKB KB',
                    style: GoogleFonts.dmMono(
                        fontSize: 10, color: AppColors.subtext(ctx))),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: isWord ? const Color(0xFF2B579A) : _kBlue,
                borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  isWord
                      ? Icons.download_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text(isWord ? 'Download' : 'Preview',
                  style: GoogleFonts.dmMono(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SgsCustomTimePickerDialog extends StatefulWidget {
  final TimeOfDay? initialTime;
  const _SgsCustomTimePickerDialog({this.initialTime});

  @override
  State<_SgsCustomTimePickerDialog> createState() =>
      _SgsCustomTimePickerDialogState();
}

class _SgsCustomTimePickerDialogState
    extends State<_SgsCustomTimePickerDialog> {
  late int _hour;
  late int _minute;
  late bool _isAm;

  bool _editingHour = false;
  bool _editingMinute = false;

  late TextEditingController _hourCtrl;
  late TextEditingController _minuteCtrl;
  late FocusNode _hourFocus;
  late FocusNode _minuteFocus;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTime ?? TimeOfDay.now();
    _isAm = t.period == DayPeriod.am;
    _hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    _minute = t.minute;

    _hourCtrl =
        TextEditingController(text: _hour.toString().padLeft(2, '0'));
    _minuteCtrl =
        TextEditingController(text: _minute.toString().padLeft(2, '0'));

    _hourFocus = FocusNode()
      ..addListener(() {
        if (_hourFocus.hasFocus) {
          _hourCtrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _hourCtrl.text.length,
          );
          setState(() => _editingHour = true);
        } else {
          _commitHour();
          setState(() => _editingHour = false);
        }
      });

    _minuteFocus = FocusNode()
      ..addListener(() {
        if (_minuteFocus.hasFocus) {
          _minuteCtrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _minuteCtrl.text.length,
          );
          setState(() => _editingMinute = true);
        } else {
          _commitMinute();
          setState(() => _editingMinute = false);
        }
      });
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  void _commitHour() {
    final v = int.tryParse(_hourCtrl.text);
    if (v != null && v >= 1 && v <= 12) {
      setState(() => _hour = v);
    }
    _hourCtrl.text = _hour.toString().padLeft(2, '0');
  }

  void _commitMinute() {
    final v = int.tryParse(_minuteCtrl.text);
    if (v != null && v >= 0 && v <= 59) {
      setState(() => _minute = v);
    }
    _minuteCtrl.text = _minute.toString().padLeft(2, '0');
  }

  TimeOfDay _toTimeOfDay() {
    int h = _hour % 12;
    if (!_isAm) h += 12;
    return TimeOfDay(hour: h, minute: _minute);
  }

  void _incrementHour(int delta) {
    setState(() {
      _hour = ((_hour - 1 + delta) % 12 + 12) % 12 + 1;
      _hourCtrl.text = _hour.toString().padLeft(2, '0');
    });
  }

  void _incrementMinute(int delta) {
    setState(() {
      _minute = (_minute + delta + 60) % 60;
      _minuteCtrl.text = _minute.toString().padLeft(2, '0');
    });
  }

  Future<void> _openDial() async {
    final isDark = AppColors.isDark(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTimeOfDay(),
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (_, child) {
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFF9CA3AF),
                    onPrimary: Colors.white,
                    surface: Color(0xFF252D47),
                    onSurface: Colors.white,
                  ),
                  timePickerTheme: TimePickerThemeData(
                    backgroundColor: const Color(0xFF252D47),
                    dialHandColor: const Color(0xFF9CA3AF),
                    dialBackgroundColor: const Color(0xFF2A3352),
                    hourMinuteTextColor: Colors.white,
                    hourMinuteColor: const Color(0xFF2A3352),
                    dayPeriodTextColor: Colors.white,
                    dayPeriodColor: const Color(0xFF2A3352),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFF3D4A6B), width: 2),
                    ),
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF6B7280),
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
                  ),
                  timePickerTheme: TimePickerThemeData(
                    backgroundColor: Colors.white,
                    dialHandColor: const Color(0xFF6B7280),
                    dialBackgroundColor: Color(0xFFF3F4F6),
                    hourMinuteTextColor: Colors.black,
                    hourMinuteColor: Color(0xFFE5E7EB),
                    dayPeriodTextColor: Colors.black,
                    dayPeriodColor: Color(0xFFE5E7EB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Colors.black, width: 2),
                    ),
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _isAm = picked.period == DayPeriod.am;
        _hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
        _minute = picked.minute;
        _hourCtrl.text = _hour.toString().padLeft(2, '0');
        _minuteCtrl.text = _minute.toString().padLeft(2, '0');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _hour.toString().padLeft(2, '0');
    final m = _minute.toString().padLeft(2, '0');
    final period = _isAm ? 'AM' : 'PM';

    return Dialog(
      backgroundColor: AppColors.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border(context), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select Time',
                style: GoogleFonts.dmMono(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _openDial,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.input(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border(context), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.access_time, size: 20,
                        color: AppColors.subtext(context)),
                    const SizedBox(width: 10),
                    Text('$h:$m $period',
                        style: GoogleFonts.dmMono(
                            fontSize: 26, fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.subtext(context).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.touch_app, size: 12,
                            color: AppColors.subtext(context)),
                        const SizedBox(width: 4),
                        Text('Use dial',
                            style: GoogleFonts.dmMono(
                                fontSize: 10, color: AppColors.subtext(context))),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Divider(color: AppColors.border(context))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('or type manually',
                    style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.subtext(context))),
              ),
              Expanded(child: Divider(color: AppColors.border(context))),
            ]),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SgsSpinnerField(
                  controller: _hourCtrl,
                  focusNode: _hourFocus,
                  label: 'HH',
                  onUp: () => _incrementHour(1),
                  onDown: () => _incrementHour(-1),
                  onSubmitted: (_) {
                    _commitHour();
                    _minuteFocus.requestFocus();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(':',
                      style: GoogleFonts.dmMono(
                          fontSize: 28, fontWeight: FontWeight.bold)),
                ),
                _SgsSpinnerField(
                  controller: _minuteCtrl,
                  focusNode: _minuteFocus,
                  label: 'MM',
                  onUp: () => _incrementMinute(1),
                  onDown: () => _incrementMinute(-1),
                  onSubmitted: (_) => _commitMinute(),
                ),
                const SizedBox(width: 14),
                _SgsAmPmToggle(
                  isAm: _isAm,
                  onChanged: (v) => setState(() => _isAm = v),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppColors.border(context), width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Cancel',
                      style: GoogleFonts.dmMono(
                          color: AppColors.text(context), fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (_editingHour) _commitHour();
                    if (_editingMinute) _commitMinute();
                    Navigator.pop(context, _toTimeOfDay());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB90000),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Confirm',
                      style: GoogleFonts.dmMono(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SgsSpinnerField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ValueChanged<String> onSubmitted;

  const _SgsSpinnerField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.onUp,
    required this.onDown,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _SgsArrowBtn(icon: Icons.keyboard_arrow_up, onTap: onUp),
      const SizedBox(height: 4),
      SizedBox(
        width: 68,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 2,
          onSubmitted: onSubmitted,
          style: GoogleFonts.dmMono(fontSize: 26, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            counterText: '',
            hintText: label,
            hintStyle: GoogleFonts.dmMono(fontSize: 18, color: AppColors.subtext(context)),
            filled: true,
            fillColor: AppColors.input(context),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border(context), width: 2)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border(context), width: 2)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.subtext(context), width: 2.5)),
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          ),
        ),
      ),
      const SizedBox(height: 4),
      _SgsArrowBtn(icon: Icons.keyboard_arrow_down, onTap: onDown),
    ]);
  }
}

class _SgsArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SgsArrowBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 68, height: 32,
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Icon(icon, size: 22, color: AppColors.subtext(context)),
      ),
    );
  }
}

class _SgsAmPmToggle extends StatelessWidget {
  final bool isAm;
  final ValueChanged<bool> onChanged;
  const _SgsAmPmToggle({required this.isAm, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _SgsPeriodBtn(label: 'AM', selected: isAm, onTap: () => onChanged(true)),
      const SizedBox(height: 6),
      _SgsPeriodBtn(label: 'PM', selected: !isAm, onTap: () => onChanged(false)),
    ]);
  }
}

class _SgsPeriodBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SgsPeriodBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52, height: 40,
        decoration: BoxDecoration(
          color: selected ? AppColors.subtext(context) : AppColors.card(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppColors.subtext(context) : AppColors.border(context),
              width: 2),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: GoogleFonts.dmMono(
                fontSize: 13, fontWeight: FontWeight.bold,
                color: selected ? Colors.white : AppColors.subtext(context))),
      ),
    );
  }
}