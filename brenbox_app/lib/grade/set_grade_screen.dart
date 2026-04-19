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

  // ── Palette matching CertificateRepositoryScreen ──────────────────────────
  static const _bgPage  = Color(0xFFE5E7EB);
  static const _tan     = Color(0xFFD4B896);
  static const _dark    = Color(0xFF292929);
  static const _bgField = Colors.white;
  static const _red     = Color(0xFFB90000);

  final List<String> _gradeLabels = [
    'A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'E/F',
  ];

  final Set<String> _selectedGrades = {};

  late final Map<String, TextEditingController> _minCtrl;
  late final Map<String, TextEditingController> _maxCtrl;

  bool _isLoading = true;
  bool _isSaving  = false;

  int _step = 1;

  @override
  void initState() {
    super.initState();
    _minCtrl = { for (final g in _gradeLabels) g: TextEditingController() };
    _maxCtrl = { for (final g in _gradeLabels) g: TextEditingController() };
    _loadGrades();
  }

  @override
  void dispose() {
    for (final c in _minCtrl.values) c.dispose();
    for (final c in _maxCtrl.values) c.dispose();
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
          final label = r['label'] as String? ?? '';
          if (_gradeLabels.contains(label)) {
            final min = (r['min'] ?? 0).toDouble();
            final max = (r['max'] ?? 0).toDouble();
            _minCtrl[label]!.text = min.toStringAsFixed(0);
            _maxCtrl[label]!.text = max.toStringAsFixed(0);
            _selectedGrades.add(label);
          }
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  void _proceedToFill() {
    if (_selectedGrades.isEmpty) {
      _snack('Select at least one grade to continue.', _red);
      return;
    }
    for (final g in _gradeLabels) {
      if (!_selectedGrades.contains(g)) {
        _minCtrl[g]!.clear();
        _maxCtrl[g]!.clear();
      }
    }
    setState(() => _step = 2);
  }

  Future<void> _saveGrades() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final ordered = _gradeLabels.where(_selectedGrades.contains).toList();

    final List<Map<String, dynamic>> ranges = [];
    for (final label in ordered) {
      final minTxt = _minCtrl[label]!.text.trim();
      final maxTxt = _maxCtrl[label]!.text.trim();

      if (minTxt.isEmpty || maxTxt.isEmpty) {
        _snack('Fill both Min and Max for $label.', _red);
        return;
      }
      final min = double.tryParse(minTxt);
      final max = double.tryParse(maxTxt);
      if (min == null || max == null) {
        _snack('Invalid number for grade $label.', _red);
        return;
      }
      if (min >= max) {
        _snack('Min must be less than Max for $label.', _red);
        return;
      }
      ranges.add({'label': label, 'min': min, 'max': max});
    }

    final sorted = List<Map<String, dynamic>>.from(ranges)
      ..sort((a, b) => (a['min'] as double).compareTo(b['min'] as double));

    if ((sorted.first['min'] as double) != 0) {
      _snack(
        'The lowest grade must start at 0. '
        '"${sorted.first['label']}" starts at ${(sorted.first['min'] as double).toInt()}.',
        _red,
      );
      return;
    }
    if ((sorted.last['max'] as double) != 100) {
      _snack(
        'The highest grade must end at 100. '
        '"${sorted.last['label']}" ends at ${(sorted.last['max'] as double).toInt()}.',
        _red,
      );
      return;
    }

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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _dark))
            : Column(
                children: [
                  // ── Top bar ────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (_step == 2) {
                              setState(() => _step = 1);
                            } else {
                              Navigator.pop(context);
                            }
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _dark,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: const Icon(Icons.arrow_back,
                                size: 16, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _step == 1 ? 'SELECT GRADES' : 'SET GRADE',
                              style: GoogleFonts.dmMono(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _dark,
                              ),
                            ),
                            Text(
                              _step == 1
                                  ? 'Choose the grades your institution uses'
                                  : 'Define the score range for each grade',
                              style: GoogleFonts.dmMono(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Step indicator ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black38, width: 2),
                      ),
                      child: Row(
                        children: [
                          _stepDot(1),
                          Expanded(
                            child: Container(
                              height: 2,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              color: _step == 2
                                  ? _tan
                                  : Colors.black26,
                            ),
                          ),
                          _stepDot(2),
                          const SizedBox(width: 12),
                          Text(
                            _step == 1 ? 'Choose grades' : 'Fill ranges',
                            style: GoogleFonts.dmMono(
                              fontSize: 11,
                              color: Colors.black45,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Body ───────────────────────────────────────────
                  Expanded(
                    child: _step == 1 ? _buildSelectStep() : _buildFillStep(),
                  ),

                  // ── Bottom button ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                    child: _step == 1
                        ? _buildContinueButton()
                        : _buildSaveButtons(),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Step 1: grade chip grid ──────────────────────────────────────
  Widget _buildSelectStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color.fromARGB(255, 62, 62, 62), width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Color(0xFF6B7280)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tap the grades your institution uses',
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _gradeLabels.map((label) {
              final isSelected = _selectedGrades.contains(label);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedGrades.remove(label);
                    } else {
                      _selectedGrades.add(label);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? _tan : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFFB8956A) : Colors.black26,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.dmMono(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _dark,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          if (_selectedGrades.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _tan.withOpacity(0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _tan, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF292929)),
                  const SizedBox(width: 6),
                  Text(
                    '${_selectedGrades.length} grade${_selectedGrades.length == 1 ? '' : 's'} selected',
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      color: _dark,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Step 2: fill ranges for selected grades only ─────────────────
  Widget _buildFillStep() {
    final orderedSelected =
        _gradeLabels.where(_selectedGrades.contains).toList();

    return Column(
      children: [
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
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Text('Max',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmMono(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: orderedSelected.length,
            itemBuilder: (_, i) {
              final label = orderedSelected[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 4),
                      decoration: BoxDecoration(
                        color: _tan,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFB8956A), width: 2),
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmMono(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _dark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _numBox(_minCtrl[label]!)),
                    const SizedBox(width: 8),
                    Text('-',
                        style: GoogleFonts.dmMono(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _dark)),
                    const SizedBox(width: 8),
                    Expanded(child: _numBox(_maxCtrl[label]!)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _proceedToFill,
        style: ElevatedButton.styleFrom(
          backgroundColor: _tan,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFB8956A), width: 2),
          ),
        ),
        child: Text(
          'Continue',
          style: GoogleFonts.dmMono(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: _dark),
        ),
      ),
    );
  }

  Widget _buildSaveButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => setState(() => _step = 1),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: Color.fromARGB(255, 30, 30, 30), width: 2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Back',
                style: GoogleFonts.dmMono(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _dark)),
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
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFB8956A), width: 2),
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
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _dark)),
          ),
        ),
      ],
    );
  }

  Widget _stepDot(int step) {
    final active = _step >= step;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: active ? _tan : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? _tan : Colors.black26,
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          '$step',
          style: GoogleFonts.dmMono(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: active ? _dark : Colors.black38,
          ),
        ),
      ),
    );
  }

  Widget _numBox(TextEditingController ctrl) => TextField(
        controller:  ctrl,
        style:       GoogleFonts.dmMono(fontSize: 13, color: _dark),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense:         true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          filled:          true,
          fillColor:       _bgField,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFB8956A), width: 2)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFB8956A), width: 2)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _dark, width: 2)),
        ),
      );
}