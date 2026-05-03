import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../services/notification_scheduler.dart';

class EditClassScreen extends StatefulWidget {
  final Map<String, dynamic> classData;

  const EditClassScreen({Key? key, required this.classData}) : super(key: key);

  @override
  State<EditClassScreen> createState() => _EditClassScreenState();
}

class _EditClassScreenState extends State<EditClassScreen> {
  late TextEditingController _classController;
  late TextEditingController _roomController;
  late TextEditingController _buildingController;
  late TextEditingController _lecturerController;

  late DateTime _classDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  int? _selectedSemester;
  int? _selectedYear;
  String? _academicYear;

  @override
  void initState() {
    super.initState();

    print('📝 Edit screen received data: ${widget.classData}');

    _classController = TextEditingController(text: widget.classData['className'] ?? '');
    _roomController = TextEditingController(text: widget.classData['room'] ?? '');
    _buildingController = TextEditingController(text: widget.classData['building'] ?? '');
    _lecturerController = TextEditingController(text: widget.classData['lecturerName'] ?? '');

    final timestamp = widget.classData['date'] as Timestamp?;
    _classDate = timestamp?.toDate() ?? DateTime.now();

    _startTime = _parseTime(widget.classData['startTime'] ?? '00:00');
    _endTime = _parseTime(widget.classData['endTime'] ?? '00:00');

    _selectedSemester = widget.classData['semester'];
    _academicYear = widget.classData['academicYear'];

    print('🔍 Semester: $_selectedSemester, Academic Year: $_academicYear');

    if (_academicYear != null) {
      final parts = _academicYear!.split('/');
      if (parts.isNotEmpty) {
        _selectedYear = int.tryParse(parts[0]);
      }
    }

    print('✅ Parsed Year: $_selectedYear');
  }

  TimeOfDay _parseTime(String time) {
    try {
      final parts = time.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return TimeOfDay.now();
    }
  }

