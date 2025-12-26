import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class EditTaskScreen extends StatefulWidget {
  final Map<String, dynamic> taskData;

  const EditTaskScreen({Key? key, required this.taskData}) : super(key: key);

  @override
  State<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends State<EditTaskScreen> {
  late TextEditingController _taskTitleController;
  late TextEditingController _taskDetailsController;

  String? _selectedSubject;
  String? _selectedType;
  late DateTime _dueDate;
  late TimeOfDay _dueTime;

  List<String> _availableSubjects = [];
  bool _isLoadingSubjects = true;

  final List<String> _taskTypes = [
    'Assignment',
    'Individual Project',
    'Group Project',
    'Meeting',
    'Lab Exercise',
    'Presentation',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    
    print('📝 Edit task screen received data: ${widget.taskData}');
    
    // Initialize controllers with existing data
    _taskTitleController = TextEditingController(
      text: widget.taskData['taskTitle'] ?? '',
    );
    _taskDetailsController = TextEditingController(
      text: widget.taskData['taskDetails'] ?? '',
    );

    // Initialize subject and type
    _selectedSubject = widget.taskData['subject']?.isNotEmpty == true 
        ? widget.taskData['subject'] 
        : null;
    _selectedType = widget.taskData['taskType'];

    // Parse date from Firestore
    final timestamp = widget.taskData['dueDate'] as Timestamp?;
    final dueDateTime = timestamp?.toDate() ?? DateTime.now();
    _dueDate = dueDateTime;
    _dueTime = TimeOfDay(hour: dueDateTime.hour, minute: dueDateTime.minute);

    _loadSubjects();
  }

  @override
  void dispose() {
    _taskTitleController.dispose();
    _taskDetailsController.dispose();
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
      initialDate: _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF008BB9)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _dueTime,
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF008BB9),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.white,
              dialHandColor: const Color(0xFF008BB9),
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
        _dueTime = picked;
      });
    }
  }

  Future<void> _updateTask() async {
    // Validation
    if (_taskTitleController.text.trim().isEmpty) {
      _showError('Validation Error', 'Please enter task title');
      return;
    }

    if (_selectedType == null) {
      _showError('Validation Error', 'Please select task type');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Error', 'User not authenticated');
      return;
    }

    try {
      // Combine date and time
      final dueDateTime = DateTime(
        _dueDate.year,
        _dueDate.month,
        _dueDate.day,
        _dueTime.hour,
        _dueTime.minute,
      );

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('tasks')
          .doc(widget.taskData['id'])
          .update({
        'taskTitle': _taskTitleController.text.trim(),
        'taskDetails': _taskDetailsController.text.trim(),
        'subject': _selectedSubject ?? '',
        'taskType': _selectedType,
        'dueDate': Timestamp.fromDate(dueDateTime),
        'updatedAt': Timestamp.now(),
      });

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
              'Task has been successfully updated',
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
      print('Error updating task: $e');
      if (mounted) {
        _showError('Update Error', 'Error updating task. Please try again.');
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
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Edit Task',
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

            // Task Title
            _buildLabel('Task'),
            const SizedBox(height: 8),
            _buildTextField(_taskTitleController, 'Task Title'),
            const SizedBox(height: 16),

            // Task Details
            _buildLabel('Details'),
            const SizedBox(height: 8),
            _buildMultilineTextField(_taskDetailsController, 'Task description'),
            const SizedBox(height: 16),

            // Subject (Optional)
            _buildLabel('Subject (Optional)'),
            const SizedBox(height: 8),
            _buildSubjectSelector(),
            const SizedBox(height: 16),

            // Task Type
            _buildLabel('Type'),
            const SizedBox(height: 8),
            _buildTypeSelector(),
            const SizedBox(height: 16),

            // Due Date and Time
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Due Date'),
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
                                  DateFormat('EEE, dd MMM yyyy').format(_dueDate),
                                  style: GoogleFonts.dmMono(fontSize: 14),
                                ),
                              ),
                              const Icon(Icons.calendar_today, size: 18),
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
                      _buildLabel('Time'),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _selectTime(context),
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
                                _formatTimeOfDay(_dueTime),
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
                    onPressed: _updateTask,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF008BB9),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Update Task',
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

  Widget _buildMultilineTextField(
    TextEditingController controller,
    String hint,
  ) {
    return TextField(
      controller: controller,
      style: GoogleFonts.dmMono(fontSize: 14),
      maxLines: 5,
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
            'No classes found. Add classes first to link them to tasks.',
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
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFF008BB9),
                                )
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
                  color: _selectedSubject != null ? Colors.black : Colors.grey,
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
    return GestureDetector(
      onTap: () {
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
                        'Select Task Type',
                        style: GoogleFonts.dmMono(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      itemCount: _taskTypes.length,
                      itemBuilder: (context, index) {
                        final type = _taskTypes[index];
                        return ListTile(
                          title: Text(
                            type,
                            style: GoogleFonts.dmMono(fontSize: 14),
                          ),
                          trailing: _selectedType == type
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFF008BB9),
                                )
                              : null,
                          onTap: () {
                            setState(() => _selectedType = type);
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
                _selectedType ?? 'Task Type',
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  color: _selectedType != null ? Colors.black : Colors.grey,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }
}