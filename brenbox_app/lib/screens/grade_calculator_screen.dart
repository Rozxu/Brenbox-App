import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../grade/set_grade_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  GradeCalculatorScreen  –  v3
//
//  Changes in this version:
//  • Semester display: "Sem 1, 26/27"  (academicYear from Firestore).
//  • Fullmarks is mandatory – rows with % but no fullmarks block saving.
//  • Partial % error: if some active rows have % and others don't → blocked.
//  • Edit mode on saved cards exposes Marks, Fullmarks, AND % per row.
//  • Edit validates % sum = 100 and marks ≤ fullmarks before allowing save.
// ─────────────────────────────────────────────────────────────────────────────

class GradeCalculatorScreen extends StatefulWidget {
  const GradeCalculatorScreen({Key? key}) : super(key: key);

  @override
  State<GradeCalculatorScreen> createState() => _GradeCalculatorScreenState();
}

class _GradeCalculatorScreenState extends State<GradeCalculatorScreen> {
  final _auth      = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _searchController = TextEditingController();

  String? _selectedSubject;
  String? _selectedSemester;
  String? _selectedAcademicYear;
  String? _selectedTargetGrade;

  List<Map<String, TextEditingController>> _assessments = [];

  double _totalPercentage = 0.0;
  double _targetNeededPct = 0.0;
  bool   _percentSumValid = false;

  List<Map<String, dynamic>> _gradeRanges        = [];
  bool                       _gradeSettingsLoaded = false;

  // subject → { semester, academicYear }
  Map<String, Map<String, String>> _subjectMeta = {};
  List<String> get _subjects => _subjectMeta.keys.toList()..sort();

  String _searchQuery = '';
  bool   _isSaving    = false;

  static const _bgPage      = Color(0xFFE8E8E8);
  static const _bgCard      = Colors.white;
  static const _bgField     = Color(0xFFE5E7EB);
  static const _dark        = Color(0xFF1A1A1A);
  static const _tan         = Color(0xFFD4B896);
  static const _gradeGreen  = Color(0xFF34A853);
  static const _gradeYellow = Color(0xFFFBBC05);
  static const _gradeRed    = Color(0xFFB90000);

  List<String> get _targetGradeOptions =>
      _gradeRanges.map((r) => r['label'] as String).toList();

  // ── "Sem 1, 26/27" ───────────────────────────────────────────────
  String get _semesterDisplayLabel {
    final sem  = _selectedSemester     ?? '';
    final year = _selectedAcademicYear ?? '';
    if (sem.isEmpty) return '—';
    final shortYear = year.isNotEmpty ? shortenAcademicYear(year) : '';
    return shortYear.isNotEmpty ? 'Sem $sem, $shortYear' : 'Sem $sem';
  }

