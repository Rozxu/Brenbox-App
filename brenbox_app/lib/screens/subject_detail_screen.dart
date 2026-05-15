import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../tasks/edit_class_screen.dart';
import '../tasks/edit_task_screen.dart';
import '../tasks/edit_exam_screen.dart';
import 'study_group_screen.dart';
import '../app_preferences.dart';

// Save this file as: lib/screens/subject_detail_screen.dart

class SubjectDetailScreen extends StatefulWidget {
  final String subjectName;
  final int? semester;
  final String? academicYear;

  const SubjectDetailScreen({
    Key? key,
    required this.subjectName,
    this.semester,
    this.academicYear,
  }) : super(key: key);

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  DateTime _currentMonth = DateTime.now();
  DateTime? _selectedDate;

  // Stable per-subject identifier — survives subject renames
  String? _subjectId;
  Future<String>? _subjectIdFuture;

  static const Color _blue = Color(0xFF3859FF);
  static const Color _red = Color(0xFFB90000);
  static const Color _green = Color(0xFF34A853);

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _subjectIdFuture = _initSubjectId();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SUBJECT ID  (stable across renames)
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> _initSubjectId() async {
    final user = _auth.currentUser;
    if (user == null) return '';

    // Build query for all timetable entries belonging to this subject
    Query<Map<String, dynamic>> query = _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .where('className', isEqualTo: widget.subjectName);
    if (widget.semester != null) {
      query = query.where('semester', isEqualTo: widget.semester);
    }
    if (widget.academicYear != null) {
      query = query.where('academicYear', isEqualTo: widget.academicYear);
    }

    final snap = await query.limit(20).get();

    // 1. Re-use existing subjectId if any timetable entry already has one
    String? found;
    for (final doc in snap.docs) {
      final sid = doc.data()['subjectId'] as String?;
      if (sid != null && sid.isNotEmpty) {
        found = sid;
        break;
      }
    }

    // 2. If not found in timetable, check existing group membership.
    //    This handles recipients who accepted an invite but had all classes
    //    already in their timetable — no new entries were created, so
    //    subjectId was never stamped, but the group already has the right one.
    //    Query by memberIds only (no composite index needed), filter locally.
    if (found == null) {
      final groupSnap = await _firestore
          .collection('study_groups')
          .where('memberIds', arrayContains: user.uid)
          .get();
      final subjectDocs = groupSnap.docs
          .where((d) => d.data()['subject'] == widget.subjectName)
          .toList();
      if (subjectDocs.isNotEmpty) {
        // Prefer a group that already has a subjectId
        for (final d in subjectDocs) {
          final sid = d.data()['subjectId'] as String?;
          if (sid != null && sid.isNotEmpty) {
            found = sid;
            break;
          }
        }
        // Legacy groups have no subjectId — generate one and patch them
        if (found == null) {
          final newId = _firestore.collection('study_groups').doc().id;
          final batch = _firestore.batch();
          for (final d in subjectDocs) {
            batch.update(d.reference, {'subjectId': newId});
          }
          await batch.commit();
          found = newId;
        }
      }
    }

    final subjectId = found ?? _firestore.collection('study_groups').doc().id;

    // Stamp subjectId on timetable entries that are still missing it
    final toUpdate = snap.docs
        .where((d) => d.data()['subjectId'] == null)
        .toList();
    if (toUpdate.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in toUpdate) {
        batch.update(doc.reference, {'subjectId': subjectId});
      }
      await batch.commit();
    }

