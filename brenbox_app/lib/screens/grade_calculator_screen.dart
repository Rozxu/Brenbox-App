import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GradeCalculatorScreen extends StatefulWidget {
  const GradeCalculatorScreen({Key? key}) : super(key: key);

  @override
  State<GradeCalculatorScreen> createState() => _GradeCalculatorScreenState();
}

class _GradeCalculatorScreenState extends State<GradeCalculatorScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _subjectController = TextEditingController();
  final _semesterController = TextEditingController();
  final _searchController = TextEditingController();

  List<Map<String, TextEditingController>> _assessments = [];

  double _totalPercentage = 0.0;
  String _searchQuery = '';
  bool _isSaving = false;

  // ── Colour palette ───────────────────────────────────────────────
  static const _bgPage    = Color(0xFFE8E8E8);
  static const _bgCard    = Colors.white;
  static const _bgField   = Color(0xFFE5E7EB);
  static const _dark      = Color(0xFF1A1A1A);
  static const _resetBtn  = Color(0xFFD4B896);
  static const _gradeGreen  = Color(0xFF34A853);
  static const _gradeYellow = Color(0xFFFBBC05);
  static const _gradeRed    = Color(0xFFB90000);

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 5; i++) _addAssessmentRow();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _semesterController.dispose();
    _searchController.dispose();
    for (final row in _assessments) {
      row.values.forEach((c) => c.dispose());
    }
    super.dispose();
  }

  // ── Row management ───────────────────────────────────────────────

  void _addAssessmentRow() {
    final nameCtrl      = TextEditingController();
    final marksCtrl     = TextEditingController();
    final fullmarksCtrl = TextEditingController();
    final percentCtrl   = TextEditingController();

    marksCtrl.addListener(_recalculate);
    fullmarksCtrl.addListener(_recalculate);
    percentCtrl.addListener(_recalculate);

    setState(() {
      _assessments.add({
        'name': nameCtrl,
        'marks': marksCtrl,
        'fullmarks': fullmarksCtrl,
        'percent': percentCtrl,
      });
    });
  }

  void _removeRow(int index) {
    if (_assessments.length <= 1) return;
    final row = _assessments[index];
    row.values.forEach((c) => c.dispose());
    setState(() => _assessments.removeAt(index));
    _recalculate();
  }

  void _recalculate() {
    double total = 0.0;
    for (final row in _assessments) {
      final marks     = double.tryParse(row['marks']!.text)     ?? 0;
      final fullmarks = double.tryParse(row['fullmarks']!.text) ?? 0;
      final percent   = double.tryParse(row['percent']!.text)   ?? 0;
      if (fullmarks > 0 && percent > 0) {
        total += (marks / fullmarks) * percent;
      }
    }
    setState(() => _totalPercentage = total);
  }

  void _reset() {
    _subjectController.clear();
    _semesterController.clear();
    for (final row in _assessments) {
      row.values.forEach((c) => c.clear());
    }
    setState(() => _totalPercentage = 0.0);
  }

  // ── Save to Firestore ────────────────────────────────────────────

  Future<void> _saveResult() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showSnack('You must be logged in to save results.', _gradeRed);
      return;
    }

    final subject  = _subjectController.text.trim();
    final semester = _semesterController.text.trim();

    if (subject.isEmpty || semester.isEmpty) {
      _showSnack('Please enter subject name and semester.', _gradeRed);
      return;
    }

    final List<Map<String, dynamic>> assessmentData = [];
    for (final row in _assessments) {
      final name      = row['name']!.text.trim();
      final marks     = double.tryParse(row['marks']!.text)     ?? 0;
      final fullmarks = double.tryParse(row['fullmarks']!.text) ?? 0;
      final percent   = double.tryParse(row['percent']!.text)   ?? 0;
      if (name.isNotEmpty || marks > 0 || fullmarks > 0) {
        assessmentData.add({
          'name': name,
          'marks': marks,
          'fullmarks': fullmarks,
          'percent': percent,
          'contribution': fullmarks > 0 ? (marks / fullmarks) * percent : 0.0,
        });
      }
    }

    if (assessmentData.isEmpty) {
      _showSnack('Please fill in at least one assessment row.', _gradeRed);
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _firestore.collection('grade_results').add({
        'userId':      user.uid,
        'userEmail':   user.email ?? '',
        'displayName': user.displayName ?? '',
        'subject':     subject,
        'semester':    semester,
        'assessments': assessmentData,
        'totalPercentage': _totalPercentage,
        'grade':    _gradeLabel(_totalPercentage),
        'savedAt':  FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnack('Result saved!', _dark);
        _reset();
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to save: $e', _gradeRed);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteResult(String docId) async {
    try {
      await _firestore.collection('grade_results').doc(docId).delete();
    } catch (e) {
      if (mounted) _showSnack('Failed to delete: $e', _gradeRed);
    }
  }

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.dmMono(fontSize: 12)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  // ── Grade helpers ────────────────────────────────────────────────

  String _gradeLabel(double total) {
    if (total >= 80) return 'A';
    if (total >= 70) return 'B';
    if (total >= 60) return 'C';
    if (total >= 50) return 'D';
    return 'F';
  }

  Color _gradeColor(double total) {
    if (total >= 70) return _gradeGreen;
    if (total >= 50) return _gradeYellow;
    return _gradeRed;
  }

  // ══════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // ── TITLE ──────────────────────────────────────────────
              Text(
                'GRADE TRACKER',
                style: GoogleFonts.dmMono(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 12),

              // ── NOTE BANNER ────────────────────────────────────────
              RichText(
                textAlign: TextAlign.justify,
                text: TextSpan(
                  style: GoogleFonts.dmMono(fontSize: 9.5, color: Colors.black87),
                  children: [
                    TextSpan(
                      text: 'NOTE: ',
                      style: GoogleFonts.dmMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                    const TextSpan(
                      text:
                          'The Grade Tracker result generated by this calculator is intended solely as an estimation tool and should not be regarded as the official or final academic record. For accurate and authoritative results, kindly refer to the official transcript or records issued by your institution.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── INPUT CARD ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _dark, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subject + Semester
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _labeledField('Subject Name', _subjectController),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: _labeledField('Semester', _semesterController),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Column headers
                    Row(
                      children: [
                        _headerCell('Assessment', flex: 3),
                        _headerCell('Marks',      flex: 2),
                        _headerCell('Fullmarks',  flex: 2),
                        _headerCell('%',          flex: 2),
                        const SizedBox(width: 22),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Assessment rows
                    ...List.generate(_assessments.length, (i) {
                      final row = _assessments[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: _inputField(row['name']!)),
                            const SizedBox(width: 4),
                            Expanded(flex: 2, child: _numberField(row['marks']!)),
                            const SizedBox(width: 4),
                            Expanded(flex: 2, child: _numberField(row['fullmarks']!)),
                            const SizedBox(width: 4),
                            Expanded(flex: 2, child: _numberField(row['percent']!)),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _removeRow(i),
                              child: const Icon(Icons.close,
                                  size: 18, color: Colors.black54),
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 14),

                    // RESET / +ADD METHOD
                    Row(
                      children: [
                        Expanded(
                          child: _actionBtn(
                            label: 'RESET',
                            color: _resetBtn,
                            onTap: _reset,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionBtn(
                            label: '+ ADD METHOD',
                            color: _bgCard,
                            onTap: _addAssessmentRow,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── TOTAL PERCENTAGE CARD ──────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: BoxDecoration(
                  color: _bgField,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _dark, width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      'Total (%):',
                      style: GoogleFonts.dmMono(fontSize: 13, color: _dark),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _totalPercentage == 0
                          ? '0'
                          : _totalPercentage.toStringAsFixed(1),
                      style: GoogleFonts.dmMono(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                        color: _dark,
                      ),
                    ),
                    if (_totalPercentage > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 6),
                        decoration: BoxDecoration(
                          color: _gradeColor(_totalPercentage),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Grade: ${_gradeLabel(_totalPercentage)}',
                          style: GoogleFonts.dmMono(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── SAVE BUTTON ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveResult,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _dark,
                    disabledBackgroundColor: Colors.black38,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'SAVE',
                          style: GoogleFonts.dmMono(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 2,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 28),

              // ── SAVED RESULTS HEADER + SEARCH ─────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Saved Results',
                    style: GoogleFonts.dmMono(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: _dark,
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.dmMono(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        hintText: 'Search...',
                        hintStyle: GoogleFonts.dmMono(
                            fontSize: 12, color: Colors.black38),
                        suffixIcon: const Icon(Icons.search,
                            size: 16, color: Colors.black45),
                        filled: true,
                        fillColor: _bgCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide:
                              const BorderSide(color: Colors.black54),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide:
                              const BorderSide(color: Colors.black38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: Colors.black),
                        ),
                      ),
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.toLowerCase()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── SAVED RESULTS LIST (Firestore stream) ─────────────
              StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('grade_results')
                    .where('userId', isEqualTo: _auth.currentUser?.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: CircularProgressIndicator(color: _dark),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _emptyState('No saved results yet');
                  }

                  final docs = snapshot.data!.docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final sub = (d['subject'] ?? '').toString().toLowerCase();
                    final sem = (d['semester'] ?? '').toString().toLowerCase();
                    return _searchQuery.isEmpty ||
                        sub.contains(_searchQuery) ||
                        sem.contains(_searchQuery);
                  }).toList()
                    ..sort((a, b) {
                      final aTime = (a.data() as Map<String, dynamic>)['savedAt'];
                      final bTime = (b.data() as Map<String, dynamic>)['savedAt'];
                      if (aTime == null && bTime == null) return 0;
                      if (aTime == null) return 1;
                      if (bTime == null) return -1;
                      return (bTime as Timestamp).compareTo(aTime as Timestamp);
                    });

                  if (docs.isEmpty) {
                    return _emptyState('No results match your search');
                  }

                  return Column(
                    children: docs
                        .map((doc) => _savedCard(
                            doc.id, doc.data() as Map<String, dynamic>))
                        .toList(),
                  );
                },
              ),

              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  SAVED RESULT CARD
  // ══════════════════════════════════════════════════════════════════

  Widget _savedCard(String docId, Map<String, dynamic> data) {
    final subject     = data['subject'] ?? '';
    final semester    = data['semester'] ?? '';
    final total       = (data['totalPercentage'] ?? 0).toDouble();
    final assessments = List<Map<String, dynamic>>.from(data['assessments'] ?? []);
    final savedAt     = (data['savedAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _dark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SUBJECT: ${subject.toUpperCase()}',
                        style: GoogleFonts.dmMono(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '(SEMESTER $semester'
                        '${savedAt != null ? ', ${savedAt.year}' : ''})',
                        style: GoogleFonts.dmMono(
                            color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (val) {
                    if (val == 'delete') _deleteResult(docId);
                  },
                  color: Colors.white,
                  icon: const Icon(Icons.more_vert,
                      color: Colors.white, size: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline,
                              color: _gradeRed, size: 18),
                          const SizedBox(width: 8),
                          Text('Delete',
                              style: GoogleFonts.dmMono(color: _gradeRed)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Results',
              style: GoogleFonts.dmMono(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
              ),
            ),
          ),

          // Sub-header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Assessment:',
                    style: GoogleFonts.dmMono(
                        color: Colors.white54, fontSize: 11)),
                Text('Total (%):',
                    style: GoogleFonts.dmMono(
                        color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),

          // Assessment rows
          ...assessments.map((a) {
            final contribution = (a['contribution'] ?? 0).toDouble();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(a['name'] ?? '',
                      style: GoogleFonts.dmMono(
                          color: Colors.white70, fontSize: 12)),
                  Text(contribution.toStringAsFixed(0),
                      style: GoogleFonts.dmMono(
                          color: Colors.white, fontSize: 12)),
                ],
              ),
            );
          }).toList(),

          const SizedBox(height: 10),

          // Final total footer
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: _gradeColor(total).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _gradeColor(total).withOpacity(0.6), width: 1.5),
            ),
            child: Center(
              child: Text(
                'FINAL TOTAL: ${total.toStringAsFixed(0)}%'
                '  •  Grade ${_gradeLabel(total)}',
                style: GoogleFonts.dmMono(
                  color: _gradeColor(total),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Small helpers ────────────────────────────────────────────────

  Widget _emptyState(String msg) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black26, width: 1.5),
        ),
        child: Center(
          child:
              Text(msg, style: GoogleFonts.dmMono(fontSize: 13, color: Colors.grey)),
        ),
      );

  Widget _labeledField(String label, TextEditingController ctrl) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.dmMono(fontSize: 11, color: _dark)),
          const SizedBox(height: 4),
          _inputField(ctrl),
        ],
      );

  Widget _headerCell(String text, {required int flex}) => Expanded(
        flex: flex,
        child: Text(text,
            style: GoogleFonts.dmMono(fontSize: 11, color: _dark)),
      );

  InputDecoration _fieldDeco() => InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        filled: true,
        fillColor: _bgField,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Colors.black38),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Colors.black87),
        ),
      );

  Widget _inputField(TextEditingController ctrl) => TextField(
        controller: ctrl,
        style: GoogleFonts.dmMono(fontSize: 12),
        decoration: _fieldDeco(),
      );

  Widget _numberField(TextEditingController ctrl) => TextField(
        controller: ctrl,
        style: GoogleFonts.dmMono(fontSize: 12),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        decoration: _fieldDeco(),
      );

  Widget _actionBtn({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _dark, width: 1.5),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.dmMono(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: _dark,
              ),
            ),
          ),
        ),
      );
}