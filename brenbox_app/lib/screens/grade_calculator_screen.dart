import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../grade/set_grade_screen.dart';

class GradeCalculatorScreen extends StatefulWidget {
  const GradeCalculatorScreen({Key? key}) : super(key: key);

  @override
  State<GradeCalculatorScreen> createState() => _GradeCalculatorScreenState();
}

class _GradeCalculatorScreenState extends State<GradeCalculatorScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _searchController = TextEditingController();

  String? _selectedSubject;
  String? _selectedSemester;
  String? _selectedAcademicYear;
  String? _selectedTargetGrade;

  List<Map<String, TextEditingController>> _assessments = [];

  double _totalPercentage = 0.0;
  double _targetNeededPct = 0.0;
  double _maxAchievable = 0.0;
  bool _percentSumValid = false;
  String? _nearestGrade;

  List<Map<String, dynamic>> _gradeRanges = [];
  bool _gradeSettingsLoaded = false;

  Map<String, Map<String, String>> _subjectMeta = {};
  List<String> get _subjects => _subjectMeta.keys.toList()..sort();

  String _searchQuery = '';
  bool _isSaving = false;

  // ── Colours aligned to CalendarScreen palette ──────────────────
  static const _bgPage   = Color(0xFFE5E7EB); // matches calendar background
  static const _bgCard   = Colors.white;
  static const _bgField  = Color(0xFFE5E7EB); // same as page bg for cohesion
  static const _dark     = Color(0xFF1A1A1A);
  static const _tan      = Color(0xFFD4B896);
  static const _gradeGreen  = Color(0xFF34A853);
  static const _gradeYellow = Color(0xFFFBBC05);
  static const _gradeRed    = Color(0xFFB90000);

  List<String> get _targetGradeOptions =>
      _gradeRanges.map((r) => r['label'] as String).toList();

  String get _semesterDisplayLabel {
    final sem  = _selectedSemester ?? '';
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
          _gradeRanges = List<Map<String, dynamic>>.from(
            doc.data()?['ranges'] ?? [],
          );
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
        final year = (d['academicYear'] ?? d['academic_year'] ?? d['year'] ?? '')
            .toString()
            .trim();
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
    final row      = _assessments[i];
    final marks    = double.tryParse(row['marks']!.text.trim());
    final fullmarks= double.tryParse(row['fullmarks']!.text.trim());
    final percent  = double.tryParse(row['percent']!.text.trim());

    if (marks != null && fullmarks != null && fullmarks > 0 && marks > fullmarks)
      return 'Marks cannot exceed fullmarks';
    if ((percent ?? 0) > 0 && (fullmarks == null || fullmarks <= 0))
      return 'Fullmarks required when % is set';
    if ((fullmarks ?? 0) > 0 && (percent == null || percent <= 0))
      return '% required when fullmarks is set';
    return null;
  }

  bool get _hasRowErrors =>
      List.generate(_assessments.length, _rowError).any((e) => e != null);

  bool get _hasPartialPercentError {
    final active = List.generate(_assessments.length, (i) => i)
        .where(_rowIsActive)
        .toList();
    if (active.isEmpty) return false;
    final withPct = active
        .where((i) => (double.tryParse(_assessments[i]['percent']!.text.trim()) ?? 0) > 0)
        .length;
    final withoutPct = active
        .where((i) => (double.tryParse(_assessments[i]['percent']!.text.trim()) ?? 0) <= 0)
        .length;
    return withPct > 0 && withoutPct > 0;
  }

  String? get _saveBlockReason {
    if (!_gradeSettingsLoaded) return 'Please set up your grade settings first (📐).';
    if (_selectedSubject == null) return 'Please select a subject.';
    if (_selectedSemester == null) return 'Semester info is missing for this subject.';
    if (_selectedTargetGrade == null) return 'Please select a target grade.';
    if (_hasRowErrors) return 'Fix the row errors before saving.';
    if (_hasPartialPercentError) return 'All active assessments must have a % value.';
    if (!_percentSumValid) return '% column must total exactly 100.';
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
    double maxPossible     = 0;
    double remainingWeight = 0;

    for (final row in _assessments) {
      final marks    = double.tryParse(row['marks']!.text) ?? -1;
      final fullmarks= double.tryParse(row['fullmarks']!.text) ?? 0;
      final percent  = double.tryParse(row['percent']!.text) ?? 0;

      percentSum += percent;

      if (marks >= 0 && fullmarks > 0 && percent > 0) {
        final contribution = (marks / fullmarks) * percent;
        earnedSoFar += contribution;
        maxPossible += contribution;
      } else if (percent > 0 && fullmarks > 0 && marks < 0) {
        maxPossible     += percent;
        remainingWeight += percent;
      } else if (percent > 0 && (marks < 0 || fullmarks <= 0)) {
        remainingWeight += percent;
      }
    }

    final valid = (percentSum - 100).abs() < 0.01;

    double targetNeeded = 0;
    String? nearestGrade;

    if (valid && _selectedTargetGrade != null && _gradeSettingsLoaded) {
      final range = _gradeRanges.firstWhere(
        (r) => r['label'] == _selectedTargetGrade,
        orElse: () => {},
      );
      if (range.isNotEmpty) {
        final targetMin = (range['min'] as num).toDouble();
        final needed    = targetMin - earnedSoFar;
        targetNeeded    = needed > 0 ? needed : 0;

        if (maxPossible < targetMin) {
          final sortedRanges = List<Map<String, dynamic>>.from(_gradeRanges)
            ..sort((a, b) => (b['min'] as num).compareTo(a['min'] as num));

          for (final r in sortedRanges) {
            final rMin = (r['min'] as num).toDouble();
            if (maxPossible >= rMin) {
              nearestGrade = r['label'] as String;
              break;
            }
          }
          nearestGrade ??= _gradeRanges.last['label'] as String;
        }
      }
    }

    setState(() {
      _totalPercentage = earnedSoFar;
      _maxAchievable   = maxPossible;
      _targetNeededPct = targetNeeded;
      _percentSumValid = valid;
      _nearestGrade    = nearestGrade;
    });
  }

  // ══════════════════════════════════════════════════════════════════
  //  MARKS-NEEDED HINT PER ROW
  // ══════════════════════════════════════════════════════════════════

  String? _marksNeededHint(int rowIdx) {
    if (!_gradeSettingsLoaded || _selectedTargetGrade == null) return null;
    final row      = _assessments[rowIdx];
    final marks    = double.tryParse(row['marks']!.text);
    final fullmarks= double.tryParse(row['fullmarks']!.text) ?? 0;
    final percent  = double.tryParse(row['percent']!.text) ?? 0;
    if (marks != null || fullmarks <= 0 || percent <= 0) return null;

    final range = _gradeRanges.firstWhere(
      (r) => r['label'] == _selectedTargetGrade,
      orElse: () => {},
    );
    if (range.isEmpty) return null;
    final targetMin = (range['min'] as num).toDouble();

    double earnedFromScored   = 0;
    double totalPendingWeight = 0;

    for (int i = 0; i < _assessments.length; i++) {
      final r   = _assessments[i];
      final m   = double.tryParse(r['marks']!.text);
      final fm  = double.tryParse(r['fullmarks']!.text) ?? 0;
      final pct = double.tryParse(r['percent']!.text) ?? 0;
      if (m != null && fm > 0 && pct > 0) {
        earnedFromScored += (m / fm) * pct;
      } else if (pct > 0 && fm > 0) {
        totalPendingWeight += pct;
      }
    }

    final totalStillNeeded = targetMin - earnedFromScored;
    if (totalStillNeeded <= 0) return null;
    if (totalPendingWeight < totalStillNeeded) return null;

    final requiredRatio = totalStillNeeded / totalPendingWeight;
    final marksNeeded   = (requiredRatio * fullmarks).clamp(0.0, fullmarks);
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
      _maxAchievable        = 0;
      _nearestGrade         = null;
      _percentSumValid      = false;
    });
    for (final row in _assessments) {
      for (final c in row.values) c.clear();
    }
  }

  Future<void> _saveResult() async {
    final reason = _saveBlockReason;
    if (reason != null) {
      _snack(reason, _gradeRed);
      return;
    }

    final user = _auth.currentUser!;
    final List<Map<String, dynamic>> assessmentData = [];

    for (int i = 0; i < _assessments.length; i++) {
      if (!_rowIsActive(i)) continue;
      final row      = _assessments[i];
      final name     = row['name']!.text.trim();
      final marks    = double.tryParse(row['marks']!.text) ?? 0;
      final fullmarks= double.tryParse(row['fullmarks']!.text) ?? 0;
      final percent  = double.tryParse(row['percent']!.text) ?? 0;
      final contribution = fullmarks > 0 ? (marks / fullmarks) * percent : 0.0;

      double marksNeededForTarget = -1;
      if (row['marks']!.text.trim().isEmpty && fullmarks > 0 && percent > 0) {
        double earnedFromScored   = 0;
        double totalPendingWeight = 0;
        for (int j = 0; j < _assessments.length; j++) {
          if (!_rowIsActive(j)) continue;
          final r   = _assessments[j];
          final m   = double.tryParse(r['marks']!.text);
          final fm  = double.tryParse(r['fullmarks']!.text) ?? 0;
          final pct = double.tryParse(r['percent']!.text) ?? 0;
          if (m != null && fm > 0 && pct > 0) {
            earnedFromScored += (m / fm) * pct;
          } else if (pct > 0 && fm > 0) {
            totalPendingWeight += pct;
          }
        }
        final range = _gradeRanges.firstWhere(
          (r) => r['label'] == _selectedTargetGrade,
          orElse: () => {},
        );
        if (range.isNotEmpty) {
          final targetMin       = (range['min'] as num).toDouble();
          final totalStillNeeded= targetMin - earnedFromScored;
          if (totalStillNeeded > 0 && totalPendingWeight >= totalStillNeeded) {
            final requiredRatio = totalStillNeeded / totalPendingWeight;
            marksNeededForTarget =
                (requiredRatio * fullmarks).clamp(0.0, fullmarks);
          }
        }
      }

      assessmentData.add({
        'name': name,
        'marks': marks,
        'fullmarks': fullmarks,
        'percent': percent,
        'contribution': contribution,
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
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'displayName': user.displayName ?? '',
        'subject': _selectedSubject,
        'semester': _selectedSemester,
        'academicYear': _selectedAcademicYear ?? '',
        'targetGrade': _selectedTargetGrade ?? '',
        'assessments': assessmentData,
        'totalPercentage': _totalPercentage,
        'maxAchievable': _maxAchievable,
        'targetNeeded': _targetNeededPct,
        'grade': _gradeLabelFor(_totalPercentage),
        'savedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _showSaveSuccessDialog();
        _reset();
      }
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
      double newTotal      = 0;
      double newMaxPossible= 0;

      for (final a in updatedAssessments) {
        final marks      = (a['marks'] ?? 0).toDouble();
        final fullmarks  = (a['fullmarks'] ?? 0).toDouble();
        final percent    = (a['percent'] ?? 0).toDouble();
        final isPending  =
            marks <= 0 && (a['marksNeededForTarget'] ?? -1).toDouble() >= 0;
        if (fullmarks > 0) {
          final contrib  = (marks / fullmarks) * percent;
          newTotal      += contrib;
          newMaxPossible+= isPending ? percent : contrib;
        }
      }

      String newGrade = '';
      if (gradeRanges.isNotEmpty) {
        for (final r in gradeRanges) {
          final min = (r['min'] as num).toDouble();
          final max = (r['max'] as num).toDouble();
          if (newTotal >= min && newTotal <= max) {
            newGrade = r['label'] as String;
            break;
          }
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
        final marks     = (a['marks'] ?? 0).toDouble();
        final fullmarks = (a['fullmarks'] ?? 0).toDouble();
        final percent   = (a['percent'] ?? 0).toDouble();

        if (marks <= 0 && fullmarks > 0 && percent > 0 && newTargetNeeded > 0) {
          double totalPendingWeight = 0;
          for (final b in updatedAssessments) {
            final bm   = (b['marks'] ?? 0).toDouble();
            final bfm  = (b['fullmarks'] ?? 0).toDouble();
            final bpct = (b['percent'] ?? 0).toDouble();
            if (bm <= 0 && bfm > 0 && bpct > 0) totalPendingWeight += bpct;
          }
          if (totalPendingWeight > 0) {
            final requiredRatio = newTargetNeeded / totalPendingWeight;
            final marksNeeded   =
                (requiredRatio * fullmarks).clamp(0.0, fullmarks);
            updated['marksNeededForTarget'] = marksNeeded;
          } else {
            updated['marksNeededForTarget'] = -1.0;
          }
        } else {
          updated['marksNeededForTarget'] = -1.0;
        }
        return updated;
      }).toList();

      await _firestore.collection('grade_results').doc(docId).update({
        'assessments': recomputed,
        'totalPercentage': newTotal,
        'maxAchievable': newMaxPossible,
        'grade': newGrade,
        'targetGrade': targetGrade,
        'targetNeeded': newTargetNeeded,
        'updatedAt': FieldValue.serverTimestamp(),
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
      if (idx < third)       return _gradeGreen;
      if (idx < third * 2)   return _gradeYellow;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.dmMono(fontSize: 12)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
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
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: _gradeGreen, size: 26),
            const SizedBox(width: 10),
            Text(
              'Saved!',
              style: GoogleFonts.dmMono(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultRow(
              'Current total',
              '${_totalPercentage.toStringAsFixed(1)}%  •  Grade $grade',
              color,
            ),
            const SizedBox(height: 8),
            if (target != null && needed > 0)
              _resultRow(
                'Still needed for $target',
                '${needed.toStringAsFixed(1)}% more',
                _gradeYellow,
              )
            else if (target != null && needed <= 0)
              _resultRow('Target $target', 'Already achieved! 🎉', _gradeGreen),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: GoogleFonts.dmMono(
                fontWeight: FontWeight.bold,
                color: _dark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, Color color) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: GoogleFonts.dmMono(fontSize: 12, color: Colors.black54),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        value,
        style: GoogleFonts.dmMono(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
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

    final bool targetImpossible =
        _selectedTargetGrade != null &&
        _percentSumValid &&
        _nearestGrade != null;

    return Scaffold(
      backgroundColor: _bgPage,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header — matches CalendarScreen title style ──────
              const SizedBox(height: 16),
              Text(
                'GRADE TRACKER',
                style: GoogleFonts.dmMono(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 12),

              // Disclaimer note
              RichText(
                textAlign: TextAlign.justify,
                text: TextSpan(
                  style: GoogleFonts.dmMono(
                    fontSize: 10,
                    color: Colors.black87,
                  ),
                  children: [
                    TextSpan(
                      text: 'NOTE: ',
                      style: GoogleFonts.dmMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
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

              // Grade-settings warning banner
              if (!_gradeSettingsLoaded)
                GestureDetector(
                  onTap: _openSetGrade,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _tan.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _tan, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 18, color: _dark),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Grade settings not set — inputs are disabled. Tap to configure.',
                            style: GoogleFonts.dmMono(
                              fontSize: 12,
                              color: _dark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Input card — calendar-matched padding & radius ───
              Opacity(
                opacity: inputsLocked ? 0.45 : 1.0,
                child: AbsorbPointer(
                  absorbing: inputsLocked,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Subject / Semester / 📐
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Subject Name',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _dark,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _dropdownField(
                                    value: _selectedSubject,
                                    items: _subjects,
                                    hint: 'Select',
                                    onChanged: (v) {
                                      if (v == null) return;
                                      final meta = _subjectMeta[v] ?? {};
                                      setState(() {
                                        _selectedSubject = v;
                                        _selectedSemester =
                                            meta['semester']?.isNotEmpty == true
                                            ? meta['semester']
                                            : null;
                                        _selectedAcademicYear =
                                            meta['academicYear']?.isNotEmpty ==
                                                true
                                            ? meta['academicYear']
                                            : null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Semester',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _dark,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _bgField,
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: Colors.black26),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _semesterDisplayLabel,
                                      style: GoogleFonts.dmMono(
                                        fontSize: 12,
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
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _openSetGrade,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _bgField,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.black38,
                                    width: 1,
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    '📐',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Tip banner
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF93C5FD),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 1),
                                child: Icon(
                                  Icons.lightbulb_outline,
                                  size: 14,
                                  color: Color.fromARGB(255, 172, 37, 235),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Tip: Leave the Marks field empty for assessments you haven\'t '
                                      'taken yet — the tracker will estimate how many marks you need '
                                      'to reach your target grade.',
                                      textAlign: TextAlign.justify,
                                      style: GoogleFonts.dmMono(
                                        fontSize: 10,
                                        color: const Color(0xFF1D4ED8),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '* Fullmarks and % are required. Leave Marks empty to see how much you need.',
                                      textAlign: TextAlign.justify,
                                      style: GoogleFonts.dmMono(
                                        fontSize: 10,
                                        color: const Color.fromARGB(255, 235, 37, 212),
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Column headers — spacing mirrors input row exactly
                        Row(
                          children: [
                            Expanded(flex: 3, child: _hdrText('Assessment')),
                            const SizedBox(width: 4),
                            Expanded(flex: 2, child: _hdrText('Marks')),
                            const SizedBox(width: 4),
                            Expanded(flex: 2, child: _hdrText('Fullmarks')),
                            const SizedBox(width: 4),
                            Expanded(flex: 2, child: _hdrText('%', center: true)),
                            const SizedBox(width: 4),
                            const SizedBox(width: 18), // matches close icon width
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Assessment rows
                        ...List.generate(_assessments.length, (i) {
                          final row  = _assessments[i];
                          final err  = _rowError(i);
                          final hint = _marksNeededHint(i);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _inputField(row['name']!),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      flex: 2,
                                      child: _numField(
                                        row['marks']!,
                                        hasError:
                                            err != null &&
                                            err.contains('exceed'),
                                        hint: '—',
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      flex: 2,
                                      child: _numField(
                                        row['fullmarks']!,
                                        hasError:
                                            err != null &&
                                            err.contains('Fullmarks'),
                                        center: true,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      flex: 2,
                                      child: _numField(
                                        row['percent']!,
                                        hasError:
                                            err != null && err.contains('%'),
                                        center: true,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => _removeRow(i),
                                      child: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                                if (err != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 2,
                                      top: 3,
                                    ),
                                    child: Text(
                                      err,
                                      style: GoogleFonts.dmMono(
                                        fontSize: 10,
                                        color: _gradeRed,
                                      ),
                                    ),
                                  ),
                                if (hint != null && err == null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 2,
                                      top: 3,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.info_outline,
                                          size: 10,
                                          color: _gradeYellow,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Need $hint for $_selectedTargetGrade',
                                          style: GoogleFonts.dmMono(
                                            fontSize: 10,
                                            color: _gradeYellow,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),

                        if (percentSum > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Icon(
                                  sumIs100
                                      ? Icons.check_circle
                                      : Icons.info_outline,
                                  size: 13,
                                  color:
                                      sumIs100 ? _gradeGreen : _gradeYellow,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  sumIs100
                                      ? '% total: 100 ✓'
                                      : '% total: ${percentSum.toStringAsFixed(0)} / 100',
                                  style: GoogleFonts.dmMono(
                                    fontSize: 11,
                                    color:
                                        sumIs100 ? _gradeGreen : _gradeYellow,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 8),

                        // Target Grade row
                        Row(
                          children: [
                            Text(
                              'Target Grade :',
                              style: GoogleFonts.dmMono(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _dark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _bgField,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.black38),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedTargetGrade,
                                  hint: Text(
                                    _gradeSettingsLoaded
                                        ? 'Select'
                                        : 'Set grade first',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 12,
                                      color: Colors.black38,
                                    ),
                                  ),
                                  style: GoogleFonts.dmMono(
                                    fontSize: 13,
                                    color: _dark,
                                  ),
                                  dropdownColor: Colors.white,
                                  icon: const Icon(
                                    Icons.arrow_drop_down,
                                    size: 20,
                                    color: _dark,
                                  ),
                                  items: _targetGradeOptions
                                      .map(
                                        (g) => DropdownMenuItem(
                                          value: g,
                                          child: Text(
                                            g,
                                            style: GoogleFonts.dmMono(
                                              fontSize: 13,
                                              color: _dark,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _gradeSettingsLoaded
                                      ? (v) {
                                          setState(
                                            () => _selectedTargetGrade = v,
                                          );
                                          _recalculate();
                                        }
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: _actionBtn(
                                label: 'RESET',
                                color: _tan,
                                onTap: _reset,
                              ),
                            ),
                            const SizedBox(width: 12),
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
                ),
              ),

              const SizedBox(height: 16),

              // Result cards
              Row(
                children: [
                  Expanded(
                    child: _resultCard(
                      label: 'Total (%):',
                      value: _percentSumValid
                          ? _totalPercentage.toStringAsFixed(1)
                          : '0',
                      grade: _percentSumValid && _totalPercentage > 0
                          ? _gradeLabelFor(_totalPercentage)
                          : null,
                      gradeColor: _gradeColor(_totalPercentage),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _resultCard(
                      label: 'Target Needed (%):',
                      value: _percentSumValid && _selectedTargetGrade != null
                          ? _targetNeededPct.toStringAsFixed(1)
                          : '0',
                      grade: null,
                      gradeColor: _gradeYellow,
                      valueColor:
                          _targetNeededPct <= 0 &&
                              _selectedTargetGrade != null &&
                              _percentSumValid
                          ? _gradeGreen
                          : null,
                      subLabel:
                          _targetNeededPct <= 0 &&
                              _selectedTargetGrade != null &&
                              _percentSumValid
                          ? 'Achieved! 🎉'
                          : null,
                    ),
                  ),
                ],
              ),

              // Impossibility warning
              if (targetImpossible) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _gradeRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _gradeRed.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.block, size: 16, color: _gradeRed),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Grade $_selectedTargetGrade is no longer achievable.',
                              style: GoogleFonts.dmMono(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _gradeRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Even scoring full marks on all remaining assessments, '
                        'your maximum possible total is ${_maxAchievable.toStringAsFixed(1)}%.',
                        style: GoogleFonts.dmMono(
                          fontSize: 11,
                          color: _gradeRed.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.emoji_events_outlined,
                            size: 14,
                            color: Color.fromARGB(255, 147, 114, 15),
                          ),
                          const SizedBox(width: 6),
                          RichText(
                            text: TextSpan(
                              style: GoogleFonts.dmMono(
                                fontSize: 12,
                                color: _dark,
                              ),
                              children: [
                                const TextSpan(
                                  text: 'Best grade you can still reach: ',
                                ),
                                TextSpan(
                                  text: _nearestGrade ?? '—',
                                  style: GoogleFonts.dmMono(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: const Color.fromARGB(
                                      255,
                                      5,
                                      157,
                                      251,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveResult,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF292929),
                    disabledBackgroundColor: Colors.black38,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
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

              // ── Saved Results header — calendar section style ────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Saved Results',
                    style: GoogleFonts.dmMono(
                      fontSize: 20,
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
                          horizontal: 12,
                          vertical: 8,
                        ),
                        hintText: 'Search...',
                        hintStyle: GoogleFonts.dmMono(
                          fontSize: 12,
                          color: Colors.black38,
                        ),
                        suffixIcon: const Icon(
                          Icons.search,
                          size: 16,
                          color: Colors.black45,
                        ),
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
              const SizedBox(height: 16),

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
                        child: CircularProgressIndicator(
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    );
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

                  if (docs.isEmpty)
                    return _emptyState('No results match your search');

                  return Column(
                    children: docs
                        .map(
                          (doc) => _SavedCard(
                            docId: doc.id,
                            data: doc.data() as Map<String, dynamic>,
                            gradeRanges: _gradeRanges,
                            onDelete: _deleteResult,
                            onUpdate: _updateSavedAssessments,
                            gradeLabelFor: _gradeLabelFor,
                            gradeColorFn: _gradeColor,
                          ),
                        )
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

  // ── Widget helpers ───────────────────────────────────────────────

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
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _dark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.dmMono(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
                color: valueColor ?? _dark,
              ),
            ),
            if (subLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                subLabel,
                style: GoogleFonts.dmMono(
                  fontSize: 12,
                  color: gradeColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (grade != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: gradeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Current Grade: $grade',
                  style: GoogleFonts.dmMono(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _emptyState(String msg) => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: _bgCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black, width: 2),
    ),
    child: Center(
      child: Text(
        msg,
        style: GoogleFonts.dmMono(fontSize: 13, color: Colors.grey),
      ),
    ),
  );

  Widget _hdrText(String text, {bool center = false}) => Text(
    text,
    textAlign: center ? TextAlign.center : TextAlign.start,
    style: GoogleFonts.dmMono(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: _dark,
    ),
  );

  InputDecoration _fieldDeco({bool hasError = false, String? hint}) =>
      InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle:
            GoogleFonts.dmMono(fontSize: 11, color: Colors.black26),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        filled: true,
        fillColor: _bgField,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: hasError ? _gradeRed : Colors.black38),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: hasError ? _gradeRed : Colors.black26),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: hasError ? _gradeRed : Colors.black87),
        ),
      );

  Widget _inputField(TextEditingController ctrl) => TextField(
    controller: ctrl,
    style: GoogleFonts.dmMono(fontSize: 12),
    decoration: _fieldDeco(),
  );

  Widget _numField(
    TextEditingController ctrl, {
    bool hasError = false,
    String? hint,
    bool center = false,
  }) =>
      TextField(
        controller: ctrl,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: GoogleFonts.dmMono(fontSize: 12),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        decoration: _fieldDeco(hasError: hasError, hint: hint),
      );

  Widget _dropdownField({
    required String? value,
    required List<String> items,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) =>
      Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _bgField,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black26),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            hint: Text(
              hint,
              style:
                  GoogleFonts.dmMono(fontSize: 12, color: Colors.black38),
            ),
            style: GoogleFonts.dmMono(fontSize: 12, color: _dark),
            dropdownColor: Colors.white,
            icon:
                const Icon(Icons.arrow_drop_down, size: 18, color: _dark),
            items: items
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(
                      s,
                      style:
                          GoogleFonts.dmMono(fontSize: 12, color: _dark),
                    ),
                  ),
                )
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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black, width: 2),
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

// ─────────────────────────────────────────────────────────────────────────────
//  _SavedCard  (visual style updated to match CalendarScreen)
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

  final String docId;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> gradeRanges;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(
    String,
    List<Map<String, dynamic>>, {
    required List<Map<String, dynamic>> gradeRanges,
    required String targetGrade,
  }) onUpdate;
  final String Function(double) gradeLabelFor;
  final Color Function(double) gradeColorFn;

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

  String? _editTargetGrade;

  List<String> get _gradeOptions =>
      widget.gradeRanges.map((r) => r['label'] as String).toList();

  @override
  void initState() {
    super.initState();
    _initEditState();
  }

  void _initEditState() {
    _editAssessments = List<Map<String, dynamic>>.from(
      widget.data['assessments'] ?? [],
    );

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

    final saved = (widget.data['targetGrade'] ?? '').toString();
    _editTargetGrade = saved.isNotEmpty ? saved : null;
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

  String? _editRowError(int i) {
    final marks    = double.tryParse(_editMarksCtrl[i].text.trim());
    final fullmarks= double.tryParse(_editFullmarksCtrl[i].text.trim()) ?? 0;
    final percent  = double.tryParse(_editPercentCtrl[i].text.trim()) ?? 0;
    if (marks != null && fullmarks > 0 && marks > fullmarks)
      return 'Marks > fullmarks';
    if (percent > 0 && fullmarks <= 0) return 'Fullmarks required';
    if (fullmarks > 0 && percent <= 0) return '% required';
    return null;
  }

  bool get _hasEditErrors =>
      List.generate(_editAssessments.length, _editRowError)
          .any((e) => e != null);

  double get _editPercentSum {
    double s = 0;
    for (final c in _editPercentCtrl)
      s += double.tryParse(c.text.trim()) ?? 0;
    return s;
  }

  bool get _editSumIs100 => (_editPercentSum - 100).abs() < 0.01;

  bool get _canSaveEdits =>
      !_hasEditErrors && _editSumIs100 && _editTargetGrade != null;

  Future<void> _saveEdits() async {
    if (_hasEditErrors) {
      _showSnack('Fix row errors before saving.');
      return;
    }
    if (!_editSumIs100) {
      _showSnack(
        '% must total 100 (currently ${_editPercentSum.toStringAsFixed(0)}).',
      );
      return;
    }
    if (_editTargetGrade == null) {
      _showSnack('Please select a target grade.');
      return;
    }

    setState(() => _isSaving = true);

    final updated = <Map<String, dynamic>>[];
    for (int i = 0; i < _editAssessments.length; i++) {
      final a        = Map<String, dynamic>.from(_editAssessments[i]);
      final marks    = double.tryParse(_editMarksCtrl[i].text.trim()) ?? 0;
      final fullmarks= double.tryParse(_editFullmarksCtrl[i].text.trim()) ?? 0;
      final percent  = double.tryParse(_editPercentCtrl[i].text.trim()) ?? 0;
      a['marks']        = marks;
      a['fullmarks']    = fullmarks;
      a['percent']      = percent;
      a['contribution'] =
          fullmarks > 0 ? (marks / fullmarks) * percent : 0.0;
      updated.add(a);
    }

    await widget.onUpdate(
      widget.docId,
      updated,
      gradeRanges: widget.gradeRanges,
      targetGrade: _editTargetGrade!,
    );

    if (mounted)
      setState(() {
        _isSaving  = false;
        _isEditing = false;
      });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.dmMono(fontSize: 12)),
        backgroundColor: _gradeRed,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String? _savedNearestGrade(
    List<Map<String, dynamic>> assessments,
    String targetGrade,
    double currentTotal,
  ) {
    if (widget.gradeRanges.isEmpty) return null;
    final range = widget.gradeRanges.firstWhere(
      (r) => r['label'] == targetGrade,
      orElse: () => {},
    );
    if (range.isEmpty) return null;
    final targetMin = (range['min'] as num).toDouble();

    double maxPossible = 0;
    for (final a in assessments) {
      final marks        = (a['marks'] ?? 0).toDouble();
      final fullmarks    = (a['fullmarks'] ?? 0).toDouble();
      final percent      = (a['percent'] ?? 0).toDouble();
      if (fullmarks <= 0 || percent <= 0) continue;
      final contribution = (a['contribution'] ?? 0).toDouble();
      final isPending =
          marks <= 0 && contribution <= 0 && fullmarks > 0;
      if (isPending) {
        maxPossible += percent;
      } else {
        maxPossible +=
            fullmarks > 0 ? (marks / fullmarks) * percent : 0;
      }
    }

    if (maxPossible >= targetMin) return null;

    final sorted = List<Map<String, dynamic>>.from(widget.gradeRanges)
      ..sort((a, b) => (b['min'] as num).compareTo(a['min'] as num));
    for (final r in sorted) {
      if (maxPossible >= (r['min'] as num).toDouble()) {
        return r['label'] as String;
      }
    }
    return widget.gradeRanges.last['label'] as String;
  }

  @override
  Widget build(BuildContext context) {
    final subject      = widget.data['subject'] ?? '';
    final semester     = (widget.data['semester'] ?? '').toString();
    final academicYear =
        (widget.data['academicYear'] ?? widget.data['year'] ?? '').toString();
    final total        = (widget.data['totalPercentage'] ?? 0).toDouble();
    final targetGrade  = (widget.data['targetGrade'] ?? '').toString();
    final targetNeeded = (widget.data['targetNeeded'] ?? 0).toDouble();
    final assessments  = List<Map<String, dynamic>>.from(
      widget.data['assessments'] ?? [],
    );
    final savedAt   = (widget.data['savedAt'] as Timestamp?)?.toDate();
    final updatedAt = (widget.data['updatedAt'] as Timestamp?)?.toDate();

    final gradeLabel = widget.gradeLabelFor(total);
    final gradeClr   = widget.gradeColorFn(total);

    final shortYear = academicYear.isNotEmpty
        ? _GradeCalculatorScreenState.shortenAcademicYear(academicYear)
        : '';
    final semLabel = semester.isNotEmpty
        ? 'Sem $semester${shortYear.isNotEmpty ? ', $shortYear' : ''}'
        : '—';

    double targetMin = 0;
    double targetMax = 100;
    if (targetGrade.isNotEmpty && widget.gradeRanges.isNotEmpty) {
      final r = widget.gradeRanges.firstWhere(
        (r) => r['label'] == targetGrade,
        orElse: () => {},
      );
      if (r.isNotEmpty) {
        targetMin = (r['min'] as num).toDouble();
        targetMax = (r['max'] as num).toDouble();
      }
    }
    final progressFraction =
        targetMin > 0 ? (total / targetMin).clamp(0.0, 1.0) : 0.0;

    final nearestGrade = targetGrade.isNotEmpty
        ? _savedNearestGrade(assessments, targetGrade, total)
        : null;

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
          // ── Header ──────────────────────────────────────────────
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
                        'SUBJECT: ${subject.toString().toUpperCase()}',
                        style: GoogleFonts.dmMono(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '($semLabel'
                        '${savedAt != null ? '  •  ${savedAt.day}/${savedAt.month}/${savedAt.year}' : ''})',
                        style: GoogleFonts.dmMono(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      if (updatedAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Updated: ${updatedAt.day}/${updatedAt.month}/${updatedAt.year}',
                          style: GoogleFonts.dmMono(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      if (targetGrade.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Target: $targetGrade',
                          style: GoogleFonts.dmMono(
                            color: _tan,
                            fontSize: 11,
                          ),
                        ),
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
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            _isEditing ? Icons.close : Icons.edit_outlined,
                            color: _isEditing ? Colors.grey : _tan,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isEditing ? 'Cancel Edit' : 'Edit Result',
                            style: GoogleFonts.dmMono(
                              color: _isEditing ? Colors.grey : _dark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_outline,
                            color: _gradeRed,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: GoogleFonts.dmMono(color: _gradeRed),
                          ),
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

          // Target Grade editor (edit mode)
          if (_isEditing) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Target Grade:',
                    style: GoogleFonts.dmMono(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 36,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _editTargetGrade == null
                              ? _gradeRed.withOpacity(0.6)
                              : Colors.white24,
                          width: 1.2,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _editTargetGrade,
                          isExpanded: true,
                          hint: Text(
                            'Select target *',
                            style: GoogleFonts.dmMono(
                              fontSize: 11,
                              color: _gradeRed.withOpacity(0.7),
                            ),
                          ),
                          style: GoogleFonts.dmMono(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                          dropdownColor: const Color(0xFF2A2A2A),
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: Colors.white54,
                          ),
                          items: _gradeOptions
                              .map(
                                (g) => DropdownMenuItem(
                                  value: g,
                                  child: Text(
                                    g,
                                    style: GoogleFonts.dmMono(
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _editTargetGrade = v),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Column headers
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: _isEditing
                ? Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Assessment',
                          style: GoogleFonts.dmMono(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Marks',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmMono(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Fullmarks',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmMono(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '%',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmMono(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Assessment:',
                        style: GoogleFonts.dmMono(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        'Contribution (%):',
                        style: GoogleFonts.dmMono(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
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
              final errMsg    = _editRowError(i);
              final hasMarksErr = errMsg != null && errMsg.contains('>');
              final hasFmErr    = errMsg != null && errMsg.contains('Fullmarks');
              final hasPctErr   = errMsg != null && errMsg.contains('%');

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            name,
                            style: GoogleFonts.dmMono(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: _editField(
                            _editMarksCtrl[i],
                            hasError: hasMarksErr,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: _editField(
                            _editFullmarksCtrl[i],
                            hasError: hasFmErr,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: _editField(
                            _editPercentCtrl[i],
                            hasError: hasPctErr,
                          ),
                        ),
                      ],
                    ),
                    if (errMsg != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          errMsg,
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            color: _gradeRed,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }

            // View mode row
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.dmMono(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        contribution > 0
                            ? '${contribution.toStringAsFixed(1)}%'
                            : '—',
                        style: GoogleFonts.dmMono(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Builder(
                    builder: (_) {
                      final marks    = (a['marks'] ?? 0).toDouble();
                      final fullmarks= (a['fullmarks'] ?? 0).toDouble();
                      final percent  = (a['percent'] ?? 0).toDouble();
                      final mNeeded  =
                          (a['marksNeededForTarget'] ?? -1).toDouble();
                      final isPending= mNeeded >= 0;

                      return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Text(
                              isPending
                                  ? '— / ${fullmarks.toStringAsFixed(0)}'
                                  : '${_fmt(marks)} / ${fullmarks.toStringAsFixed(0)}',
                              style: GoogleFonts.dmMono(
                                fontSize: 10,
                                color: isPending
                                    ? Colors.white38
                                    : Colors.white54,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 1,
                              height: 10,
                              color: Colors.white24,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${percent.toStringAsFixed(0)}% weight',
                              style: GoogleFonts.dmMono(
                                fontSize: 10,
                                color: Colors.white38,
                              ),
                            ),
                            if (isPending) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 1,
                                height: 10,
                                color: Colors.white24,
                              ),
                              const SizedBox(width: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 10,
                                    color: _gradeYellow,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Need ${mNeeded.toStringAsFixed(1)} / ${fullmarks.toStringAsFixed(0)} for $targetGrade',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 9,
                                      color: _gradeYellow,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }),

          // % sum indicator (edit mode)
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    _editSumIs100
                        ? Icons.check_circle
                        : Icons.info_outline,
                    size: 12,
                    color: _editSumIs100 ? _gradeGreen : _gradeYellow,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _editSumIs100
                        ? '% total: 100 ✓'
                        : '% total: ${_editPercentSum.toStringAsFixed(0)} / 100',
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      color:
                          _editSumIs100 ? _gradeGreen : _gradeYellow,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Save changes button
          if (_isEditing)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _isSaving || !_canSaveEdits ? null : _saveEdits,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _tan,
                    disabledBackgroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Save Changes',
                          style: GoogleFonts.dmMono(
                            fontWeight: FontWeight.bold,
                            color: _dark,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
            ),

          const SizedBox(height: 10),

          // Final total footer
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: gradeClr.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: gradeClr.withOpacity(0.6),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                'FINAL TOTAL: ${total.toStringAsFixed(1)}%  •  Grade $gradeLabel',
                style: GoogleFonts.dmMono(
                  color: gradeClr,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),

          // Target progress section
          if (targetGrade.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: nearestGrade != null
                    ? _gradeRed.withOpacity(0.10)
                    : targetNeeded <= 0
                    ? _gradeGreen.withOpacity(0.10)
                    : _gradeYellow.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: nearestGrade != null
                      ? _gradeRed.withOpacity(0.45)
                      : targetNeeded <= 0
                      ? _gradeGreen.withOpacity(0.5)
                      : _gradeYellow.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        nearestGrade != null
                            ? Icons.block
                            : targetNeeded <= 0
                            ? Icons.emoji_events
                            : Icons.trending_up,
                        size: 14,
                        color: nearestGrade != null
                            ? _gradeRed
                            : targetNeeded <= 0
                            ? _gradeGreen
                            : _gradeYellow,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          nearestGrade != null
                              ? 'Grade $targetGrade no longer achievable'
                              : targetNeeded <= 0
                              ? 'Target $targetGrade: Achieved! 🎉'
                              : 'Target: $targetGrade',
                          style: GoogleFonts.dmMono(
                            color: nearestGrade != null
                                ? _gradeRed
                                : targetNeeded <= 0
                                ? _gradeGreen
                                : _gradeYellow,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (nearestGrade != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _gradeYellow.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _gradeYellow.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            'Best: $nearestGrade',
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              color: _gradeYellow,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),

                  if (targetNeeded > 0 || nearestGrade != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressFraction,
                        minHeight: 7,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          nearestGrade != null
                              ? _gradeRed
                              : _gradeYellow,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _progressStat(
                          label: 'Earned',
                          value: '${total.toStringAsFixed(1)}%',
                          color: Colors.white70,
                        ),
                        _progressStat(
                          label: 'Still need',
                          value: nearestGrade != null
                              ? 'N/A'
                              : '+${targetNeeded.toStringAsFixed(1)}%',
                          color: nearestGrade != null
                              ? _gradeRed
                              : _gradeYellow,
                        ),
                        _progressStat(
                          label: 'Target min',
                          value: '${targetMin.toStringAsFixed(0)}%',
                          color: Colors.white54,
                        ),
                        _progressStat(
                          label: 'Progress',
                          value:
                              '${(progressFraction * 100).toStringAsFixed(0)}%',
                          color: nearestGrade != null
                              ? _gradeRed
                              : _gradeYellow,
                        ),
                      ],
                    ),
                    if (nearestGrade != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Even with perfect scores on remaining assessments, '
                        'the best you can achieve is Grade $nearestGrade.',
                        style: GoogleFonts.dmMono(
                          fontSize: 10,
                          color: _gradeRed.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),

          // How-to-reach breakdown
          Builder(
            builder: (_) {
              final pending = assessments.where(
                (a) =>
                    (a['marksNeededForTarget'] ?? -1).toDouble() >= 0 &&
                    (a['fullmarks'] ?? 0) > 0,
              );
              if (pending.isEmpty || targetGrade.isEmpty) {
                return const SizedBox.shrink();
              }

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
                    Row(
                      children: [
                        const Icon(
                          Icons.checklist_outlined,
                          size: 13,
                          color: _gradeYellow,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'How to reach $targetGrade:',
                          style: GoogleFonts.dmMono(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...pending.map((a) {
                      final mNeeded =
                          (a['marksNeededForTarget'] as num).toDouble();
                      final fm    = (a['fullmarks'] as num).toDouble();
                      final pct   = (a['percent'] as num? ?? 0).toDouble();
                      final aName = (a['name'] ?? '').toString();
                      final contributionIfScored =
                          fm > 0 ? (mNeeded / fm) * pct : 0.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.arrow_right,
                                  color: _gradeYellow,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: GoogleFonts.dmMono(
                                        fontSize: 11,
                                        color: Colors.white70,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: aName.isNotEmpty
                                              ? '$aName:  '
                                              : 'Assessment:  ',
                                        ),
                                        TextSpan(
                                          text:
                                              '${mNeeded.toStringAsFixed(1)} / ${fm.toStringAsFixed(0)} marks',
                                          style: GoogleFonts.dmMono(
                                            fontWeight: FontWeight.bold,
                                            color: _gradeYellow,
                                            fontSize: 11,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              '  → +${contributionIfScored.toStringAsFixed(1)}% to total',
                                          style: GoogleFonts.dmMono(
                                            fontSize: 10,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 18,
                                top: 3,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: fm > 0
                                      ? (mNeeded / fm).clamp(0.0, 1.0)
                                      : 0.0,
                                  minHeight: 4,
                                  backgroundColor: Colors.white10,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        _gradeYellow,
                                      ),
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
            },
          ),
        ],
      ),
    );
  }

  Widget _progressStat({
    required String label,
    required String value,
    required Color color,
  }) =>
      Column(
        children: [
          Text(
            value,
            style: GoogleFonts.dmMono(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 9,
              color: Colors.white38,
            ),
          ),
        ],
      );

  Widget _editField(
    TextEditingController ctrl, {
    bool hasError = false,
  }) =>
      TextField(
        controller: ctrl,
        onChanged: (_) => setState(() {}),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        textAlign: TextAlign.center,
        style: GoogleFonts.dmMono(
          fontSize: 11,
          color: hasError ? _gradeRed : Colors.white,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          filled: true,
          fillColor: Colors.white12,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: hasError ? _gradeRed : Colors.white24,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: hasError ? _gradeRed : Colors.white24,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: hasError ? _gradeRed : Colors.white70,
            ),
          ),
        ),
      );
}