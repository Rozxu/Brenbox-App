import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
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
    
    // Add empty slots for days before the first day of the month
    int firstWeekday = firstDay.weekday;
    if (firstWeekday == 7) firstWeekday = 0; // Sunday = 0
    
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
              _weekdayLabel('MON'),
              _weekdayLabel('TUE'),
              _weekdayLabel('WED'),
              _weekdayLabel('THU'),
              _weekdayLabel('FRI'),
              _weekdayLabel('SAT'),
              _weekdayLabel('SUN'),
            ],
          ),
          const SizedBox(height: 12),
          
          // Calendar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
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
      child: Container(
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
                } else if (event['type'] == 'exam') {
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
                  final startTime = (data['startTime'] as Timestamp).toDate();
                  final endTime = (data['endTime'] as Timestamp).toDate();
                  
                  allEvents.add({
                    'id': doc.id,
                    'type': 'exam',
                    'examName': data['examName'] ?? 'Untitled Exam',
                    'subject': data['subject'] ?? '',
                    'examType': data['type'] ?? 'Exam',
                    'mode': data['mode'] ?? 'In Person',
                    'venue': data['venue'] ?? '',
                    'examDate': timestamp,
                    'startTime': DateFormat('HH:mm').format(startTime),
                    'endTime': DateFormat('HH:mm').format(endTime),
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
    
    return Container(
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
    );
  }

  Widget _buildExamCard(Map<String, dynamic> exam) {
    return Container(
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
                        exam['examType'].toString().toUpperCase(),
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
                        exam['examName'],
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
                  '${_formatTime(exam['startTime'])} - ${_formatTime(exam['endTime'])}${exam['subject'].isNotEmpty ? ' • ${exam['subject']}' : ''}',
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
    );
  }

  Widget _buildClassCard(Map<String, dynamic> event) {
    Color labelColor = const Color(0xFFB90000);
    
    return Container(
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