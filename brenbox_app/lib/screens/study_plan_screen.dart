import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../app_preferences.dart';
import '../services/notification_scheduler.dart';

// ignore_for_file: use_build_context_synchronously

// ─────────────────────────────────────────────────────────────────────────────
// ADD STUDY PLAN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class AddStudyPlanScreen extends StatefulWidget {
  final String subjectName;
  final Map<String, dynamic> exam;
  final String examId;

  const AddStudyPlanScreen({
    Key? key,
    required this.subjectName,
    required this.exam,
    required this.examId,
  }) : super(key: key);

  @override
  State<AddStudyPlanScreen> createState() => _AddStudyPlanScreenState();
}

class _AddStudyPlanScreenState extends State<AddStudyPlanScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _planNameController = TextEditingController();
  final List<TextEditingController> _items = [];
  bool _isSaving = false;

  static const Color _red = Color(0xFFB90000);
  static const Color _green = Color(0xFF34A853);
  static const Color _yellow = Color(0xFF9AB900);

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 3; i++) _items.add(TextEditingController());
  }

  @override
  void dispose() {
    _planNameController.dispose();
    for (final c in _items) c.dispose();
    super.dispose();
  }

  void _addItem() => setState(() => _items.add(TextEditingController()));

  void _removeItem(int i) {
    if (_items.length <= 1) return;
    setState(() {
      _items[i].dispose();
      _items.removeAt(i);
    });
  }

  Future<void> _save() async {
    final planName = _planNameController.text.trim();
    if (planName.isEmpty) {
      _snack('Please enter a plan name', error: true);
      return;
    }
    final checklist = _items
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .map((t) => {'text': t, 'done': false})
        .toList();
    if (checklist.isEmpty) {
      _snack('Add at least one checklist item', error: true);
      return;
    }

    setState(() => _isSaving = true);
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('study_plans').add({
        'userId': user.uid,
        'examId': widget.examId,
        'examName': widget.exam['examName'] ?? 'Untitled',
        'examType': (widget.exam['type'] ?? 'EXAM').toString().toUpperCase(),
        'subjectName': widget.subjectName,
        'planName': planName,
        'checklist': checklist,
        // Use startTime (full exam datetime) so the countdown and notifications
        // count down to the actual exam start, not midnight of the exam day.
        'dueDate': widget.exam['startTime'] ?? widget.exam['examDate'],
        'createdAt': Timestamp.now(),
        'status': 'incomplete',
      });
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _snack('Failed to save. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.dmMono()),
      backgroundColor: error ? _red : _green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final examDate = (widget.exam['examDate'] as Timestamp?)?.toDate();
    final examType = (widget.exam['type'] ?? 'EXAM').toString().toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'ADD STUDY PLAN',
          style: GoogleFonts.dmMono(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Linked exam banner ────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _yellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _yellow, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, color: _yellow, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$examType  •  ${widget.exam['examName'] ?? ''}${examDate != null ? '  •  ${DateFormat('dd MMM yyyy').format(examDate)}' : ''}',
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _yellow,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Plan Name ─────────────────────────────────────
            _label('Plan Name'),
            const SizedBox(height: 8),
            _field(_planNameController, 'e.g. Final Exam Study Plan'),
            const SizedBox(height: 24),

            // ── Checklist ─────────────────────────────────────
            _label('Checklist'),
            const SizedBox(height: 12),
            ..._items.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(child: _field(e.value, 'Item ${e.key + 1}')),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _removeItem(e.key),
                    child: Container(
                      width: 46,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            )),

            // ── Add item ──────────────────────────────────────
            GestureDetector(
              onTap: _addItem,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.chipBg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(height: 32),

            // ── Action buttons ────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border(context), width: 2),
                      ),
                      child: Text(
                        'Cancel',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmMono(
                          fontWeight: FontWeight.bold,
                          color: AppColors.text(context),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _isSaving ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isSaving
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Save Task',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.dmMono(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: GoogleFonts.dmMono(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppColors.text(context),
        ),
      );

  Widget _field(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        style: GoogleFonts.dmMono(fontSize: 14, color: AppColors.text(context)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.dmMono(fontSize: 14, color: AppColors.subtext(context)),
          filled: true,
          fillColor: AppColors.input(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border(context), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border(context), width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border(context), width: 2),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// STUDY PLAN DETAIL SCREEN  (view + toggle checklist)
// ─────────────────────────────────────────────────────────────────────────────

class StudyPlanDetailScreen extends StatefulWidget {
  final String planId;
  final Map<String, dynamic> data;

  const StudyPlanDetailScreen({
    Key? key,
    required this.planId,
    required this.data,
  }) : super(key: key);

  @override
  State<StudyPlanDetailScreen> createState() => _StudyPlanDetailScreenState();
}

class _StudyPlanDetailScreenState extends State<StudyPlanDetailScreen> {
  final _firestore = FirebaseFirestore.instance;
  late List<Map<String, dynamic>> _checklist;
  late String _planName;

  static const Color _red = Color(0xFFB90000);
  static const Color _green = Color(0xFF34A853);
  static const Color _yellow = Color(0xFF9AB900);

  @override
  void initState() {
    super.initState();
    _planName = widget.data['planName'] ?? 'Study Plan';
    _checklist = List<Map<String, dynamic>>.from(
      (widget.data['checklist'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  Future<void> _openEdit() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditStudyPlanScreen(
          planId: widget.planId,
          data: widget.data,
          currentPlanName: _planName,
          currentChecklist: _checklist,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _planName = result['planName'] as String? ?? _planName;
        _checklist = List<Map<String, dynamic>>.from(
          (result['checklist'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map)),
        );
      });
    }
  }

  Future<void> _toggle(int i) async {
    setState(() => _checklist[i]['done'] = !(_checklist[i]['done'] as bool));
    final allDone = _checklist.every((e) => e['done'] == true);
    await _firestore.collection('study_plans').doc(widget.planId).update({
      'checklist': _checklist,
      'status': allDone ? 'complete' : 'incomplete',
    });
    if (allDone) {
      NotificationScheduler().rescheduleAllNotifications(forceFull: true);
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmDeleteDialog(
      context,
      title: 'Delete Study Plan',
      message: 'Are you sure you want to delete this study plan? This cannot be undone.',
    );
    if (!confirmed) return;
    await _firestore.collection('study_plans').doc(widget.planId).delete();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dueDate = (widget.data['dueDate'] as Timestamp?)?.toDate();
    final examType = widget.data['examType'] ?? 'EXAM';
    final doneCount = _checklist.where((e) => e['done'] == true).length;
    final total = _checklist.length;
    final progress = total > 0 ? doneCount / total : 0.0;
    final isComplete = doneCount == total && total > 0;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'STUDY PLAN',
          style: GoogleFonts.dmMono(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_outlined, color: AppColors.text(context)),
            onPressed: _openEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: _red),
            onPressed: _delete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Plan name + status badge ──────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _planName,
                    style: GoogleFonts.dmMono(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text(context),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isComplete
                        ? _green.withValues(alpha: 0.12)
                        : _red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isComplete ? _green : _red,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    isComplete ? 'COMPLETE' : 'INCOMPLETE',
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isComplete ? _green : _red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Linked exam chip ──────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _yellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _yellow, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_rounded, color: _yellow, size: 13),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '$examType  •  ${widget.data['examName'] ?? ''}${dueDate != null ? '  •  ${DateFormat('dd MMM yyyy').format(dueDate)}' : ''}',
                      style: GoogleFonts.dmMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _yellow,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Progress ──────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: AppColors.border(context),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isComplete ? _green : _red,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$doneCount / $total',
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.subtext(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Checklist items ───────────────────────────────
            ..._checklist.asMap().entries.map((e) {
              final done = e.value['done'] == true;
              return GestureDetector(
                onTap: () => _toggle(e.key),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: done ? _green : AppColors.border(context),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done ? _green : Colors.transparent,
                          border: Border.all(
                            color: done ? _green : AppColors.subtext(context),
                            width: 2,
                          ),
                        ),
                        child: done
                            ? const Icon(Icons.check, color: Colors.white, size: 13)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.value['text'] ?? '',
                          style: GoogleFonts.dmMono(
                            fontSize: 13,
                            color: done
                                ? AppColors.subtext(context)
                                : AppColors.text(context),
                            decoration: done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT STUDY PLAN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class EditStudyPlanScreen extends StatefulWidget {
  final String planId;
  final Map<String, dynamic> data;
  final String currentPlanName;
  final List<Map<String, dynamic>> currentChecklist;

  const EditStudyPlanScreen({
    Key? key,
    required this.planId,
    required this.data,
    required this.currentPlanName,
    required this.currentChecklist,
  }) : super(key: key);

  @override
  State<EditStudyPlanScreen> createState() => _EditStudyPlanScreenState();
}

class _EditStudyPlanScreenState extends State<EditStudyPlanScreen> {
  final _firestore = FirebaseFirestore.instance;
  late final TextEditingController _planNameController;
  late final List<TextEditingController> _items;
  bool _isSaving = false;

  static const Color _red = Color(0xFFB90000);
  static const Color _green = Color(0xFF34A853);
  static const Color _yellow = Color(0xFF9AB900);

  @override
  void initState() {
    super.initState();
    _planNameController = TextEditingController(text: widget.currentPlanName);
    _items = widget.currentChecklist
        .map((e) => TextEditingController(text: e['text'] as String? ?? ''))
        .toList();
    if (_items.isEmpty) _items.add(TextEditingController());
  }

  @override
  void dispose() {
    _planNameController.dispose();
    for (final c in _items) c.dispose();
    super.dispose();
  }

  void _addItem() => setState(() => _items.add(TextEditingController()));

  void _removeItem(int i) {
    if (_items.length <= 1) return;
    setState(() {
      _items[i].dispose();
      _items.removeAt(i);
    });
  }

  Future<void> _save() async {
    final planName = _planNameController.text.trim();
    if (planName.isEmpty) {
      _snack('Please enter a plan name', error: true);
      return;
    }
    final newTexts = _items.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (newTexts.isEmpty) {
      _snack('Add at least one checklist item', error: true);
      return;
    }

    // Preserve done state for items that match existing text, reset new ones.
    final oldChecklist = widget.currentChecklist;
    final updatedChecklist = newTexts.map((text) {
      final existing = oldChecklist.firstWhere(
        (e) => e['text'] == text,
        orElse: () => {'text': text, 'done': false},
      );
      return {'text': text, 'done': existing['done'] ?? false};
    }).toList();

    setState(() => _isSaving = true);
    try {
      await _firestore.collection('study_plans').doc(widget.planId).update({
        'planName': planName,
        'checklist': updatedChecklist,
        'status': updatedChecklist.every((e) => e['done'] == true) ? 'complete' : 'incomplete',
      });
      if (mounted) {
        Navigator.pop(context, {'planName': planName, 'checklist': updatedChecklist});
      }
    } catch (_) {
      _snack('Failed to save. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.dmMono()),
      backgroundColor: error ? _red : _green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dueDate = (widget.data['dueDate'] as Timestamp?)?.toDate();
    final examType = (widget.data['examType'] ?? 'EXAM').toString().toUpperCase();
    final examName = widget.data['examName'] ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'EDIT STUDY PLAN',
          style: GoogleFonts.dmMono(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Linked exam banner ────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _yellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _yellow, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, color: _yellow, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$examType  •  $examName${dueDate != null ? '  •  ${DateFormat('dd MMM yyyy').format(dueDate)}' : ''}',
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _yellow,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Plan Name ─────────────────────────────────────
            _label('Plan Name'),
            const SizedBox(height: 8),
            _field(_planNameController, 'e.g. Final Exam Study Plan'),
            const SizedBox(height: 24),

            // ── Checklist ─────────────────────────────────────
            _label('Checklist'),
            const SizedBox(height: 12),
            ..._items.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(child: _field(e.value, 'Item ${e.key + 1}')),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _removeItem(e.key),
                    child: Container(
                      width: 46,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            )),

            // ── Add item ──────────────────────────────────────
            GestureDetector(
              onTap: _addItem,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.chipBg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(height: 32),

            // ── Action buttons ────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border(context), width: 2),
                      ),
                      child: Text(
                        'Cancel',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmMono(
                          fontWeight: FontWeight.bold,
                          color: AppColors.text(context),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _isSaving ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isSaving
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Save Changes',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.dmMono(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: GoogleFonts.dmMono(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppColors.text(context),
        ),
      );

  Widget _field(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        style: GoogleFonts.dmMono(fontSize: 14, color: AppColors.text(context)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.dmMono(fontSize: 14, color: AppColors.subtext(context)),
          filled: true,
          fillColor: AppColors.input(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border(context), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border(context), width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border(context), width: 2),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED COUNTDOWN BANNER — days · hours · minutes · seconds display
// ─────────────────────────────────────────────────────────────────────────────

class StudyPlanCountdownBanner extends StatefulWidget {
  final DateTime? dueDate;
  final Color accentColor;
  /// compact = true → plain row, no background box, smaller numbers
  final bool compact;
  const StudyPlanCountdownBanner({super.key, this.dueDate, required this.accentColor, this.compact = false});

  @override
  State<StudyPlanCountdownBanner> createState() => _StudyPlanCountdownBannerState();
}

class _StudyPlanCountdownBannerState extends State<StudyPlanCountdownBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.dueDate != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final due = widget.dueDate;
    final c   = widget.accentColor;
    if (due == null) return const SizedBox();

    final diff    = due.difference(DateTime.now());
    final overdue = diff.isNegative;

    if (widget.compact) {
      final color = overdue ? const Color(0xFFB90000) : c;
      final String text;
      if (overdue) {
        text = 'UNFINISHED';
      } else {
        final d = diff.inDays;
        final h = diff.inHours % 24;
        final m = diff.inMinutes % 60;
        final s = diff.inSeconds % 60;
        text = '${d}d ${h.toString().padLeft(2, '0')}h '
               '${m.toString().padLeft(2, '0')}m '
               '${s.toString().padLeft(2, '0')}s';
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(overdue ? Icons.cancel : Icons.schedule, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              text,
              style: GoogleFonts.dmMono(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      );
    }

    if (overdue) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFB90000).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            'UNFINISHED',
            style: GoogleFonts.dmMono(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFB90000)),
          ),
        ),
      );
    }

    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _unit('$d',                          'DAYS', c),
          _sep(c),
          _unit(h.toString().padLeft(2, '0'), 'HRS',  c),
          _sep(c),
          _unit(m.toString().padLeft(2, '0'), 'MIN',  c),
          _sep(c),
          _unit(s.toString().padLeft(2, '0'), 'SEC',  c),
        ],
      ),
    );
  }

  Widget _unit(String val, String label, Color c) {
    final numSize   = widget.compact ? 16.0 : 22.0;
    final labelSize = widget.compact ?  7.0 :  8.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(val,   style: GoogleFonts.dmMono(fontSize: numSize,   fontWeight: FontWeight.bold, color: c)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.dmMono(fontSize: labelSize, fontWeight: FontWeight.bold, color: c.withValues(alpha: 0.65))),
      ],
    );
  }

  Widget _sep(Color c) => Padding(
    padding: EdgeInsets.only(bottom: widget.compact ? 8.0 : 12.0),
    child: Text(':', style: GoogleFonts.dmMono(
      fontSize: widget.compact ? 15.0 : 20.0,
      fontWeight: FontWeight.bold,
      color: c.withValues(alpha: 0.35),
    )),
  );
}
