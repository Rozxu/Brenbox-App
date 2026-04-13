import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SetGradeScreen extends StatefulWidget {
  const SetGradeScreen({Key? key}) : super(key: key);

  @override
  State<SetGradeScreen> createState() => _SetGradeScreenState();
}

class _SetGradeScreenState extends State<SetGradeScreen> {
  final _auth      = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  static const _bgPage  = Color(0xFFE8E8E8);
  static const _tan     = Color(0xFFD4B896);
  static const _dark    = Color(0xFF1A1A1A);
  static const _bgField = Colors.white;
  static const _red     = Color(0xFFB90000);

  final List<String> _gradeLabels = [
    'A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'E/F',
  ];

  late final List<TextEditingController> _minCtrl;
  late final List<TextEditingController> _maxCtrl;

  bool _isLoading = true;
  bool _isSaving  = false;

  @override
  void initState() {
    super.initState();
    _minCtrl = List.generate(_gradeLabels.length, (_) => TextEditingController());
    _maxCtrl = List.generate(_gradeLabels.length, (_) => TextEditingController());
    _loadGrades();
  }

  @override
  void dispose() {
    for (final c in _minCtrl) c.dispose();
    for (final c in _maxCtrl) c.dispose();
    super.dispose();
  }

  Future<void> _loadGrades() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) { setState(() => _isLoading = false); return; }

    try {
      final doc = await _firestore.collection('grade_settings').doc(uid).get();
      if (doc.exists) {
        final ranges = List<Map<String, dynamic>>.from(doc.data()?['ranges'] ?? []);
        for (final r in ranges) {
          final idx = _gradeLabels.indexOf(r['label'] ?? '');
          if (idx != -1) {
            final min = (r['min'] ?? 0).toDouble();
            final max = (r['max'] ?? 0).toDouble();
            _minCtrl[idx].text = min.toStringAsFixed(0);
            _maxCtrl[idx].text = max.toStringAsFixed(0);
          }
        }
      } else {
        _minCtrl[0].text = '90';
        _maxCtrl[0].text = '100';
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveGrades() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // ── Step 1: Determine which rows are filled vs empty ────────────
    final List<int> filledIndices = [];
    final List<int> emptyIndices  = [];

    for (int i = 0; i < _gradeLabels.length; i++) {
      final minTxt = _minCtrl[i].text.trim();
      final maxTxt = _maxCtrl[i].text.trim();

      if (minTxt.isEmpty && maxTxt.isEmpty) {
        emptyIndices.add(i);
        continue;
      }
      if (minTxt.isEmpty || maxTxt.isEmpty) {
        _snack('Fill both Min and Max for ${_gradeLabels[i]}, or leave both empty.', _red);
        return;
      }
      filledIndices.add(i);
    }

    if (filledIndices.isEmpty) {
      _snack('Please fill in at least one grade range.', _red);
      return;
    }

    // ── Step 2: No skipping — filled rows must be consecutive ───────
    final firstFilled = filledIndices.first;
    final lastFilled  = filledIndices.last;

    for (int i = firstFilled; i <= lastFilled; i++) {
      if (emptyIndices.contains(i)) {
        final skipped = _gradeLabels[i];
        final prev    = _gradeLabels[i - 1];
        final next    = (i + 1 <= lastFilled) ? _gradeLabels[i + 1] : '';
        _snack(
          'Cannot skip "$skipped" between "$prev"'
          '${next.isNotEmpty ? ' and "$next"' : ''}. Fill it or remove grades after it.',
          _red,
        );
        return;
      }
    }

    // ── Step 3: Parse and validate filled rows ───────────────────────
    final List<Map<String, dynamic>> ranges = [];

    for (final i in filledIndices) {
      final min = double.tryParse(_minCtrl[i].text.trim());
      final max = double.tryParse(_maxCtrl[i].text.trim());

      if (min == null || max == null) {
        _snack('Invalid number for grade ${_gradeLabels[i]}.', _red);
        return;
      }
      if (min >= max) {
        _snack('Min must be less than Max for ${_gradeLabels[i]}.', _red);
        return;
      }
      ranges.add({'label': _gradeLabels[i], 'min': min, 'max': max});
    }

    // ── Step 4: Sort by min ascending ───────────────────────────────
    final sorted = List<Map<String, dynamic>>.from(ranges)
      ..sort((a, b) => (a['min'] as double).compareTo(b['min'] as double));

    // ── Step 5: Must start at 0 and end at 100 ──────────────────────
    if ((sorted.first['min'] as double) != 0) {
      _snack(
        'The lowest grade must start at 0. '
        '"${sorted.first['label']}" currently starts at ${(sorted.first['min'] as double).toInt()}.',
        _red,
      );
      return;
    }
    if ((sorted.last['max'] as double) != 100) {
      _snack(
        'The highest grade must end at 100. '
        '"${sorted.last['label']}" currently ends at ${(sorted.last['max'] as double).toInt()}.',
        _red,
      );
      return;
    }

    // ── Step 6: No gaps or overlaps between consecutive ranges ──────
    for (int i = 1; i < sorted.length; i++) {
      final prevMax   = (sorted[i - 1]['max'] as double);
      final currMin   = (sorted[i]['min'] as double);
      final prevLabel = sorted[i - 1]['label'];
      final currLabel = sorted[i]['label'];

      if (currMin != prevMax + 1) {
        _snack(
          '"$prevLabel" ends at ${prevMax.toInt()}, '
          'so "$currLabel" must start at ${(prevMax + 1).toInt()} — not ${currMin.toInt()}.',
          _red,
        );
        return;
      }
    }

    // ── Step 7: Save ─────────────────────────────────────────────────
    setState(() => _isSaving = true);
    try {
      await _firestore.collection('grade_settings').doc(uid).set({
        'userId':    uid,
        'ranges':    ranges,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _snack('Grade settings saved!', _dark);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _snack('Failed to save: $e', _red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg, style: GoogleFonts.dmMono(fontSize: 12)),
      backgroundColor: bg,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B7280),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF6B7280)),
                      ),
                      child: const Icon(Icons.arrow_back,
                          size: 16, color: Color.fromARGB(255, 255, 255, 255)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'SET GRADE',
                    style: GoogleFonts.dmMono(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: _dark,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Column headers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const SizedBox(width: 72),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Min',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmMono(
                            fontSize: 12, color: Colors.black54)),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Text('Max',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmMono(
                            fontSize: 12, color: Colors.black54)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Grade rows
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _dark))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _gradeLabels.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            // Grade chip
                            Container(
                              width: 72,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 4),
                              decoration: BoxDecoration(
                                color: _tan,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.black26, width: 1),
                              ),
                              child: Text(
                                _gradeLabels[i],
                                textAlign: TextAlign.center,
                                style: GoogleFonts.dmMono(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _dark,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Min field
                            Expanded(child: _numBox(_minCtrl[i])),
                            const SizedBox(width: 8),
                            Text('-',
                                style: GoogleFonts.dmMono(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: _dark)),
                            const SizedBox(width: 8),
                            // Max field
                            Expanded(child: _numBox(_maxCtrl[i])),
                          ],
                        ),
                      ),
                    ),
            ),

            // Bottom buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.black, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('Cancel',
                          style: GoogleFonts.dmMono(
                              fontWeight: FontWeight.bold, color: _dark)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveGrades,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tan,
                        disabledBackgroundColor: Colors.black26,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.black26),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text('Save Grade',
                              style: GoogleFonts.dmMono(
                                  fontWeight: FontWeight.bold, color: _dark)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numBox(TextEditingController ctrl) => TextField(
        controller:  ctrl,
        style:       GoogleFonts.dmMono(fontSize: 13),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense:      true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          filled:    true,
          fillColor: _bgField,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.black26)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.black26)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.black87)),
        ),
      );
}