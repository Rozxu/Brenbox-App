import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../tasks/edit_class_screen.dart';
import '../tasks/edit_task_screen.dart';
import '../tasks/edit_exam_screen.dart';
import 'subject_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  DateTime _currentMonth = DateTime.now();
  DateTime? _selectedDate;
  
  // Subject filters
  String _subjectStatus = 'On-Going'; // On-Going or Ended
  String _selectedSemester = 'All'; // All, Semester 1, Semester 2, etc., Non Semester

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    // Don't call _loadAvailableSemesters here anymore
  }

  // NEW: Stream-based approach for real-time semester updates
  Stream<List<String>> _getAvailableSemestersStream() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(['All']);
    }

    return _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
      Set<String> semesters = {'All'};
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['semester'] != null && data['academicYear'] != null) {
          semesters.add('Semester ${data['semester']}');
        }
      }
      
      // Check if there are any subjects without semester
      final hasNonSemester = snapshot.docs.any((doc) => 
        doc.data()['semester'] == null || doc.data()['academicYear'] == null
      );
      
      if (hasNonSemester) {
        semesters.add('Non Semester');
      }

      List<String> semesterList = semesters.toList()..sort((a, b) {
        if (a == 'All') return -1;
        if (b == 'All') return 1;
        if (a == 'Non Semester') return 1;
        if (b == 'Non Semester') return -1;
        // Extract semester numbers for proper sorting
        final aNum = int.tryParse(a.replaceAll('Semester ', ''));
        final bNum = int.tryParse(b.replaceAll('Semester ', ''));
        if (aNum != null && bNum != null) return aNum.compareTo(bNum);
        return a.compareTo(b);
      });

      return semesterList;
    });
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(
        _currentMonth.year,
        _currentMonth.month - 1,
        1,
      );
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(
        _currentMonth.year,
        _currentMonth.month + 1,
        1,
      );
    });
  }

  Stream<Map<String, bool>> _checkEventsOnDateStream(DateTime date) {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value({'hasEvents': false, 'isUpcoming': false});
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkDate = DateTime(date.year, date.month, date.day);

    return _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .asyncMap((timetableSnapshot) async {
          final tasksSnapshot = await _firestore
              .collection('tasks')
              .where('userId', isEqualTo: user.uid)
              .get();

          final examsSnapshot = await _firestore
              .collection('exams')
              .where('userId', isEqualTo: user.uid)
              .get();

          List<QueryDocumentSnapshot> matchingDocs = [];

          // Check timetable events
          for (var doc in timetableSnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
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
                matchingDocs.add(doc);
              }
            }
          }

          // Check tasks
          for (var doc in tasksSnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
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
                matchingDocs.add(doc);
              }
            }
          }

          // Check exams
          for (var doc in examsSnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
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
                matchingDocs.add(doc);
              }
            }
          }

          bool hasEvents = matchingDocs.isNotEmpty;
          bool isUpcoming = hasEvents && checkDate.isAfter(today);

          return {'hasEvents': hasEvents, 'isUpcoming': isUpcoming};
        });
  }

  List<DateTime> _getDaysInMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    
    List<DateTime> days = [];
    
    // Get the weekday of the first day (1 = Monday, 7 = Sunday in Dart)
    // Convert to 0 = Sunday, 1 = Monday, etc.
    int firstWeekday = firstDay.weekday % 7; // This makes Sunday = 0
    
    // Fill with previous month's trailing days
    for (int i = firstWeekday - 1; i >= 0; i--) {
      days.add(firstDay.subtract(Duration(days: i + 1)));
    }
    
    // Add all days of the current month
    for (int day = 1; day <= lastDay.day; day++) {
      days.add(DateTime(month.year, month.month, day));
    }
    
    // Add next month's leading days to complete the grid
    int remainingDays = 42 - days.length; // 6 rows × 7 days
    for (int i = 1; i <= remainingDays; i++) {
      days.add(lastDay.add(Duration(days: i)));
    }
    
    return days;
  }

  bool _isCurrentMonth(DateTime date) {
    return date.month == _currentMonth.month && 
           date.year == _currentMonth.year;
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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _buildHeader(),
                const SizedBox(height: 24),
                _buildCalendar(daysInMonth),
                const SizedBox(height: 24),
                _buildSelectedDateEvents(),
                const SizedBox(height: 24),
                _buildSubjectsSection(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Text(
      'CALENDAR',
      style: GoogleFonts.dmMono(
        fontSize: 24,
        fontWeight: FontWeight.bold,
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
          // Month selector with arrows
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
          
          // Weekday labels
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
          
          // Calendar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.85, // Reduced from 1 to give more height for triangle
              crossAxisSpacing: 8,
              mainAxisSpacing: 12, // Increased spacing between rows
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final date = days[index];
              final isCurrentMonth = _isCurrentMonth(date);
              final isToday = _isToday(date);
              final isSelected = _isSelected(date);
              
              return StreamBuilder<Map<String, bool>>(
                stream: _checkEventsOnDateStream(date),
                builder: (context, snapshot) {
                  bool hasEvents = snapshot.data?['hasEvents'] ?? false;
                  bool isUpcoming = snapshot.data?['isUpcoming'] ?? false;
                  
                  return _buildDateCell(
                    date,
                    isCurrentMonth,
                    isToday,
                    isSelected,
                    hasEvents,
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
    bool hasEvents,
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
      } else if (hasEvents) {
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
            CustomPaint(
              size: const Size(10, 8),
              painter: TrianglePainter(),
            ),
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

  Widget _buildSelectedDateEvents() {
    if (_selectedDate == null) return const SizedBox();

    final user = _auth.currentUser;
    if (user == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Events - ${DateFormat('EEE, dd MMM').format(_selectedDate!)}',
          style: GoogleFonts.dmMono(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getCombinedEventsStream(user.uid, _selectedDate!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                    color: Color(0xFF6B7280),
                  ),
                ),
              );
            }

            if (snapshot.hasError ||
                !snapshot.hasData ||
                snapshot.data!.isEmpty) {
              return _buildEmptyState();
            }

            List<Map<String, dynamic>> events = snapshot.data!;

            // Sort events by time
            events.sort((a, b) {
              String timeA;
              String timeB;
              
              if (a['type'] == 'task') {
                timeA = a['dueTime'] as String;
              } else if (a['type'] == 'exam') {
                timeA = a['startTime'] as String;
              } else {
                timeA = a['startTime'] as String;
              }
              
              if (b['type'] == 'task') {
                timeB = b['dueTime'] as String;
              } else if (b['type'] == 'exam') {
                timeB = b['startTime'] as String;
              } else {
                timeB = b['startTime'] as String;
              }
              
              return timeA.compareTo(timeB);
            });

            return Column(
              children: events.map((event) {
                if (event['type'] == 'task') {
                  return _buildTaskCard(event);
                } else if (event['eventType'] == 'exam') {
                  return _buildExamCard(event);
                } else {
                  return _buildClassCard(event);
                }
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> _getCombinedEventsStream(
    String userId,
    DateTime date,
  ) {
    return _firestore
        .collection('timetable')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((timetableSnapshot) async {
          List<Map<String, dynamic>> allEvents = [];

          // Get timetable/classes
          for (var doc in timetableSnapshot.docs) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = data['date'] as Timestamp?;

              if (timestamp != null) {
                final eventDate = timestamp.toDate();

                if (eventDate.year == date.year &&
                    eventDate.month == date.month &&
                    eventDate.day == date.day) {
                  allEvents.add({
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
              print('Error processing timetable document ${doc.id}: $e');
              continue;
            }
          }

          // Get tasks
          final tasksSnapshot = await _firestore
              .collection('tasks')
              .where('userId', isEqualTo: userId)
              .get();

          for (var doc in tasksSnapshot.docs) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = data['dueDate'] as Timestamp?;

              if (timestamp != null) {
                final dueDate = timestamp.toDate();

                if (dueDate.year == date.year &&
                    dueDate.month == date.month &&
                    dueDate.day == date.day) {
                  allEvents.add({
                    'id': doc.id,
                    'type': 'task',
                    'taskTitle': data['taskTitle'] ?? 'Untitled Task',
                    'taskDetails': data['taskDetails'] ?? '',
                    'subject': data['subject'] ?? '',
                    'taskType': data['taskType'] ?? '',
                    'dueDate': timestamp,
                    'dueTime': DateFormat('HH:mm').format(dueDate),
                    'completed': data['completed'] ?? false,
                  });
                }
              }
            } catch (e) {
              print('Error processing task document ${doc.id}: $e');
              continue;
            }
          }

          // Get exams
          final examsSnapshot = await _firestore
              .collection('exams')
              .where('userId', isEqualTo: userId)
              .get();

          for (var doc in examsSnapshot.docs) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = data['examDate'] as Timestamp?;

              if (timestamp != null) {
                final examDate = timestamp.toDate();

                if (examDate.year == date.year &&
                    examDate.month == date.month &&
                    examDate.day == date.day) {
                  allEvents.add({
                    'id': doc.id,
                    'eventType': 'exam', // Use this to identify it's an exam
                    'type': data['type'] ?? 'Exam', // Exam type (Midterm, Final, etc.)
                    'examName': data['examName'] ?? 'Untitled Exam',
                    'subject': data['subject'] ?? '',
                    'mode': data['mode'] ?? 'In Person',
                    'venue': data['venue'] ?? '',
                    'examDate': timestamp,
                    'startTime': data['startTime'],
                    'endTime': data['endTime'],
                  });
                }
              }
            } catch (e) {
              print('Error processing exam document ${doc.id}: $e');
              continue;
            }
          }

          return allEvents;
        });
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final isCompleted = task['completed'] ?? false;
    
    return _AnimatedTapButton(
      onTap: () => _showTaskDetails(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCompleted ? const Color(0xFF34A853) : const Color(0xFF008BB9),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCompleted ? const Color(0xFF34A853) : const Color(0xFF008BB9),
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
                          color: isCompleted ? const Color(0xFF34A853) : const Color(0xFF008BB9),
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
                            decoration: isCompleted ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatTime(task['dueTime'])}${task['subject'].isNotEmpty ? ' • ${task['subject']}' : ''}',
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
      final startTime = (exam['startTime'] as Timestamp?)?.toDate();
      final endTime = (exam['endTime'] as Timestamp?)?.toDate();
      
      if (startTime == null || endTime == null) {
        // Fallback if timestamps are missing
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF9AB900), width: 2),
          ),
          child: Text(
            exam['examName'] ?? 'Exam',
            style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        );
      }
      
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
                      '${DateFormat('hh:mm a').format(startTime)} - ${DateFormat('hh:mm a').format(endTime)}${(exam['subject'] ?? '').isNotEmpty ? ' • ${exam['subject']}' : ''}',
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
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF9AB900), width: 2),
        ),
        child: Text(
          exam['examName'] ?? 'Exam (Error loading details)',
          style: GoogleFonts.dmMono(fontSize: 13),
        ),
      );
    }
  }

  Widget _buildClassCard(Map<String, dynamic> event) {
    Color labelColor = const Color(0xFFB90000);
    
    return _AnimatedTapButton(
      onTap: () => _showClassDetails(event),
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
                color: labelColor,
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
                          event['className'],
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
                    '${_formatTime(event['startTime'])} - ${_formatTime(event['endTime'])}${event['room'].isNotEmpty || event['building'].isNotEmpty ? ' • ${event['room']}${event['room'].isNotEmpty && event['building'].isNotEmpty ? ', ' : ''}${event['building']}' : ''}',
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

  Widget _buildEmptyState() {
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
            'No events scheduled',
            style: GoogleFonts.dmMono(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Subjects Section
  Widget _buildSubjectsSection() {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subjects',
          style: GoogleFonts.dmMono(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        // Semester Dropdown and Status Toggle
        Row(
          children: [
            // Semester Dropdown
            Expanded(
              child: _AnimatedTapButton(
                onTap: _showSemesterPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          _selectedSemester == 'All' 
                              ? 'All' 
                              : _selectedSemester == 'Non Semester'
                                  ? 'Non Semester'
                                  : '${_selectedSemester.toUpperCase()} , 25/26',
                          style: GoogleFonts.dmMono(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Status Toggle
            _AnimatedTapButton(
              onTap: () {
                setState(() {
                  _subjectStatus = 'On-Going';
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: _subjectStatus == 'On-Going'
                      ? const Color(0xFF75E1D1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _subjectStatus == 'On-Going'
                        ? const Color(0xFF006E5E)
                        : Colors.black,
                    width: 2,
                  ),
                ),
                child: Text(
                  'On-Going',
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _subjectStatus == 'On-Going'
                        ? const Color(0xFF006E5E)
                        : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _AnimatedTapButton(
              onTap: () {
                setState(() {
                  _subjectStatus = 'Ended';
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: _subjectStatus == 'Ended'
                      ? const Color(0xFF75E1D1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _subjectStatus == 'Ended'
                        ? const Color(0xFF006E5E)
                        : Colors.black,
                    width: 2,
                  ),
                ),
                child: Text(
                  'Ended',
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _subjectStatus == 'Ended'
                        ? const Color(0xFF006E5E)
                        : Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Subjects Grid
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getSubjectsStream(user.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                    color: Color(0xFF6B7280),
                  ),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptySubjectsState();
            }

            final subjects = snapshot.data!;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: subjects.length,
              itemBuilder: (context, index) {
                return _buildSubjectCard(subjects[index]);
              },
            );
          },
        ),
      ],
    );
  }

  void _showSemesterPicker() {
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
                    'Select Semester',
                    style: GoogleFonts.dmMono(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Use StreamBuilder for real-time updates
                StreamBuilder<List<String>>(
                  stream: _getAvailableSemestersStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                          color: Color(0xFF6B7280),
                        ),
                      );
                    }

                    final semesters = snapshot.data ?? ['All'];

                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: semesters.length,
                      itemBuilder: (context, index) {
                        final semester = semesters[index];
                        final isSelected = semester == _selectedSemester;
                        
                        return ListTile(
                          title: Text(
                            semester,
                            style: GoogleFonts.dmMono(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: Color(0xFF34A853))
                              : null,
                          onTap: () {
                            setState(() => _selectedSemester = semester);
                            Navigator.pop(context);
                          },
                        );
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
  }

  Stream<List<Map<String, dynamic>>> _getSubjectsStream(String userId) {
    return _firestore
        .collection('timetable')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // Group by class name
      Map<String, Map<String, dynamic>> subjectsMap = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final className = data['className'] ?? 'Untitled';
        final timestamp = data['date'] as Timestamp?;
        
        if (timestamp == null) continue;
        
        final eventDate = timestamp.toDate();
        final eventDateOnly = DateTime(eventDate.year, eventDate.month, eventDate.day);
        
        // Filter by semester
        if (_selectedSemester != 'All') {
          if (_selectedSemester == 'Non Semester') {
            if (data['semester'] != null || data['academicYear'] != null) {
              continue;
            }
          } else {
            final semesterNum = int.tryParse(_selectedSemester.replaceAll('Semester ', ''));
            if (semesterNum == null || data['semester'] != semesterNum) {
              continue;
            }
          }
        }
        
        // Track the latest date for each subject
        if (!subjectsMap.containsKey(className)) {
          subjectsMap[className] = {
            'className': className,
            'semester': data['semester'],
            'academicYear': data['academicYear'],
            'latestDate': eventDateOnly,
          };
        } else {
          final existingDate = subjectsMap[className]!['latestDate'] as DateTime;
          if (eventDateOnly.isAfter(existingDate)) {
            subjectsMap[className]!['latestDate'] = eventDateOnly;
          }
        }
      }

      // Filter by status (On-Going or Ended)
      List<Map<String, dynamic>> filteredSubjects = subjectsMap.values.where((subject) {
        final latestDate = subject['latestDate'] as DateTime;
        final isEnded = latestDate.isBefore(today);
        
        return (_subjectStatus == 'On-Going' && !isEnded) ||
               (_subjectStatus == 'Ended' && isEnded);
      }).toList();

      // Sort alphabetically
      filteredSubjects.sort((a, b) => 
        (a['className'] as String).compareTo(b['className'] as String)
      );

      return filteredSubjects;
    });
  }

 Widget _buildSubjectCard(Map<String, dynamic> subject) {
  return _AnimatedTapButton(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SubjectDetailScreen(
            subjectName: subject['className'],
            semester: subject['semester'],
            academicYear: subject['academicYear'],
          ),
        ),
      );
    },
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Center(
        child: Text(
          subject['className'],
          style: GoogleFonts.dmMono(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}

  Widget _buildEmptySubjectsState() {
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
            Icons.school_outlined,
            size: 48,
            color: Color(0xFF6B7280),
          ),
          const SizedBox(height: 12),
          Text(
            _subjectStatus == 'On-Going' 
                ? 'No ongoing subjects'
                : 'No ended subjects',
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

  // Detail row helper
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

  // Show task details modal
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
                          if (task['taskDetails'] != null && task['taskDetails'].isNotEmpty)
                            _buildDetailRow('Details', task['taskDetails']),
                          if (task['subject'] != null && task['subject'].isNotEmpty)
                            _buildDetailRow('Subject', task['subject']),
                          _buildDetailRow('Type', task['taskType']),
                          _buildDetailRow(
                            'Due Date',
                            DateFormat('EEE, dd MMM yyyy').format(dueDate),
                          ),
                          _buildDetailRow('Due Time', _formatTime(task['dueTime'])),
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
                                    builder: (_) => EditTaskScreen(taskData: task),
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
                                side: const BorderSide(color: Colors.black, width: 2),
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
                                await _firestore.collection('tasks').doc(task['id']).delete();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Task deleted', style: GoogleFonts.dmMono()),
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
      },
    );
  }

  // Status toggle for task
  Widget _buildStatusToggleInModal(Map<String, dynamic> task, StateSetter setModalState) {
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
                      await _firestore.collection('tasks').doc(task['id']).update({'completed': false});
                      setModalState(() {
                        task['completed'] = false;
                      });
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: !isCompleted ? const Color(0xFF008BB9) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !isCompleted ? const Color(0xFF008BB9) : Colors.grey.shade400,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Pending',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: !isCompleted ? Colors.white : Colors.grey.shade600,
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
                      await _firestore.collection('tasks').doc(task['id']).update({'completed': true});
                      setModalState(() {
                        task['completed'] = true;
                      });
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isCompleted ? const Color(0xFF34A853) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCompleted ? const Color(0xFF34A853) : Colors.grey.shade400,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Completed',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isCompleted ? Colors.white : Colors.grey.shade600,
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

  // Show exam details modal
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
                      if (exam['mode'] == 'In Person' && exam['venue'].isNotEmpty)
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

  // Show class details modal
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
                      if (event['building'] != null && event['building'].isNotEmpty)
                        _buildDetailRow('Building', event['building']),
                      if (event['lecturerName'] != null && event['lecturerName'].isNotEmpty)
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
                                builder: (_) => EditClassScreen(classData: event),
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
                            side: const BorderSide(color: Colors.black, width: 2),
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
                            await _firestore.collection('timetable').doc(event['id']).delete();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Class deleted', style: GoogleFonts.dmMono()),
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