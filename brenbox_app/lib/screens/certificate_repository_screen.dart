import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../services/certificate_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CERTIFICATE REPOSITORY SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class CertificateRepositoryScreen extends StatefulWidget {
  const CertificateRepositoryScreen({Key? key}) : super(key: key);

  @override
  State<CertificateRepositoryScreen> createState() =>
      _CertificateRepositoryScreenState();
}

class _CertificateRepositoryScreenState
    extends State<CertificateRepositoryScreen> {
  final _service = CertificateService();
  final _searchController = TextEditingController();

  String _searchQuery = '';
  String? _filterYear;
  String? _filterTag;

  // ── Palette matching calendar_screen ──────────────────────────────────────
  static const _bgPage = Color(0xFFE5E7EB);   // same as CalendarScreen
  static const _dark   = Color(0xFF292929);   // same pill/header dark
  static const _red    = Color(0xFFB90000);   // accent red
  static const _tan    = Color(0xFFD4B896);   // keep for tags

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showUploadDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadEditSheet(
        service: _service,
        onDone: () => setState(() {}),
      ),
    );
  }

  void _showEditDialog(String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadEditSheet(
        service: _service,
        docId: docId,
        initialData: data,
        onDone: () => setState(() {}),
      ),
    );
  }

  Future<void> _confirmDelete(String docId, String storagePath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        title: Text(
          'Delete Certificate?',
          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'This will permanently delete the certificate file. This action cannot be undone.',
          style: GoogleFonts.dmMono(fontSize: 12, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.dmMono(color: Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            child: Text('Delete',
                style: GoogleFonts.dmMono(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.deleteCertificate(
          docId: docId, storagePath: storagePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Certificate deleted',
              style: GoogleFonts.dmMono(fontSize: 12)),
          backgroundColor: _dark,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
      }
    }
  }

  // ── Client-side filter ────────────────────────────────────────────────────
  List<QueryDocumentSnapshot> _applyFilters(
      List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;

      if (_searchQuery.isNotEmpty) {
        final title = (d['title'] ?? '').toString().toLowerCase();
        if (!title.contains(_searchQuery)) return false;
      }

      if (_filterYear != null && _filterYear!.isNotEmpty) {
        final year = (d['year'] ?? '').toString();
        if (year != _filterYear) return false;
      }

      if (_filterTag != null && _filterTag!.isNotEmpty) {
        final tags = List<String>.from(d['tags'] ?? []);
        if (!tags.contains(_filterTag)) return false;
      }

      return true;
    }).toList();
  }

  List<String> _extractYears(List<QueryDocumentSnapshot> docs) {
    final years = docs
        .map((d) =>
            (d.data() as Map<String, dynamic>)['year']?.toString() ?? '')
        .where((y) => y.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  List<String> _extractTags(List<QueryDocumentSnapshot> docs) {
    final tags = <String>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      tags.addAll(List<String>.from(data['tags'] ?? []));
    }
    return tags.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgPage,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ── Header — mirrors CalendarScreen ─────────────────
                Text(
                  'CERTIFICATES',
                  style: GoogleFonts.dmMono(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),
                Text(
                  'Store and manage your achievement certificates',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: Colors.black45,
                  ),
                ),

                const SizedBox(height: 20),

                // ── Search bar ───────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.dmMono(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search certificates...',
                      hintStyle: GoogleFonts.dmMono(
                          fontSize: 12, color: Colors.black38),
                      prefixIcon: const Icon(Icons.search,
                          size: 18, color: Colors.black45),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 18),
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.toLowerCase()),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Main stream ──────────────────────────────────────
                StreamBuilder<QuerySnapshot>(
                  stream: _service.getCertificates(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(48),
                          child: CircularProgressIndicator(
                              color: Color(0xFF6B7280)),
                        ),
                      );
                    }

                    final allDocs = snapshot.data?.docs ?? [];
                    final years = _extractYears(allDocs);
                    final tags = _extractTags(allDocs);
                    final filtered = _applyFilters(allDocs);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Filter chips
                        _buildFilterRow(years, tags),

                        const SizedBox(height: 16),

                        // Stats bar
                        if (allDocs.isNotEmpty) ...[
                          _buildStatsBar(allDocs.length),
                          const SizedBox(height: 16),
                        ],

                        // Grid or empty
                        filtered.isEmpty
                            ? _emptyState(allDocs.isEmpty)
                            : _buildGrid(filtered),

                        const SizedBox(height: 24),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(List<QueryDocumentSnapshot> filtered) {
    // Include the "+ Add" card as the last item
    final itemCount = filtered.length + 1;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == filtered.length) {
          return _AddCard(onTap: _showUploadDialog);
        }
        final doc = filtered[index];
        final data = doc.data() as Map<String, dynamic>;
        return _CertCard(
          docId: doc.id,
          data: data,
          service: _service,
          onEdit: () => _showEditDialog(doc.id, data),
          onDelete: () =>
              _confirmDelete(doc.id, data['storagePath'] ?? ''),
        );
      },
    );
  }

  Widget _buildFilterRow(List<String> years, List<String> tags) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip(
            'All',
            _filterYear == null && _filterTag == null,
            () => setState(() {
              _filterYear = null;
              _filterTag = null;
            }),
          ),
          ...years.map((y) => _filterChip(
                y,
                _filterYear == y,
                () => setState(() {
                  _filterYear = _filterYear == y ? null : y;
                  _filterTag = null;
                }),
              )),
          ...tags.map((t) => _filterChip(
                t,
                _filterTag == t,
                () => setState(() {
                  _filterTag = _filterTag == t ? null : t;
                  _filterYear = null;
                }),
                isTag: true,
              )),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap,
      {bool isTag = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _dark : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? _dark
                : isTag
                    ? _tan
                    : Colors.black,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTag) ...[
              Icon(Icons.label_outline,
                  size: 11, color: selected ? Colors.white : _tan),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.dmMono(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsBar(int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _dark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, size: 16, color: _tan),
          const SizedBox(width: 10),
          Text(
            '$total certificate${total == 1 ? '' : 's'} stored',
            style: GoogleFonts.dmMono(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _AnimatedTapButton(
            onTap: _showUploadDialog,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _tan,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '+ ADD',
                style: GoogleFonts.dmMono(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _dark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(bool noData) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        children: [
          const Icon(Icons.workspace_premium_outlined,
              size: 48, color: Color(0xFF6B7280)),
          const SizedBox(height: 12),
          Text(
            noData ? 'No certificates yet' : 'No results found',
            style: GoogleFonts.dmMono(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            noData
                ? 'Tap + to upload your first certificate'
                : 'Try a different search or filter',
            style: GoogleFonts.dmMono(fontSize: 11, color: Colors.black38),
            textAlign: TextAlign.center,
          ),
          if (noData) ...[
            const SizedBox(height: 24),
            _AnimatedTapButton(
              onTap: _showUploadDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: _dark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Text(
                  'Upload Certificate',
                  style: GoogleFonts.dmMono(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CERTIFICATE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _CertCard extends StatelessWidget {
  const _CertCard({
    required this.docId,
    required this.data,
    required this.service,
    required this.onEdit,
    required this.onDelete,
  });

  final String docId;
  final Map<String, dynamic> data;
  final CertificateService service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _dark = Color(0xFF292929);
  static const _tan  = Color(0xFFD4B896);
  static const _red  = Color(0xFFB90000);

  @override
  Widget build(BuildContext context) {
    final title      = (data['title'] ?? 'Untitled').toString();
    final year       = (data['year'] ?? '').toString();
    final tags       = List<String>.from(data['tags'] ?? []);
    final storagePath = (data['storagePath'] ?? '').toString();
    final fileName   = (data['fileName'] ?? 'certificate.pdf').toString();
    final sizeKB     = (data['fileSizeKB'] ?? 0).toDouble();

    return _AnimatedTapButton(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CertificateViewerScreen(
            title: title,
            storagePath: storagePath,
            fileName: fileName,
            service: service,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail ──────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF5F0EB),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // PDF icon mock
                        Container(
                          width: 52,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.black26, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(2, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(6, 8, 6, 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: List.generate(
                                      5,
                                      (i) => Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 3),
                                        height: 2,
                                        decoration: BoxDecoration(
                                          color: i == 0
                                              ? _tan
                                              : Colors.black12,
                                          borderRadius:
                                              BorderRadius.circular(1),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                decoration: BoxDecoration(
                                  color: _red.withOpacity(0.85),
                                  borderRadius: const BorderRadius.vertical(
                                      bottom: Radius.circular(5)),
                                ),
                                child: Text(
                                  'PDF',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.dmMono(
                                    fontSize: 7,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (sizeKB > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${sizeKB.toStringAsFixed(0)} KB',
                            style: GoogleFonts.dmMono(
                                fontSize: 9, color: Colors.black38),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 3-dot menu
                  Positioned(
                    top: 4,
                    right: 4,
                    child: PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'edit') onEdit();
                        if (val == 'delete') onDelete();
                      },
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(
                            color: Colors.black26, width: 1),
                      ),
                      icon: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.black26, width: 1),
                        ),
                        child: const Icon(Icons.more_vert,
                            size: 18, color: Colors.black54),
                      ),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            const Icon(Icons.edit_outlined,
                                color: Color(0xFF292929), size: 16),
                            const SizedBox(width: 8),
                            Text('Edit',
                                style: GoogleFonts.dmMono(
                                    fontSize: 13,
                                    color: const Color(0xFF292929))),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            const Icon(Icons.delete_outline,
                                color: _red, size: 16),
                            const SizedBox(width: 8),
                            Text('Delete',
                                style: GoogleFonts.dmMono(
                                    fontSize: 13, color: _red)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Info ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _dark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (year.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 9, color: Colors.black38),
                        const SizedBox(width: 3),
                        Text(year,
                            style: GoogleFonts.dmMono(
                                fontSize: 9, color: Colors.black45)),
                      ],
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      children: tags
                          .take(2)
                          .map((t) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _tan.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: _tan.withOpacity(0.5),
                                      width: 0.8),
                                ),
                                child: Text(t,
                                    style: GoogleFonts.dmMono(
                                        fontSize: 8, color: _dark)),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ADD CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AddCard extends StatelessWidget {
  const _AddCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _AnimatedTapButton(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFF292929),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              'Add Certificate',
              style: GoogleFonts.dmMono(
                fontSize: 11,
                color: Colors.black54,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  UPLOAD / EDIT BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _UploadEditSheet extends StatefulWidget {
  const _UploadEditSheet({
    required this.service,
    required this.onDone,
    this.docId,
    this.initialData,
  });

  final CertificateService service;
  final VoidCallback onDone;
  final String? docId;
  final Map<String, dynamic>? initialData;

  bool get isEdit => docId != null;

  @override
  State<_UploadEditSheet> createState() => _UploadEditSheetState();
}

class _UploadEditSheetState extends State<_UploadEditSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _yearCtrl;
  final TextEditingController _tagCtrl = TextEditingController();

  late List<String> _tags;

  Uint8List? _pickedBytes;
  String? _pickedFileName;

  double _uploadProgress = 0;
  bool _isLoading = false;
  String? _errorMsg;

  static const _dark  = Color(0xFF292929);
  static const _tan   = Color(0xFFD4B896);
  static const _red   = Color(0xFFB90000);
  static const _green = Color(0xFF2E7D32);

  static const _tagOptions = [
    'competition',
    'course',
    'workshop',
    'conference',
    'internship',
    'award',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _titleCtrl = TextEditingController(text: d?['title'] ?? '');
    _yearCtrl = TextEditingController(
        text: d?['year'] ?? DateTime.now().year.toString());
    _tags = List<String>.from(d?['tags'] ?? []);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _yearCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    final t = tag.trim().toLowerCase();
    if (t.isNotEmpty && !_tags.contains(t)) setState(() => _tags.add(t));
    _tagCtrl.clear();
  }

  Future<void> _pickFile() async {
    setState(() => _errorMsg = null);
    try {
      final picked = await widget.service.pickPdf();
      if (picked == null) return;
      setState(() {
        _pickedBytes   = picked.bytes;
        _pickedFileName = picked.name;
        if (_titleCtrl.text.trim().isEmpty) {
          _titleCtrl.text = picked.name
              .replaceAll('.pdf', '')
              .replaceAll('_', ' ')
              .replaceAll('-', ' ');
        }
      });
    } catch (e) {
      setState(() => _errorMsg = 'Could not pick file: $e');
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Please enter a certificate title.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg  = null;
    });

    try {
      if (widget.isEdit) {
        await widget.service.updateCertificate(
          docId: widget.docId!,
          title: _titleCtrl.text.trim(),
          year:  _yearCtrl.text.trim(),
          tags:  _tags,
        );
        if (mounted) {
          Navigator.pop(context);
          widget.onDone();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Certificate updated!',
                style: GoogleFonts.dmMono(fontSize: 12)),
            backgroundColor: _dark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ));
        }
      } else {
        if (_pickedBytes == null || _pickedFileName == null) {
          setState(() {
            _isLoading = false;
            _errorMsg  = 'Please pick a PDF file first.';
          });
          return;
        }

        final result = await widget.service.uploadCertificate(
          bytes:    _pickedBytes!,
          fileName: _pickedFileName!,
          title:    _titleCtrl.text.trim(),
          year:     _yearCtrl.text.trim(),
          tags:     _tags,
          onProgress: (p) {
            if (mounted) setState(() => _uploadProgress = p);
          },
        );

        if (result == null) {
          setState(() {
            _isLoading = false;
            _errorMsg  = 'Upload failed. Please try again.';
          });
          return;
        }

        if (mounted) {
          Navigator.pop(context);
          widget.onDone();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Certificate uploaded!',
                style: GoogleFonts.dmMono(fontSize: 12)),
            backgroundColor: _dark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ));
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMsg  = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit  = widget.isEdit;
    final hasFile = _pickedBytes != null;

    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top:   BorderSide(color: Colors.black, width: 2),
          left:  BorderSide(color: Colors.black, width: 2),
          right: BorderSide(color: Colors.black, width: 2),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Sheet title
              Text(
                isEdit ? 'Edit Certificate' : 'Upload Certificate',
                style: GoogleFonts.dmMono(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              // ── STEP 1: Pick PDF (upload mode only) ──────────────
              if (!isEdit) ...[
                Text(
                  'Step 1 — Select PDF File',
                  style: GoogleFonts.dmMono(
                      fontSize: 11,
                      color: Colors.black54,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                GestureDetector(
                  onTap: _isLoading ? null : _pickFile,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: hasFile
                          ? _green.withOpacity(0.07)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasFile ? _green : Colors.black38,
                        width: hasFile ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: hasFile
                                ? _green.withOpacity(0.15)
                                : Colors.black.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            hasFile
                                ? Icons.check_circle_outline
                                : Icons.picture_as_pdf_outlined,
                            color: hasFile ? _green : Colors.black45,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hasFile
                                    ? _pickedFileName!
                                    : 'No file selected',
                                style: GoogleFonts.dmMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: hasFile
                                      ? _green
                                      : Colors.black45,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (hasFile && _pickedBytes != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '${(_pickedBytes!.lengthInBytes / 1024).toStringAsFixed(0)} KB',
                                  style: GoogleFonts.dmMono(
                                      fontSize: 10,
                                      color: Colors.black38),
                                ),
                              ] else ...[
                                const SizedBox(height: 2),
                                Text('Tap to browse PDF files',
                                    style: GoogleFonts.dmMono(
                                        fontSize: 10,
                                        color: Colors.black38)),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: hasFile ? _green : _dark,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            hasFile ? 'Change' : 'Browse',
                            style: GoogleFonts.dmMono(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                Text(
                  'Step 2 — Fill in Details',
                  style: GoogleFonts.dmMono(
                      fontSize: 11,
                      color: Colors.black54,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
              ],

              // Certificate Title
              Text('Certificate Title *',
                  style: GoogleFonts.dmMono(
                      fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 6),
              TextField(
                controller: _titleCtrl,
                style: GoogleFonts.dmMono(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. Coding Champ 2024',
                  hintStyle: GoogleFonts.dmMono(
                      fontSize: 12, color: Colors.black26),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),

              // Year
              Text('Year',
                  style: GoogleFonts.dmMono(
                      fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 6),
              TextField(
                controller: _yearCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.dmMono(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. 2024',
                  hintStyle: GoogleFonts.dmMono(
                      fontSize: 12, color: Colors.black26),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),

              // Tags
              Text('Tags',
                  style: GoogleFonts.dmMono(
                      fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _tagOptions.map((t) {
                  final selected = _tags.contains(t);
                  return GestureDetector(
                    onTap: () => setState(() =>
                        selected ? _tags.remove(t) : _tags.add(t)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? _dark : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: selected ? _dark : Colors.black38,
                            width: 1.5),
                      ),
                      child: Text(t,
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            color: selected ? Colors.white : _dark,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          )),
                    ),
                  );
                }).toList(),
              ),

              // Custom tag
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagCtrl,
                      style: GoogleFonts.dmMono(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Custom tag...',
                        hintStyle: GoogleFonts.dmMono(
                            fontSize: 11, color: Colors.black26),
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: _addTag,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _addTag(_tagCtrl.text),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: _dark,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.add,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),

              // Custom tag chips
              if (_tags
                  .where((t) => !_tagOptions.contains(t))
                  .isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: _tags
                      .where((t) => !_tagOptions.contains(t))
                      .map((t) => Chip(
                            label: Text(t,
                                style: GoogleFonts.dmMono(fontSize: 11)),
                            backgroundColor: _tan.withOpacity(0.2),
                            deleteIcon:
                                const Icon(Icons.close, size: 14),
                            onDeleted: () =>
                                setState(() => _tags.remove(t)),
                          ))
                      .toList(),
                ),
              ],

              // Progress bar
              if (_isLoading && !isEdit) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _uploadProgress > 0 ? _uploadProgress : null,
                    minHeight: 6,
                    backgroundColor: Colors.black12,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(_dark),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _uploadProgress > 0
                      ? 'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                      : 'Uploading...',
                  style: GoogleFonts.dmMono(
                      fontSize: 11, color: Colors.black54),
                ),
              ],

              // Error
              if (_errorMsg != null) ...[
                const SizedBox(height: 10),
                Text(_errorMsg!,
                    style: GoogleFonts.dmMono(fontSize: 11, color: _red)),
              ],

              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: const BorderSide(
                            color: Colors.black, width: 2),
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Cancel',
                          style: GoogleFonts.dmMono(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Icon(
                              isEdit
                                  ? Icons.save_outlined
                                  : Icons.cloud_upload_outlined,
                              size: 18),
                      label: Text(
                        isEdit ? 'Save Changes' : 'Upload PDF',
                        style: GoogleFonts.dmMono(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            (!isEdit && !hasFile) ? Colors.black26 : _dark,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.black26,
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PDF VIEWER SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class CertificateViewerScreen extends StatefulWidget {
  const CertificateViewerScreen({
    Key? key,
    required this.title,
    required this.storagePath,
    required this.fileName,
    required this.service,
  }) : super(key: key);

  final String title;
  final String storagePath;
  final String fileName;
  final CertificateService service;

  @override
  State<CertificateViewerScreen> createState() =>
      _CertificateViewerScreenState();
}

class _CertificateViewerScreenState extends State<CertificateViewerScreen> {
  String? _localPath;
  bool _loading = true;
  String? _error;
  bool _downloading = false;

  static const _dark = Color(0xFF292929);
  static const _tan  = Color(0xFFD4B896);

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final bytes = await widget.service
          .downloadCertificateBytes(widget.storagePath);
      if (bytes == null) {
        setState(() {
          _loading = false;
          _error   = 'Failed to download PDF.';
        });
        return;
      }

      final dir  = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/cert_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);

      if (mounted) {
        setState(() {
          _localPath = file.path;
          _loading   = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error   = 'Error: $e';
        });
      }
    }
  }

  Future<void> _downloadToDevice() async {
    setState(() => _downloading = true);
    try {
      final savedPath = await widget.service.savePdfToDevice(
        storagePath: widget.storagePath,
        fileName:    widget.fileName,
      );

      if (!mounted) return;

      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saved to device!',
                  style: GoogleFonts.dmMono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              Text(savedPath,
                  style: GoogleFonts.dmMono(
                      fontSize: 10, color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Download failed. Please try again.',
              style: GoogleFonts.dmMono(fontSize: 12)),
          backgroundColor: const Color(0xFFB90000),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _dark,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: GoogleFonts.dmMono(
              fontSize: 14, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _downloading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Color(0xFFD4B896), strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      onPressed: _downloadToDevice,
                      tooltip: 'Save to device',
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _tan.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _tan.withOpacity(0.5), width: 1),
                        ),
                        child: const Icon(Icons.download_outlined,
                            color: _tan, size: 18),
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
                  const CircularProgressIndicator(
                      color: Color(0xFFD4B896)),
                  const SizedBox(height: 16),
                  Text('Loading certificate...',
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
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 48),
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
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED ANIMATED TAP BUTTON  (mirrors calendar_screen)
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedTapButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Duration duration;

  const _AnimatedTapButton({
    required this.child,
    required this.onTap,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<_AnimatedTapButton> createState() => _AnimatedTapButtonState();
}

class _AnimatedTapButtonState extends State<_AnimatedTapButton> {
  bool _isTapped = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => setState(() => _isTapped = true),
      onTapUp:     (_) => setState(() => _isTapped = false),
      onTapCancel: ()  => setState(() => _isTapped = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale:    _isTapped ? 0.95 : 1.0,
        duration: widget.duration,
        child:    widget.child,
      ),
    );
  }
}