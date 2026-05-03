import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../services/notification_scheduler.dart';

class AddClassScreen extends StatefulWidget {
  const AddClassScreen({Key? key}) : super(key: key);

  @override
  State<AddClassScreen> createState() => _AddClassScreenState();
}

class _AddClassScreenState extends State<AddClassScreen> {
  final _classController = TextEditingController();
  final _roomController = TextEditingController();
  final _buildingController = TextEditingController();
  final _lecturerController = TextEditingController();

  String _dateOption = 'None'; // None, Manual, Academic Year/Term
  String _occurrence = 'Once'; // Once, Repeating

  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  int _selectedSemester = 1;
  int _selectedYear = DateTime.now().year;

  Set<int> _selectedDays = {}; // 1=Mon, 2=Tue, ..., 7=Sun

  @override
  void dispose() {
    _classController.dispose();
    _roomController.dispose();
    _buildingController.dispose();
    _lecturerController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
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
        if (isStartDate) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(picked)) {
            _endDate = null;
          }
        } else {
          if (_startDate != null && picked.isBefore(_startDate!)) {
            _showError('Invalid Date', 'End date must be after start date');
            return;
          }
          _endDate = picked;
        }
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

  Future<void> _saveClass() async {
    if (_classController.text.trim().isEmpty) {
      _showMessage('Please enter class name');
      return;
    }

    if (_startTime == null || _endTime == null) {
      _showMessage('Please select start and end time');
      return;
    }

    if (_dateOption == 'Manual' &&
        (_startDate == null || _endDate == null)) {
      _showMessage('Please select start and end dates');
      return;
    }

    if (_dateOption == 'Manual' &&
        _occurrence == 'Repeating' &&
        _selectedDays.isEmpty) {
      _showMessage('Please select at least one day for repeating class');
      return;
    }

    if (_dateOption == 'Academic Year/Term' &&
        (_startDate == null || _endDate == null)) {
      _showMessage('Please select start and end dates');
      return;
    }

    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
    if (endMinutes <= startMinutes) {
      _showMessage('End time must be after start time');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('User not authenticated');
      return;
    }

    try {
      List<Map<String, dynamic>> classEvents = [];
      final startTimeStr =
          '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}';
      final endTimeStr =
          '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}';

      if (_dateOption == 'None') {
        final eventDate = _startDate ?? DateTime.now();
        final normalizedDate = DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
        );

        final clash = await _checkClassClash(
          normalizedDate,
          startTimeStr,
          endTimeStr,
        );
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

        classEvents.add({
          'date': Timestamp.fromDate(normalizedDate),
          'className': _classController.text.trim(),
          'room': _roomController.text.trim(),
          'building': _buildingController.text.trim(),
          'lecturerName': _lecturerController.text.trim(),
          'startTime': startTimeStr,
          'endTime': endTimeStr,
          'type': 'class',
          'userId': user.uid,
          'createdAt': Timestamp.now(),
        });
      } else if (_occurrence == 'Once') {
        final eventDate = _startDate!;
        final normalizedDate = DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
        );

        final clash = await _checkClassClash(
          normalizedDate,
          startTimeStr,
          endTimeStr,
        );
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

        Map<String, dynamic> event = {
          'date': Timestamp.fromDate(normalizedDate),
          'className': _classController.text.trim(),
          'room': _roomController.text.trim(),
          'building': _buildingController.text.trim(),
          'lecturerName': _lecturerController.text.trim(),
          'startTime': startTimeStr,
          'endTime': endTimeStr,
          'type': 'class',
          'userId': user.uid,
          'createdAt': Timestamp.now(),
        };

        if (_dateOption == 'Academic Year/Term') {
          event['semester'] = _selectedSemester;
          event['academicYear'] = '$_selectedYear/${_selectedYear + 1}';
        }

        classEvents.add(event);
      } else if (_occurrence == 'Repeating') {
        DateTime currentDate = _startDate!;
        final endDate = _endDate!;
        List<Map<String, dynamic>> clashInfo = [];

        while (currentDate.isBefore(endDate) ||
            (currentDate.year == endDate.year &&
                currentDate.month == endDate.month &&
                currentDate.day == endDate.day)) {
          if (_selectedDays.contains(currentDate.weekday)) {
            final normalizedDate = DateTime(
              currentDate.year,
              currentDate.month,
              currentDate.day,
            );

            final clash = await _checkClassClash(
              normalizedDate,
              startTimeStr,
              endTimeStr,
            );
            if (clash != null) {
              clashInfo.add({
                'date': normalizedDate,
                'className': clash['className'],
                'startTime': clash['startTime'],
                'endTime': clash['endTime'],
              });
            } else {
              Map<String, dynamic> event = {
                'date': Timestamp.fromDate(normalizedDate),
                'className': _classController.text.trim(),
                'room': _roomController.text.trim(),
                'building': _buildingController.text.trim(),
                'lecturerName': _lecturerController.text.trim(),
                'startTime': startTimeStr,
                'endTime': endTimeStr,
                'type': 'class',
                'userId': user.uid,
                'createdAt': Timestamp.now(),
              };

              if (_dateOption == 'Academic Year/Term') {
                event['semester'] = _selectedSemester;
                event['academicYear'] =
                    '$_selectedYear/${_selectedYear + 1}';
              }

              classEvents.add(event);
            }
          }
          currentDate = currentDate.add(const Duration(days: 1));
        }

        if (clashInfo.isNotEmpty && classEvents.isEmpty) {
          final firstClash = clashInfo.first;
          _showError(
            'All Dates Clash',
            'All selected dates have time clashes.\n\n'
                'Example clash:\n'
                '${firstClash['className']}\n'
                '${_formatTime(firstClash['startTime'])} - ${_formatTime(firstClash['endTime'])}\n'
                'on ${DateFormat('EEE, dd MMM').format(firstClash['date'])}',
          );
          return;
        } else if (clashInfo.isNotEmpty) {
          final clashCount = clashInfo.length;
          final savedCount = classEvents.length;

          final shouldContinue = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.black, width: 2),
              ),
              title: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Clash Warning',
                      style: GoogleFonts.dmMono(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$clashCount date(s) skipped due to time clashes.\n$savedCount class(es) will be saved.',
                    style: GoogleFonts.dmMono(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Continue?',
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.dmMono(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    'Continue',
                    style: GoogleFonts.dmMono(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          );

          if (shouldContinue != true) return;
        }
      }

      if (classEvents.isEmpty) {
        _showMessage('No classes to save. Please check your settings.');
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (var event in classEvents) {
        final docRef =
            FirebaseFirestore.instance.collection('timetable').doc();
        batch.set(docRef, event);
      }

      await batch.commit();

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
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Success!',
                      style: GoogleFonts.dmMono(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                classEvents.length == 1
                    ? 'Class has been successfully saved'
                    : '${classEvents.length} classes have been successfully saved',
                style: GoogleFonts.dmMono(fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(true),
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
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      print('Error saving class: $e');
      if (mounted) {
        _showError('Save Error', 'Error saving class. Please try again.');
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
            const Icon(
              Icons.error_outline,
              color: Color(0xFFB90000),
              size: 24,
            ),
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
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: SingleChildScrollView(
            child: Text(
              message,
              style: GoogleFonts.dmMono(fontSize: 12),
            ),
          ),
        ),
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

  void _showMessage(String message) => _showError('Validation Error', message);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('Class'),
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
                    _buildTextField(_roomController, ''),
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
                    _buildTextField(_buildingController, ''),
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

          _buildLabel('Start/End Dates'),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildDateOptionButton('None'),
              const SizedBox(width: 8),
              _buildDateOptionButton('Academic Year/Term'),
              const SizedBox(width: 8),
              _buildDateOptionButton('Manual'),
            ],
          ),
          const SizedBox(height: 16),

          if (_dateOption == 'None') ...[
            _buildDateField('Date', _startDate, true),
            _buildTimeFields(),
          ] else if (_dateOption == 'Manual') ...[
            _buildDateField('Start Date', _startDate, true),
            _buildDateField('End Date', _endDate, false),
            _buildOccurrenceSection(),
            if (_occurrence == 'Repeating') _buildDaySelector(),
            _buildTimeFields(),
          ] else if (_dateOption == 'Academic Year/Term') ...[
            _buildSemesterYearSelector(),
            _buildDateField('Start Date', _startDate, true),
            _buildDateField('End Date', _endDate, false),
            _buildOccurrenceSection(),
            if (_occurrence == 'Repeating') _buildDaySelector(),
            _buildTimeFields(),
          ],

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
                  onPressed: _saveClass,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB90000),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Save Class',
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

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
  ) {
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

  Widget _buildDateOptionButton(String label) {
    final isSelected = _dateOption == label;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _dateOption = label;
            if (label == 'None') _endDate = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFEBEE) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFFB90000) : Colors.black,
              width: 2,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmMono(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOccurrenceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Occurrence'),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildOccurrenceButton('Once'),
            const SizedBox(width: 8),
            _buildOccurrenceButton('Repeating'),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildOccurrenceButton(String label) {
    final isSelected = _occurrence == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _occurrence = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFEBEE) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFFB90000) : Colors.black,
              width: 2,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmMono(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateField(
    String label,
    DateTime? date,
    bool isStartDate,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _selectDate(context, isStartDate),
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
                    date != null
                        ? DateFormat('EEE, dd MMM yyyy').format(date)
                        : 'Select date',
                    style: GoogleFonts.dmMono(
                      fontSize: 14,
                      color: date != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_today, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSemesterYearSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Semester'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
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
                        value: _selectedSemester,
                        isExpanded: true,
                        underline: const SizedBox(),
                        style: GoogleFonts.dmMono(
                          fontSize: 14,
                          color: Colors.black,
                        ),
                        dropdownColor: Colors.white,
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: Colors.black,
                        ),
                        items: List.generate(10, (index) => index + 1)
                            .map(
                              (i) => DropdownMenuItem(
                                value: i,
                                child: Text(
                                  'Semester $i',
                                  style: GoogleFonts.dmMono(
                                    fontSize: 14,
                                    color: Colors.black,
                                  ),
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
                  _buildLabel('Year'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.black,
                              width: 2,
                            ),
                          ),
                          child: TextField(
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.dmMono(fontSize: 14),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: (_selectedYear % 100)
                                  .toString()
                                  .padLeft(2, '0'),
                              hintStyle: GoogleFonts.dmMono(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              border: InputBorder.none,
                            ),
                            maxLength: 2,
                            buildCounter: (
                              context, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) =>
                                null,
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
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.black,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            ((_selectedYear + 1) % 100)
                                .toString()
                                .padLeft(2, '0'),
                            style: GoogleFonts.dmMono(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDaySelector() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Date*'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(7, (index) {
            final dayIndex = index + 1;
            final isSelected = _selectedDays.contains(dayIndex);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedDays.remove(dayIndex);
                  } else {
                    _selectedDays.add(dayIndex);
                  }
                });
              },
              child: Container(
                width: 70,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF6B7280)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Text(
                  days[index],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmMono(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.black,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTimeFields() {
    return Row(
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
                            : '00:00 AM',
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
                            : '00:00 AM',
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
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
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

  // ── Helpers ────────────────────────────────────────────────────────────────

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

  /// Convert internal 12h state back to a 24h TimeOfDay
  TimeOfDay _toTimeOfDay() {
    int h = _hour % 12; // 12 → 0
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

  /// Opens Flutter's native dialOnly picker and syncs result back
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

  // ── Build ──────────────────────────────────────────────────────────────────

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
            // ── Title ──────────────────────────────────────────────────────
            Text(
              'Select Time',
              style: GoogleFonts.dmMono(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // ── Dial trigger ───────────────────────────────────────────────
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
                      color: Color(0xFF6B7280),
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
                        color: const Color(0xFF6B7280).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.touch_app,
                            size: 12,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Use dial',
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              color: const Color(0xFF6B7280),
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

            // ── Divider ────────────────────────────────────────────────────
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

            // ── Spinners + AM/PM ───────────────────────────────────────────
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

            // ── Action buttons ─────────────────────────────────────────────
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
                  color: Color(0xFF6B7280),
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