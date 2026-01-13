import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'edit_class_screen.dart';
import 'edit_task_screen.dart';
import 'edit_exam_screen.dart';

// Save this file as: subject_detail_screen.dart

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

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  Stream<Map<String, bool>> _checkClassesOnDateStream(DateTime date) {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value({'hasClasses': false, 'isUpcoming': false});
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkDate = DateTime(date.year, date.month, date.day);

    return _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .where('className', isEqualTo: widget.subjectName)
        .snapshots()
        .asyncMap((timetableSnapshot) async {
          bool hasClasses = false;
          bool isUpcoming = false;

          // Check timetable/classes
          for (var doc in timetableSnapshot.docs) {
            final data = doc.data();
            final timestamp = data['date'] as Timestamp?;
            if (timestamp != null) {
              final docDate = timestamp.toDate();
              final docDateOnly = DateTime(
                docDate.year,
                docDate.month,
                docDate.day,
              );
              if (docDateOnly.year == checkDate.year &&
                  docDateOnly.month == checkDate.month &&
                  docDateOnly.day == checkDate.day) {
                hasClasses = true;
                if (checkDate.isAfter(today)) {
                  isUpcoming = true;
                }
                break;
              }
            }
          }

          // Check tasks
          if (!hasClasses) {
            final tasksSnapshot = await _firestore
                .collection('tasks')
                .where('userId', isEqualTo: user.uid)
                .where('subject', isEqualTo: widget.subjectName)
                .get();

            for (var doc in tasksSnapshot.docs) {
              final data = doc.data();
              final timestamp = data['dueDate'] as Timestamp?;
              if (timestamp != null) {
                final docDate = timestamp.toDate();
                final docDateOnly = DateTime(
                  docDate.year,
                  docDate.month,
                  docDate.day,
                );
                if (docDateOnly.year == checkDate.year &&
                    docDateOnly.month == checkDate.month &&
                    docDateOnly.day == checkDate.day) {
                  hasClasses = true;
                  if (checkDate.isAfter(today)) {
                    isUpcoming = true;
                  }
                  break;
                }
              }
            }
          }

          // Check exams
          if (!hasClasses) {
            final examsSnapshot = await _firestore
                .collection('exams')
                .where('userId', isEqualTo: user.uid)
                .where('subject', isEqualTo: widget.subjectName)
                .get();

            for (var doc in examsSnapshot.docs) {
              final data = doc.data();
              final timestamp = data['examDate'] as Timestamp?;
              if (timestamp != null) {
                final docDate = timestamp.toDate();
                final docDateOnly = DateTime(
                  docDate.year,
                  docDate.month,
                  docDate.day,
                );
                if (docDateOnly.year == checkDate.year &&
                    docDateOnly.month == checkDate.month &&
                    docDateOnly.day == checkDate.day) {
                  hasClasses = true;
                  if (checkDate.isAfter(today)) {
                    isUpcoming = true;
                  }
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

    List<DateTime> days = [];

    int firstWeekday = firstDay.weekday % 7;

    for (int i = firstWeekday - 1; i >= 0; i--) {
      days.add(firstDay.subtract(Duration(days: i + 1)));
    }

    for (int day = 1; day <= lastDay.day; day++) {
      days.add(DateTime(month.year, month.month, day));
    }

    int remainingDays = 42 - days.length;
    for (int i = 1; i <= remainingDays; i++) {
      days.add(lastDay.add(Duration(days: i)));
    }

    return days;
  }

  bool _isCurrentMonth(DateTime date) {
    return date.month == _currentMonth.month && date.year == _currentMonth.year;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _isSelected(DateTime date) {
    if (_selectedDate == null) return false;
    return date.year == _selectedDate!.year &&
        date.month == _selectedDate!.month &&
        date.day == _selectedDate!.day;
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = _getDaysInMonth(_currentMonth);

    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
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
                      _buildCalendar(daysInMonth),
                      const SizedBox(height: 24),
                      _buildSelectedDateClasses(),
                      const SizedBox(height: 24),
                      _buildUpcomingEvents(),
                      const SizedBox(height: 24),
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

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: Color(0xFFE5E7EB)),
      child: Row(
        children: [
          _AnimatedTapButton(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF6B7280),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'SUBJECTS',
                style: GoogleFonts.dmMono(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 40),
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
          border: Border.all(color: const Color(0xFF3859FF), width: 3),
        ),
        child: Text(
          widget.subjectName,
          style: GoogleFonts.dmMono(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
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
                  color: const Color(0xFF292929),
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
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: const Icon(
                        Icons.chevron_left,
                        size: 20,
                        color: Colors.black,
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
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: Colors.black,
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
              _weekdayLabel('SUN'),
              _weekdayLabel('MON'),
              _weekdayLabel('TUE'),
              _weekdayLabel('WED'),
              _weekdayLabel('THU'),
              _weekdayLabel('FRI'),
              _weekdayLabel('SAT'),
            ],
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
            itemBuilder: (context, index) {
              final date = days[index];
              final isCurrentMonth = _isCurrentMonth(date);
              final isToday = _isToday(date);
              final isSelected = _isSelected(date);

              return StreamBuilder<Map<String, bool>>(
                stream: _checkClassesOnDateStream(date),
                builder: (context, snapshot) {
                  bool hasClasses = snapshot.data?['hasClasses'] ?? false;
                  bool isUpcoming = snapshot.data?['isUpcoming'] ?? false;

                  return _buildDateCell(
                    date,
                    isCurrentMonth,
                    isToday,
                    isSelected,
                    hasClasses,
                    isUpcoming,
                  );
                },
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
    Color? backgroundColor;
    Color? borderColor;
    double? borderWidth;
    Color textColor = Colors.black;

    if (isToday) {
      backgroundColor = const Color(0xFFB90000);
      textColor = Colors.white;
    } else {
      backgroundColor = Colors.transparent;

      if (isUpcoming) {
        borderColor = const Color(0xFFB90000);
        borderWidth = 2;
      } else if (hasClasses) {
        borderColor = Colors.black;
        borderWidth = 2;
      }
    }

    if (!isCurrentMonth) {
      textColor = Colors.grey.shade400;
    }

    return _AnimatedTapButton(
      onTap: () {
        setState(() {
          _selectedDate = date;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              border: borderColor != null && borderWidth != null
                  ? Border.all(color: borderColor, width: borderWidth)
                  : null,
            ),
            child: Center(
              child: Text(
                '${date.day.toString().padLeft(2, '0')}',
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
            CustomPaint(size: const Size(10, 8), painter: TrianglePainter()),
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
          color: Colors.black87,
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
          'Classes - ${DateFormat('EEE, dd MMM').format(_selectedDate!)}',
          style: GoogleFonts.dmMono(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getClassesOnDateStream(user.uid, _selectedDate!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Color(0xFF6B7280)),
                ),
              );
            }

            if (snapshot.hasError ||
                !snapshot.hasData ||
                snapshot.data!.isEmpty) {
              return _buildEmptyState('No classes scheduled');
            }

            List<Map<String, dynamic>> classes = snapshot.data!;

            classes.sort((a, b) {
              String timeA = a['startTime'] as String;
              String timeB = b['startTime'] as String;
              return timeA.compareTo(timeB);
            });

            return Column(
              children: classes.map((classData) {
                return _buildClassCard(classData);
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
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Color(0xFF6B7280)),
                ),
              );
            }

            if (snapshot.hasError ||
                !snapshot.hasData ||
                snapshot.data!.isEmpty) {
              return _buildEmptyState('No upcoming events');
            }

            List<Map<String, dynamic>> events = snapshot.data!;

            return Column(
              children: events.map((event) {
                if (event['type'] == 'task') {
                  return _buildTaskCard(event);
                } else {
                  return _buildExamCard(event);
                }
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> _getClassesOnDateStream(
    String userId,
    DateTime date,
  ) {
    return _firestore
        .collection('timetable')
        .where('userId', isEqualTo: userId)
        .where('className', isEqualTo: widget.subjectName)
        .snapshots()
        .map((snapshot) {
          List<Map<String, dynamic>> classes = [];

          for (var doc in snapshot.docs) {
            try {
              final data = doc.data();
              final timestamp = data['date'] as Timestamp?;

              if (timestamp != null) {
                final eventDate = timestamp.toDate();

                if (eventDate.year == date.year &&
                    eventDate.month == date.month &&
                    eventDate.day == date.day) {
                  classes.add({
                    'id': doc.id,
                    'className': data['className'] ?? 'Untitled',
                    'startTime': data['startTime'] ?? '00:00',
                    'endTime': data['endTime'] ?? '00:00',
                    'room': data['room'] ?? '',
                    'building': data['building'] ?? '',
                    'lecturerName': data['lecturerName'] ?? '',
                    'type': data['type'] ?? 'class',
                    'date': timestamp,
                  });
                }
              }
            } catch (e) {
              print('Error processing class: $e');
            }
          }

          return classes;
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
        .asyncMap((tasksSnapshot) async {
          List<Map<String, dynamic>> events = [];

          // Get tasks
          for (var doc in tasksSnapshot.docs) {
            try {
              final data = doc.data();
              final timestamp = data['dueDate'] as Timestamp?;

              if (timestamp != null) {
                final dueDate = timestamp.toDate();
                final dueDateOnly = DateTime(
                  dueDate.year,
                  dueDate.month,
                  dueDate.day,
                );

                if (dueDateOnly.isAfter(today) ||
                    dueDateOnly.isAtSameMomentAs(today)) {
                  events.add({
                    'id': doc.id,
                    'type': 'task',
                    'taskTitle': data['taskTitle'] ?? 'Untitled Task',
                    'taskDetails': data['taskDetails'] ?? '',
                    'subject': data['subject'] ?? '',
                    'taskType': data['taskType'] ?? '',
                    'dueDate': timestamp,
                    'dueTime': DateFormat('HH:mm').format(dueDate),
                    'completed': data['completed'] ?? false,
                    'sortDate': dueDate,
                  });
                }
              }
            } catch (e) {
              print('Error processing task: $e');
            }
          }

          // Get exams
          final examsSnapshot = await _firestore
              .collection('exams')
              .where('userId', isEqualTo: userId)
              .where('subject', isEqualTo: widget.subjectName)
              .get();

          for (var doc in examsSnapshot.docs) {
            try {
              final data = doc.data();
              final timestamp = data['examDate'] as Timestamp?;

              if (timestamp != null) {
                final examDate = timestamp.toDate();
                final examDateOnly = DateTime(
                  examDate.year,
                  examDate.month,
                  examDate.day,
                );

                if (examDateOnly.isAfter(today) ||
                    examDateOnly.isAtSameMomentAs(today)) {
                  events.add({
                    'id': doc.id,
                    'eventType': 'exam',
                    'type': data['type'] ?? 'Exam',
                    'examName': data['examName'] ?? 'Untitled Exam',
                    'subject': data['subject'] ?? '',
                    'mode': data['mode'] ?? 'In Person',
                    'venue': data['venue'] ?? '',
                    'examDate': timestamp,
                    'startTime': data['startTime'],
                    'endTime': data['endTime'],
                    'sortDate': examDate,
                  });
                }
              }
            } catch (e) {
              print('Error processing exam: $e');
            }
          }

          // Sort by date
          events.sort((a, b) => a['sortDate'].compareTo(b['sortDate']));

          return events;
        });
  }

  Widget _buildClassCard(Map<String, dynamic> classData) {
    return _AnimatedTapButton(
      onTap: () => _showClassDetails(classData),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFB90000), width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFB90000),
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
                          color: const Color(0xFFB90000),
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
                          classData['className'],
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
                    '${_formatTime(classData['startTime'])} - ${_formatTime(classData['endTime'])}${classData['room'].isNotEmpty || classData['building'].isNotEmpty ? ' • ${classData['room']}${classData['room'].isNotEmpty && classData['building'].isNotEmpty ? ', ' : ''}${classData['building']}' : ''}',
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      color: const Color(0xFF6B7280),
                    ),
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

    return _AnimatedTapButton(
      onTap: () => _showTaskDetails(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCompleted
                ? const Color(0xFF34A853)
                : const Color(0xFF008BB9),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCompleted
                    ? const Color(0xFF34A853)
                    : const Color(0xFF008BB9),
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
                          color: isCompleted
                              ? const Color(0xFF34A853)
                              : const Color(0xFF008BB9),
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
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      color: const Color(0xFF6B7280),
                    ),
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
            color: Colors.white,
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
                      '${DateFormat('EEE, dd MMM').format(examDate)}${startTime != null && endTime != null ? ' • ${DateFormat('hh:mm a').format(startTime)} - ${DateFormat('hh:mm a').format(endTime)}' : ''}',
                      style: GoogleFonts.dmMono(
                        fontSize: 10,
                        color: const Color(0xFF6B7280),
                      ),
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
    } catch (e) {
      print('Error building exam card: $e');
      return const SizedBox();
    }
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.event_note_outlined,
            size: 48,
            color: Color(0xFF6B7280),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: GoogleFonts.dmMono(fontSize: 13, color: Colors.grey),
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
    } catch (e) {
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
              style: GoogleFonts.dmMono(
                fontSize: 12,
                color: const Color(0xFF6B7280),
              ),
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
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      if (event['room'] != null && event['room'].isNotEmpty)
                        _buildDetailRow('Room', event['room']),
                      if (event['building'] != null &&
                          event['building'].isNotEmpty)
                        _buildDetailRow('Building', event['building']),
                      if (event['lecturerName'] != null &&
                          event['lecturerName'].isNotEmpty)
                        _buildDetailRow('Lecturer', event['lecturerName']),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditClassScreen(classData: event),
                              ),
                            );
                            if (result == true && mounted) {
                              setState(() {});
                            }
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: Text('Edit', style: GoogleFonts.dmMono()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: const BorderSide(
                              color: Colors.black,
                              width: 2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.pop(context);
                            await _firestore
                                .collection('timetable')
                                .doc(event['id'])
                                .delete();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Class deleted',
                                  style: GoogleFonts.dmMono(),
                                ),
                                backgroundColor: const Color(0xFFB90000),
                              ),
                            );
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: Text('Delete', style: GoogleFonts.dmMono()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB90000),
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
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTaskDetails(Map<String, dynamic> task) {
    final dueDate = (task['dueDate'] as Timestamp).toDate();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final isCompleted = task['completed'] ?? false;

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
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          if (task['taskDetails'] != null &&
                              task['taskDetails'].isNotEmpty)
                            _buildDetailRow('Details', task['taskDetails']),
                          if (task['subject'] != null &&
                              task['subject'].isNotEmpty)
                            _buildDetailRow('Subject', task['subject']),
                          _buildDetailRow('Type', task['taskType']),
                          _buildDetailRow(
                            'Due Date',
                            DateFormat('EEE, dd MMM yyyy').format(dueDate),
                          ),
                          _buildDetailRow(
                            'Due Time',
                            _formatTime(task['dueTime']),
                          ),
                          const SizedBox(height: 8),
                          _buildStatusToggleInModal(task, setModalState),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                Navigator.pop(context);
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EditTaskScreen(taskData: task),
                                  ),
                                );
                                if (result == true && mounted) {
                                  setState(() {});
                                }
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: Text('Edit', style: GoogleFonts.dmMono()),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black,
                                side: const BorderSide(
                                  color: Colors.black,
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                Navigator.pop(context);
                                await _firestore
                                    .collection('tasks')
                                    .doc(task['id'])
                                    .delete();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Task deleted',
                                      style: GoogleFonts.dmMono(),
                                    ),
                                    backgroundColor: const Color(0xFFB90000),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: Text(
                                'Delete',
                                style: GoogleFonts.dmMono(),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB90000),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusToggleInModal(
    Map<String, dynamic> task,
    StateSetter setModalState,
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
              style: GoogleFonts.dmMono(
                fontSize: 12,
                color: const Color(0xFF6B7280),
              ),
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
                      setModalState(() {
                        task['completed'] = false;
                      });
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
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !isCompleted
                              ? const Color(0xFF008BB9)
                              : Colors.grey.shade400,
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
                                : Colors.grey.shade600,
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
                      setModalState(() {
                        task['completed'] = true;
                      });
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? const Color(0xFF34A853)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCompleted
                              ? const Color(0xFF34A853)
                              : Colors.grey.shade400,
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
                                : Colors.grey.shade600,
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

  void _showExamDetails(Map<String, dynamic> exam) {
    final examDate = (exam['examDate'] as Timestamp).toDate();
    final startTime = (exam['startTime'] as Timestamp).toDate();
    final endTime = (exam['endTime'] as Timestamp).toDate();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      if (exam['subject'].isNotEmpty)
                        _buildDetailRow('Subject', exam['subject']),
                      _buildDetailRow('Type', exam['type']),
                      _buildDetailRow('Mode', exam['mode']),
                      if (exam['mode'] == 'In Person' &&
                          exam['venue'].isNotEmpty)
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
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditExamScreen(examData: exam),
                              ),
                            );
                            if (result == true && mounted) {
                              setState(() {});
                            }
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: Text('Edit', style: GoogleFonts.dmMono()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: const BorderSide(
                              color: Colors.black,
                              width: 2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.pop(context);
                            await _firestore
                                .collection('exams')
                                .doc(exam['id'])
                                .delete();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Exam deleted',
                                  style: GoogleFonts.dmMono(),
                                ),
                                backgroundColor: const Color(0xFFB90000),
                              ),
                            );
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: Text('Delete', style: GoogleFonts.dmMono()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB90000),
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
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
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