    if (mounted) setState(() => _subjectId = subjectId);
    return subjectId;
  }

  void _previousMonth() => setState(() {
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
  });

  void _nextMonth() => setState(() {
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CALENDAR HELPERS (unchanged)
  // ══════════════════════════════════════════════════════════════════════════

  Stream<Map<String, bool>> _checkClassesOnDateStream(DateTime date) {
    final user = _auth.currentUser;
    if (user == null)
      return Stream.value({'hasClasses': false, 'isUpcoming': false});
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkDate = DateTime(date.year, date.month, date.day);

    return _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .where('className', isEqualTo: widget.subjectName)
        .snapshots()
        .asyncMap((snap) async {
          bool hasClasses = false;
          bool isUpcoming = false;
          for (var doc in snap.docs) {
            final ts = doc.data()['date'] as Timestamp?;
            if (ts != null) {
              final d = ts.toDate();
              if (DateTime(d.year, d.month, d.day) == checkDate) {
                hasClasses = true;
                if (checkDate.isAfter(today)) isUpcoming = true;
                break;
              }
            }
          }
          if (!hasClasses) {
            final t = await _firestore
                .collection('tasks')
                .where('userId', isEqualTo: user.uid)
                .where('subject', isEqualTo: widget.subjectName)
                .get();
            for (var doc in t.docs) {
              final ts = doc.data()['dueDate'] as Timestamp?;
              if (ts != null) {
                final d = ts.toDate();
                if (DateTime(d.year, d.month, d.day) == checkDate) {
                  hasClasses = true;
                  if (checkDate.isAfter(today)) isUpcoming = true;
                  break;
                }
              }
            }
          }
          if (!hasClasses) {
            final e = await _firestore
                .collection('exams')
                .where('userId', isEqualTo: user.uid)
                .where('subject', isEqualTo: widget.subjectName)
                .get();
            for (var doc in e.docs) {
              final ts = doc.data()['examDate'] as Timestamp?;
              if (ts != null) {
                final d = ts.toDate();
                if (DateTime(d.year, d.month, d.day) == checkDate) {
                  hasClasses = true;
                  if (checkDate.isAfter(today)) isUpcoming = true;
                  break;
                }
              }
            }
          }
          return {'hasClasses': hasClasses, 'isUpcoming': isUpcoming};
        });
  }

  List<DateTime> _getDaysInMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final days = <DateTime>[];
    final firstWeekday = firstDay.weekday % 7;
    for (int i = firstWeekday - 1; i >= 0; i--) {
      days.add(firstDay.subtract(Duration(days: i + 1)));
    }
    for (int d = 1; d <= lastDay.day; d++) {
      days.add(DateTime(month.year, month.month, d));
    }
    for (int i = 1; i <= 42 - days.length; i++) {
      days.add(lastDay.add(Duration(days: i)));
    }
    return days;
  }

  bool _isCurrentMonth(DateTime d) =>
      d.month == _currentMonth.month && d.year == _currentMonth.year;
  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  bool _isSelected(DateTime d) =>
      _selectedDate != null &&
      d.year == _selectedDate!.year &&
      d.month == _selectedDate!.month &&
      d.day == _selectedDate!.day;

  // ══════════════════════════════════════════════════════════════════════════
  // STUDY GROUPS LOGIC
  // ══════════════════════════════════════════════════════════════════════════

  // Returns groups where the user is a member and the subject matches.
  // Queries only by memberIds (no composite index needed) and filters locally.
  // Matches by subjectId when both sides have it (handles renames); otherwise
  // falls back to subject name so recipients see the group immediately.
  Stream<List<DocumentSnapshot>> _myGroupsStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _firestore
        .collection('study_groups')
        .where('memberIds', arrayContains: user.uid)
        .snapshots()
        .map(
          (snap) => snap.docs.where((doc) {
            final data = doc.data();
            final groupSubjectId = data['subjectId'] as String?;
            // Prefer ID-based match when both sides have a subjectId
            if (_subjectId != null &&
                _subjectId!.isNotEmpty &&
                groupSubjectId != null &&
                groupSubjectId.isNotEmpty) {
              return groupSubjectId == _subjectId;
            }
            // Fall back to subject name (covers recipients before subjectId is stamped)
            return data['subject'] == widget.subjectName;
          }).toList(),
        )
        .handleError((_) {});
  }

  Future<void> _createGroup(String groupName) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final subjectId =
        _subjectId ?? await (_subjectIdFuture ?? _initSubjectId());
    if (subjectId.isEmpty) return;
    final ud = await _firestore.collection('users').doc(user.uid).get();
    final username = ud.data()?['username'] ?? 'Unknown';
    await _firestore.collection('study_groups').add({
      'name': groupName,
      'subject': widget.subjectName,
      'subjectId': subjectId,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'memberIds': [user.uid],
      'members': [
        {'uid': user.uid, 'username': username},
      ],
    });
  }

  Future<void> _sendInvitation(
    String groupId,
    String groupName,
    String inviteeEmail,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final q = await _firestore
        .collection('users')
        .where('email', isEqualTo: inviteeEmail.trim().toLowerCase())
        .limit(1)
        .get();

    if (q.docs.isEmpty) {
      if (mounted) _showSnack('No user found with that email.', isError: true);
      return;
    }
    final inviteeId = q.docs.first.id;

    if (inviteeId == user.uid) {
      if (mounted) _showSnack('You cannot invite yourself.', isError: true);
      return;
    }

    final gd = await _firestore.collection('study_groups').doc(groupId).get();
    if (List<String>.from(gd.data()?['memberIds'] ?? []).contains(inviteeId)) {
      if (mounted)
        _showSnack('That user is already in the group.', isError: true);
      return;
    }

    final ex = await _firestore
        .collection('group_invitations')
        .where('groupId', isEqualTo: groupId)
        .where('inviteeId', isEqualTo: inviteeId)
        .where('status', isEqualTo: 'pending')
        .get();
    if (ex.docs.isNotEmpty) {
      if (mounted) _showSnack('Invitation already sent.', isError: true);
      return;
    }

    final sd = await _firestore.collection('users').doc(user.uid).get();
    final senderUsername = sd.data()?['username'] ?? 'Someone';

    // Fetch sender's classes, tasks and exams for this subject
    final classesSnap = await _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .where('className', isEqualTo: widget.subjectName)
        .get();

    final tasksSnap = await _firestore
        .collection('tasks')
        .where('userId', isEqualTo: user.uid)
        .where('subject', isEqualTo: widget.subjectName)
        .get();

    final examsSnap = await _firestore
        .collection('exams')
        .where('userId', isEqualTo: user.uid)
        .where('subject', isEqualTo: widget.subjectName)
        .get();

    final classesList = classesSnap.docs.map((d) {
      final cd = d.data();
      return {
        'className': cd['className'] ?? widget.subjectName,
        'startTime': cd['startTime'] ?? '',
        'endTime': cd['endTime'] ?? '',
        'room': cd['room'] ?? '',
        'building': cd['building'] ?? '',
        'lecturerName': cd['lecturerName'] ?? '',
        'date': cd['date'],
        'semester': cd['semester'],
        'academicYear': cd['academicYear'],
      };
    }).toList();

    final tasksList = tasksSnap.docs.map((d) {
      final td = d.data();
      return {
        'taskTitle': td['taskTitle'] ?? '',
        'taskDetails': td['taskDetails'] ?? '',
        'taskType': td['taskType'] ?? '',
        'subject': td['subject'] ?? widget.subjectName,
        'dueDate': td['dueDate'],
      };
    }).toList();

    final examsList = examsSnap.docs.map((d) {
      final ed = d.data();
      return {
        'examName': ed['examName'] ?? '',
        'subject': ed['subject'] ?? widget.subjectName,
        'type': ed['type'] ?? 'Exam',
        'mode': ed['mode'] ?? 'In Person',
        'venue': ed['venue'] ?? '',
        'examDate': ed['examDate'],
        'startTime': ed['startTime'],
        'endTime': ed['endTime'],
      };
    }).toList();

    final subjectId =
        _subjectId ?? await (_subjectIdFuture ?? _initSubjectId());

    await _firestore.collection('group_invitations').add({
      'groupId': groupId,
      'groupName': groupName,
      'subject': widget.subjectName,
      'subjectId': subjectId,
      'inviterId': user.uid,
      'inviterUsername': senderUsername,
      'inviteeId': inviteeId,
      'inviteeEmail': inviteeEmail.trim().toLowerCase(),
      'status': 'pending',
      'classes': classesList,
      'tasks': tasksList,
      'exams': examsList,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) _showSnack('Invitation sent to $inviteeEmail!');
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.dmMono()),
        backgroundColor: isError ? _red : _green,
      ),
    );
  }

  void _showCreateGroupDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border(context), width: 2),
        ),
        title: Text(
          'Create Study Group',
          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: ctrl,
          style: GoogleFonts.dmMono(),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Group name',
            hintStyle: GoogleFonts.dmMono(color: AppColors.subtext(context)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.border(context), width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _blue, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.dmMono(color: AppColors.subtext(context))),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await _createGroup(name);
              if (mounted) _showSnack('Group "$name" created!');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Create',
              style: GoogleFonts.dmMono(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInviteDialog(String groupId, String groupName) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border(context), width: 2),
        ),
        title: Text(
          'Invite to Group',
          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the email of the user to invite:',
              style: GoogleFonts.dmMono(fontSize: 12, color: AppColors.subtext(context)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              style: GoogleFonts.dmMono(),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'user@email.com',
                hintStyle: GoogleFonts.dmMono(color: AppColors.subtext(context)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border(context), width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _blue, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.dmMono(color: AppColors.subtext(context))),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = ctrl.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(ctx);
              await _sendInvitation(groupId, groupName, email);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Send',
              style: GoogleFonts.dmMono(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SHARE TIMETABLE DIALOG
  // ══════════════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════════
  // ADD EXTRA CLASS DIALOG
  // ══════════════════════════════════════════════════════════════════════

  void _showAddClassDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Controllers
    final roomCtrl = TextEditingController();
    final buildingCtrl = TextEditingController();
    final lecturerCtrl = TextEditingController();

    DateTime? selectedDate;
    TimeOfDay? startTime;
    TimeOfDay? endTime;

    String? errorMsg;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: AppColors.border(context), width: 2),
                  left: BorderSide(color: AppColors.border(context), width: 2),
                  right: BorderSide(color: AppColors.border(context), width: 2),
                ),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Header ──────────────────────────────────────────
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.add_circle_outline,
                              color: _red,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Add Extra Class',
                                  style: GoogleFonts.dmMono(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  widget.subjectName,
                                  style: GoogleFonts.dmMono(
                                    fontSize: 12,
                                    color: AppColors.subtext(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Icon(
                              Icons.close,
                              color: AppColors.subtext(context),
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Date picker ─────────────────────────────────────
                      _addClassLabel('Date *'),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () async {
                          final isDark = AppColors.isDark(ctx);
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            builder: (_, child) => Theme(
                              data: isDark
                                  ? ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Color(0xFFB90000),
                                        onPrimary: Colors.white,
                                        surface: Color(0xFF252D47),
                                        onSurface: Colors.white,
                                      ),
                                    )
                                  : ThemeData.light().copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: Color(0xFFB90000),
                                      ),
                                    ),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setS(() {
                              selectedDate = picked;
                              errorMsg = null;
                            });
                          }
                        },
                        child: _addClassPickerTile(
                          icon: Icons.calendar_today,
                          label: selectedDate != null
                              ? DateFormat(
                                  'EEE, dd MMM yyyy',
                                ).format(selectedDate!)
                              : 'Select date',
                          active: selectedDate != null,
                          required: true,
                          hasError: errorMsg != null && selectedDate == null,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Start time ──────────────────────────────────────
                      _addClassLabel('Start Time *'),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDialog<TimeOfDay>(
                            context: ctx,
                            builder: (_) => _CustomTimePickerDialog(
                              initialTime:
                                  startTime ??
                                  const TimeOfDay(hour: 8, minute: 0),
                            ),
                          );
                          if (picked != null) {
                            setS(() {
                              startTime = picked;
                              errorMsg = null;
                            });
                          }
                        },
                        child: _addClassPickerTile(
                          icon: Icons.access_time,
                          label: startTime != null
                              ? startTime!.format(ctx)
                              : 'Select start time',
                          active: startTime != null,
                          required: true,
                          hasError: errorMsg != null && startTime == null,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── End time ────────────────────────────────────────
                      _addClassLabel('End Time *'),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDialog<TimeOfDay>(
                            context: ctx,
                            builder: (_) => _CustomTimePickerDialog(
                              initialTime:
                                  endTime ??
                                  (startTime != null
                                      ? TimeOfDay(
                                          hour: (startTime!.hour + 2) % 24,
                                          minute: startTime!.minute,
                                        )
                                      : const TimeOfDay(hour: 10, minute: 0)),
                            ),
                          );
                          if (picked != null) {
                            setS(() {
                              endTime = picked;
                              errorMsg = null;
                            });
                          }
                        },
                        child: _addClassPickerTile(
                          icon: Icons.access_time_filled,
                          label: endTime != null
                              ? endTime!.format(ctx)
                              : 'Select end time',
                          active: endTime != null,
                          required: true,
                          hasError: errorMsg != null && endTime == null,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Room (optional) ─────────────────────────────────
                      _addClassLabel('Room (optional)'),
                      const SizedBox(height: 6),
                      _addClassTextField(roomCtrl, 'e.g. A101'),
                      const SizedBox(height: 14),

                      // ── Building (optional) ─────────────────────────────
                      _addClassLabel('Building (optional)'),
                      const SizedBox(height: 6),
                      _addClassTextField(buildingCtrl, 'e.g. Block A'),
                      const SizedBox(height: 14),

                      // ── Lecturer (optional) ─────────────────────────────
                      _addClassLabel('Lecturer (optional)'),
                      const SizedBox(height: 6),
                      _addClassTextField(lecturerCtrl, 'e.g. Dr. Smith'),
                      const SizedBox(height: 8),

                      // ── Error message ───────────────────────────────────
                      if (errorMsg != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 14,
                                color: Color(0xFFB90000),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                errorMsg!,
                                style: GoogleFonts.dmMono(
                                  fontSize: 12,
                                  color: const Color(0xFFB90000),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 8),

                      // ── Save button ─────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            // Validate required fields
                            if (selectedDate == null ||
                                startTime == null ||
                                endTime == null) {
                              setS(
                                () => errorMsg =
                                    'Please fill in date, start time and end time.',
                              );
                              return;
                            }

                            // Validate end time is after start time
                            final startMins =
                                startTime!.hour * 60 + startTime!.minute;
                            final endMins =
                                endTime!.hour * 60 + endTime!.minute;
                            if (endMins <= startMins) {
                              setS(
                                () => errorMsg =
                                    'End time must be after start time.',
                              );
                              return;
                            }

                            // Format HH:mm strings
                            final startStr =
                                '${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}';
                            final endStr =
                                '${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}';

                            // Save to Firestore
                            await _firestore.collection('timetable').add({
                              'userId': user.uid,
                              'className': widget.subjectName,
                              'date': Timestamp.fromDate(selectedDate!),
                              'startTime': startStr,
                              'endTime': endStr,
                              'room': roomCtrl.text.trim(),
                              'building': buildingCtrl.text.trim(),
                              'lecturerName': lecturerCtrl.text.trim(),
                              'type': 'class',
                              'semester': widget.semester,
                              'academicYear': widget.academicYear,
                            });

                            if (ctx.mounted) Navigator.pop(ctx);

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Class added for ${DateFormat('EEE, dd MMM yyyy').format(selectedDate!)}',
                                    style: GoogleFonts.dmMono(),
                                  ),
                                  backgroundColor: _green,
                                ),
                              );
                              // Refresh calendar to show new dot
                              setState(() {});
                            }
                          },
                          icon: const Icon(Icons.check, size: 20),
                          label: Text(
                            'Save Class',
                            style: GoogleFonts.dmMono(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _addClassLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.dmMono(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: AppColors.subtext(context),
      ),
    );
  }

  Widget _addClassTextField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: GoogleFonts.dmMono(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmMono(
          color: AppColors.subtext(context),
          fontSize: 14,
        ),
        filled: true,
        fillColor: AppColors.input(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFB90000), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _addClassPickerTile({
    required IconData icon,
    required String label,
    required bool active,
    required bool required,
    bool hasError = false,
  }) {
    final Color borderColor = hasError
        ? const Color(0xFFB90000)
        : active
        ? const Color(0xFFB90000)
        : AppColors.border(context);
    final Color iconColor = hasError
        ? const Color(0xFFB90000)
        : active
        ? const Color(0xFFB90000)
        : AppColors.subtext(context);
    final Color textColor =
        active ? AppColors.text(context) : AppColors.subtext(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFB90000).withOpacity(0.04)
            : AppColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: borderColor,
          width: active || hasError ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.dmMono(fontSize: 14, color: textColor),
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: AppColors.subtext(context)),
        ],
      ),
    );
  }

  void _showShareDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Load all classes for this subject
    final classesSnap = await _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .where('className', isEqualTo: widget.subjectName)
        .get();

    final tasksSnap = await _firestore
        .collection('tasks')
        .where('userId', isEqualTo: user.uid)
        .where('subject', isEqualTo: widget.subjectName)
        .get();

    final examsSnap = await _firestore
        .collection('exams')
        .where('userId', isEqualTo: user.uid)
        .where('subject', isEqualTo: widget.subjectName)
        .get();

    if (!mounted) return;

    final emailCtrl = TextEditingController();
    // Share mode: 'all' or 'individual'
    String shareMode = 'all';
    // Individual selections
    final Set<String> selectedClasses = {};
    final Set<String> selectedTasks = {};
    final Set<String> selectedExams = {};

    final classes =
        classesSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList()
          ..sort((a, b) {
            final ta = (a['date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final tb = (b['date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return ta.compareTo(tb);
          });
    final tasks = tasksSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    final exams = examsSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            builder: (ctx, scroll) => Container(
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: AppColors.border(context), width: 2),
                  left: BorderSide(color: AppColors.border(context), width: 2),
                  right: BorderSide(color: AppColors.border(context), width: 2),
                ),
              ),
              child: Column(
                children: [
                  // ── Header ────────────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SHARE TIMETABLE',
                                style: GoogleFonts.dmMono(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.subjectName,
                                style: GoogleFonts.dmMono(
                                  fontSize: 11,
                                  color: _blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),

                  Expanded(
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.all(24),
                      children: [
                        // ── Mode toggle ─────────────────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setS(() => shareMode = 'all'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: shareMode == 'all'
                                        ? _blue
                                        : AppColors.card(context),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(10),
                                      bottomLeft: Radius.circular(10),
                                    ),
                                    border: Border.all(
                                      color: shareMode == 'all'
                                          ? _blue
                                          : AppColors.border(context),
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Full Semester',
                                      style: GoogleFonts.dmMono(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: shareMode == 'all'
                                            ? Colors.white
                                            : AppColors.subtext(context),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setS(() => shareMode = 'individual'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: shareMode == 'individual'
                                        ? _blue
                                        : AppColors.card(context),
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(10),
                                      bottomRight: Radius.circular(10),
                                    ),
                                    border: Border.all(
                                      color: shareMode == 'individual'
                                          ? _blue
                                          : AppColors.border(context),
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Individual',
                                      style: GoogleFonts.dmMono(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: shareMode == 'individual'
                                            ? Colors.white
                                            : AppColors.subtext(context),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── Classes ─────────────────────────────────────────────
                        if (classes.isNotEmpty) ...[
                          _shareSection(
                            'Timetable',
                            Icons.school_outlined,
                            _red,
                          ),
                          const SizedBox(height: 8),
                          ...classes.map((cls) {
                            final id = cls['id'] as String;
                            final ts = cls['date'] as Timestamp?;
                            final dateStr = ts != null
                                ? DateFormat('EEE, dd MMM').format(ts.toDate())
                                : '—';
                            final start = cls['startTime'] ?? '';
                            final end = cls['endTime'] ?? '';
                            final room = cls['room'] ?? '';
                            final building = cls['building'] ?? '';
                            final loc = [
                              room,
                              building,
                            ].where((s) => (s as String).isNotEmpty).join(', ');
                            final selected =
                                shareMode == 'all' ||
                                selectedClasses.contains(id);
                            return _shareItem(
                              selected: selected,
                              selectable: shareMode == 'individual',
                              onTap: () => setS(() {
                                if (selectedClasses.contains(id)) {
                                  selectedClasses.remove(id);
                                } else {
                                  selectedClasses.add(id);
                                }
                              }),
                              color: _red,
                              icon: Icons.school_outlined,
                              title: cls['className'] ?? widget.subjectName,
                              subtitle:
                                  '$dateStr  •  ${_formatTime(start)} – ${_formatTime(end)}'
                                  '${loc.isNotEmpty ? '  •  $loc' : ''}',
                            );
                          }),
                          const SizedBox(height: 16),
                        ],

                        // ── Tasks ───────────────────────────────────────────────
                        if (tasks.isNotEmpty) ...[
                          _shareSection(
                            'Tasks',
                            Icons.task_alt,
                            const Color(0xFF008BB9),
                          ),
                          const SizedBox(height: 8),
                          ...tasks.map((task) {
                            final id = task['id'] as String;
                            final ts = task['dueDate'] as Timestamp?;
                            final dateStr = ts != null
                                ? DateFormat(
                                    'EEE, dd MMM, h:mm a',
                                  ).format(ts.toDate())
                                : '—';
                            final selected =
                                shareMode == 'all' ||
                                selectedTasks.contains(id);
                            return _shareItem(
                              selected: selected,
                              selectable: shareMode == 'individual',
                              onTap: () => setS(() {
                                if (selectedTasks.contains(id)) {
                                  selectedTasks.remove(id);
                                } else {
                                  selectedTasks.add(id);
                                }
                              }),
                              color: const Color(0xFF008BB9),
                              icon: Icons.task_alt,
                              title: task['taskTitle'] ?? 'Task',
                              subtitle:
                                  '$dateStr  •  ${task['taskType'] ?? ''}',
                            );
                          }),
                          const SizedBox(height: 16),
                        ],

                        // ── Exams ───────────────────────────────────────────────
                        if (exams.isNotEmpty) ...[
                          _shareSection(
                            'Exams',
                            Icons.assignment_outlined,
                            const Color(0xFF9AB900),
                          ),
                          const SizedBox(height: 8),
                          ...exams.map((exam) {
                            final id = exam['id'] as String;
                            final ts = exam['examDate'] as Timestamp?;
                            final sts = exam['startTime'] as Timestamp?;
                            final ets = exam['endTime'] as Timestamp?;
                            final dateStr = ts != null
                                ? DateFormat('EEE, dd MMM').format(ts.toDate())
                                : '—';
                            final timeStr = sts != null && ets != null
                                ? '${DateFormat('h:mm a').format(sts.toDate())} – ${DateFormat('h:mm a').format(ets.toDate())}'
                                : '';
                            final selected =
                                shareMode == 'all' ||
                                selectedExams.contains(id);
                            return _shareItem(
                              selected: selected,
                              selectable: shareMode == 'individual',
                              onTap: () => setS(() {
                                if (selectedExams.contains(id)) {
                                  selectedExams.remove(id);
                                } else {
                                  selectedExams.add(id);
                                }
                              }),
                              color: const Color(0xFF9AB900),
                              icon: Icons.assignment_outlined,
                              title: exam['examName'] ?? 'Exam',
                              subtitle:
                                  '$dateStr${timeStr.isNotEmpty ? '  •  $timeStr' : ''}  •  ${exam['type'] ?? ''}',
                            );
                          }),
                          const SizedBox(height: 16),
                        ],

                        if (classes.isEmpty && tasks.isEmpty && exams.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'No data to share for this subject.',
                                style: GoogleFonts.dmMono(
                                  fontSize: 13,
                                  color: AppColors.subtext(context),
                                ),
                              ),
                            ),
                          ),

                        // ── Recipient email ──────────────────────────────────────
                        const SizedBox(height: 8),
                        Text(
                          'Send to:',
                          style: GoogleFonts.dmMono(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.subtext(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border(context), width: 2),
                          ),
                          child: TextField(
                            controller: emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: GoogleFonts.dmMono(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Please enter recipient email:',
                              hintStyle: GoogleFonts.dmMono(
                                color: AppColors.subtext(context),
                                fontSize: 12,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Send button ──────────────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              final email = emailCtrl.text.trim();
                              if (email.isEmpty) return;

                              // Build payload
                              List<Map<String, dynamic>> sharedClasses = [];
                              List<Map<String, dynamic>> sharedTasks = [];
                              List<Map<String, dynamic>> sharedExams = [];

                              if (shareMode == 'all') {
                                sharedClasses = classes
                                    .map(
                                      (c) =>
                                          Map<String, dynamic>.from(c)
                                            ..remove('id'),
                                    )
                                    .toList();
                                sharedTasks = tasks
                                    .map(
                                      (t) =>
                                          Map<String, dynamic>.from(t)
                                            ..remove('id'),
                                    )
                                    .toList();
                                sharedExams = exams
                                    .map(
                                      (e) =>
                                          Map<String, dynamic>.from(e)
                                            ..remove('id'),
                                    )
                                    .toList();
                              } else {
                                sharedClasses = classes
                                    .where(
                                      (c) => selectedClasses.contains(c['id']),
                                    )
                                    .map(
                                      (c) =>
                                          Map<String, dynamic>.from(c)
                                            ..remove('id'),
                                    )
                                    .toList();
                                sharedTasks = tasks
                                    .where(
                                      (t) => selectedTasks.contains(t['id']),
                                    )
                                    .map(
                                      (t) =>
                                          Map<String, dynamic>.from(t)
                                            ..remove('id'),
                                    )
                                    .toList();
                                sharedExams = exams
                                    .where(
                                      (e) => selectedExams.contains(e['id']),
                                    )
                                    .map(
                                      (e) =>
                                          Map<String, dynamic>.from(e)
                                            ..remove('id'),
                                    )
                                    .toList();
                              }

                              if (sharedClasses.isEmpty &&
                                  sharedTasks.isEmpty &&
                                  sharedExams.isEmpty) {
                                _showSnack(
                                  'Please select at least one item to share.',
                                  isError: true,
                                );
                                return;
                              }

                              await _sendShareTimetable(
                                email: email,
                                classes: sharedClasses,
                                tasks: sharedTasks,
                                exams: sharedExams,
                              );
                              if (mounted) Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _red,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Send Timetable',
                              style: GoogleFonts.dmMono(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _shareSection(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.dmMono(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _shareItem({
    required bool selected,
    required bool selectable,
    required VoidCallback onTap,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return GestureDetector(
      onTap: selectable ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.05) : AppColors.input(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : AppColors.border(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(selected ? 1 : 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: selected
                          ? AppColors.text(context)
                          : AppColors.subtext(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmMono(
                        fontSize: 10, color: AppColors.subtext(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (selectable)
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? color : AppColors.subtext(context),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendShareTimetable({
    required String email,
    required List<Map<String, dynamic>> classes,
    required List<Map<String, dynamic>> tasks,
    required List<Map<String, dynamic>> exams,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final q = await _firestore
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();

    if (q.docs.isEmpty) {
      if (mounted) _showSnack('No user found with that email.', isError: true);
      return;
    }

    final inviteeId = q.docs.first.id;

    if (inviteeId == user.uid) {
      if (mounted) _showSnack('You cannot share with yourself.', isError: true);
      return;
    }

    final sd = await _firestore.collection('users').doc(user.uid).get();
    final senderUsername = sd.data()?['username'] ?? 'Someone';

    // Check if already sent recently
    final ex = await _firestore
        .collection('timetable_shares')
        .where('senderId', isEqualTo: user.uid)
        .where('recipientId', isEqualTo: inviteeId)
        .where('subject', isEqualTo: widget.subjectName)
        .where('status', isEqualTo: 'pending')
        .get();
    if (ex.docs.isNotEmpty) {
      if (mounted)
        _showSnack(
          'You already have a pending share with this user.',
          isError: true,
        );
      return;
    }

    await _firestore.collection('timetable_shares').add({
      'senderId': user.uid,
      'senderUsername': senderUsername,
      'recipientId': inviteeId,
      'recipientEmail': email.trim().toLowerCase(),
      'subject': widget.subjectName,
      'classes': classes,
      'tasks': tasks,
      'exams': exams,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) _showSnack('Timetable shared with $email!');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInMonth(_currentMonth);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      _buildSubjectHeader(),
                      const SizedBox(height: 24),
                      _buildCalendar(days),
                      const SizedBox(height: 24),
                      _buildSelectedDateClasses(),
                      const SizedBox(height: 24),
                      // ── Study Groups ABOVE Upcoming Events ──────────────
                      _buildStudyGroupsSection(),
                      const SizedBox(height: 24),
                      _buildUpcomingEvents(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STUDY GROUPS SECTION
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStudyGroupsSection() {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Study Groups',
              style: GoogleFonts.dmMono(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            GestureDetector(
              onTap: _showCreateGroupDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _blue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'New Group',
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<DocumentSnapshot>>(
          stream: _myGroupsStream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: _blue),
                ),
              );
            }
            final groups = snap.data ?? [];
            if (groups.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border(context), width: 2),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _blue.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.group_outlined,
                        size: 36,
                        color: _blue,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No study groups yet',
                      style: GoogleFonts.dmMono(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.subtext(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create one or accept an invitation',
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        color: AppColors.subtext(context),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: groups.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final groupId = doc.id;
                final groupName = data['name'] ?? 'Unnamed Group';
                final memberCount = (data['memberIds'] as List?)?.length ?? 0;
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudyGroupScreen(
                        groupId: groupId,
                        groupName: groupName,
                        subject: widget.subjectName,
                      ),
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _blue, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: _blue.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.group,
                            color: _blue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                groupName,
                                style: GoogleFonts.dmMono(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    size: 12,
                                    color: AppColors.subtext(context),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$memberCount member${memberCount == 1 ? '' : 's'}',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 10,
                                      color: AppColors.subtext(context),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Invite button
                        GestureDetector(
                          onTap: () => _showInviteDialog(groupId, groupName),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_add_outlined,
                                  size: 14,
                                  color: _blue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Invite',
                                  style: GoogleFonts.dmMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: AppColors.subtext(context)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ALL EXISTING WIDGETS — UNCHANGED
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: AppColors.bg(context)),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.chipBg(context),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'SUBJECTS',
                style: TextStyle(
                  fontFamily: 'DM Mono',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // Add extra class button
          GestureDetector(
            onTap: _showAddClassDialog,
            child: Icon(
              Icons.add_circle_outline,
              color: AppColors.text(context),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          // Share timetable button
          GestureDetector(
            onTap: _showShareDialog,
            child: Icon(
              Icons.share_outlined,
              color: AppColors.text(context),
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectHeader() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFBFCAFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _blue, width: 3),
        ),
        child: Text(
          widget.subjectName,
          style: GoogleFonts.dmMono(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildCalendar(List<DateTime> days) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context), width: 2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.chipBg(context),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  DateFormat('MMMM, yyyy').format(_currentMonth),
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: [
                  _AnimatedTapButton(
                    onTap: _previousMonth,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border(context), width: 2),
                      ),
                      child: Icon(
                        Icons.chevron_left,
                        size: 20,
                        color: AppColors.text(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _AnimatedTapButton(
                    onTap: _nextMonth,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border(context), width: 2),
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppColors.text(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              'SUN',
              'MON',
              'TUE',
              'WED',
              'THU',
              'FRI',
              'SAT',
            ].map(_weekdayLabel).toList(),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.85,
              crossAxisSpacing: 8,
              mainAxisSpacing: 12,
            ),
            itemCount: days.length,
            itemBuilder: (ctx, i) {
              final date = days[i];
              return StreamBuilder<Map<String, bool>>(
                stream: _checkClassesOnDateStream(date),
                builder: (ctx, snap) => _buildDateCell(
                  date,
                  _isCurrentMonth(date),
                  _isToday(date),
                  _isSelected(date),
                  snap.data?['hasClasses'] ?? false,
                  snap.data?['isUpcoming'] ?? false,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDateCell(
    DateTime date,
    bool isCurrentMonth,
    bool isToday,
    bool isSelected,
    bool hasClasses,
    bool isUpcoming,
  ) {
    Color? bg;
    Color? border;
    double? bw;
    Color textColor = AppColors.text(context);
    if (isToday) {
      bg = _red;
      textColor = Colors.white;
    } else {
      bg = Colors.transparent;
      if (isUpcoming) {
        border = _red;
        bw = 2;
      } else if (hasClasses) {
        border = AppColors.border(context);
        bw = 2;
      }
    }
    if (!isCurrentMonth) textColor = AppColors.subtext(context);
    return _AnimatedTapButton(
      onTap: () => setState(() => _selectedDate = date),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: border != null && bw != null
                  ? Border.all(color: border, width: bw)
                  : null,
            ),
            child: Center(
              child: Text(
                date.day.toString().padLeft(2, '0'),
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
          if (isSelected) ...[
            const SizedBox(height: 4),
            CustomPaint(size: const Size(10, 8), painter: TrianglePainter(color: AppColors.text(context))),
          ],
        ],
      ),
    );
  }

  Widget _weekdayLabel(String day) {
    return SizedBox(
      width: 38,
      child: Text(
        day,
        textAlign: TextAlign.center,
        style: GoogleFonts.dmMono(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.text(context),
        ),
      ),
    );
  }

  Widget _buildSelectedDateClasses() {
    if (_selectedDate == null) return const SizedBox();
    final user = _auth.currentUser;
    if (user == null) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Events - ${DateFormat('EEE, dd MMM').format(_selectedDate!)}',
          style: GoogleFonts.dmMono(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getEventsOnDateStream(user.uid, _selectedDate!),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: AppColors.subtext(context)),
                ),
              );
            }
            if (snap.hasError || !snap.hasData || snap.data!.isEmpty) {
              return _buildEmptyState('No events scheduled');
            }
            final events = snap.data!
              ..sort((a, b) {
                String ta, tb;

                if (a['eventType'] == 'exam') {
                  final ts = a['startTime'];
                  if (ts is Timestamp) {
                    final dt = ts.toDate();
                    ta =
                        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  } else {
                    ta = '00:00';
                  }
                } else if (a['type'] == 'task') {
                  ta = (a['dueTime'] as String?) ?? '00:00';
                } else {
                  ta = (a['startTime'] as String?) ?? '00:00';
                }

                if (b['eventType'] == 'exam') {
                  final ts = b['startTime'];
                  if (ts is Timestamp) {
                    final dt = ts.toDate();
                    tb =
                        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  } else {
                    tb = '00:00';
                  }
                } else if (b['type'] == 'task') {
                  tb = (b['dueTime'] as String?) ?? '00:00';
                } else {
                  tb = (b['startTime'] as String?) ?? '00:00';
                }

                return ta.compareTo(tb);
              });
            return Column(
              children: events.map((event) {
                if (event['type'] == 'task') return _buildTaskCard(event);
                if (event['eventType'] == 'exam') return _buildExamCard(event);
                return _buildClassCard(event);
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildUpcomingEvents() {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upcoming Tasks & Exams',
          style: GoogleFonts.dmMono(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getUpcomingEventsStream(user.uid),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: AppColors.subtext(context)),
                ),
              );
            }
            if (snap.hasError || !snap.hasData || snap.data!.isEmpty) {
              return _buildEmptyState('No upcoming events');
            }
            return Column(
              children: snap.data!.map((event) {
                if (event['type'] == 'task') return _buildTaskCard(event);
                return _buildExamCard(event);
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> _getEventsOnDateStream(
    String userId,
    DateTime date,
  ) {
    return _firestore
        .collection('timetable')
        .where('userId', isEqualTo: userId)
        .where('className', isEqualTo: widget.subjectName)
        .snapshots()
        .asyncMap((timetableSnap) async {
          final list = <Map<String, dynamic>>[];

          // Classes
          for (var doc in timetableSnap.docs) {
            try {
              final data = doc.data();
              final ts = data['date'] as Timestamp?;
              if (ts != null) {
                final d = ts.toDate();
                if (d.year == date.year &&
                    d.month == date.month &&
                    d.day == date.day) {
                  list.add({
                    'id': doc.id,
                    'className': data['className'] ?? 'Untitled',
                    'startTime': data['startTime'] ?? '00:00',
                    'endTime': data['endTime'] ?? '00:00',
                    'room': data['room'] ?? '',
                    'building': data['building'] ?? '',
                    'lecturerName': data['lecturerName'] ?? '',
                    'type': data['type'] ?? 'class',
                    'date': ts,
                  });
                }
              }
            } catch (_) {}
          }

          // Tasks
          final tasksSnap = await _firestore
              .collection('tasks')
              .where('userId', isEqualTo: userId)
              .where('subject', isEqualTo: widget.subjectName)
              .get();
          for (var doc in tasksSnap.docs) {
            try {
              final data = doc.data();
              final ts = data['dueDate'] as Timestamp?;
              if (ts != null) {
                final d = ts.toDate();
                if (d.year == date.year &&
                    d.month == date.month &&
                    d.day == date.day) {
                  list.add({
                    'id': doc.id,
                    'type': 'task',
                    'taskTitle': data['taskTitle'] ?? 'Untitled Task',
                    'taskDetails': data['taskDetails'] ?? '',
                    'subject': data['subject'] ?? '',
                    'taskType': data['taskType'] ?? '',
                    'dueDate': ts,
                    'dueTime': DateFormat('HH:mm').format(d),
                    'completed': data['completed'] ?? false,
                  });
                }
              }
            } catch (_) {}
          }

          // Exams
          final examsSnap = await _firestore
              .collection('exams')
              .where('userId', isEqualTo: userId)
              .where('subject', isEqualTo: widget.subjectName)
              .get();
          for (var doc in examsSnap.docs) {
            try {
              final data = doc.data();
              final ts = data['examDate'] as Timestamp?;
              if (ts != null) {
                final d = ts.toDate();
                if (d.year == date.year &&
                    d.month == date.month &&
                    d.day == date.day) {
                  list.add({
                    'id': doc.id,
                    'eventType': 'exam',
                    'type': data['type'] ?? 'Exam',
                    'examName': data['examName'] ?? 'Untitled Exam',
                    'subject': data['subject'] ?? '',
                    'mode': data['mode'] ?? 'In Person',
                    'venue': data['venue'] ?? '',
                    'examDate': ts,
                    'startTime': data['startTime'],
                    'endTime': data['endTime'],
                  });
                }
              }
            } catch (_) {}
          }

          return list;
        });
  }

  Stream<List<Map<String, dynamic>>> _getUpcomingEventsStream(String userId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _firestore
        .collection('tasks')
        .where('userId', isEqualTo: userId)
        .where('subject', isEqualTo: widget.subjectName)
        .snapshots()
        .asyncMap((tasksSnap) async {
          final events = <Map<String, dynamic>>[];
          for (var doc in tasksSnap.docs) {
            try {
              final data = doc.data();
              final ts = data['dueDate'] as Timestamp?;
              if (ts != null) {
                final dd = ts.toDate();
                final dOnly = DateTime(dd.year, dd.month, dd.day);
                if (!dOnly.isBefore(today)) {
                  events.add({
                    'id': doc.id,
                    'type': 'task',
                    'taskTitle': data['taskTitle'] ?? 'Untitled Task',
                    'taskDetails': data['taskDetails'] ?? '',
                    'subject': data['subject'] ?? '',
                    'taskType': data['taskType'] ?? '',
                    'dueDate': ts,
                    'dueTime': DateFormat('HH:mm').format(dd),
                    'completed': data['completed'] ?? false,
                    'sortDate': dd,
                  });
                }
              }
            } catch (_) {}
          }
          final examsSnap = await _firestore
              .collection('exams')
              .where('userId', isEqualTo: userId)
              .where('subject', isEqualTo: widget.subjectName)
              .get();
          for (var doc in examsSnap.docs) {
            try {
              final data = doc.data();
              final ts = data['examDate'] as Timestamp?;
              if (ts != null) {
                final ed = ts.toDate();
                final eOnly = DateTime(ed.year, ed.month, ed.day);
                if (!eOnly.isBefore(today)) {
                  events.add({
                    'id': doc.id,
                    'eventType': 'exam',
                    'type': data['type'] ?? 'Exam',
                    'examName': data['examName'] ?? 'Untitled Exam',
                    'subject': data['subject'] ?? '',
                    'mode': data['mode'] ?? 'In Person',
                    'venue': data['venue'] ?? '',
                    'examDate': ts,
                    'startTime': data['startTime'],
                    'endTime': data['endTime'],
                    'sortDate': ed,
                  });
                }
              }
            } catch (_) {}
          }
          events.sort((a, b) => a['sortDate'].compareTo(b['sortDate']));
          return events;
        });
  }

  Widget _buildClassCard(Map<String, dynamic> c) {
    return _AnimatedTapButton(
      onTap: () => _showClassDetails(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _red, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _red,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.school_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'CLASS',
                          style: GoogleFonts.dmMono(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          c['className'],
                          style: GoogleFonts.dmMono(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatTime(c['startTime'])} - ${_formatTime(c['endTime'])}'
                    '${c['room'].isNotEmpty || c['building'].isNotEmpty ? ' • ${c['room']}${c['room'].isNotEmpty && c['building'].isNotEmpty ? ', ' : ''}${c['building']}' : ''}',
                    style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.subtext(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final isCompleted = task['completed'] ?? false;
    final dueDate = (task['dueDate'] as Timestamp).toDate();
    final tc = isCompleted ? _green : const Color(0xFF008BB9);
    return _AnimatedTapButton(
      onTap: () => _showTaskDetails(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tc, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tc,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isCompleted ? Icons.check_circle : Icons.task_alt,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tc,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          task['taskType'].toString().toUpperCase(),
                          style: GoogleFonts.dmMono(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          task['taskTitle'],
                          style: GoogleFonts.dmMono(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat('EEE, dd MMM').format(dueDate)} • ${_formatTime(task['dueTime'])}',
                    style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.subtext(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamCard(Map<String, dynamic> exam) {
    try {
      final examDate = (exam['examDate'] as Timestamp).toDate();
      final startTime = (exam['startTime'] as Timestamp?)?.toDate();
      final endTime = (exam['endTime'] as Timestamp?)?.toDate();
      return _AnimatedTapButton(
        onTap: () => _showExamDetails(exam),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF9AB900), width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF9AB900),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF9AB900),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            (exam['type'] ?? 'EXAM').toString().toUpperCase(),
                            style: GoogleFonts.dmMono(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            exam['examName'] ?? 'Untitled Exam',
                            style: GoogleFonts.dmMono(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('EEE, dd MMM').format(examDate)}'
                      '${startTime != null && endTime != null ? ' • ${DateFormat('hh:mm a').format(startTime)} - ${DateFormat('hh:mm a').format(endTime)}' : ''}',
                      style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.subtext(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      return const SizedBox();
    }
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context), width: 2),
      ),
      child: Column(
        children: [
          Icon(Icons.event_note_outlined, size: 48, color: AppColors.subtext(context)),
          const SizedBox(height: 12),
          Text(
            msg,
            style: GoogleFonts.dmMono(fontSize: 13, color: AppColors.subtext(context)),
          ),
        ],
      ),
    );
  }

  String _formatTime(String time) {
    try {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      if (hour == 0) return '12:$minute AM';
      if (hour < 12) return '$hour:$minute AM';
      if (hour == 12) return '12:$minute PM';
      return '${hour - 12}:$minute PM';
    } catch (_) {
      return time;
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.dmMono(fontSize: 12, color: AppColors.subtext(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showClassDetails(Map<String, dynamic> event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _detailSheet(
        children: [
          Text(
            'Class Details',
            style: GoogleFonts.dmMono(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow('Class Name', event['className']),
          _buildDetailRow(
            'Time',
            '${_formatTime(event['startTime'])} - ${_formatTime(event['endTime'])}',
          ),
          if ((event['room'] ?? '').isNotEmpty)
            _buildDetailRow('Room', event['room']),
          if ((event['building'] ?? '').isNotEmpty)
            _buildDetailRow('Building', event['building']),
          if ((event['lecturerName'] ?? '').isNotEmpty)
            _buildDetailRow('Lecturer', event['lecturerName']),
        ],
        actions: [
          _outlineBtn('Edit', () async {
            Navigator.pop(ctx);
            final r = await Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) => EditClassScreen(classData: event),
              ),
            );
            if (r == true && mounted) setState(() {});
          }),
          _deleteBtn('Delete Class', () async {
            final m = ScaffoldMessenger.of(ctx);
            Navigator.pop(ctx);
            await _firestore.collection('timetable').doc(event['id']).delete();
            m.showSnackBar(
              SnackBar(
                content: Text('Class deleted', style: GoogleFonts.dmMono()),
                backgroundColor: _red,
              ),
            );
          }, confirmMessage: 'Are you sure you want to delete this class? This cannot be undone.'),
        ],
      ),
    );
  }

  void _showTaskDetails(Map<String, dynamic> task) {
    final dueDate = (task['dueDate'] as Timestamp).toDate();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final isCompleted = task['completed'] ?? false;
          return _detailSheet(
            children: [
              Text(
                'Task Details',
                style: GoogleFonts.dmMono(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildDetailRow('Task Title', task['taskTitle']),
              if ((task['taskDetails'] ?? '').isNotEmpty)
                _buildDetailRow('Details', task['taskDetails']),
              if ((task['subject'] ?? '').isNotEmpty)
                _buildDetailRow('Subject', task['subject']),
              _buildDetailRow('Type', task['taskType']),
              _buildDetailRow(
                'Due Date',
                DateFormat('EEE, dd MMM yyyy').format(dueDate),
              ),
              _buildDetailRow('Due Time', _formatTime(task['dueTime'])),
              const SizedBox(height: 8),
              _buildStatusToggleInModal(task, setModal),
            ],
            actions: [
              _outlineBtn('Edit', () async {
                Navigator.pop(ctx);
                final r = await Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => EditTaskScreen(taskData: task),
                  ),
                );
                if (r == true && mounted) setState(() {});
              }),
              _deleteBtn('Delete Task', () async {
                final m = ScaffoldMessenger.of(ctx);
                Navigator.pop(ctx);
                await _firestore.collection('tasks').doc(task['id']).delete();
                m.showSnackBar(
                  SnackBar(
                    content: Text('Task deleted', style: GoogleFonts.dmMono()),
                    backgroundColor: _red,
                  ),
                );
              }, confirmMessage: 'Are you sure you want to delete this task? This cannot be undone.'),
            ],
          );
        },
      ),
    );
  }

  void _showExamDetails(Map<String, dynamic> exam) {
    final examDate = (exam['examDate'] as Timestamp).toDate();
    final startTime = (exam['startTime'] as Timestamp).toDate();
    final endTime = (exam['endTime'] as Timestamp).toDate();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _detailSheet(
        children: [
          Text(
            'Exam Details',
            style: GoogleFonts.dmMono(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow('Exam Name', exam['examName']),
          if ((exam['subject'] ?? '').isNotEmpty)
            _buildDetailRow('Subject', exam['subject']),
          _buildDetailRow('Type', exam['type']),
          _buildDetailRow('Mode', exam['mode']),
          if (exam['mode'] == 'In Person' && (exam['venue'] ?? '').isNotEmpty)
            _buildDetailRow('Venue', exam['venue']),
          _buildDetailRow(
            'Date',
            DateFormat('EEE, dd MMM yyyy').format(examDate),
          ),
          _buildDetailRow(
            'Time',
            '${DateFormat('hh:mm a').format(startTime)} - ${DateFormat('hh:mm a').format(endTime)}',
          ),
        ],
        actions: [
          _outlineBtn('Edit', () async {
            Navigator.pop(ctx);
            final r = await Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => EditExamScreen(examData: exam)),
            );
            if (r == true && mounted) setState(() {});
          }),
          _deleteBtn('Delete Exam', () async {
            final m = ScaffoldMessenger.of(ctx);
            Navigator.pop(ctx);
            await _firestore.collection('exams').doc(exam['id']).delete();
            m.showSnackBar(
              SnackBar(
                content: Text('Exam deleted', style: GoogleFonts.dmMono()),
                backgroundColor: _red,
              ),
            );
          }, confirmMessage: 'Are you sure you want to delete this exam? This cannot be undone.'),
        ],
      ),
    );
  }

  Widget _detailSheet({
    required List<Widget> children,
    required List<Widget> actions,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.border(context), width: 2),
          left: BorderSide(color: AppColors.border(context), width: 2),
          right: BorderSide(color: AppColors.border(context), width: 2),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(child: actions[0]),
                  const SizedBox(width: 12),
                  Expanded(child: actions[1]),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _outlineBtn(String label, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.edit_outlined),
      label: Text(label, style: GoogleFonts.dmMono()),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text(context),
        side: BorderSide(color: AppColors.border(context), width: 2),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _deleteBtn(String label, Future<void> Function() onConfirmed, {String? confirmMessage}) {
    return ElevatedButton.icon(
      onPressed: () async {
        final ok = await confirmDeleteDialog(
          context,
          title: label,
          message: confirmMessage ?? 'Are you sure you want to delete this? This cannot be undone.',
        );
        if (ok) await onConfirmed();
      },
      icon: const Icon(Icons.delete_outline),
      label: Text(label, style: GoogleFonts.dmMono()),
      style: ElevatedButton.styleFrom(
        backgroundColor: _red,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildStatusToggleInModal(
    Map<String, dynamic> task,
    StateSetter setModal,
  ) {
    final isCompleted = task['completed'] ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              'Status',
              style: GoogleFonts.dmMono(fontSize: 12, color: AppColors.subtext(context)),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _AnimatedTapButton(
                    onTap: () async {
                      await _firestore
                          .collection('tasks')
                          .doc(task['id'])
                          .update({'completed': false});
                      setModal(() => task['completed'] = false);
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: !isCompleted
                            ? const Color(0xFF008BB9)
                            : AppColors.fieldBg(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !isCompleted
                              ? const Color(0xFF008BB9)
                              : AppColors.border(context),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Pending',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: !isCompleted
                                ? Colors.white
                                : AppColors.subtext(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AnimatedTapButton(
                    onTap: () async {
                      await _firestore
                          .collection('tasks')
                          .doc(task['id'])
                          .update({'completed': true});
                      setModal(() => task['completed'] = true);
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isCompleted ? _green : AppColors.fieldBg(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCompleted ? _green : AppColors.border(context),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Completed',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isCompleted
                                ? Colors.white
                                : AppColors.subtext(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
      onTapDown: (_) => setState(() => _isTapped = true),
      onTapUp: (_) => setState(() => _isTapped = false),
      onTapCancel: () => setState(() => _isTapped = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isTapped ? 0.95 : 1.0,
        duration: widget.duration,
        child: widget.child,
      ),
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color color;
  const TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// Custom Time Picker Dialog  (exact copy from AddClassScreen)
// =============================================================================

class _CustomTimePickerDialog extends StatefulWidget {
  final TimeOfDay? initialTime;
  const _CustomTimePickerDialog({this.initialTime});

  @override
  State<_CustomTimePickerDialog> createState() =>
      _CustomTimePickerDialogState();
}

class _CustomTimePickerDialogState extends State<_CustomTimePickerDialog> {
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

    _hourCtrl = TextEditingController(text: _hour.toString().padLeft(2, '0'));
    _minuteCtrl = TextEditingController(
      text: _minute.toString().padLeft(2, '0'),
    );

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
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTimeOfDay(),
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF6B7280),
              onPrimary: Colors.white,
              surface: AppColors.card(context),
              onSurface: AppColors.text(context),
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: AppColors.card(context),
              dialHandColor: const Color(0xFF6B7280),
              dialBackgroundColor: AppColors.fieldBg(context),
              hourMinuteTextColor: AppColors.text(context),
              hourMinuteColor: AppColors.fieldBg(context),
              dayPeriodTextColor: AppColors.text(context),
              dayPeriodColor: AppColors.fieldBg(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.border(context), width: 2),
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
            Text(
              'Select Time',
              style: GoogleFonts.dmMono(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            GestureDetector(
              onTap: _openDial,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.input(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border(context), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 20,
                      color: AppColors.subtext(context),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$h:$m $period',
                      style: GoogleFonts.dmMono(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.subtext(context).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app,
                            size: 12,
                            color: AppColors.subtext(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Use dial',
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              color: AppColors.subtext(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: Divider(color: AppColors.border(context))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or type manually',
                    style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.subtext(context)),
                  ),
                ),
                Expanded(child: Divider(color: AppColors.border(context))),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SpinnerField(
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
                  child: Text(
                    ':',
                    style: GoogleFonts.dmMono(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _SpinnerField(
                  controller: _minuteCtrl,
                  focusNode: _minuteFocus,
                  label: 'MM',
                  onUp: () => _incrementMinute(1),
                  onDown: () => _incrementMinute(-1),
                  onSubmitted: (_) => _commitMinute(),
                ),
                const SizedBox(width: 14),
                _AmPmToggle(
                  isAm: _isAm,
                  onChanged: (v) => setState(() => _isAm = v),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: AppColors.border(context), width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.dmMono(
                        color: AppColors.text(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Confirm',
                      style: GoogleFonts.dmMono(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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
}

// =============================================================================
// Spinner field: up/down arrows + editable text input
// =============================================================================

class _SpinnerField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ValueChanged<String> onSubmitted;

  const _SpinnerField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.onUp,
    required this.onDown,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ArrowBtn(icon: Icons.keyboard_arrow_up, onTap: onUp),
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
            style: GoogleFonts.dmMono(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: label,
              hintStyle: GoogleFonts.dmMono(
                fontSize: 18,
                color: AppColors.subtext(context),
              ),
              filled: true,
              fillColor: AppColors.input(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border(context), width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border(context), width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.subtext(context),
                  width: 2.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _ArrowBtn(icon: Icons.keyboard_arrow_down, onTap: onDown),
      ],
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ArrowBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 68,
        height: 32,
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

// =============================================================================
// AM / PM toggle
// =============================================================================

class _AmPmToggle extends StatelessWidget {
  final bool isAm;
  final ValueChanged<bool> onChanged;
  const _AmPmToggle({required this.isAm, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PeriodBtn(label: 'AM', selected: isAm, onTap: () => onChanged(true)),
        const SizedBox(height: 6),
        _PeriodBtn(label: 'PM', selected: !isAm, onTap: () => onChanged(false)),
      ],
    );
  }
}

class _PeriodBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? AppColors.subtext(context) : AppColors.fieldBg(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.subtext(context) : AppColors.border(context),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.dmMono(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : AppColors.subtext(context),
          ),
        ),
      ),
    );
  }
}
