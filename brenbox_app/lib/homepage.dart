import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'tasks/add_new_screen.dart';
import 'tasks/edit_class_screen.dart';
import 'tasks/edit_task_screen.dart';
import 'tasks/edit_exam_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/study_group_screen.dart';
import 'screens/study_plan_screen.dart';
import 'authenticate/account_screen.dart';
import 'screens/grade_calculator_screen.dart';
import 'screens/certificate_repository_screen.dart';
import 'screens/notification_history_screen.dart';
import 'services/notification_service.dart';
import 'services/notification_scheduler.dart';
import 'app_preferences.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map?;
      if (args == null || !mounted) return;
      if (args['navIndex'] != null) {
        setState(() => _selectedNavIndex = args['navIndex'] as int);
      }
      if (args['groupId'] != null) {
        _navigateToGroup(
          args['groupId'] as String,
          args['tab'] as int? ?? 0,
        );
      }
      if (args['planId'] != null) {
        _navigateToStudyPlan(args['planId'] as String);
      }
    });
    _loadUserData();
  }

  StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  Timer? _studyPlanExpiry;

  @override
  void dispose() {
    _fcmForegroundSub?.cancel();
    _studyPlanExpiry?.cancel();
    super.dispose();
  }

  void _scheduleStudyPlanExpiry(List<QueryDocumentSnapshot> docs) {
    _studyPlanExpiry?.cancel();
    _studyPlanExpiry = null;
    final now = DateTime.now();
    DateTime? soonest;
    for (final doc in docs) {
      final dueTs = (doc.data() as Map<String, dynamic>)['dueDate'] as Timestamp?;
      if (dueTs == null) continue;
      final due = dueTs.toDate();
      if (due.isAfter(now) && (soonest == null || due.isBefore(soonest))) {
        soonest = due;
      }
    }
    if (soonest == null) return;
    final delay = soonest.difference(DateTime.now());
    if (delay.inSeconds <= 0) { if (mounted) setState(() {}); return; }
    _studyPlanExpiry = Timer(delay, () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _navigateToGroup(String groupId, int tab) async {
    try {
      final doc = await _firestore.collection('study_groups').doc(groupId).get();
      if (!mounted) return;
      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Group not found. It may have been deleted.',
            style: GoogleFonts.dmMono(),
          ),
          backgroundColor: const Color(0xFFB90000),
        ));
        return;
      }
      final data      = doc.data()!;
      final groupName = data['name']    as String? ?? '';
      final subject   = data['subject'] as String? ?? '';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudyGroupScreen(
            groupId:    groupId,
            groupName:  groupName,
            subject:    subject,
            initialTab: tab,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open group.', style: GoogleFonts.dmMono()),
        backgroundColor: const Color(0xFFB90000),
      ));
    }
  }

  Future<void> _navigateToStudyPlan(String planId) async {
    try {
      final doc = await _firestore.collection('study_plans').doc(planId).get();
      if (!mounted || !doc.exists) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudyPlanDetailScreen(
            planId: planId,
            data: doc.data()!,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final doc = await _firestore.collection('users').doc(user.uid).get();

    if (!mounted) return;

    setState(() {
      _username = doc.data()?['username'] ?? 'User';
      _isLoading = false;
    });

    fontScaleNotifier.value = (doc.data()?['fontScale'] as num?)?.toDouble() ?? kDefaultFontScale;
    darkModeNotifier.value  = doc.data()?['darkMode']  as bool? ?? false;

    // Save FCM token so Cloud Functions can push to this device
    NotificationService().saveFcmToken(user.uid);

    // Foreground: Android won't auto-display FCM — show it ourselves
    _fcmForegroundSub = FirebaseMessaging.onMessage.listen(
      (msg) => NotificationService().handleForegroundFcmMessage(msg),
    );

    // Background tap (app was suspended, user tapped notification)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmTap);

    // Terminated tap (app was fully closed, user tapped notification)
    FirebaseMessaging.instance
        .getInitialMessage()
        .then((msg) { if (msg != null) _handleFcmTap(msg); });

    // onAppOpen() is lightweight — schedules new events and restores lost OS
    // alarms without cancelling everything already queued.
    NotificationScheduler().onAppOpen();
  }

  void _handleFcmTap(RemoteMessage message) {
    final data         = message.data;
    final type         = data['type']         as String? ?? '';
    final historyDocId = data['historyDocId'] as String?;

    if (historyDocId != null) {
      _firestore
          .collection('notification_history')
          .doc(historyDocId)
          .update({'isRead': true});
    }

    if (type.startsWith('group_')) {
      final groupId = data['groupId'] as String?;
      final tab     = int.tryParse(data['tab'] ?? '0') ?? 0;
      if (groupId != null && mounted) _navigateToGroup(groupId, tab);
    } else if (type == 'group_invite' || type == 'timetable_invite') {
      if (mounted) setState(() => _selectedNavIndex = 1);
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    // AuthGate listens to authStateChanges() and navigates automatically.
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

      // Also check exams so past exam dates show a black circle border
      final examsSnapshot = await _firestore
          .collection('exams')
          .where('userId', isEqualTo: user.uid)
          .get();

      bool _matchesDate(DateTime docDate) {
        final d = DateTime(docDate.year, docDate.month, docDate.day);
        return d.year == checkDate.year &&
            d.month == checkDate.month &&
            d.day == checkDate.day;
      }

      bool hasEvents = false;

      for (var doc in timetableSnapshot.docs) {
        final ts = (doc.data() as Map<String, dynamic>)['date'] as Timestamp?;
        if (ts != null && _matchesDate(ts.toDate())) { hasEvents = true; break; }
      }

      if (!hasEvents) {
        for (var doc in tasksSnapshot.docs) {
          final ts = (doc.data() as Map<String, dynamic>)['dueDate'] as Timestamp?;
          if (ts != null && _matchesDate(ts.toDate())) { hasEvents = true; break; }
        }
      }

      if (!hasEvents) {
        for (var doc in examsSnapshot.docs) {
          final ts = (doc.data() as Map<String, dynamic>)['examDate'] as Timestamp?;
          if (ts != null && _matchesDate(ts.toDate())) { hasEvents = true; break; }
        }
      }

      final bool isUpcoming = hasEvents && checkDate.isAfter(today);
      return {'hasEvents': hasEvents, 'isUpcoming': isUpcoming};
    }).handleError((_) {});
  }

  Stream<List<Map<String, dynamic>>> _getExamsForDateStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('exams')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
      final now   = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final List<Map<String, dynamic>> result = [];
      for (var doc in snapshot.docs) {
        try {
          final data              = doc.data();
          final examDateTimestamp = data['examDate'] as Timestamp?;
          if (examDateTimestamp == null) continue;
          final examDate  = examDateTimestamp.toDate();
          final examDay   = DateTime(examDate.year, examDate.month, examDate.day);
          final startTime = (data['startTime'] as Timestamp).toDate();
          final endTime   = (data['endTime']   as Timestamp).toDate();

          // Skip exams from previous days — only show today and future
          if (examDay.isBefore(today)) continue;

          result.add({
            'id':        doc.id,
            'examName':  data['examName'] ?? 'Untitled Exam',
            'subject':   data['subject']  ?? '',
            'type':      data['type']     ?? 'Exam',
            'mode':      data['mode']     ?? 'In Person',
            'venue':     data['venue']    ?? '',
            'examDate':  examDateTimestamp,
            'startTime': startTime,
            'endTime':   endTime,
          });
        } catch (_) {
          continue;
        }
      }
      // Sort by exam date ascending so nearest exam appears first
      result.sort((a, b) =>
          (a['examDate'] as Timestamp).compareTo(b['examDate'] as Timestamp));
      return result;
    }).handleError((_) => <Map<String, dynamic>>[]);
  }

  @override
  Widget build(BuildContext context) {
    DateTime today = DateTime.now();
    List<DateTime> weekDates = _getWeekDates();
    String currentMonth = DateFormat('MMMM').format(today);

    final List<Widget> _screens = [
      _buildHomeScreen(currentMonth, weekDates, today),
      const CalendarScreen(),
      const GradeCalculatorScreen(),
      const CertificateRepositoryScreen(),
      AccountScreen(
        onBackPressed: () {
          setState(() {
            _selectedNavIndex = 0;
          });
        },
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedNavIndex,
              children: _screens,
            ),
          ),
          if (_selectedNavIndex != 4) _buildBottomNavigation(),
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
              const SizedBox(height: 16),

              const SizedBox(height: 24),
              _buildScheduleSection(currentMonth, weekDates, today),
              const SizedBox(height: 24),
              _buildTodayTimetable(),
              const SizedBox(height: 24),
              _buildAssessmentsSection(),
              const SizedBox(height: 24),
              _buildStudyPlanSection(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }



  // ════════════════════════════════════════════════════════════════════════════
  // HEADER with real-time unread notification dot
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'HOME',
          style: GoogleFonts.dmMono(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
        ),
        Row(
          children: [
            _BellDot(
              userId: _auth.currentUser?.uid ?? '',
              firestore: _firestore,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotificationHistoryScreen(
                      onGoToCalendar: () {
                        setState(() => _selectedNavIndex = 1);
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
            _AnimatedTapButton(
              onTap: () => setState(() => _selectedNavIndex = 4),
              child: Icon(
                Icons.person_outline,
                color: AppColors.text(context),
                size: 28,
              ),
            ),
          ],
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
          style: GoogleFonts.dmMono(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border(context), width: 2),
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
                      color: AppColors.text(context),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.chipBg(context),
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
                  bool isToday = date.day == today.day &&
                      date.month == today.month &&
                      date.year == today.year;
                  bool isSelected = date.day == _selectedDate.day &&
                      date.month == _selectedDate.month &&
                      date.year == _selectedDate.year;

                  return StreamBuilder<Map<String, bool>>(
                    stream: _checkEventsOnDateStream(date),
                    builder: (context, snapshot) {
                      bool hasEvents =
                          snapshot.data?['hasEvents'] ?? false;
                      bool isUpcoming =
                          snapshot.data?['isUpcoming'] ?? false;
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
                _selectedNavIndex = 1;
              });
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.chipBg(context),
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
          'Assessment Dates',
          style: GoogleFonts.dmMono(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getExamsForDateStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: 140,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(
                    color: Color(0xFF9AB900)),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Container(
                height: 140,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border(context), width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_outlined,
                        size: 40, color: AppColors.subtext(context)),
                    const SizedBox(height: 8),
                    Text(
                      'No upcoming assessments',
                      style: GoogleFonts.dmMono(
                          fontSize: 12, color: AppColors.subtext(context)),
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
    final examDate  = (exam['examDate'] as Timestamp).toDate();
    final startTime = exam['startTime'] as DateTime;
    final endTime   = exam['endTime']   as DateTime;
    final now       = DateTime.now();
    // Compute isPast live so the card shows DONE on the day the exam ends
    final isPast    = endTime.isBefore(now);
    final today     = DateTime(now.year, now.month, now.day);
    final examDay   = DateTime(examDate.year, examDate.month, examDate.day);
    final daysUntil = examDay.difference(today).inDays;

    final bool isToday = daysUntil == 0;

    String durationLabel;
    Color  labelBg;
    Color  labelFg;
    Color  cardBorderColor;

    if (isPast) {
      durationLabel   = 'DONE';
      labelBg         = AppColors.fieldBg(context);
      labelFg         = AppColors.subtext(context);
      cardBorderColor = AppColors.border(context);
    } else if (isToday) {
      durationLabel   = 'TODAY';
      labelBg         = const Color(0xFF9AB900);
      labelFg         = Colors.white;
      cardBorderColor = AppColors.border(context);
    } else if (daysUntil == 1) {
      durationLabel   = '1 DAY';
      labelBg         = const Color(0xFFFEFFE6);
      labelFg         = const Color(0xFF9AB900);
      cardBorderColor = AppColors.border(context);
    } else {
      durationLabel   = '$daysUntil DAYS';
      labelBg         = const Color(0xFFFEFFE6);
      labelFg         = const Color(0xFF9AB900);
      cardBorderColor = AppColors.border(context);
    }

    return _AnimatedTapButton(
      onTap: () => _showExamDetails(exam),
      child: Container(
        width: 280,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorderColor, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 90,
              padding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                    right: BorderSide(color: AppColors.border(context), width: 2)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: labelBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isPast
                              ? AppColors.border(context)
                              : const Color(0xFF9AB900),
                          width: 2),
                    ),
                    child: Text(
                      durationLabel,
                      style: GoogleFonts.dmMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: labelFg,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM').format(examDate).toUpperCase(),
                    style: GoogleFonts.dmMono(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd').format(examDate),
                    style: GoogleFonts.dmMono(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text(context),
                    ),
                  ),
                ],
              ),
            ),
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
                        color: AppColors.text(context),
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
                            color: AppColors.subtext(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 12, color: AppColors.subtext(context)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${DateFormat('hh:mm a').format(startTime)} - ${DateFormat('hh:mm a').format(endTime)}',
                            style: GoogleFonts.dmMono(
                                fontSize: 10,
                                color: AppColors.subtext(context)),
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
                          color: AppColors.subtext(context),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            exam['mode'] == 'Online'
                                ? 'Online'
                                : (exam['venue'].isEmpty
                                    ? 'F2 Attend'
                                    : exam['venue']),
                            style: GoogleFonts.dmMono(
                                fontSize: 10,
                                color: AppColors.subtext(context)),
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
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: AppColors.border(context), width: 2),
              left: BorderSide(color: AppColors.border(context), width: 2),
              right: BorderSide(color: AppColors.border(context), width: 2),
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
                    color: AppColors.border(context),
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
                          color: AppColors.text(context),
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
                      _buildDetailRow('Date',
                          DateFormat('EEE, dd MMM yyyy').format(examDate)),
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
                                builder: (_) =>
                                    EditExamScreen(examData: exam),
                              ),
                            );
                            if (result == true && mounted) setState(() {});
                          },
                          icon: Icon(Icons.edit_outlined,
                              color: AppColors.text(context)),
                          label: Text('Edit',
                              style: GoogleFonts.dmMono(
                                  color: AppColors.text(context))),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text(context),
                            side: BorderSide(
                                color: AppColors.border(context), width: 2),
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final messenger =
                                ScaffoldMessenger.of(context);
                            Navigator.pop(context);
                            final ok = await confirmDeleteDialog(context,
                                title: 'Delete Exam',
                                message: 'Are you sure you want to delete this exam? This cannot be undone.');
                            if (!ok) return;
                            // Cancel notifications and clean up Firestore
                            await NotificationService()
                                .cancelNotificationsForEvent(exam['id']);
                            await _firestore
                                .collection('exams')
                                .doc(exam['id'])
                                .delete();
                            messenger.showSnackBar(SnackBar(
                              content: Text('Exam deleted',
                                  style: GoogleFonts.dmMono()),
                              backgroundColor: const Color(0xFFB90000),
                            ));
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
                                borderRadius: BorderRadius.circular(12)),
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
          color: AppColors.text(context),
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
    Color backgroundColor =
        isToday ? const Color(0xFFB90000) : Colors.transparent;

    Color? borderColor;
    double? borderWidth;

    if (isToday) {
      borderColor = null;
      borderWidth = null;
    } else if (isUpcoming) {
      borderColor = const Color(0xFFB90000);
      borderWidth = 2;
    } else if (hasEvents) {
      borderColor = AppColors.isDark(context)
          ? Colors.white.withValues(alpha: 0.35)
          : Colors.black;
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
                    color: isToday ? Colors.white : AppColors.text(context),
                  ),
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                top: 36,
                child: CustomPaint(
                  size: const Size(10, 8),
                  painter: TrianglePainter(color: AppColors.text(context)),
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
          style: GoogleFonts.dmMono(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getCombinedEventsStream(user.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                      color: Color(0xFF6B7280)),
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
                return (a['dueTime'] as String)
                    .compareTo(b['dueTime'] as String);
              } else if (a['type'] == 'task') {
                return (a['dueTime'] as String)
                    .compareTo(b['startTime'] as String);
              } else if (b['type'] == 'task') {
                return (a['startTime'] as String)
                    .compareTo(b['dueTime'] as String);
              } else {
                return (a['startTime'] as String)
                    .compareTo(b['startTime'] as String);
              }
            });

            return Column(
              children: events.map((event) {
                if (event['type'] == 'task') {
                  return _buildTaskCard(event);
                } else {
                  return _buildEnhancedClassCard(event);
                }
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> _getCombinedEventsStream(String userId) {
    final controller = StreamController<List<Map<String, dynamic>>>();

    List<QueryDocumentSnapshot<Map<String, dynamic>>> timetableDocs = [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> tasksDocs = [];

    void emitCombined() {
      if (controller.isClosed) return;
      final allEvents = <Map<String, dynamic>>[];

      for (var doc in timetableDocs) {
        try {
          final data = doc.data();
          final timestamp = data['date'] as Timestamp?;
          if (timestamp == null) continue;
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
        } catch (e) {
          print('Error processing timetable document ${doc.id}: $e');
        }
      }

      for (var doc in tasksDocs) {
        try {
          final data = doc.data();
          final timestamp = data['dueDate'] as Timestamp?;
          if (timestamp == null) continue;
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
        } catch (e) {
          print('Error processing task document ${doc.id}: $e');
        }
      }

      controller.add(allEvents);
    }

    final timetableSub = _firestore
        .collection('timetable')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen(
          (snap) { timetableDocs = snap.docs; emitCombined(); },
          onError: (_) {},
        );

    final tasksSub = _firestore
        .collection('tasks')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen(
          (snap) { tasksDocs = snap.docs; emitCombined(); },
          onError: (_) {},
        );

    controller.onCancel = () {
      timetableSub.cancel();
      tasksSub.cancel();
      if (!controller.isClosed) controller.close();
    };

    return controller.stream;
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final dueDate = (task['dueDate'] as Timestamp).toDate();
    final isCompleted = task['completed'] ?? false;

    return _AnimatedTapButton(
      onTap: () => _showTaskDetails(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCompleted
                ? const Color(0xFF34A853)
                : AppColors.border(context),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    isCompleted
                        ? const Color(0xFF34A853).withValues(alpha: 0.15)
                        : const Color(0xFF008BB9).withValues(alpha: 0.15),
                    AppColors.card(context),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18)),
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
                      isCompleted
                          ? Icons.check_circle
                          : Icons.task_alt,
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
                                      ? AppColors.subtext(context)
                                      : AppColors.text(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!isCompleted)
                              _CountdownTimer(dueDate: dueDate),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
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
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF34A853),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check,
                                        size: 10, color: Colors.white),
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
                              Icons.subject, task['subject']),
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
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context), width: 2),
      ),
      child: Column(
        children: [
          Icon(Icons.event_note_outlined,
              size: 48, color: AppColors.subtext(context)),
          const SizedBox(height: 12),
          Text(
            'No events scheduled',
            style: GoogleFonts.dmMono(
                fontSize: 13, color: AppColors.subtext(context)),
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
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border(context), width: 2),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    labelColor.withValues(alpha: 0.15),
                    AppColors.card(context),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18)),
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
                            color: AppColors.text(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
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
                  if (event['room'].isNotEmpty ||
                      event['building'].isNotEmpty)
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
        Icon(icon, size: 16, color: AppColors.subtext(context)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.dmMono(
                fontSize: 11, color: AppColors.subtext(context)),
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
            return Container(
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: AppColors.border(context), width: 2),
                  left: BorderSide(color: AppColors.border(context), width: 2),
                  right: BorderSide(color: AppColors.border(context), width: 2),
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
                        color: AppColors.border(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Task Details',
                            style: GoogleFonts.dmMono(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text(context),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildDetailRow(
                              'Task Title', task['taskTitle']),
                          if (task['taskDetails'].isNotEmpty)
                            _buildDetailRow(
                                'Details', task['taskDetails']),
                          if (task['subject'].isNotEmpty)
                            _buildDetailRow('Subject', task['subject']),
                          _buildDetailRow('Type', task['taskType']),
                          _buildDetailRow(
                            'Due Date',
                            DateFormat('EEE, dd MMM yyyy')
                                .format(dueDate),
                          ),
                          _buildDetailRow('Due Time',
                              _formatTime(task['dueTime'])),
                          const SizedBox(height: 8),
                          _buildStatusToggleInModal(task, setModalState),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 24),
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
                              icon: Icon(Icons.edit_outlined,
                                  color: AppColors.text(context)),
                              label: Text('Edit',
                                  style: GoogleFonts.dmMono(
                                      color: AppColors.text(context))),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.text(context),
                                side: BorderSide(
                                    color: AppColors.border(context), width: 2),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                Navigator.pop(context);
                                final ok = await confirmDeleteDialog(context,
                                    title: 'Delete Task',
                                    message: 'Are you sure you want to delete this task? This cannot be undone.');
                                if (!ok) return;
                                // Cancel notifications and clean Firestore
                                await NotificationService()
                                    .cancelNotificationsForEvent(
                                        task['id']);
                                await _firestore
                                    .collection('tasks')
                                    .doc(task['id'])
                                    .delete();
                                messenger.showSnackBar(SnackBar(
                                  content: Text('Task deleted',
                                      style: GoogleFonts.dmMono()),
                                  backgroundColor:
                                      const Color(0xFFB90000),
                                ));
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: Text('Delete',
                                  style: GoogleFonts.dmMono()),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFFB90000),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
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
        return Container(
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: AppColors.border(context), width: 2),
              left: BorderSide(color: AppColors.border(context), width: 2),
              right: BorderSide(color: AppColors.border(context), width: 2),
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
                    color: AppColors.border(context),
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
                          color: AppColors.text(context),
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
                        _buildDetailRow(
                            'Lecturer', event['lecturerName']),
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
                          icon: Icon(Icons.edit_outlined,
                              color: AppColors.text(context)),
                          label: Text('Edit',
                              style: GoogleFonts.dmMono(
                                  color: AppColors.text(context))),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text(context),
                            side: BorderSide(
                                color: AppColors.border(context), width: 2),
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final messenger =
                                ScaffoldMessenger.of(context);
                            Navigator.pop(context);
                            final ok = await confirmDeleteDialog(context,
                                title: 'Delete Class',
                                message: 'Are you sure you want to delete this class? This cannot be undone.');
                            if (!ok) return;
                            // Cancel notifications and clean Firestore
                            await NotificationService()
                                .cancelNotificationsForEvent(event['id']);
                            await _firestore
                                .collection('timetable')
                                .doc(event['id'])
                                .delete();
                            messenger.showSnackBar(SnackBar(
                              content: Text('Class deleted',
                                  style: GoogleFonts.dmMono()),
                              backgroundColor: const Color(0xFFB90000),
                            ));
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
                                borderRadius: BorderRadius.circular(12)),
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
                  fontSize: 12, color: AppColors.subtext(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.text(context),
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
                  fontSize: 12, color: const Color(0xFF6B7280)),
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
                      setModalState(() => task['completed'] = false);
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: !isCompleted
                            ? const Color(0xFFFBBC05)
                            : AppColors.fieldBg(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !isCompleted
                              ? const Color(0xFFFBBC05)
                              : AppColors.border(context),
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
                                : AppColors.subtext(context),
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
                      setModalState(() => task['completed'] = true);
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? const Color(0xFF34A853)
                            : AppColors.fieldBg(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCompleted
                              ? const Color(0xFF34A853)
                              : AppColors.border(context),
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
                                : AppColors.subtext(context),
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

  // ════════════════════════════════════════════════════════════════════════════
  // STUDY PLAN SECTION
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildStudyPlanSection() {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Study Plans',
          style: GoogleFonts.dmMono(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('study_plans')
              .where('userId', isEqualTo: user.uid)
              .where('status', isEqualTo: 'incomplete')
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFB90000))),
              );
            }
            final allDocs = snap.data?.docs ?? [];
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scheduleStudyPlanExpiry(allDocs);
            });
            final docs = allDocs.where((doc) {
              final dueTs = (doc.data() as Map<String, dynamic>)['dueDate'] as Timestamp?;
              if (dueTs == null) return true;
              return dueTs.toDate().isAfter(DateTime.now());
            }).toList();
            if (docs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border(context), width: 2),
                ),
                child: Column(
                  children: [
                    Icon(Icons.checklist_rounded, size: 36, color: AppColors.subtext(context)),
                    const SizedBox(height: 10),
                    Text('No active study plans',
                        style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.subtext(context))),
                    const SizedBox(height: 4),
                    Text('Go to a subject to create one',
                        style: GoogleFonts.dmMono(fontSize: 11, color: AppColors.subtext(context))),
                  ],
                ),
              );
            }

            final sorted = docs.toList()
              ..sort((a, b) {
                final ta = (a.data() as Map)['dueDate'];
                final tb = (b.data() as Map)['dueDate'];
                if (ta == null) return 1;
                if (tb == null) return -1;
                return (ta as Timestamp).compareTo(tb as Timestamp);
              });

            return Column(
              children: sorted.map((doc) {
                final data      = doc.data() as Map<String, dynamic>;
                final checklist = (data['checklist'] as List<dynamic>? ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                final doneCount  = checklist.where((e) => e['done'] == true).length;
                final total      = checklist.length;
                final progress   = total > 0 ? doneCount / total : 0.0;
                final isComplete = total > 0 && doneCount == total;
                final dueDate    = (data['dueDate'] as Timestamp?)?.toDate();
                const accent    = Color(0xFF00BCD4);
                const doneColor = Color(0xFF2ECC71);
                final ringColor = isComplete ? doneColor : accent;
                final pct        = (progress * 100).round();
                final preview    = checklist.take(2).toList();
                final examType   = (data['examType'] ?? 'EXAM') as String;
                final examName   = (data['examName'] ?? '') as String;

                return _AnimatedTapButton(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => StudyPlanDetailScreen(planId: doc.id, data: data),
                  )),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.card(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border(context), width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left content
                            Expanded(
                          child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Plan name
                                  Text(
                                    data['planName'] ?? 'Study Plan',
                                    style: GoogleFonts.dmMono(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text(context)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (examName.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      examName,
                                      style: GoogleFonts.dmMono(fontSize: 11, color: AppColors.subtext(context)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  // Badge row: status + exam type + date
                                  Wrap(
                                    spacing: 5,
                                    runSpacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isComplete ? doneColor : const Color(0xFFCC0000),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: isComplete ? doneColor : const Color(0xFFCC0000), width: 1.5),
                                        ),
                                        child: Text(
                                          isComplete ? 'COMPLETE' : 'INCOMPLETE',
                                          style: GoogleFonts.dmMono(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEFFE6),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF9AB900), width: 1.5),
                                        ),
                                        child: Text(
                                          examType,
                                          style: GoogleFonts.dmMono(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF9AB900)),
                                        ),
                                      ),
                                      if (dueDate != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEFFE6),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF9AB900), width: 1.5),
                                          ),
                                          child: Text(
                                            DateFormat('dd MMM yyyy').format(dueDate),
                                            style: GoogleFonts.dmMono(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF9AB900)),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 5,
                                      backgroundColor: ringColor.withValues(alpha: 0.18),
                                      valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Divider(color: AppColors.border(context), height: 1),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Ring
                            SizedBox(
                              width: 78, height: 78,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(value: 1.0, strokeWidth: 7, strokeCap: StrokeCap.round, color: ringColor.withValues(alpha: 0.18)),
                                  CircularProgressIndicator(value: progress, strokeWidth: 7, strokeCap: StrokeCap.round, color: ringColor),
                                  Text('$pct%', style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold, color: ringColor)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ...preview.map((item) {
                                    final d = item['done'] == true;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 5),
                                      child: Row(children: [
                                        Icon(d ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                          size: 13, color: d ? doneColor : AppColors.subtext(context)),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text(
                                          item['text'] ?? '',
                                          style: GoogleFonts.dmMono(fontSize: 12,
                                            color: d ? AppColors.subtext(context) : AppColors.text(context),
                                            decoration: d ? TextDecoration.lineThrough : null),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        )),
                                      ]),
                                    );
                                  }),
                                  if (checklist.length > 2)
                                    Text('+${checklist.length - 2} more',
                                      style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.subtext(context))),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            StudyPlanCountdownBanner(dueDate: dueDate, accentColor: ringColor, compact: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration: BoxDecoration(color: AppColors.navBg(context)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavIcon(Icons.home, 0),
              _buildNavIcon(Icons.calendar_today, 1),
              _buildAddButton(),
              _buildNavIcon(Icons.percent, 2),
              _buildNavIcon(Icons.file_copy_outlined, 3),
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
          color: isActive
              ? const Color(0xFF6B7280)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : AppColors.text(context),
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
        decoration: BoxDecoration(
          color: AppColors.chipBg(context),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
    );
  }
}