  @override
  void dispose() {
    _classController.dispose();
    _roomController.dispose();
    _buildingController.dispose();
    _lecturerController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _classDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF6B7280)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _classDate = picked;
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
        final startMins = picked.hour * 60 + picked.minute;
        final endMins = _endTime.hour * 60 + _endTime.minute;
        if (endMins <= startMins) {
          _endTime = TimeOfDay(hour: picked.hour + 1, minute: picked.minute);
        }
      } else {
        final startMins = _startTime.hour * 60 + _startTime.minute;
        final endMins = picked.hour * 60 + picked.minute;
        if (endMins <= startMins) {
          _showError('Invalid Time', 'End time must be after start time');
          return;
        }
        _endTime = picked;
      }
    });
  }

  Future<void> _updateClass() async {
    if (_classController.text.trim().isEmpty) {
      _showError('Validation Error', 'Please enter class name');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Error', 'User not authenticated');
      return;
    }

    try {
      final startTimeStr =
          '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
      final endTimeStr =
          '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';

      final normalizedDate =
          DateTime(_classDate.year, _classDate.month, _classDate.day);

      final clash =
          await _checkClassClash(normalizedDate, startTimeStr, endTimeStr);
      if (clash != null) {
        _showError(
          'Time Clash',
          'Class time clashes with:\n\n'
              '${clash['className']}\n'
              '${_formatTime(clash['startTime'])} - ${_formatTime(clash['endTime'])}\n'
              'on ${DateFormat('EEE, dd MMM yyyy').format(clash['date'])}',
        );
        return;
      }

      Map<String, dynamic> updateData = {
        'className': _classController.text.trim(),
        'room': _roomController.text.trim(),
        'building': _buildingController.text.trim(),
        'lecturerName': _lecturerController.text.trim(),
        'date': Timestamp.fromDate(normalizedDate),
        'startTime': startTimeStr,
        'endTime': endTimeStr,
        'updatedAt': Timestamp.now(),
      };

      if (_selectedSemester != null) {
        updateData['semester'] = _selectedSemester;
      }
      if (_selectedYear != null) {
        updateData['academicYear'] = '$_selectedYear/${_selectedYear! + 1}';
      }

      await FirebaseFirestore.instance
          .collection('timetable')
          .doc(widget.classData['id'])
          .update(updateData);

      await NotificationScheduler().rescheduleAllNotifications();

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
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
                    'Updated!',
                    style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(
              'Class has been successfully updated',
              style: GoogleFonts.dmMono(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  'OK',
                  style: GoogleFonts.dmMono(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      print('Error updating class: $e');
      if (mounted) {
        _showError('Update Error', 'Error updating class. Please try again.');
      }
    }
  }

  Future<Map<String, dynamic>?> _checkClassClash(
    DateTime date,
    String startTime,
    String endTime,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final existingClasses = await FirebaseFirestore.instance
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .get();

    for (var doc in existingClasses.docs) {
      if (doc.id == widget.classData['id']) continue;

      try {
        final data = doc.data();
        final timestamp = data['date'] as Timestamp?;

        if (timestamp != null) {
          final eventDate = timestamp.toDate();

          if (eventDate.year == date.year &&
              eventDate.month == date.month &&
              eventDate.day == date.day) {
            final existingStart = data['startTime'] as String;
            final existingEnd = data['endTime'] as String;

            final newStartMinutes = _timeToMinutes(startTime);
            final newEndMinutes = _timeToMinutes(endTime);
            final existingStartMinutes = _timeToMinutes(existingStart);
            final existingEndMinutes = _timeToMinutes(existingEnd);

            if (newStartMinutes < existingEndMinutes &&
                newEndMinutes > existingStartMinutes) {
              return {
                'className': data['className'] ?? 'Untitled Class',
                'startTime': existingStart,
                'endTime': existingEnd,
                'date': eventDate,
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

    if (hour == 0) return '12:$minute AM';
    if (hour < 12) return '$hour:$minute AM';
    if (hour == 12) return '12:$minute PM';
    return '${hour - 12}:$minute PM';
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
                    fontWeight: FontWeight.bold, fontSize: 14),
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
                  fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color.fromARGB(255, 43, 43, 43),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        title: Text(
          'EDIT CLASS',
          style: GoogleFonts.dmMono(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            _buildLabel('Class Name'),
            const SizedBox(height: 8),
            _buildTextField(_classController, 'Enter class name'),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Room'),
                      const SizedBox(height: 8),
                      _buildTextField(_roomController, 'Room'),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Building'),
                      const SizedBox(height: 8),
                      _buildTextField(_buildingController, 'Building'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildLabel('Lecturer Name'),
            const SizedBox(height: 8),
            _buildTextField(_lecturerController, 'Enter lecturer name'),
            const SizedBox(height: 16),

            if (_selectedSemester != null || _selectedYear != null) ...[
              _buildSemesterYearSelector(),
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
                        DateFormat('EEE, dd MMM yyyy').format(_classDate),
                        style: GoogleFonts.dmMono(fontSize: 14),
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
                                _formatTimeOfDay(_startTime),
                                style: GoogleFonts.dmMono(fontSize: 14),
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
                                _formatTimeOfDay(_endTime),
                                style: GoogleFonts.dmMono(fontSize: 14),
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
                    onPressed: _updateClass,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB90000),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Update Class',
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

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Widget _buildSemesterYearSelector() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Semester'),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    canvasColor: Colors.white,
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFF6B7280),
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: Colors.black,
                    ),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedSemester ?? 1,
                    isExpanded: true,
                    underline: const SizedBox(),
                    style:
                        GoogleFonts.dmMono(fontSize: 14, color: Colors.black),
                    dropdownColor: Colors.white,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
                    items: List.generate(10, (index) => index + 1)
                        .map(
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text(
                              'Semester $i',
                              style: GoogleFonts.dmMono(
                                  fontSize: 14, color: Colors.black),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedSemester = value);
                      }
                    },
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
              _buildLabel('Academic Year'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: TextField(
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.dmMono(fontSize: 14),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: _selectedYear != null
                              ? (_selectedYear! % 100)
                                  .toString()
                                  .padLeft(2, '0')
                              : '25',
                          hintStyle: GoogleFonts.dmMono(
                              fontSize: 14, color: Colors.grey),
                          border: InputBorder.none,
                        ),
                        maxLength: 2,
                        buildCounter: (context,
                                {required currentLength,
                                required isFocused,
                                maxLength}) =>
                            null,
                        controller: TextEditingController(
                          text: _selectedYear != null
                              ? (_selectedYear! % 100)
                                  .toString()
                                  .padLeft(2, '0')
                              : '',
                        ),
                        onChanged: (value) {
                          if (value.isNotEmpty && value.length == 2) {
                            final year = int.tryParse('20$value');
                            if (year != null) {
                              setState(() => _selectedYear = year);
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '/',
                      style: GoogleFonts.dmMono(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: TextField(
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.dmMono(fontSize: 14),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: _selectedYear != null
                              ? ((_selectedYear! + 1) % 100)
                                  .toString()
                                  .padLeft(2, '0')
                              : '26',
                          hintStyle: GoogleFonts.dmMono(
                              fontSize: 14, color: Colors.grey),
                          border: InputBorder.none,
                        ),
                        maxLength: 2,
                        buildCounter: (context,
                                {required currentLength,
                                required isFocused,
                                maxLength}) =>
                            null,
                        controller: TextEditingController(
                          text: _selectedYear != null
                              ? ((_selectedYear! + 1) % 100)
                                  .toString()
                                  .padLeft(2, '0')
                              : '',
                        ),
                        enabled: false,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
              primary: Color(0xFF6B7280),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.white,
              dialHandColor: const Color(0xFF6B7280),
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
                  fontSize: 15, fontWeight: FontWeight.bold),
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
                    const Icon(Icons.access_time,
                        size: 20, color: Color(0xFF6B7280)),
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
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B7280).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.touch_app,
                              size: 12, color: Color(0xFF6B7280)),
                          const SizedBox(width: 4),
                          Text(
                            'Use dial',
                            style: GoogleFonts.dmMono(
                                fontSize: 10, color: const Color(0xFF6B7280)),
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
                    style: GoogleFonts.dmMono(fontSize: 10, color: Colors.grey),
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
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Cancel',
                        style: GoogleFonts.dmMono(
                            color: Colors.black, fontWeight: FontWeight.bold)),
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
                            color: Colors.white, fontWeight: FontWeight.bold)),
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
            style: GoogleFonts.dmMono(fontSize: 26, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              counterText: '',
              hintText: label,
              hintStyle:
                  GoogleFonts.dmMono(fontSize: 18, color: Colors.grey.shade400),
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
                borderSide:
                    const BorderSide(color: Color(0xFF6B7280), width: 2.5),
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
          color: selected ? const Color(0xFF6B7280) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF6B7280) : Colors.black26,
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