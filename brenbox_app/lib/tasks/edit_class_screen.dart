import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

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

  // Additional fields for repeating and academic year
  int? _selectedSemester;
  int? _selectedYear;
  String? _academicYear;

  @override
  void initState() {
    super.initState();
    
    print('📝 Edit screen received data: ${widget.classData}');
    
    // Initialize controllers with existing data
    _classController = TextEditingController(text: widget.classData['className'] ?? '');
    _roomController = TextEditingController(text: widget.classData['room'] ?? '');
    _buildingController = TextEditingController(text: widget.classData['building'] ?? '');
    _lecturerController = TextEditingController(text: widget.classData['lecturerName'] ?? '');

    // Parse date from Firestore
    final timestamp = widget.classData['date'] as Timestamp?;
    _classDate = timestamp?.toDate() ?? DateTime.now();

    // Parse times
    _startTime = _parseTime(widget.classData['startTime'] ?? '00:00');
    _endTime = _parseTime(widget.classData['endTime'] ?? '00:00');

    // Parse semester and academic year if they exist
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

  Future<void> _selectTime(BuildContext context, bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStartTime ? _startTime : _endTime,
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
          // Validate end time is after start time
          if (_endTime != null) {
            final startMinutes = picked.hour * 60 + picked.minute;
            final endMinutes = _endTime.hour * 60 + _endTime.minute;
            if (endMinutes <= startMinutes) {
              _endTime = TimeOfDay(hour: picked.hour + 1, minute: picked.minute);
            }
          }
        } else {
          // Validate end time is after start time
          final startMinutes = _startTime.hour * 60 + _startTime.minute;
          final endMinutes = picked.hour * 60 + picked.minute;
          if (endMinutes <= startMinutes) {
            _showError('Invalid Time', 'End time must be after start time');
            return;
          }
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _updateClass() async {
    // Validation
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
      final startTimeStr = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
      final endTimeStr = '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';
      
      final normalizedDate = DateTime(_classDate.year, _classDate.month, _classDate.day);

      // Check for time clash with other classes (excluding this one)
      final clash = await _checkClassClash(normalizedDate, startTimeStr, endTimeStr);
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

      // Update Firestore
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

      // Add semester and academic year if they exist
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

      if (!mounted) return;

      // Show success dialog
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
                onPressed: () {
                  Navigator.of(dialogContext).pop();
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
          );
        },
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
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
      // Skip checking against the current class being edited
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
                style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, fontSize: 14),
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
            child: const Icon(
              Icons.arrow_back,
              color: Colors.white,
              size: 20,
            ),
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
            
            // Class Name
            _buildLabel('Class Name'),
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

            // Lecturer Name
            _buildLabel('Lecturer Name'),
            const SizedBox(height: 8),
            _buildTextField(_lecturerController, 'Enter lecturer name'),
            const SizedBox(height: 16),

            // Semester and Academic Year (show if they exist in the data)
            if (_selectedSemester != null || _selectedYear != null) ...[
              _buildSemesterYearSelector(),
              const SizedBox(height: 16),
            ],

            // Date
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

            // Time Fields
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    canvasColor: Colors.white, // Dropdown menu background
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFF6B7280), // Selected item color
                      onPrimary: Colors.white, // Text on selected item
                      surface: Colors.white, // Dropdown background
                      onSurface: Colors.black, // Text color
                    ),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedSemester ?? 1,
                    isExpanded: true,
                    underline: const SizedBox(),
                    style: GoogleFonts.dmMono(fontSize: 14, color: Colors.black),
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
                              ? (_selectedYear! % 100).toString().padLeft(2, '0')
                              : '25',
                          hintStyle: GoogleFonts.dmMono(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                          border: InputBorder.none,
                        ),
                        maxLength: 2,
                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                        controller: TextEditingController(
                          text: _selectedYear != null 
                              ? (_selectedYear! % 100).toString().padLeft(2, '0')
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
                              ? ((_selectedYear! + 1) % 100).toString().padLeft(2, '0')
                              : '26',
                          hintStyle: GoogleFonts.dmMono(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                          border: InputBorder.none,
                        ),
                        maxLength: 2,
                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                        controller: TextEditingController(
                          text: _selectedYear != null 
                              ? ((_selectedYear! + 1) % 100).toString().padLeft(2, '0')
                              : '',
                        ),
                        onChanged: (value) {
                          // Read-only for consistency, first year determines second year
                        },
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