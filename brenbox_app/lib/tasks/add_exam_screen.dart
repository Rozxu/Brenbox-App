import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../services/notification_scheduler.dart';

class AddExamScreen extends StatefulWidget {
  const AddExamScreen({Key? key}) : super(key: key);

  @override
  State<AddExamScreen> createState() => _AddExamScreenState();
}

class _AddExamScreenState extends State<AddExamScreen> {
  final _examNameController = TextEditingController();
  final _venueController = TextEditingController();

  String? _selectedSubject;
  String? _selectedType;
  String? _selectedMode;
  DateTime? _examDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  List<String> _availableSubjects = [];
  bool _isLoadingSubjects = true;

  final List<String> _examTypes = ['Final Exam', 'Quiz', 'Test'];
  final List<String> _examModes = ['In Person', 'Online'];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  @override
  void dispose() {
    _examNameController.dispose();
    _venueController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('timetable')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'class')
          .get();

      final subjects = <String>{};
      for (var doc in classesSnapshot.docs) {
        final className = doc.data()['className'] as String?;
        if (className != null && className.isNotEmpty) {
          subjects.add(className);
        }
      }

      setState(() {
        _availableSubjects = subjects.toList()..sort();
        _isLoadingSubjects = false;
      });
    } catch (e) {
      print('Error loading subjects: $e');
      setState(() {
        _isLoadingSubjects = false;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF9AB900)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _examDate = picked;
      });
    }
  }

  // ── Updated _selectTime: opens the custom dialog ──────────────────────────
  Future<void> _selectTime(BuildContext context, bool isStartTime) async {
    final initial = isStartTime ? _startTime : _endTime;

    final TimeOfDay? picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (_) => _CustomTimePickerDialog(initialTime: initial),
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (isStartTime) {
        _startTime = picked;
        if (_endTime != null) {
          final startMins = picked.hour * 60 + picked.minute;
          final endMins = _endTime!.hour * 60 + _endTime!.minute;
          if (endMins <= startMins) {
            _endTime = null;
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                final h =
                    picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
                final m = picked.minute.toString().padLeft(2, '0');
                final p =
                    picked.period == DayPeriod.am ? 'AM' : 'PM';
                _showError(
                  'Time Validation',
                  'Please select a new end time after $h:$m $p',
                );
              }
            });
          }
        }
      } else {
        if (_startTime != null) {
          final startMins = _startTime!.hour * 60 + _startTime!.minute;
          final endMins = picked.hour * 60 + picked.minute;
          if (endMins <= startMins) {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                _showError(
                  'Invalid Time',
                  'End time must be after start time',
                );
              }
            });
            return;
          }
        }
        _endTime = picked;
      }
    });
  }

  // Check for exam time clash
  Future<Map<String, dynamic>?> _checkExamClash(
    DateTime date,
    String startTime,
    String endTime,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final existingExams = await FirebaseFirestore.instance
        .collection('exams')
        .where('userId', isEqualTo: user.uid)
        .get();

    for (var doc in existingExams.docs) {
      try {
        final data = doc.data();
        final timestamp = data['examDate'] as Timestamp?;

        if (timestamp != null) {
          final examDate = timestamp.toDate();

          if (examDate.year == date.year &&
              examDate.month == date.month &&
              examDate.day == date.day) {
            final existingStartTimestamp = data['startTime'] as Timestamp;
            final existingEndTimestamp = data['endTime'] as Timestamp;

            final existingStart = existingStartTimestamp.toDate();
            final existingEnd = existingEndTimestamp.toDate();

            final existingStartStr =
                '${existingStart.hour.toString().padLeft(2, '0')}:${existingStart.minute.toString().padLeft(2, '0')}';
            final existingEndStr =
                '${existingEnd.hour.toString().padLeft(2, '0')}:${existingEnd.minute.toString().padLeft(2, '0')}';

            final newStartMinutes = _timeToMinutes(startTime);
            final newEndMinutes = _timeToMinutes(endTime);
            final existingStartMinutes = _timeToMinutes(existingStartStr);
            final existingEndMinutes = _timeToMinutes(existingEndStr);

            if (newStartMinutes < existingEndMinutes &&
                newEndMinutes > existingStartMinutes) {
              return {
                'examName': data['examName'] ?? 'Untitled Exam',
                'type': data['type'] ?? 'Exam',
                'startTime': existingStartStr,
                'endTime': existingEndStr,
                'date': examDate,
              };
            }
          }
        }
      } catch (e) {
        print('Error checking clash: $e');
        continue;
      }
    }

    return null;
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String _formatTime(String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];

    if (hour == 0) {
      return '12:$minute AM';
    } else if (hour < 12) {
      return '$hour:$minute AM';
    } else if (hour == 12) {
      return '12:$minute PM';
    } else {
      return '${hour - 12}:$minute PM';
    }
  }

  Future<void> _saveExam() async {
    if (_examNameController.text.trim().isEmpty) {
      _showError('Validation Error', 'Please enter exam name');
      return;
    }

    if (_selectedType == null) {
      _showError('Validation Error', 'Please select exam type');
      return;
    }

    if (_selectedMode == null) {
      _showError('Validation Error', 'Please select exam mode');
      return;
    }

    if (_selectedMode == 'In Person' && _venueController.text.trim().isEmpty) {
      _showError('Validation Error', 'Please enter venue for in-person exam');
      return;
    }

    if (_examDate == null) {
      _showError('Validation Error', 'Please select exam date');
      return;
    }

    if (_startTime == null) {
      _showError('Validation Error', 'Please select start time');
      return;
    }

    if (_endTime == null) {
      _showError('Validation Error', 'Please select end time');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Error', 'User not authenticated');
      return;
    }

    try {
      final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
      final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
      if (endMinutes <= startMinutes) {
        _showError('Validation Error', 'End time must be after start time');
        return;
      }

      final startTimeStr =
          '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}';
      final endTimeStr =
          '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}';

      final normalizedDate = DateTime(
        _examDate!.year,
        _examDate!.month,
        _examDate!.day,
      );

      final clash = await _checkExamClash(
        normalizedDate,
        startTimeStr,
        endTimeStr,
      );

      if (clash != null) {
        _showError(
          'Time Clash',
          'Exam time clashes with:\n\n'
              '${clash['examName']} (${clash['type']})\n'
              '${_formatTime(clash['startTime'])} - ${_formatTime(clash['endTime'])}\n'
              'on ${DateFormat('EEE, dd MMM yyyy').format(clash['date'])}',
        );
        return;
      }

      final startDateTime = DateTime(
        _examDate!.year,
        _examDate!.month,
        _examDate!.day,
        _startTime!.hour,
        _startTime!.minute,
      );

      final endDateTime = DateTime(
        _examDate!.year,
        _examDate!.month,
        _examDate!.day,
        _endTime!.hour,
        _endTime!.minute,
      );

      await FirebaseFirestore.instance.collection('exams').add({
        'userId': user.uid,
        'examName': _examNameController.text.trim(),
        'subject': _selectedSubject ?? '',
        'type': _selectedType,
        'mode': _selectedMode,
        'venue':
            _selectedMode == 'In Person' ? _venueController.text.trim() : '',
        'examDate': Timestamp.fromDate(_examDate!),
        'startTime': Timestamp.fromDate(startDateTime),
        'endTime': Timestamp.fromDate(endDateTime),
        'createdAt': Timestamp.now(),
      });

      await NotificationScheduler().rescheduleAllNotifications();

      if (!mounted) return;

      final shouldNavigate = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.black, width: 2),
              ),
              title: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Success!',
                      style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Text(
                'Exam has been successfully saved',
                style: GoogleFonts.dmMono(fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(
                    'OK',
                    style: GoogleFonts.dmMono(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );

      if (shouldNavigate == true && mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      print('Error saving exam: $e');
      if (mounted) {
        _showError('Save Error', 'Error saving exam. Please try again.');
      }
    }
  }

  void _showError(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFB90000), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.dmMono(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        content: Text(message, style: GoogleFonts.dmMono(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: GoogleFonts.dmMono(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('Exam'),
          const SizedBox(height: 8),
          _buildTextField(_examNameController, 'Exam Name'),
          const SizedBox(height: 16),

          _buildLabel('Subject (Optional)'),
          const SizedBox(height: 8),
          _buildSubjectSelector(),
          const SizedBox(height: 16),

          _buildLabel('Type'),
          const SizedBox(height: 8),
          _buildTypeSelector(),
          const SizedBox(height: 16),

          _buildLabel('Mode'),
          const SizedBox(height: 8),
          _buildModeSelector(),
          const SizedBox(height: 16),

          if (_selectedMode == 'In Person') ...[
            _buildLabel('Venue'),
            const SizedBox(height: 8),
            _buildTextField(_venueController, 'Venue Name'),
            const SizedBox(height: 16),
          ],

          _buildLabel('Date'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _selectDate(context),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _examDate != null
                          ? DateFormat('EEE, dd MMM yyyy').format(_examDate!)
                          : 'Sun, 21 Dec 2025',
                      style: GoogleFonts.dmMono(
                        fontSize: 14,
                        color: _examDate != null ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                  const Icon(Icons.calendar_today, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Start Time'),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _selectTime(context, true),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _startTime != null
                                  ? _formatTimeOfDay(_startTime!)
                                  : '05:00 AM',
                              style: GoogleFonts.dmMono(
                                fontSize: 14,
                                color: _startTime != null
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                            const Icon(Icons.access_time, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('End Time'),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _selectTime(context, false),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _endTime != null
                                  ? _formatTimeOfDay(_endTime!)
                                  : '08:00 AM',
                              style: GoogleFonts.dmMono(
                                fontSize: 14,
                                color: _endTime != null
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                            const Icon(Icons.access_time, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.black, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.dmMono(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveExam,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9AB900),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Save Exam',
                    style: GoogleFonts.dmMono(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: GoogleFonts.dmMono(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmMono(fontSize: 14, color: Colors.grey),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildSubjectSelector() {
    if (_isLoadingSubjects) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading subjects...',
              style: GoogleFonts.dmMono(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (_availableSubjects.isEmpty) {
          _showError(
            'No Subjects',
            'No classes found. Add classes first to link them to exams.',
          );
          return;
        }

        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: Colors.black, width: 2),
                  left: BorderSide(color: Colors.black, width: 2),
                  right: BorderSide(color: Colors.black, width: 2),
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
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Select Subject',
                        style: GoogleFonts.dmMono(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      itemCount: _availableSubjects.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ListTile(
                            title: Text(
                              'None',
                              style: GoogleFonts.dmMono(fontSize: 14),
                            ),
                            onTap: () {
                              setState(() => _selectedSubject = null);
                              Navigator.pop(context);
                            },
                          );
                        }
                        final subject = _availableSubjects[index - 1];
                        return ListTile(
                          title: Text(
                            subject,
                            style: GoogleFonts.dmMono(fontSize: 14),
                          ),
                          trailing: _selectedSubject == subject
                              ? const Icon(Icons.check,
                                  color: Color(0xFF9AB900))
                              : null,
                          onTap: () {
                            setState(() => _selectedSubject = subject);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _selectedSubject ?? 'Select Subject',
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  color:
                      _selectedSubject != null ? Colors.black : Colors.grey,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: _examTypes.map((type) {
        final isSelected = _selectedType == type;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: type != _examTypes.last ? 8 : 0,
            ),
            child: GestureDetector(
              onTap: () => setState(() => _selectedType = type),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFEFFE6) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        isSelected ? const Color(0xFF9AB900) : Colors.black,
                    width: 2,
                  ),
                ),
                child: Text(
                  type,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmMono(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: _examModes.map((mode) {
        final isSelected = _selectedMode == mode;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: mode != _examModes.last ? 8 : 0,
            ),
            child: GestureDetector(
              onTap: () => setState(() => _selectedMode = mode),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFEFFE6) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        isSelected ? const Color(0xFF9AB900) : Colors.black,
                    width: 2,
                  ),
                ),
                child: Text(
                  mode,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmMono(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
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
  late int _hour;   // 1–12
  late int _minute; // 0–59
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
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTimeOfDay(),
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF9AB900),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.white,
              dialHandColor: const Color(0xFF9AB900),
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
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black26, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 20,
                      color: Color(0xFF9AB900),
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
                        color: const Color(0xFF9AB900).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.touch_app,
                            size: 12,
                            color: Color(0xFF9AB900),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Use dial',
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              color: const Color(0xFF9AB900),
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
                const Expanded(child: Divider(color: Colors.black12)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or type manually',
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
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
                      side: const BorderSide(color: Colors.black, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.dmMono(
                        color: Colors.black,
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
                      backgroundColor: const Color(0xFF9AB900),
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
                color: Colors.grey.shade400,
              ),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.black, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.black, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Color(0xFF9AB900),
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
          label: 'PM',
          selected: !isAm,
          onTap: () => onChanged(false),
        ),
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
          color: selected ? const Color(0xFF9AB900) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF9AB900) : Colors.black26,
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