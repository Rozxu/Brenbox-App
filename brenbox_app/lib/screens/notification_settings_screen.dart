import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_scheduler.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  bool _isLoading = true;
  bool _isSaving = false;

  // ── Track whether anything has changed since last save / load ─────────────
  bool _hasUnsavedChanges = false;

  // ── CLASS ──────────────────────────────────────────────────────────────────
  bool _classEnabled = true;
  bool _classDayBefore = true;
  int _classReminderHour = 20;
  int _classReminderMin = 0;
  bool _classHourBefore = true;
  bool _class10MinBefore = true;
  bool _classOnTime = true;

  // ── TASK ───────────────────────────────────────────────────────────────────
  bool _taskEnabled = true;
  List<int> _taskDays = [3, 2, 1];
  bool _taskHourBefore = true;
  bool _task10MinBefore = true;
  bool _taskDueNow = true;

  // ── EXAM ───────────────────────────────────────────────────────────────────
  bool _examEnabled = true;
  List<int> _examDays = [3, 2, 1];
  bool _examHourBefore = true;
  bool _exam30MinBefore = true;
  bool _exam10MinBefore = true;
  bool _examOnTime = true;

  static const List<int> _dayOptions = [1, 2, 3];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ── Mark dirty whenever any value changes ─────────────────────────────────
  void _change(VoidCallback fn) {
    setState(() {
      fn();
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _loadSettings() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final s = doc.data()?['notificationSettings'] as Map<String, dynamic>?;

    if (s != null) {
      setState(() {
        _classEnabled = s['classEnabled'] ?? true;
        _classDayBefore = s['classDayBefore'] ?? true;
        _classReminderHour = s['classReminderHour'] ?? 20;
        _classReminderMin = s['classReminderMin'] ?? 0;
        _classHourBefore = s['classHourBefore'] ?? true;
        _class10MinBefore = s['class10MinBefore'] ?? true;
        _classOnTime = s['classOnTime'] ?? true;

        _taskEnabled = s['taskEnabled'] ?? true;
        final rawTask = List<int>.from(s['taskDays'] ?? [3, 2, 1]);
        _taskDays = rawTask.where((d) => _dayOptions.contains(d)).toList();
        _taskHourBefore = s['taskHourBefore'] ?? true;
        _task10MinBefore = s['task10MinBefore'] ?? true;
        _taskDueNow = s['taskDueNow'] ?? true;

        _examEnabled = s['examEnabled'] ?? true;
        final rawExam = List<int>.from(s['examDays'] ?? [3, 2, 1]);
        _examDays = rawExam.where((d) => _dayOptions.contains(d)).toList();
        _examHourBefore = s['examHourBefore'] ?? true;
        _exam30MinBefore = s['exam30MinBefore'] ?? true;
        _exam10MinBefore = s['exam10MinBefore'] ?? true;
        _examOnTime = s['examOnTime'] ?? true;
      });
    }

    setState(() {
      _isLoading = false;
      _hasUnsavedChanges = false; // fresh from Firestore — nothing dirty
    });
  }

  Future<void> _saveSettings() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    final settings = <String, dynamic>{
      'classEnabled': _classEnabled,
      'classDayBefore': _classDayBefore,
      'classReminderHour': _classReminderHour,
      'classReminderMin': _classReminderMin,
      'classHourBefore': _classHourBefore,
      'class10MinBefore': _class10MinBefore,
      'classOnTime': _classOnTime,
      'taskEnabled': _taskEnabled,
      'taskDays': _taskDays,
      'taskHourBefore': _taskHourBefore,
      'task10MinBefore': _task10MinBefore,
      'taskDueNow': _taskDueNow,
      'examEnabled': _examEnabled,
      'examDays': _examDays,
      'examHourBefore': _examHourBefore,
      'exam30MinBefore': _exam30MinBefore,
      'exam10MinBefore': _exam10MinBefore,
      'examOnTime': _examOnTime,
    };

    await _firestore
        .collection('users')
        .doc(user.uid)
        .update({'notificationSettings': settings});

    await NotificationScheduler().rescheduleAllNotifications(forceFull: true);

    setState(() {
      _isSaving = false;
      _hasUnsavedChanges = false; // clean after save
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved!', style: GoogleFonts.dmMono()),
          backgroundColor: const Color(0xFF34A853),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Back button: ask if there are unsaved changes ──────────────────────────
  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        title: Text('Unsaved Changes',
            style: GoogleFonts.dmMono(
                fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'You have unsaved changes. Would you like to save them before leaving?',
          style: GoogleFonts.dmMono(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: Text('Discard',
                style: GoogleFonts.dmMono(
                    color: const Color(0xFFB90000),
                    fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text('Cancel',
                style: GoogleFonts.dmMono(color: const Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF292929),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Save',
                style: GoogleFonts.dmMono(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result == 'save') {
      await _saveSettings();
      return true;
    }
    if (result == 'discard') return true;
    return false; // 'cancel' — stay on screen
  }

  // ── Custom time picker ─────────────────────────────────────────────────────
  Future<void> _pickReminderTime() async {
    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (_) => _CustomTimePickerDialog(
        initialTime:
            TimeOfDay(hour: _classReminderHour, minute: _classReminderMin),
      ),
    );
    if (picked != null && mounted) {
      _change(() {
        _classReminderHour = picked.hour;
        _classReminderMin = picked.minute;
      });
    }
  }

  String _fmt12(int hour, int minute) {
    final min = minute.toString().padLeft(2, '0');
    if (hour == 0) return '12:$min AM';
    if (hour < 12) return '$hour:$min AM';
    if (hour == 12) return '12:$min PM';
    return '${hour - 12}:$min PM';
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFFE5E7EB),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () async {
              final canPop = await _onWillPop();
              if (canPop && mounted) Navigator.pop(context);
            },
          ),
          title: Row(
            children: [
              Text(
                'Notification Settings',
                style: GoogleFonts.dmMono(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              if (_hasUnsavedChanges) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBC05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Unsaved',
                      style: GoogleFonts.dmMono(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
        // ── Fixed save button at bottom ────────────────────────────────────
        bottomNavigationBar: _isLoading
            ? null
            : SafeArea(
                child: Container(
                  color: const Color(0xFFE5E7EB),
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasUnsavedChanges
                          ? const Color(0xFF292929)
                          : const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _hasUnsavedChanges
                                    ? Icons.save
                                    : Icons.check_circle_outline,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _hasUnsavedChanges
                                    ? 'Save Settings'
                                    : 'Settings Saved',
                                style: GoogleFonts.dmMono(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
        body: _isLoading
            ? const Center(
                child:
                    CircularProgressIndicator(color: Color(0xFF6B7280)))
            : SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ══ CLASS ════════════════════════════════════════════
                    _sectionHeader(
                      '📚 Class Notifications',
                      _classEnabled,
                      (v) => _change(() => _classEnabled = v),
                      const Color(0xFFB90000),
                    ),
                    if (_classEnabled) ...[
                      const SizedBox(height: 10),
                      _dayBeforeRow(),
                      _toggleRow(
                        '1 hour before class starts',
                        _classHourBefore,
                        (v) => _change(() => _classHourBefore = v),
                      ),
                      _toggleRow(
                        '10 minutes before class starts',
                        _class10MinBefore,
                        (v) => _change(() => _class10MinBefore = v),
                      ),
                      _toggleRow(
                        'When class is starting (on time)',
                        _classOnTime,
                        (v) => _change(() => _classOnTime = v),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ══ TASK ═════════════════════════════════════════════
                    _sectionHeader(
                      '✅ Task Notifications',
                      _taskEnabled,
                      (v) => _change(() => _taskEnabled = v),
                      const Color(0xFF008BB9),
                    ),
                    if (_taskEnabled) ...[
                      const SizedBox(height: 10),
                      _subLabel(
                          'Remind before due date (fires N×24h before the due time):'),
                      const SizedBox(height: 8),
                      _daysSelector(_taskDays,
                          (d) => _change(() => _taskDays = d)),
                      const SizedBox(height: 6),
                      _toggleRow(
                        '1 hour before deadline',
                        _taskHourBefore,
                        (v) => _change(() => _taskHourBefore = v),
                      ),
                      _toggleRow(
                        '10 minutes before deadline',
                        _task10MinBefore,
                        (v) => _change(() => _task10MinBefore = v),
                      ),
                      _toggleRow(
                        'When deadline arrives (due now)',
                        _taskDueNow,
                        (v) => _change(() => _taskDueNow = v),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ══ EXAM ═════════════════════════════════════════════
                    _sectionHeader(
                      '📝 Exam Notifications',
                      _examEnabled,
                      (v) => _change(() => _examEnabled = v),
                      const Color(0xFF9AB900),
                    ),
                    if (_examEnabled) ...[
                      const SizedBox(height: 10),
                      _subLabel(
                          'Remind before exam (fires N×24h before the exam start time):'),
                      const SizedBox(height: 8),
                      _daysSelector(_examDays,
                          (d) => _change(() => _examDays = d)),
                      const SizedBox(height: 6),
                      _toggleRow(
                        '1 hour before exam',
                        _examHourBefore,
                        (v) => _change(() => _examHourBefore = v),
                      ),
                      _toggleRow(
                        '30 minutes before exam',
                        _exam30MinBefore,
                        (v) => _change(() => _exam30MinBefore = v),
                      ),
                      _toggleRow(
                        '10 minutes before exam',
                        _exam10MinBefore,
                        (v) => _change(() => _exam10MinBefore = v),
                      ),
                      _toggleRow(
                        'When exam is starting (on time)',
                        _examOnTime,
                        (v) => _change(() => _examOnTime = v),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
      ),
    );
  }

  // ── WIDGET HELPERS ─────────────────────────────────────────────────────────

  Widget _sectionHeader(
    String title,
    bool enabled,
    ValueChanged<bool> onChanged,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Row(
        children: [
          Expanded(
              child: Text(title,
                  style: GoogleFonts.dmMono(
                      fontSize: 14, fontWeight: FontWeight.bold))),
          Switch(value: enabled, onChanged: onChanged, activeColor: color),
        ],
      ),
    );
  }

  Widget _dayBeforeRow() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Day before class reminder',
                    style: GoogleFonts.dmMono(fontSize: 12)),
                if (_classDayBefore) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickReminderTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB90000).withOpacity(0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFB90000), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time,
                              size: 14, color: Color(0xFFB90000)),
                          const SizedBox(width: 6),
                          Text(
                            'Remind at ${_fmt12(_classReminderHour, _classReminderMin)}',
                            style: GoogleFonts.dmMono(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFB90000),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.edit,
                              size: 12, color: Color(0xFFB90000)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: _classDayBefore,
            onChanged: (v) => _change(() => _classDayBefore = v),
            activeColor: const Color(0xFF34A853),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
              child: Text(label, style: GoogleFonts.dmMono(fontSize: 12))),
          Switch(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF34A853)),
        ],
      ),
    );
  }

  Widget _subLabel(String text) {
    return Text(text,
        style: GoogleFonts.dmMono(
            fontSize: 11, color: const Color(0xFF6B7280)));
  }

  Widget _daysSelector(List<int> selected, ValueChanged<List<int>> onChange) {
    return Row(
      children: _dayOptions.map((day) {
        final isSel = selected.contains(day);
        return GestureDetector(
          onTap: () {
            final updated = List<int>.from(selected);
            isSel ? updated.remove(day) : updated.add(day);
            updated.sort((a, b) => b.compareTo(a));
            onChange(updated);
          },
          child: Container(
            margin: const EdgeInsets.only(right: 10),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: isSel ? const Color(0xFF292929) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSel ? const Color(0xFF292929) : Colors.grey,
                width: 1.5,
              ),
            ),
            child: Text(
              day == 1 ? '1 day' : '$day days',
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSel ? Colors.white : Colors.black,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// =============================================================================
// Custom Time Picker Dialog
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
    _minuteCtrl =
        TextEditingController(text: _minute.toString().padLeft(2, '0'));
    _hourFocus = FocusNode()
      ..addListener(() {
        if (_hourFocus.hasFocus) {
          _hourCtrl.selection =
              TextSelection(baseOffset: 0, extentOffset: _hourCtrl.text.length);
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
              baseOffset: 0, extentOffset: _minuteCtrl.text.length);
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
    if (v != null && v >= 1 && v <= 12) setState(() => _hour = v);
    _hourCtrl.text = _hour.toString().padLeft(2, '0');
  }

  void _commitMinute() {
    final v = int.tryParse(_minuteCtrl.text);
    if (v != null && v >= 0 && v <= 59) setState(() => _minute = v);
    _minuteCtrl.text = _minute.toString().padLeft(2, '0');
  }

  TimeOfDay _toTimeOfDay() {
    int h = _hour % 12;
    if (!_isAm) h += 12;
    return TimeOfDay(hour: h, minute: _minute);
  }

  void _incrementHour(int d) {
    setState(() {
      _hour = ((_hour - 1 + d) % 12 + 12) % 12 + 1;
      _hourCtrl.text = _hour.toString().padLeft(2, '0');
    });
  }

  void _incrementMinute(int d) {
    setState(() {
      _minute = (_minute + d + 60) % 60;
      _minuteCtrl.text = _minute.toString().padLeft(2, '0');
    });
  }

  Future<void> _openDial() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTimeOfDay(),
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFB90000),
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Colors.black,
          ),
          timePickerTheme: TimePickerThemeData(
            backgroundColor: Colors.white,
            dialHandColor: const Color(0xFFB90000),
            dialBackgroundColor: Colors.grey.shade100,
            hourMinuteTextColor: Colors.black,
            hourMinuteColor: Colors.grey.shade200,
            dayPeriodTextColor: Colors.black,
            dayPeriodColor: Colors.grey.shade200,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.black, width: 2),
            ),
          ),
        ),
        child: child!,
      ),
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
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select Reminder Time',
                style: GoogleFonts.dmMono(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _openDial,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black26, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.access_time,
                        size: 20, color: Color(0xFFB90000)),
                    const SizedBox(width: 10),
                    Text('$h:$m $period',
                        style: GoogleFonts.dmMono(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB90000).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.touch_app,
                              size: 12, color: Color(0xFFB90000)),
                          const SizedBox(width: 4),
                          Text('Use dial',
                              style: GoogleFonts.dmMono(
                                  fontSize: 10,
                                  color: const Color(0xFFB90000))),
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
                const Expanded(child: Divider(color: Colors.black12)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('or type manually',
                      style: GoogleFonts.dmMono(
                          fontSize: 10, color: Colors.grey)),
                ),
                const Expanded(child: Divider(color: Colors.black12)),
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
                  child: Text(':',
                      style: GoogleFonts.dmMono(
                          fontSize: 28, fontWeight: FontWeight.bold)),
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
                    isAm: _isAm, onChanged: (v) => setState(() => _isAm = v)),
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
                      side: const BorderSide(color: Colors.black, width: 2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Cancel',
                        style: GoogleFonts.dmMono(
                            color: Colors.black,
                            fontWeight: FontWeight.bold)),
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
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
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
// Spinner field
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
                fontSize: 26, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              counterText: '',
              hintText: label,
              hintStyle: GoogleFonts.dmMono(
                  fontSize: 18, color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Colors.black, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Colors.black, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: Color(0xFFB90000), width: 2.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black12),
        ),
        child: Icon(icon, size: 22, color: Colors.black54),
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
        _PeriodBtn(
            label: 'PM', selected: !isAm, onTap: () => onChanged(false)),
      ],
    );
  }
}

class _PeriodBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFB90000) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFFB90000) : Colors.black26,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.dmMono(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}