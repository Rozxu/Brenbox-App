import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

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
      firstDate: DateTime.now(), // Prevent past dates
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
          // Reset end date if it's before new start date
          if (_endDate != null && _endDate!.isBefore(picked)) {
            _endDate = null;
          }
        } else {
          // Validate end date is after start date
          if (_startDate != null && picked.isBefore(_startDate!)) {
            _showError('Invalid Date', 'End date must be after start date');
            return;
          }
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6B7280), // Gray color for selected elements
              onPrimary: Colors.white, // White text on selected elements
              surface: Colors.white, // Background color
              onSurface: Colors.black, // Text color
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.white,
              dialHandColor: const Color(0xFF6B7280), // Clock hand color
              dialBackgroundColor: Colors.grey.shade100, // Clock face background
              hourMinuteTextColor: Colors.black,
              hourMinuteColor: Colors.grey.shade200, // Hour/minute box background
              dayPeriodTextColor: Colors.black,
              dayPeriodColor: Colors.grey.shade200, // AM/PM background
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
        if (isStartTime) {
          _startTime = picked;
          if (_endTime != null) {
            final startMinutes = picked.hour * 60 + picked.minute;
            final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
            if (endMinutes <= startMinutes) {
              _endTime = null;
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) {
                  final hour = picked.hourOfPeriod == 0
                      ? 12
                      : picked.hourOfPeriod;
                  final minute = picked.minute.toString().padLeft(2, '0');
                  final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
                  _showError(
                    'Time Validation',
                    'Please select a new end time after $hour:$minute $period',
                  );
                }
              });
            }
          }
        } else {
          if (_startTime != null) {
            final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
            final endMinutes = picked.hour * 60 + picked.minute;
            if (endMinutes <= startMinutes) {
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
  }

  // Check for class time clash
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

    // Filter by exact date and check time overlap
    for (var doc in existingClasses.docs) {
      try {
        final data = doc.data();
        final timestamp = data['date'] as Timestamp?;

        if (timestamp != null) {
          final eventDate = timestamp.toDate();

          // Check if EXACT same date (year, month, day)
          if (eventDate.year == date.year &&
              eventDate.month == date.month &&
              eventDate.day == date.day) {
            final existingStart = data['startTime'] as String;
            final existingEnd = data['endTime'] as String;

            // Convert times to minutes for comparison
            final newStartMinutes = _timeToMinutes(startTime);
            final newEndMinutes = _timeToMinutes(endTime);
            final existingStartMinutes = _timeToMinutes(existingStart);
            final existingEndMinutes = _timeToMinutes(existingEnd);

            // Check for overlap: (StartA < EndB) AND (EndA > StartB)
            if (newStartMinutes < existingEndMinutes &&
                newEndMinutes > existingStartMinutes) {
              return {
                'className': data['className'] ?? 'Untitled Class',
                'startTime': existingStart,
                'endTime': existingEnd,
                'date': eventDate,
              }; // Clash detected
            }
          }
        }
      } catch (e) {
        print('Error checking clash: $e');
        continue;
      }
    }

    return null; // No clash
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

  Future<void> _saveClass() async {
    // Validation
    if (_classController.text.trim().isEmpty) {
      _showMessage('Please enter class name');
      return;
    }

    if (_startTime == null || _endTime == null) {
      _showMessage('Please select start and end time');
      return;
    }

    if (_dateOption == 'Manual' && (_startDate == null || _endDate == null)) {
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

    // Validate time range
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
      // Generate class events
      List<Map<String, dynamic>> classEvents = [];
      final startTimeStr =
          '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}';
      final endTimeStr =
          '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}';

      if (_dateOption == 'None') {
        // Single occurrence for None option
        final eventDate = _startDate ?? DateTime.now();
        final normalizedDate = DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
        );

        // Check for clash
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
        // Single occurrence for Manual/Academic options
        final eventDate = _startDate!;
        final normalizedDate = DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
        );

        // Check for clash
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
        // Multiple occurrences
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

            // Check for clash
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
                event['academicYear'] = '$_selectedYear/${_selectedYear + 1}';
              }

              classEvents.add(event);
            }
          }
          currentDate = currentDate.add(const Duration(days: 1));
        }

        // Show clash warning if any
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
                      style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
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

          // If user cancels, don't proceed with saving
          if (shouldContinue != true) {
            return;
          }
        }
      }

      if (classEvents.isEmpty) {
        _showMessage('No classes to save. Please check your settings.');
        return;
      }

      // Save to Firestore
      final batch = FirebaseFirestore.instance.batch();
      for (var event in classEvents) {
        final docRef = FirebaseFirestore.instance.collection('timetable').doc();
        batch.set(docRef, event);
      }

      await batch.commit();

      // Success - Navigate properly
      if (!mounted) return;

      // Show success dialog and wait for it to close
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
                classEvents.length == 1
                    ? 'Class has been successfully saved'
                    : '${classEvents.length} classes have been successfully saved',
                style: GoogleFonts.dmMono(fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(
                      dialogContext,
                    ).pop(true); // Return true to navigate
                  },
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

      // Navigate back only if dialog returned true and widget is still mounted
      if (shouldNavigate == true && mounted) {
        // Use a small delay to ensure dialog is fully closed
        await Future.delayed(const Duration(milliseconds: 100));

        if (mounted) {
          // Pop back to previous screen (should go back to home/main screen)
          Navigator.of(context).pop(true);
        }
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
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.of(context).size.height *
                0.4, // Max 40% of screen height
            maxWidth:
                MediaQuery.of(context).size.width *
                0.8, // Max 80% of screen width
          ),
          child: SingleChildScrollView(
            child: Text(message, style: GoogleFonts.dmMono(fontSize: 12)),
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

  void _showMessage(String message) {
    _showError('Validation Error', message);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Class Name
          _buildLabel('Class'),
          const SizedBox(height: 8),
          _buildTextField(_classController, 'Enter class name'),
          const SizedBox(height: 16),

          // Room and Building
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

          // Lecturer Name
          _buildLabel('Lecturer Name'),
          const SizedBox(height: 8),
          _buildTextField(_lecturerController, 'Enter lecturer name'),
          const SizedBox(height: 16),

          // Start/End Dates Options
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

          // Conditional fields based on date option
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

          // Action Buttons
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

  Widget _buildDateOptionButton(String label) {
    final isSelected = _dateOption == label;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _dateOption = label;
            // Reset dates when changing option
            if (label == 'None') {
              _endDate = null;
            }
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

  Widget _buildDateField(String label, DateTime? date, bool isStartDate) {
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
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
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
                              hintText: (_selectedYear % 100).toString().padLeft(2, '0'),
                              hintStyle: GoogleFonts.dmMono(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              border: InputBorder.none,
                            ),
                            maxLength: 2,
                            buildCounter:
                                (
                                  context, {
                                  required currentLength,
                                  required isFocused,
                                  maxLength,
                                }) => null,
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
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: Text(
                            ((_selectedYear + 1) % 100).toString().padLeft(2, '0'),
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
                  color: isSelected ? const Color(0xFF6B7280) : Colors.white,
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
                          color: _endTime != null ? Colors.black : Colors.grey,
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