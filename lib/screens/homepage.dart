import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'add_new_screen.dart';
import 'edit_class_screen.dart';
import 'edit_task_screen.dart';
import 'edit_exam_screen.dart';
import 'calendar_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String _username = '';
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    final doc = await _firestore.collection('users').doc(user.uid).get();
    setState(() {
      _username = doc.data()?['username'] ?? 'User';
      _isLoading = false;
    });
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  List<DateTime> _getWeekDates() {
    DateTime now = DateTime.now();
    int currentWeekday = now.weekday;
    DateTime monday = now.subtract(Duration(days: currentWeekday - 1));

    List<DateTime> weekDates = [];
    for (int i = 0; i < 7; i++) {
      weekDates.add(monday.add(Duration(days: i)));
    }
    return weekDates;
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

          List<QueryDocumentSnapshot> matchingDocs = [];

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

          bool hasEvents = matchingDocs.isNotEmpty;
          bool isUpcoming = hasEvents && checkDate.isAfter(today);

          return {'hasEvents': hasEvents, 'isUpcoming': isUpcoming};
        });
  }

  Stream<List<Map<String, dynamic>>> _getUpcomingExamsStream() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _firestore
        .collection('exams')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
      List<Map<String, dynamic>> exams = [];

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          final examDateTimestamp = data['examDate'] as Timestamp?;

          if (examDateTimestamp != null) {
            final examDate = examDateTimestamp.toDate();
            final examDateOnly = DateTime(
              examDate.year,
              examDate.month,
              examDate.day,
            );

            // Only include upcoming exams (today or future)
            if (examDateOnly.isAfter(today) ||
                (examDateOnly.year == today.year &&
                    examDateOnly.month == today.month &&
                    examDateOnly.day == today.day)) {
              final startTime = (data['startTime'] as Timestamp).toDate();
              final endTime = (data['endTime'] as Timestamp).toDate();

              exams.add({
                'id': doc.id,
                'examName': data['examName'] ?? 'Untitled Exam',
                'subject': data['subject'] ?? '',
                'type': data['type'] ?? 'Exam',
                'mode': data['mode'] ?? 'In Person',
                'venue': data['venue'] ?? '',
                'examDate': examDateTimestamp,
                'startTime': startTime,
                'endTime': endTime,
              });
            }
          }
        } catch (e) {
          print('Error processing exam document ${doc.id}: $e');
          continue;
        }
      }

      // Sort by exam date (earliest first)
      exams.sort((a, b) {
        final aDate = (a['examDate'] as Timestamp).toDate();
        final bDate = (b['examDate'] as Timestamp).toDate();
        return aDate.compareTo(bDate);
      });

      return exams;
    });
  }

  @override
  Widget build(BuildContext context) {
    DateTime today = DateTime.now();
    List<DateTime> weekDates = _getWeekDates();
    String currentMonth = DateFormat('MMMM').format(today);

    // Define the screens
    final List<Widget> _screens = [
      _buildHomeScreen(currentMonth, weekDates, today),
      const CalendarScreen(),
      const Center(child: Text('Tasks Screen')), // Placeholder
      const Center(child: Text('Profile Screen')), // Placeholder
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedNavIndex,
              children: _screens,
            ),
          ),
          _buildBottomNavigation(),
        ],
      ),
    );
  }

  Widget _buildHomeScreen(
    String currentMonth,
    List<DateTime> weekDates,
    DateTime today,
  ) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _buildHeader(),
              const SizedBox(height: 24),
              _buildGreeting(),
              const SizedBox(height: 24),
              _buildScheduleSection(currentMonth, weekDates, today),
              const SizedBox(height: 24),
              _buildTodayTimetable(),
              const SizedBox(height: 24),
              _buildAssessmentsSection(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'HOME',
          style: GoogleFonts.dmMono(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        _AnimatedTapButton(
          onTap: _logout,
          child: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFF6B7280),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.logout, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildGreeting() {
    return _isLoading
        ? const SizedBox()
        : Text(
            'Hi, $_username !!!',
            style: GoogleFonts.dmMono(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          );
  }

  Widget _buildScheduleSection(
    String currentMonth,
    List<DateTime> weekDates,
    DateTime today,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Schedule',
          style: GoogleFonts.dmMono(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
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
                  Text(
                    'This Week',
                    style: GoogleFonts.dmMono(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B7280),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      currentMonth,
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: weekDates.map((date) {
                  bool isToday =
                      date.day == today.day &&
                      date.month == today.month &&
                      date.year == today.year;

                  bool isSelected =
                      date.day == _selectedDate.day &&
                      date.month == _selectedDate.month &&
                      date.year == _selectedDate.year;

                  return StreamBuilder<Map<String, bool>>(
                    stream: _checkEventsOnDateStream(date),
                    builder: (context, snapshot) {
                      bool hasEvents = snapshot.data?['hasEvents'] ?? false;
                      bool isUpcoming = snapshot.data?['isUpcoming'] ?? false;
                      return _dateCircle(
                        date.day.toString().padLeft(2, '0'),
                        isToday,
                        isSelected,
                        hasEvents,
                        isUpcoming,
                        date,
                      );
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: _AnimatedTapButton(
            onTap: () {
              setState(() {
                _selectedNavIndex = 1; // Switch to calendar tab
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF292929),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                'MORE',
                style: GoogleFonts.dmMono(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssessmentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assessments Dates',
          style: GoogleFonts.dmMono(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getUpcomingExamsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: 140,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(
                  color: Color(0xFF9AB900),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Container(
                height: 140,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.assignment_outlined,
                      size: 40,
                      color: Color(0xFF6B7280),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No upcoming assessments',
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }

            return SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final exam = snapshot.data![index];
                  return _buildExamCard(exam);
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildExamCard(Map<String, dynamic> exam) {
    final examDate = (exam['examDate'] as Timestamp).toDate();
    final startTime = exam['startTime'] as DateTime;
    final endTime = exam['endTime'] as DateTime;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final examDateOnly = DateTime(examDate.year, examDate.month, examDate.day);
    
    final daysUntil = examDateOnly.difference(today).inDays;
    
    String durationLabel;
    bool isToday = daysUntil == 0;
    
    if (isToday) {
      durationLabel = 'TODAY';
    } else if (daysUntil == 1) {
      durationLabel = '1 DAY';
    } else {
      durationLabel = '$daysUntil DAYS';
    }

    return _AnimatedTapButton(
      onTap: () => _showExamDetails(exam),
      child: Container(
        width: 280,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Row(
          children: [
            // Left side - Date
            Container(
              width: 90,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: Colors.black, width: 2),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isToday
                          ? const Color(0xFF9AB900)
                          : const Color(0xFFFEFFE6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF9AB900),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      durationLabel,
                      style: GoogleFonts.dmMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isToday ? Colors.white : const Color(0xFF9AB900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat('MMM').format(examDate).toUpperCase(),
                    style: GoogleFonts.dmMono(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd').format(examDate),
                    style: GoogleFonts.dmMono(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Right side - Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      exam['type'].toString().toUpperCase(),
                      style: GoogleFonts.dmMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF9AB900),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      exam['examName'],
                      style: GoogleFonts.dmMono(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (exam['subject'].isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        exam['subject'],
                        style: GoogleFonts.dmMono(
                          fontSize: 10,
                          color: const Color(0xFF6B7280),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 12,
                          color: Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${DateFormat('hh:mm a').format(startTime)} - ${DateFormat('hh:mm a').format(endTime)}',
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              color: const Color(0xFF6B7280),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          exam['mode'] == 'Online'
                              ? Icons.computer
                              : Icons.location_on_outlined,
                          size: 12,
                          color: const Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            exam['mode'] == 'Online'
                                ? 'Online'
                                : (exam['venue'].isEmpty ? 'F2 Attend' : exam['venue']),
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              color: const Color(0xFF6B7280),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExamDetails(Map<String, dynamic> exam) {
    final examDate = (exam['examDate'] as Timestamp).toDate();
    final startTime = exam['startTime'] as DateTime;
    final endTime = exam['endTime'] as DateTime;

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

  Widget _weekdayLabel(String day) {
    return SizedBox(
      width: 38,
      child: Text(
        day,
        textAlign: TextAlign.center,
        style: GoogleFonts.dmMono(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _dateCircle(
    String date,
    bool isToday,
    bool isSelected,
    bool hasEvents,
    bool isUpcoming,
    DateTime dateTime,
  ) {
    Color backgroundColor = isToday
        ? const Color(0xFFB90000)
        : Colors.transparent;

    Color? borderColor;
    double? borderWidth;

    if (isToday) {
      borderColor = null;
      borderWidth = null;
    } else if (isUpcoming) {
      borderColor = const Color(0xFFB90000);
      borderWidth = 2;
    } else if (hasEvents) {
      borderColor = Colors.black;
      borderWidth = 2;
    }

    return _AnimatedTapButton(
      onTap: () {
        setState(() {
          _selectedDate = dateTime;
        });
      },
      child: SizedBox(
        width: 38,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
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
                  date,
                  style: GoogleFonts.dmMono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isToday ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                top: 36,
                child: CustomPaint(
                  size: const Size(10, 8),
                  painter: TrianglePainter(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayTimetable() {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('dd MMM yyyy').format(_selectedDate) ==
                  DateFormat('dd MMM yyyy').format(DateTime.now())
              ? 'Today Timetable'
              : 'Timetable - ${DateFormat('EEE, dd MMM').format(_selectedDate)}',
          style: GoogleFonts.dmMono(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getCombinedEventsStream(user.uid),
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
              return _buildEmptyState();
            }

            List<Map<String, dynamic>> events = snapshot.data!;

            events.sort((a, b) {
              if (a['type'] == 'task' && b['type'] == 'task') {
                return (a['dueTime'] as String).compareTo(
                  b['dueTime'] as String,
                );
              } else if (a['type'] == 'task') {
                return (a['dueTime'] as String).compareTo(
                  b['startTime'] as String,
                );
              } else if (b['type'] == 'task') {
                return (a['startTime'] as String).compareTo(
                  b['dueTime'] as String,
                );
              } else {
                return (a['startTime'] as String).compareTo(
                  b['startTime'] as String,
                );
              }
            });

            return Column(
              children: [
                ...events.map((event) {
                  if (event['type'] == 'task') {
                    return _buildTaskCard(event);
                  } else {
                    return _buildEnhancedClassCard(event);
                  }
                }).toList(),
              ],
            );
          },
        ),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> _getCombinedEventsStream(String userId) {
    return _firestore
        .collection('timetable')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((timetableSnapshot) async {
          List<Map<String, dynamic>> allEvents = [];

          for (var doc in timetableSnapshot.docs) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = data['date'] as Timestamp?;

              if (timestamp != null) {
                final eventDate = timestamp.toDate();

                if (eventDate.year == _selectedDate.year &&
                    eventDate.month == _selectedDate.month &&
                    eventDate.day == _selectedDate.day) {
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
                    'semester': data['semester'],
                    'academicYear': data['academicYear'],
                  });
                }
              }
            } catch (e) {
              print('Error processing timetable document ${doc.id}: $e');
              continue;
            }
          }

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

                if (dueDate.year == _selectedDate.year &&
                    dueDate.month == _selectedDate.month &&
                    dueDate.day == _selectedDate.day) {
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

          return allEvents;
        });
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final dueDate = (task['dueDate'] as Timestamp).toDate();
    final isCompleted = task['completed'] ?? false;

    return _AnimatedTapButton(
      onTap: () => _showTaskDetails(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCompleted ? const Color(0xFF34A853) : Colors.black,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    isCompleted
                        ? const Color(0xFF34A853).withOpacity(0.1)
                        : const Color(0xFF008BB9).withOpacity(0.1),
                    Colors.white,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? const Color(0xFF34A853)
                          : const Color(0xFF008BB9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isCompleted ? Icons.check_circle : Icons.task_alt,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task['taskTitle'],
                                style: GoogleFonts.dmMono(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: isCompleted
                                      ? Colors.grey.shade600
                                      : Colors.black,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!isCompleted) _CountdownTimer(dueDate: dueDate),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? const Color(0xFF34A853)
                                    : const Color(0xFF008BB9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                task['taskType'] ?? 'TASK',
                                style: GoogleFonts.dmMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (isCompleted) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF34A853),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.check,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'COMPLETED',
                                      style: GoogleFonts.dmMono(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailItem(
                          Icons.calendar_today,
                          DateFormat('dd MMM yyyy').format(dueDate),
                        ),
                      ),
                      Expanded(
                        child: _buildDetailItem(
                          Icons.access_time,
                          _formatTime(task['dueTime']),
                        ),
                      ),
                    ],
                  ),
                  if (task['subject'].isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailItem(
                            Icons.subject,
                            task['subject'],
                          ),
                        ),
                      ],
                    ),
                  ],
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

  Widget _buildEnhancedClassCard(Map<String, dynamic> event) {
    Color labelColor;
    String labelText;
    IconData labelIcon;

    switch (event['type']) {
      case 'exam':
        labelColor = const Color.fromARGB(255, 139, 185, 0);
        labelText = 'EXAM';
        labelIcon = Icons.assignment_outlined;
        break;
      case 'task':
        labelColor = const Color.fromARGB(255, 0, 195, 255);
        labelText = 'TASK';
        labelIcon = Icons.task_alt;
        break;
      default:
        labelColor = const Color.fromARGB(255, 198, 0, 0);
        labelText = 'CLASS';
        labelIcon = Icons.school_outlined;
    }

    return _AnimatedTapButton(
      onTap: () => _showEnhancedClassDetails(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [labelColor.withOpacity(0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: labelColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(labelIcon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event['className'],
                          style: GoogleFonts.dmMono(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: labelColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            labelText,
                            style: GoogleFonts.dmMono(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildDetailItem(
                      Icons.access_time,
                      '${_formatTime(event['startTime'])} - ${_formatTime(event['endTime'])}',
                    ),
                  ),
                  if (event['room'].isNotEmpty || event['building'].isNotEmpty)
                    Expanded(
                      child: _buildDetailItem(
                        Icons.location_on_outlined,
                        '${event['room']}${event['room'].isNotEmpty && event['building'].isNotEmpty ? ', ' : ''}${event['building']}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.dmMono(
              fontSize: 11,
              color: const Color(0xFF6B7280),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
                          if (task['taskDetails'].isNotEmpty)
                            _buildDetailRow('Details', task['taskDetails']),
                          if (task['subject'].isNotEmpty)
                            _buildDetailRow('Subject', task['subject']),
                          _buildDetailRow('Type', task['taskType']),
                          _buildDetailRow(
                            'Due Date',
                            DateFormat('EEE, dd MMM yyyy').format(dueDate),
                          ),
                          _buildDetailRow(
                              'Due Time', _formatTime(task['dueTime'])),
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
                                side: const BorderSide(
                                  color: Colors.black,
                                  width: 2,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
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
                              label:
                                  Text('Delete', style: GoogleFonts.dmMono()),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB90000),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
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

  void _showEnhancedClassDetails(Map<String, dynamic> event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        Color labelColor;
        switch (event['type']) {
          case 'exam':
            labelColor = const Color(0xFFB90000);
            break;
          case 'task':
            labelColor = Colors.orange;
            break;
          default:
            labelColor = const Color(0xFFFBBC05);
        }

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
                      if (event['room'].isNotEmpty)
                        _buildDetailRow('Room', event['room']),
                      if (event['building'].isNotEmpty)
                        _buildDetailRow('Building', event['building']),
                      if (event['lecturerName'].isNotEmpty)
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
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditClassScreen(classData: event),
                              ),
                            );
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

  Widget _buildStatusToggleInModal(
      Map<String, dynamic> task, StateSetter setModalState) {
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
                            ? const Color(0xFFFBBC05)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !isCompleted
                              ? const Color(0xFFFBBC05)
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

  Widget _buildBottomNavigation() {
    return Container(
      decoration: const BoxDecoration(color: Colors.white),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavIcon(Icons.home, 0),
              _buildNavIcon(Icons.calendar_today, 1),
              _buildAddButton(),
              _buildNavIcon(Icons.access_time, 2),
              _buildNavIcon(Icons.person, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, int index) {
    bool isActive = _selectedNavIndex == index;
    return _AnimatedTapButton(
      onTap: () {
        setState(() {
          _selectedNavIndex = index;
        });
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF6B7280) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : Colors.black,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return _AnimatedTapButton(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddNewScreen()),
        ).then((_) => setState(() {}));
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: Color(0xFF292929),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
    );
  }
}

// Real-time countdown timer widget
class _CountdownTimer extends StatefulWidget {
  final DateTime dueDate;

  const _CountdownTimer({required this.dueDate});

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  late Timer _timer;
  Duration _remainingTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemainingTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateRemainingTime();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateRemainingTime() {
    setState(() {
      _remainingTime = widget.dueDate.difference(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    String countdownText;
    Color countdownColor;
    IconData countdownIcon;

    if (_remainingTime.isNegative) {
      countdownText = 'SUBMISSION CLOSED';
      countdownColor = const Color(0xFFB90000);
      countdownIcon = Icons.cancel;
    } else {
      countdownColor = const Color(0xFF34A853);
      countdownIcon = Icons.schedule;
      
      if (_remainingTime.inDays > 0) {
        final days = _remainingTime.inDays;
        final hours = _remainingTime.inHours % 24;
        final minutes = _remainingTime.inMinutes % 60;
        final seconds = _remainingTime.inSeconds % 60;
        countdownText = '${days}d ${hours}h ${minutes}m ${seconds}s';
      } else if (_remainingTime.inHours > 0) {
        final hours = _remainingTime.inHours;
        final minutes = _remainingTime.inMinutes % 60;
        final seconds = _remainingTime.inSeconds % 60;
        countdownText = '${hours}h ${minutes}m ${seconds}s';
      } else {
        final minutes = _remainingTime.inMinutes;
        final seconds = _remainingTime.inSeconds % 60;
        countdownText = '${minutes}m ${seconds}s';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: countdownColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: countdownColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(countdownIcon, size: 14, color: countdownColor),
          const SizedBox(width: 6),
          Text(
            countdownText,
            style: GoogleFonts.dmMono(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: countdownColor,
            ),
          ),
        ],
      ),
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