// ── BELL DOT ─────────────────────────────────────────────────────────────────
// Filters by scheduledFor <= now — checked every second via Timer.
// instant the OS fires the alarm (via onDidReceiveNotificationResponse).
// That Firestore write triggers the stream, so the dot appears in real time
// with zero polling — no timer needed.

class _BellDot extends StatefulWidget {
  final String userId;
  final FirebaseFirestore firestore;
  final VoidCallback onTap;

  const _BellDot({
    required this.userId,
    required this.firestore,
    required this.onTap,
  });

  @override
  State<_BellDot> createState() => _BellDotState();
}

class _BellDotState extends State<_BellDot> {
  // Docs are cached from Firestore stream. A 60-second timer re-runs build()
  // so that DateTime.now() advances and the scheduledFor<=now check picks up
  // newly-fired notifications even when no Firestore write has occurred.
  List<QueryDocumentSnapshot> _docs = [];
  StreamSubscription<QuerySnapshot>? _sub;
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    // Real-time Firestore listener — updates instantly when isRead changes
    _sub = widget.firestore
        .collection('notification_history')
        .where('userId', isEqualTo: widget.userId)
        .snapshots()
        .listen(
      (snap) {
        if (mounted) setState(() => _docs = snap.docs);
      },
      onError: (_) {},
    );
    // Timer re-evaluates scheduledFor<=now every 60s for notifications that
    // fire without triggering a Firestore write (no user tap needed)
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Show red dot if any unread notification has already fired
    final hasUnread = _docs.any((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final isRead = data['isRead'] as bool? ?? false;
      if (isRead) return false;
      final ts = data['scheduledFor'] as Timestamp?;
      if (ts == null) return false;
      return !ts.toDate().isAfter(now);
    });

    return _AnimatedTapButton(
      onTap: widget.onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            hasUnread
                ? Icons.notifications
                : Icons.notifications_outlined,
            color: AppColors.text(context),
            size: 28,
          ),
          if (hasUnread)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFB90000),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.bg(context),
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── COUNTDOWN TIMER ──────────────────────────────────────────────────────────

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
      if (mounted) _updateRemainingTime();
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: countdownColor.withValues(alpha: 0.1),
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

// ── ANIMATED TAP BUTTON ──────────────────────────────────────────────────────

class _AnimatedTapButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _AnimatedTapButton({
    required this.child,
    required this.onTap,
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
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

// ── TRIANGLE PAINTER ─────────────────────────────────────────────────────────

class TrianglePainter extends CustomPainter {
  final Color color;
  const TrianglePainter({this.color = Colors.black});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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