  static String shortenAcademicYear(String y) {
    final parts = y.split('/');
    if (parts.length == 2) {
      final a = parts[0].trim();
      final b = parts[1].trim();
      final sa = a.length > 2 ? a.substring(a.length - 2) : a;
      final sb = b.length > 2 ? b.substring(b.length - 2) : b;
      return '$sa/$sb';
    }
    return y.length > 2 ? y.substring(y.length - 2) : y;
  }

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 5; i++) _addAssessmentRow();
    _loadGradeSettings();
    _loadSubjectMeta();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final row in _assessments) {
      for (final c in row.values) c.dispose();
    }
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════
  //  DATA LOADING
  // ══════════════════════════════════════════════════════════════════

  Future<void> _loadGradeSettings() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.collection('grade_settings').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _gradeRanges         = List<Map<String, dynamic>>.from(doc.data()?['ranges'] ?? []);
          _gradeSettingsLoaded = _gradeRanges.isNotEmpty;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSubjectMeta() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _firestore
          .collection('timetable')
          .where('userId', isEqualTo: uid)
          .get();

      final map = <String, Map<String, String>>{};
      for (final doc in snap.docs) {
        final d   = doc.data();
        final cls = (d['className'] ?? '').toString().trim();
        if (cls.isEmpty) continue;

        final sem  = (d['semester'] ?? '').toString().trim();
        final year = (d['academicYear'] ?? d['academic_year'] ?? d['year'] ?? '').toString().trim();

        if (!map.containsKey(cls)) {
          map[cls] = {'semester': sem, 'academicYear': year};
        } else if ((map[cls]!['academicYear'] ?? '').isEmpty && year.isNotEmpty) {
          map[cls] = {'semester': sem, 'academicYear': year};
        }
      }

      if (mounted) setState(() => _subjectMeta = map);
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════
  //  ASSESSMENT ROW MANAGEMENT
  // ══════════════════════════════════════════════════════════════════

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
        'name':      nameCtrl,
        'marks':     marksCtrl,
        'fullmarks': fullmarksCtrl,
        'percent':   percentCtrl,
      });
    });
  }

  void _removeRow(int index) {
    if (_assessments.length <= 1) return;
    final row = _assessments[index];
    for (final c in row.values) c.dispose();
    setState(() => _assessments.removeAt(index));
    _recalculate();
  }

  // ══════════════════════════════════════════════════════════════════
  //  VALIDATION
  // ══════════════════════════════════════════════════════════════════

  bool _rowIsActive(int i) {
    final row = _assessments[i];
    return row['name']!.text.trim().isNotEmpty ||
        row['marks']!.text.trim().isNotEmpty ||
        row['fullmarks']!.text.trim().isNotEmpty ||
        row['percent']!.text.trim().isNotEmpty;
  }

  String? _rowError(int i) {
    if (!_rowIsActive(i)) return null;
    final row       = _assessments[i];
    final marks     = double.tryParse(row['marks']!.text.trim());
    final fullmarks = double.tryParse(row['fullmarks']!.text.trim());
    final percent   = double.tryParse(row['percent']!.text.trim());

    if (marks != null && fullmarks != null && fullmarks > 0 && marks > fullmarks) {
      return 'Marks cannot exceed fullmarks';
    }
    if ((percent ?? 0) > 0 && (fullmarks == null || fullmarks <= 0)) {
      return 'Fullmarks required when % is set';
    }
    if ((fullmarks ?? 0) > 0 && (percent == null || percent <= 0)) {
      return '% required when fullmarks is set';
    }
    return null;
  }

  bool get _hasRowErrors =>
      List.generate(_assessments.length, _rowError).any((e) => e != null);

  bool get _hasPartialPercentError {
    final active = List.generate(_assessments.length, (i) => i).where(_rowIsActive).toList();
    if (active.isEmpty) return false;
    final withPct    = active.where((i) => (double.tryParse(_assessments[i]['percent']!.text.trim()) ?? 0) > 0).length;
    final withoutPct = active.where((i) => (double.tryParse(_assessments[i]['percent']!.text.trim()) ?? 0) <= 0).length;
    return withPct > 0 && withoutPct > 0;
  }

  String? get _saveBlockReason {
    if (!_gradeSettingsLoaded) return 'Please set up your grade settings first (📐).';
    if (_selectedSubject == null)  return 'Please select a subject.';
    if (_selectedSemester == null) return 'Semester info is missing for this subject.';
    if (_hasRowErrors)             return 'Fix the row errors before saving.';
    if (_hasPartialPercentError)   return 'All active assessments must have a % value — some rows are missing %.';
    if (!_percentSumValid)         return '% column must total exactly 100.';
    for (int i = 0; i < _assessments.length; i++) {
      if (!_rowIsActive(i)) continue;
      final fm = double.tryParse(_assessments[i]['fullmarks']!.text.trim()) ?? 0;
      if (fm <= 0) return 'Every assessment needs a Fullmarks value.';
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  //  CORE CALCULATION
  // ══════════════════════════════════════════════════════════════════

  void _recalculate() {
    double percentSum      = 0;
    double earnedSoFar     = 0;
    double remainingWeight = 0;

    for (final row in _assessments) {
      final marks     = double.tryParse(row['marks']!.text)     ?? -1;
      final fullmarks = double.tryParse(row['fullmarks']!.text) ?? 0;
      final percent   = double.tryParse(row['percent']!.text)   ?? 0;

      percentSum += percent;

      if (marks >= 0 && fullmarks > 0 && percent > 0) {
        earnedSoFar += (marks / fullmarks) * percent;
      } else if (percent > 0 && (marks < 0 || fullmarks <= 0)) {
        remainingWeight += percent;
      }
    }

    final valid = (percentSum - 100).abs() < 0.01;

    double targetNeeded = 0;
    if (valid && _selectedTargetGrade != null && _gradeSettingsLoaded) {
      final range = _gradeRanges.firstWhere(
        (r) => r['label'] == _selectedTargetGrade,
        orElse: () => {},
      );
      if (range.isNotEmpty) {
        final targetMin = (range['min'] as num).toDouble();
        final needed    = targetMin - earnedSoFar;
        targetNeeded    = needed > 0 ? needed : 0;
      }
    }

    setState(() {
      _totalPercentage = earnedSoFar;
      _targetNeededPct = targetNeeded;
      _percentSumValid = valid;
    });
  }

  // ══════════════════════════════════════════════════════════════════
  //  MARKS-NEEDED HINT PER ROW
  // ══════════════════════════════════════════════════════════════════

  String? _marksNeededHint(int rowIdx) {
    if (!_gradeSettingsLoaded || _selectedTargetGrade == null) return null;
    final row       = _assessments[rowIdx];
    final marks     = double.tryParse(row['marks']!.text);
    final fullmarks = double.tryParse(row['fullmarks']!.text) ?? 0;
    final percent   = double.tryParse(row['percent']!.text)   ?? 0;
    if (marks != null || fullmarks <= 0 || percent <= 0) return null;

    final range = _gradeRanges.firstWhere(
      (r) => r['label'] == _selectedTargetGrade,
      orElse: () => {},
    );
    if (range.isEmpty) return null;
    final targetMin = (range['min'] as num).toDouble();

    double earnedExcl = 0, remainingExcl = 0;
    for (int i = 0; i < _assessments.length; i++) {
      if (i == rowIdx) continue;
      final r   = _assessments[i];
      final m   = double.tryParse(r['marks']!.text) ?? -1;
      final fm  = double.tryParse(r['fullmarks']!.text) ?? 0;
      final pct = double.tryParse(r['percent']!.text) ?? 0;
      if (m >= 0 && fm > 0 && pct > 0) {
        earnedExcl += (m / fm) * pct;
      } else if (pct > 0) {
        remainingExcl += pct;
      }
    }

    final totalRemaining = remainingExcl + percent;
    if (totalRemaining <= 0) return null;
    final totalNeeded = targetMin - earnedExcl;
    if (totalNeeded <= 0) return null;

    final rowNeededContrib = totalNeeded * (percent / totalRemaining);
    final marksNeeded      = (rowNeededContrib / percent * fullmarks).clamp(0, fullmarks);
    return '${marksNeeded.toStringAsFixed(1)} / ${fullmarks.toStringAsFixed(0)} needed';
  }

  // ══════════════════════════════════════════════════════════════════
  //  RESET / SAVE / DELETE / UPDATE
  // ══════════════════════════════════════════════════════════════════

  void _reset() {
    setState(() {
      _selectedSubject      = null;
      _selectedSemester     = null;
      _selectedAcademicYear = null;
      _selectedTargetGrade  = null;
      _totalPercentage      = 0;
      _targetNeededPct      = 0;
      _percentSumValid      = false;
    });
    for (final row in _assessments) {
      for (final c in row.values) c.clear();
    }
  }

  Future<void> _saveResult() async {
    final reason = _saveBlockReason;
    if (reason != null) { _snack(reason, _gradeRed); return; }

    final user = _auth.currentUser!;
    final List<Map<String, dynamic>> assessmentData = [];

    for (int i = 0; i < _assessments.length; i++) {
      if (!_rowIsActive(i)) continue;
      final row       = _assessments[i];
      final name      = row['name']!.text.trim();
      final marks     = double.tryParse(row['marks']!.text)     ?? 0;
      final fullmarks = double.tryParse(row['fullmarks']!.text) ?? 0;
      final percent   = double.tryParse(row['percent']!.text)   ?? 0;
      final contribution = fullmarks > 0 ? (marks / fullmarks) * percent : 0.0;

      double marksNeededForTarget = -1;
      if (row['marks']!.text.trim().isEmpty && fullmarks > 0 && percent > 0) {
        final hint = _marksNeededHint(i);
        if (hint != null) {
          marksNeededForTarget = double.tryParse(hint.split(' / ').first) ?? -1;
        }
      }

      assessmentData.add({
        'name':                 name,
        'marks':                marks,
        'fullmarks':            fullmarks,
        'percent':              percent,
        'contribution':         contribution,
        'marksNeededForTarget': marksNeededForTarget,
      });
    }

    if (assessmentData.isEmpty) {
      _snack('Please fill in at least one assessment row.', _gradeRed);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _firestore.collection('grade_results').add({
        'userId':          user.uid,
        'userEmail':       user.email ?? '',
        'displayName':     user.displayName ?? '',
        'subject':         _selectedSubject,
        'semester':        _selectedSemester,
        'academicYear':    _selectedAcademicYear ?? '',
        'targetGrade':     _selectedTargetGrade ?? '',
        'assessments':     assessmentData,
        'totalPercentage': _totalPercentage,
        'targetNeeded':    _targetNeededPct,
        'grade':           _gradeLabelFor(_totalPercentage),
        'savedAt':         FieldValue.serverTimestamp(),
      });
      if (mounted) { _showSaveSuccessDialog(); _reset(); }
    } catch (e) {
      if (mounted) _snack('Failed to save: $e', _gradeRed);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteResult(String docId) async {
    try {
      await _firestore.collection('grade_results').doc(docId).delete();
      _snack('Result deleted.', _dark);
    } catch (e) {
      _snack('Failed to delete: $e', _gradeRed);
    }
  }

  Future<void> _updateSavedAssessments(
    String docId,
    List<Map<String, dynamic>> updatedAssessments, {
    required List<Map<String, dynamic>> gradeRanges,
    required String targetGrade,
  }) async {
    try {
      double newTotal = 0;
      for (final a in updatedAssessments) {
        final marks     = (a['marks']     ?? 0).toDouble();
        final fullmarks = (a['fullmarks'] ?? 0).toDouble();
        final percent   = (a['percent']   ?? 0).toDouble();
        if (fullmarks > 0) newTotal += (marks / fullmarks) * percent;
      }

      String newGrade = '';
      if (gradeRanges.isNotEmpty) {
        for (final r in gradeRanges) {
          final min = (r['min'] as num).toDouble();
          final max = (r['max'] as num).toDouble();
          if (newTotal >= min && newTotal <= max) { newGrade = r['label'] as String; break; }
        }
        if (newGrade.isEmpty) newGrade = gradeRanges.last['label'] as String;
      }

      double newTargetNeeded = 0;
      if (targetGrade.isNotEmpty && gradeRanges.isNotEmpty) {
        final range = gradeRanges.firstWhere(
          (r) => r['label'] == targetGrade,
          orElse: () => {},
        );
        if (range.isNotEmpty) {
          final targetMin = (range['min'] as num).toDouble();
          final needed    = targetMin - newTotal;
          newTargetNeeded = needed > 0 ? needed : 0;
        }
      }

      final recomputed = updatedAssessments.map((a) {
        final updated   = Map<String, dynamic>.from(a);
        final marks     = (a['marks']     ?? 0).toDouble();
        final fullmarks = (a['fullmarks'] ?? 0).toDouble();
        final percent   = (a['percent']   ?? 0).toDouble();
        if (marks <= 0 && fullmarks > 0 && percent > 0 && newTargetNeeded > 0) {
          final share      = newTargetNeeded * (percent / 100);
          final marksNeeded = (share / percent * fullmarks).clamp(0, fullmarks);
          updated['marksNeededForTarget'] = marksNeeded;
        } else {
          updated['marksNeededForTarget'] = -1.0;
        }
        return updated;
      }).toList();

      await _firestore.collection('grade_results').doc(docId).update({
        'assessments':     recomputed,
        'totalPercentage': newTotal,
        'grade':           newGrade,
        'targetNeeded':    newTargetNeeded,
        'updatedAt':       FieldValue.serverTimestamp(),
      });
      _snack('Result updated!', _dark);
    } catch (e) {
      _snack('Failed to update: $e', _gradeRed);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  GRADE HELPERS
  // ══════════════════════════════════════════════════════════════════

  String _gradeLabelFor(double pct) {
    if (_gradeRanges.isNotEmpty) {
      for (final r in _gradeRanges) {
        final min = (r['min'] as num).toDouble();
        final max = (r['max'] as num).toDouble();
        if (pct >= min && pct <= max) return r['label'] as String;
      }
      return _gradeRanges.last['label'] as String;
    }
    if (pct >= 80) return 'A';
    if (pct >= 70) return 'B';
    if (pct >= 60) return 'C';
    if (pct >= 50) return 'D';
    return 'F';
  }

  Color _gradeColor(double pct) {
    if (_gradeRanges.isNotEmpty) {
      final total = _gradeRanges.length;
      final idx   = _gradeRanges.indexWhere((r) {
        final min = (r['min'] as num).toDouble();
        final max = (r['max'] as num).toDouble();
        return pct >= min && pct <= max;
      });
      if (idx == -1) return _gradeRed;
      final third = total ~/ 3;
      if (idx < third)     return _gradeGreen;
      if (idx < third * 2) return _gradeYellow;
      return _gradeRed;
    }
    if (pct >= 70) return _gradeGreen;
    if (pct >= 50) return _gradeYellow;
    return _gradeRed;
  }

  // ══════════════════════════════════════════════════════════════════
  //  DIALOGS & SNACKBAR
  // ══════════════════════════════════════════════════════════════════

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg, style: GoogleFonts.dmMono(fontSize: 12)),
      backgroundColor: bg,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  void _showSaveSuccessDialog() {
    final grade  = _gradeLabelFor(_totalPercentage);
    final color  = _gradeColor(_totalPercentage);
    final target = _selectedTargetGrade;
    final needed = _targetNeededPct;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        title: Row(children: [
          const Icon(Icons.check_circle, color: _gradeGreen, size: 26),
          const SizedBox(width: 10),
          Text('Saved!',
              style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultRow('Current total',
                '${_totalPercentage.toStringAsFixed(1)}%  •  Grade $grade', color),
            const SizedBox(height: 8),
            if (target != null && needed > 0)
              _resultRow('Still needed for $target',
                  '${needed.toStringAsFixed(1)}% more', _gradeYellow)
            else if (target != null && needed <= 0)
              _resultRow('Target $target', 'Already achieved! 🎉', _gradeGreen),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK',
                style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: _dark)),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: Text(label,
                  style: GoogleFonts.dmMono(fontSize: 12, color: Colors.black54))),
          const SizedBox(width: 8),
          Text(value,
              style: GoogleFonts.dmMono(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      );

  Future<void> _openSetGrade() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SetGradeScreen()),
    );
    if (result == true) await _loadGradeSettings();
  }

  // ══════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bool inputsLocked = !_gradeSettingsLoaded;

    double percentSum = 0;
    for (final row in _assessments) {
      percentSum += double.tryParse(row['percent']!.text) ?? 0;
    }
    final bool sumIs100 = (percentSum - 100).abs() < 0.01;

    return Scaffold(
      backgroundColor: _bgPage,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text('GRADE TRACKER',
                  style: GoogleFonts.dmMono(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: _dark,
                  )),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.justify,
                text: TextSpan(
                  style: GoogleFonts.dmMono(fontSize: 9.5, color: Colors.black87),
                  children: [
                    TextSpan(
                      text: 'NOTE: ',
                      style: GoogleFonts.dmMono(
                          fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    const TextSpan(
                      text:
                          'The Grade Tracker result is an estimation only and should not be '
                          'regarded as an official academic record. Refer to your institution\'s '
                          'official transcript for authoritative results.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Grade-not-set banner
              if (!_gradeSettingsLoaded)
                GestureDetector(
                  onTap: _openSetGrade,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _tan.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _tan, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 18, color: _dark),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Grade settings not set — inputs are disabled. Tap to configure.',
                            style: GoogleFonts.dmMono(fontSize: 11, color: _dark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Input card
              Opacity(
                opacity: inputsLocked ? 0.45 : 1.0,
                child: AbsorbPointer(
                  absorbing: inputsLocked,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _dark, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Subject / Semester display / 📐
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Subject Name',
                                      style: GoogleFonts.dmMono(fontSize: 11, color: _dark)),
                                  const SizedBox(height: 4),
                                  _dropdownField(
                                    value: _selectedSubject,
                                    items: _subjects,
                                    hint: 'Select',
                                    onChanged: (v) {
                                      if (v == null) return;
                                      final meta = _subjectMeta[v] ?? {};
                                      setState(() {
                                        _selectedSubject      = v;
                                        _selectedSemester     = meta['semester']?.isNotEmpty == true ? meta['semester'] : null;
                                        _selectedAcademicYear = meta['academicYear']?.isNotEmpty == true ? meta['academicYear'] : null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Semester',
                                      style: GoogleFonts.dmMono(fontSize: 11, color: _dark)),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: 36,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: _bgField,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.black26),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _semesterDisplayLabel,
                                      style: GoogleFonts.dmMono(
                                        fontSize: 11,
                                        color: _selectedSemester != null
                                            ? _dark
                                            : Colors.black38,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _openSetGrade,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: _bgField,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.black38, width: 1),
                                ),
                                child: const Center(
                                  child: Text('📐', style: TextStyle(fontSize: 18)),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Column headers
                        Row(
                          children: [
                            _hdr('Assessment', flex: 3),
                            _hdr('Marks',       flex: 2),
                            _hdr('Fullmarks *', flex: 2),
                            _hdr('%  *',         flex: 2),
                            const SizedBox(width: 22),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Assessment rows
                        ...List.generate(_assessments.length, (i) {
                          final row  = _assessments[i];
                          final err  = _rowError(i);
                          final hint = _marksNeededHint(i);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(flex: 3, child: _inputField(row['name']!)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                        flex: 2,
                                        child: _numField(row['marks']!,
                                            hasError: err != null && err.contains('exceed'))),
                                    const SizedBox(width: 4),
                                    Expanded(
                                        flex: 2,
                                        child: _numField(row['fullmarks']!,
                                            hasError: err != null && err.contains('Fullmarks'))),
                                    const SizedBox(width: 4),
                                    Expanded(
                                        flex: 2,
                                        child: _numField(row['percent']!,
                                            hasError: err != null && err.contains('%'))),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => _removeRow(i),
                                      child: const Icon(Icons.close,
                                          size: 18, color: Colors.black54),
                                    ),
                                  ],
                                ),
                                if (err != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 2, top: 2),
                                    child: Text(err,
                                        style: GoogleFonts.dmMono(fontSize: 9, color: _gradeRed)),
                                  ),
                                if (hint != null && err == null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 2, top: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info_outline,
                                            size: 10, color: _gradeYellow),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Need $hint for $_selectedTargetGrade',
                                          style: GoogleFonts.dmMono(
                                              fontSize: 9,
                                              color: _gradeYellow,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),

                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: Text(
                            '* Fullmarks and % are required for every active assessment.',
                            style: GoogleFonts.dmMono(fontSize: 9, color: Colors.black45),
                          ),
                        ),

                        if (percentSum > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Icon(
                                  sumIs100 ? Icons.check_circle : Icons.info_outline,
                                  size: 13,
                                  color: sumIs100 ? _gradeGreen : _gradeYellow,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  sumIs100
                                      ? '% total: 100 ✓'
                                      : '% total: ${percentSum.toStringAsFixed(0)} / 100',
                                  style: GoogleFonts.dmMono(
                                    fontSize: 10,
                                    color: sumIs100 ? _gradeGreen : _gradeYellow,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 10),

                        // Target Grade
                        Row(
                          children: [
                            Text('Target Grade :',
                                style: GoogleFonts.dmMono(fontSize: 12, color: _dark)),
                            const SizedBox(width: 12),
                            Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: _bgField,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.black38),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedTargetGrade,
                                  hint: Text(
                                    _gradeSettingsLoaded ? 'Select' : 'Set grade first',
                                    style: GoogleFonts.dmMono(fontSize: 12, color: Colors.black38),
                                  ),
                                  style: GoogleFonts.dmMono(fontSize: 13, color: _dark),
                                  dropdownColor: Colors.white,
                                  icon: const Icon(Icons.arrow_drop_down, size: 20, color: _dark),
                                  items: _targetGradeOptions
                                      .map((g) => DropdownMenuItem(
                                            value: g,
                                            child: Text(g,
                                                style: GoogleFonts.dmMono(
                                                    fontSize: 13, color: _dark)),
                                          ))
                                      .toList(),
                                  onChanged: _gradeSettingsLoaded
                                      ? (v) {
                                          setState(() => _selectedTargetGrade = v);
                                          _recalculate();
                                        }
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(child: _actionBtn(label: 'RESET', color: _tan, onTap: _reset)),
                            const SizedBox(width: 10),
                            Expanded(child: _actionBtn(label: '+ ADD METHOD', color: _bgCard, onTap: _addAssessmentRow)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Result cards
              Row(
                children: [
                  Expanded(child: _resultCard(
                    label: 'Total (%):',
                    value: _percentSumValid ? _totalPercentage.toStringAsFixed(1) : '0',
                    grade: _percentSumValid && _totalPercentage > 0 ? _gradeLabelFor(_totalPercentage) : null,
                    gradeColor: _gradeColor(_totalPercentage),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _resultCard(
                    label: 'Target Needed (%):',
                    value: _percentSumValid && _selectedTargetGrade != null
                        ? _targetNeededPct.toStringAsFixed(1)
                        : '0',
                    grade: null,
                    gradeColor: _gradeYellow,
                    valueColor: _targetNeededPct <= 0 && _selectedTargetGrade != null && _percentSumValid
                        ? _gradeGreen
                        : null,
                    subLabel: _targetNeededPct <= 0 && _selectedTargetGrade != null && _percentSumValid
                        ? 'Achieved! 🎉'
                        : null,
                  )),
                ],
              ),

              const SizedBox(height: 16),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveResult,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _dark,
                    disabledBackgroundColor: Colors.black38,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('SAVE',
                          style: GoogleFonts.dmMono(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 2,
                          )),
                ),
              ),

              const SizedBox(height: 28),

              // Saved results header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Saved Results',
                      style: GoogleFonts.dmMono(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: _dark,
                      )),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.dmMono(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        hintText: 'Search...',
                        hintStyle:
                            GoogleFonts.dmMono(fontSize: 12, color: Colors.black38),
                        suffixIcon:
                            const Icon(Icons.search, size: 16, color: Colors.black45),
                        filled: true, fillColor: _bgCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: Colors.black54),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: Colors.black38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: Colors.black),
                        ),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Saved results stream
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
                    ));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _emptyState('No saved results yet');
                  }

                  final docs = snapshot.data!.docs.where((doc) {
                    final d   = doc.data() as Map<String, dynamic>;
                    final sub = (d['subject'] ?? '').toString().toLowerCase();
                    final sem = (d['semester'] ?? '').toString().toLowerCase();
                    return _searchQuery.isEmpty ||
                        sub.contains(_searchQuery) ||
                        sem.contains(_searchQuery);
                  }).toList()
                    ..sort((a, b) {
                      final at = (a.data() as Map<String, dynamic>)['savedAt'];
                      final bt = (b.data() as Map<String, dynamic>)['savedAt'];
                      if (at == null && bt == null) return 0;
                      if (at == null) return 1;
                      if (bt == null) return -1;
                      return (bt as Timestamp).compareTo(at as Timestamp);
                    });

                  if (docs.isEmpty) return _emptyState('No results match your search');

                  return Column(
                    children: docs
                        .map((doc) => _SavedCard(
                              docId: doc.id,
                              data:  doc.data() as Map<String, dynamic>,
                              gradeRanges: _gradeRanges,
                              onDelete: _deleteResult,
                              onUpdate: _updateSavedAssessments,
                              gradeLabelFor: _gradeLabelFor,
                              gradeColorFn: _gradeColor,
                            ))
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

  Widget _resultCard({
    required String label,
    required String value,
    String? grade,
    required Color gradeColor,
    Color? valueColor,
    String? subLabel,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: _bgField,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _dark, width: 2),
        ),
        child: Column(
          children: [
            Text(label, style: GoogleFonts.dmMono(fontSize: 12, color: _dark)),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.dmMono(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  color: valueColor ?? _dark,
                )),
            if (subLabel != null) ...[
              const SizedBox(height: 4),
              Text(subLabel,
                  style: GoogleFonts.dmMono(
                      fontSize: 11, color: gradeColor, fontWeight: FontWeight.bold)),
            ],
            if (grade != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                    color: gradeColor, borderRadius: BorderRadius.circular(20)),
                child: Text('Grade: $grade',
                    style: GoogleFonts.dmMono(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ],
        ),
      );

  Widget _emptyState(String msg) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black26, width: 1.5),
        ),
        child: Center(
          child: Text(msg, style: GoogleFonts.dmMono(fontSize: 13, color: Colors.grey)),
        ),
      );

  Widget _hdr(String text, {required int flex}) => Expanded(
        flex: flex,
        child: Text(text, style: GoogleFonts.dmMono(fontSize: 10, color: _dark)),
      );

  InputDecoration _fieldDeco({bool hasError = false}) => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        filled: true, fillColor: _bgField,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: hasError ? _gradeRed : Colors.black38),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: hasError ? _gradeRed : Colors.black26),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: hasError ? _gradeRed : Colors.black87),
        ),
      );

  Widget _inputField(TextEditingController ctrl) => TextField(
        controller: ctrl,
        style: GoogleFonts.dmMono(fontSize: 12),
        decoration: _fieldDeco(),
      );

  Widget _numField(TextEditingController ctrl, {bool hasError = false}) => TextField(
        controller: ctrl,
        style: GoogleFonts.dmMono(fontSize: 12),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
        decoration: _fieldDeco(hasError: hasError),
      );

  Widget _dropdownField({
    required String? value,
    required List<String> items,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) =>
      Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _bgField,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black26),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            hint: Text(hint,
                style: GoogleFonts.dmMono(fontSize: 12, color: Colors.black38)),
            style: GoogleFonts.dmMono(fontSize: 12, color: _dark),
            dropdownColor: Colors.white,
            icon: const Icon(Icons.arrow_drop_down, size: 18, color: _dark),
            items: items
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s,
                          style: GoogleFonts.dmMono(fontSize: 12, color: _dark)),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
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
            child: Text(label,
                style: GoogleFonts.dmMono(
                    fontWeight: FontWeight.bold, fontSize: 13, color: _dark)),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  _SavedCard  –  v3
//
//  Edit mode now exposes Marks, Fullmarks AND % for every row.
//  Validates: marks ≤ fullmarks, % sum = 100, fullmarks required.
// ─────────────────────────────────────────────────────────────────────────────

class _SavedCard extends StatefulWidget {
  const _SavedCard({
    required this.docId,
    required this.data,
    required this.gradeRanges,
    required this.onDelete,
    required this.onUpdate,
    required this.gradeLabelFor,
    required this.gradeColorFn,
  });

  final String                     docId;
  final Map<String, dynamic>       data;
  final List<Map<String, dynamic>> gradeRanges;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(
    String,
    List<Map<String, dynamic>>, {
    required List<Map<String, dynamic>> gradeRanges,
    required String targetGrade,
  }) onUpdate;
  final String Function(double) gradeLabelFor;
  final Color  Function(double) gradeColorFn;

  @override
  State<_SavedCard> createState() => _SavedCardState();
}

class _SavedCardState extends State<_SavedCard> {
  static const _dark        = Color(0xFF1A1A1A);
  static const _tan         = Color(0xFFD4B896);
  static const _gradeGreen  = Color(0xFF34A853);
  static const _gradeYellow = Color(0xFFFBBC05);
  static const _gradeRed    = Color(0xFFB90000);

  bool _isEditing = false;
  bool _isSaving  = false;

  late List<TextEditingController> _editMarksCtrl;
  late List<TextEditingController> _editFullmarksCtrl;
  late List<TextEditingController> _editPercentCtrl;
  late List<Map<String, dynamic>>  _editAssessments;

  @override
  void initState() {
    super.initState();
    _initEditState();
  }

  void _initEditState() {
    _editAssessments = List<Map<String, dynamic>>.from(widget.data['assessments'] ?? []);

    _editMarksCtrl = _editAssessments.map((a) {
      final v = (a['marks'] ?? 0).toDouble();
      return TextEditingController(text: v > 0 ? _fmt(v) : '');
    }).toList();

    _editFullmarksCtrl = _editAssessments.map((a) {
      final v = (a['fullmarks'] ?? 0).toDouble();
      return TextEditingController(text: v > 0 ? _fmt(v) : '');
    }).toList();

    _editPercentCtrl = _editAssessments.map((a) {
      final v = (a['percent'] ?? 0).toDouble();
      return TextEditingController(text: v > 0 ? _fmt(v) : '');
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _editMarksCtrl)     c.dispose();
    for (final c in _editFullmarksCtrl) c.dispose();
    for (final c in _editPercentCtrl)   c.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  // ── Edit validation ──────────────────────────────────────────────

  /// Returns error string for row i, or null if ok.
  String? _editRowError(int i) {
    final marks     = double.tryParse(_editMarksCtrl[i].text.trim());
    final fullmarks = double.tryParse(_editFullmarksCtrl[i].text.trim()) ?? 0;
    final percent   = double.tryParse(_editPercentCtrl[i].text.trim())   ?? 0;

    if (marks != null && fullmarks > 0 && marks > fullmarks) return 'Marks > fullmarks';
    if (percent > 0 && fullmarks <= 0) return 'Fullmarks required';
    if (fullmarks > 0 && percent <= 0) return '% required';
    return null;
  }

  bool get _hasEditErrors =>
      List.generate(_editAssessments.length, _editRowError).any((e) => e != null);

  double get _editPercentSum {
    double s = 0;
    for (final c in _editPercentCtrl) s += double.tryParse(c.text.trim()) ?? 0;
    return s;
  }

  bool get _editSumIs100 => (_editPercentSum - 100).abs() < 0.01;

  Future<void> _saveEdits() async {
    if (_hasEditErrors) { _showSnack('Fix row errors before saving.'); return; }
    if (!_editSumIs100) {
      _showSnack('% must total 100 (currently ${_editPercentSum.toStringAsFixed(0)}).');
      return;
    }

    setState(() => _isSaving = true);

    final updated = <Map<String, dynamic>>[];
    for (int i = 0; i < _editAssessments.length; i++) {
      final a         = Map<String, dynamic>.from(_editAssessments[i]);
      final marks     = double.tryParse(_editMarksCtrl[i].text.trim())     ?? 0;
      final fullmarks = double.tryParse(_editFullmarksCtrl[i].text.trim()) ?? 0;
      final percent   = double.tryParse(_editPercentCtrl[i].text.trim())   ?? 0;

      a['marks']        = marks;
      a['fullmarks']    = fullmarks;
      a['percent']      = percent;
      a['contribution'] = fullmarks > 0 ? (marks / fullmarks) * percent : 0.0;
      // onUpdate will recompute marksNeededForTarget
      updated.add(a);
    }

    await widget.onUpdate(
      widget.docId,
      updated,
      gradeRanges: widget.gradeRanges,
      targetGrade: (widget.data['targetGrade'] ?? '').toString(),
    );

    if (mounted) setState(() { _isSaving = false; _isEditing = false; });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg, style: GoogleFonts.dmMono(fontSize: 12)),
      backgroundColor: _gradeRed,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final subject      = widget.data['subject']      ?? '';
    final semester     = (widget.data['semester']    ?? '').toString();
    final academicYear = (widget.data['academicYear'] ?? widget.data['year'] ?? '').toString();
    final total        = (widget.data['totalPercentage'] ?? 0).toDouble();
    final targetGrade  = (widget.data['targetGrade'] ?? '').toString();
    final targetNeeded = (widget.data['targetNeeded'] ?? 0).toDouble();
    final assessments  = List<Map<String, dynamic>>.from(widget.data['assessments'] ?? []);
    final savedAt      = (widget.data['savedAt']   as Timestamp?)?.toDate();
    final updatedAt    = (widget.data['updatedAt'] as Timestamp?)?.toDate();

    final gradeLabel = widget.gradeLabelFor(total);
    final gradeClr   = widget.gradeColorFn(total);

    // Format: "Sem 1, 26/27"
    final shortYear = academicYear.isNotEmpty
        ? _GradeCalculatorScreenState.shortenAcademicYear(academicYear)
        : '';
    final semLabel = semester.isNotEmpty
        ? 'Sem $semester${shortYear.isNotEmpty ? ', $shortYear' : ''}'
        : '—';

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
                      Text('SUBJECT: ${subject.toString().toUpperCase()}',
                          style: GoogleFonts.dmMono(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      const SizedBox(height: 3),
                      Text(
                        '($semLabel'
                        '${savedAt != null ? '  •  ${savedAt.day}/${savedAt.month}/${savedAt.year}' : ''})',
                        style: GoogleFonts.dmMono(color: Colors.white60, fontSize: 11),
                      ),
                      if (updatedAt != null) ...[
                        const SizedBox(height: 2),
                        Text('Updated: ${updatedAt.day}/${updatedAt.month}/${updatedAt.year}',
                            style: GoogleFonts.dmMono(color: Colors.white38, fontSize: 10)),
                      ],
                      if (targetGrade.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text('Target: $targetGrade',
                            style: GoogleFonts.dmMono(color: _tan, fontSize: 11)),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (val) async {
                    if (val == 'edit') {
                      setState(() {
                        _isEditing = !_isEditing;
                        if (_isEditing) _initEditState();
                      });
                    } else if (val == 'delete') {
                      await widget.onDelete(widget.docId);
                    }
                  },
                  color: Colors.white,
                  icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(
                          _isEditing ? Icons.close : Icons.edit_outlined,
                          color: _isEditing ? Colors.grey : _tan,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isEditing ? 'Cancel Edit' : 'Edit Result',
                          style: GoogleFonts.dmMono(
                              color: _isEditing ? Colors.grey : _dark),
                        ),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        const Icon(Icons.delete_outline, color: _gradeRed, size: 18),
                        const SizedBox(width: 8),
                        Text('Delete', style: GoogleFonts.dmMono(color: _gradeRed)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Section label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _isEditing ? 'Edit Assessment Data' : 'Results',
              style: GoogleFonts.dmMono(
                color: _isEditing ? _tan : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                decoration: TextDecoration.underline,
                decorationColor: _isEditing ? _tan : Colors.white,
              ),
            ),
          ),

          // Column headers
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _isEditing
                ? Row(children: [
                    Expanded(
                        flex: 3,
                        child: Text('Assessment',
                            style: GoogleFonts.dmMono(
                                color: Colors.white54, fontSize: 10))),
                    Expanded(
                        flex: 2,
                        child: Text('Marks',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.dmMono(
                                color: Colors.white54, fontSize: 10))),
                    Expanded(
                        flex: 2,
                        child: Text('Fullmarks',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.dmMono(
                                color: Colors.white54, fontSize: 10))),
                    Expanded(
                        flex: 2,
                        child: Text('%',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.dmMono(
                                color: Colors.white54, fontSize: 10))),
                  ])
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Assessment:',
                          style: GoogleFonts.dmMono(
                              color: Colors.white54, fontSize: 11)),
                      Text('Contribution (%):',
                          style: GoogleFonts.dmMono(
                              color: Colors.white54, fontSize: 11)),
                    ],
                  ),
          ),

          // Assessment rows
          ...List.generate(assessments.length, (i) {
            final a            = assessments[i];
            final name         = (a['name'] ?? '').toString();
            final contribution = (a['contribution'] ?? 0).toDouble();
            final mNeeded      = (a['marksNeededForTarget'] ?? -1).toDouble();
            final fullmarks    = (a['fullmarks'] ?? 0).toDouble();

            if (_isEditing) {
              final errMsg      = _editRowError(i);
              final hasMarksErr = errMsg != null && errMsg.contains('>');
              final hasFmErr    = errMsg != null && errMsg.contains('Fullmarks');
              final hasPctErr   = errMsg != null && errMsg.contains('%');

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(name,
                              style: GoogleFonts.dmMono(
                                  color: Colors.white70, fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: _editField(_editMarksCtrl[i], hasError: hasMarksErr),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: _editField(_editFullmarksCtrl[i], hasError: hasFmErr),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: _editField(_editPercentCtrl[i], hasError: hasPctErr),
                        ),
                      ],
                    ),
                    if (errMsg != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(errMsg,
                            style: GoogleFonts.dmMono(fontSize: 9, color: _gradeRed)),
                      ),
                  ],
                ),
              );
            }

            // View mode
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(name,
                            style: GoogleFonts.dmMono(
                                color: Colors.white70, fontSize: 12)),
                      ),
                      Text(
                        contribution > 0 ? contribution.toStringAsFixed(1) : '—',
                        style: GoogleFonts.dmMono(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                  if (mNeeded >= 0 && fullmarks > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 10, color: _gradeYellow),
                          const SizedBox(width: 3),
                          Text(
                            'Need ${mNeeded.toStringAsFixed(1)} / ${fullmarks.toStringAsFixed(0)} marks for $targetGrade',
                            style: GoogleFonts.dmMono(
                                fontSize: 9,
                                color: _gradeYellow,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),

          // % sum indicator (edit mode)
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    _editSumIs100 ? Icons.check_circle : Icons.info_outline,
                    size: 12,
                    color: _editSumIs100 ? _gradeGreen : _gradeYellow,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _editSumIs100
                        ? '% total: 100 ✓'
                        : '% total: ${_editPercentSum.toStringAsFixed(0)} / 100',
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      color: _editSumIs100 ? _gradeGreen : _gradeYellow,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Save changes button
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving || _hasEditErrors || !_editSumIs100
                      ? null
                      : _saveEdits,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _tan,
                    disabledBackgroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Save Changes',
                          style: GoogleFonts.dmMono(
                              fontWeight: FontWeight.bold,
                              color: _dark,
                              fontSize: 13)),
                ),
              ),
            ),

          const SizedBox(height: 10),

          // Final total footer
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: gradeClr.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: gradeClr.withOpacity(0.6), width: 1.5),
            ),
            child: Center(
              child: Text(
                'FINAL TOTAL: ${total.toStringAsFixed(1)}%  •  Grade $gradeLabel',
                style: GoogleFonts.dmMono(
                    color: gradeClr, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),

          // Target footer
          if (targetGrade.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: targetNeeded <= 0
                    ? _gradeGreen.withOpacity(0.12)
                    : _gradeYellow.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: targetNeeded <= 0
                        ? _gradeGreen.withOpacity(0.5)
                        : _gradeYellow.withOpacity(0.5),
                    width: 1.5),
              ),
              child: Center(
                child: Text(
                  targetNeeded <= 0
                      ? 'Target $targetGrade: Achieved! 🎉'
                      : 'Still need ${targetNeeded.toStringAsFixed(1)}% more for Grade $targetGrade',
                  style: GoogleFonts.dmMono(
                    color: targetNeeded <= 0 ? _gradeGreen : _gradeYellow,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),

          // How-to-reach breakdown
          Builder(builder: (_) {
            final pending = assessments.where((a) =>
                (a['marksNeededForTarget'] ?? -1).toDouble() >= 0 &&
                (a['fullmarks'] ?? 0) > 0);
            if (pending.isEmpty || targetGrade.isEmpty) return const SizedBox.shrink();

            return Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to reach $targetGrade:',
                      style: GoogleFonts.dmMono(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                  const SizedBox(height: 6),
                  ...pending.map((a) {
                    final mNeeded = (a['marksNeededForTarget'] as num).toDouble();
                    final fm      = (a['fullmarks'] as num).toDouble();
                    final aName   = (a['name'] ?? '').toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_right, color: _gradeYellow, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.dmMono(
                                    fontSize: 11, color: Colors.white70),
                                children: [
                                  TextSpan(
                                      text: aName.isNotEmpty
                                          ? '$aName: '
                                          : 'Assessment: '),
                                  TextSpan(
                                    text: '${mNeeded.toStringAsFixed(1)} / ${fm.toStringAsFixed(0)}',
                                    style: GoogleFonts.dmMono(
                                        fontWeight: FontWeight.bold,
                                        color: _gradeYellow,
                                        fontSize: 11),
                                  ),
                                  const TextSpan(text: ' marks needed'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _editField(TextEditingController ctrl, {bool hasError = false}) => TextField(
        controller: ctrl,
        onChanged: (_) => setState(() {}),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
        textAlign: TextAlign.center,
        style: GoogleFonts.dmMono(
            fontSize: 11, color: hasError ? _gradeRed : Colors.white),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          filled: true,
          fillColor: Colors.white12,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                BorderSide(color: hasError ? _gradeRed : Colors.white24),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                BorderSide(color: hasError ? _gradeRed : Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                BorderSide(color: hasError ? _gradeRed : Colors.white70),
          ),
        ),
      );
}