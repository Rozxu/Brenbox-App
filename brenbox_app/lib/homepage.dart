import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'services/google_calendar_service.dart';
import 'widgets/app_time_picker_dialog.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'tasks/add_new_screen.dart';
import 'tasks/edit_class_screen.dart';
import 'tasks/edit_task_screen.dart';
import 'tasks/edit_exam_screen.dart';
import 'tasks/edit_group_event_screen.dart';
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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String _username = '';
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  int _selectedNavIndex = 0;
  List<Map<String, dynamic>> _cachedGroupEvents = [];
  StreamSubscription<QuerySnapshot>? _groupEventsSub;
  final ScrollController _homeScrollController = ScrollController();
  Stream<List<Map<String, dynamic>>>? _timetableStream;
  DateTime? _timetableStreamDate;
  Stream<List<Map<String, dynamic>>>? _examsStream;
  DateTime? _examsStreamDate;

  // Cross-device notification sync — listen for Firestore changes made by
  // another device logged into the same account, then reschedule local alarms.
  StreamSubscription<QuerySnapshot>? _taskChangeSub;
  StreamSubscription<QuerySnapshot>? _timetableChangeSub;
  StreamSubscription<QuerySnapshot>? _examChangeSub;
  Timer? _notifRescheduleDebounce;

  // Google Calendar
  List<gcal.Event> _gcalUpcoming = [];
  List<gcal.Event> _selectedDateGcalEvents = [];
  bool _selectedDateGcalLoading = false;
  bool? _calendarPermissionGranted; // null = not yet loaded / legacy user

  // Legend overlay for "This Week" info button
  final GlobalKey _legendKey = GlobalKey();
  OverlayEntry? _legendOverlay;

  // Event-type dot colors
  static const Color _kColorClass = Color(0xFFB90000);
  static const Color _kColorExam  = Color(0xFF9AB900);
  static const Color _kColorTask  = Color(0xFF008BB9);
  static const Color _kColorStudy = Color(0xFF7C3AED);
  static const Color _kColorGCal  = Color(0xFF4285F4);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _listenToGroupEvents();
    _initGoogleCalendar();
  }

  StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  Timer? _studyPlanExpiry;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fcmForegroundSub?.cancel();
    _studyPlanExpiry?.cancel();
    _groupEventsSub?.cancel();
    _taskChangeSub?.cancel();
    _timetableChangeSub?.cancel();
    _examChangeSub?.cancel();
    _notifRescheduleDebounce?.cancel();
    _homeScrollController.dispose();
    GoogleCalendarService.instance.removeListener(_onGcalChanged);
    _legendOverlay?.remove();
    super.dispose();
  }

  // Re-sync notifications the moment the user brings the app to foreground.
  // Covers changes made on another device while this one was in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      NotificationScheduler().onAppOpen();
    }
  }

  // Debounce helper — waits 3 s after the last Firestore change before
  // running onAppOpen(), so rapid edits don't trigger multiple reschedules.
  void _scheduleNotifRefresh() {
    _notifRescheduleDebounce?.cancel();
    _notifRescheduleDebounce = Timer(const Duration(seconds: 3), () {
      NotificationScheduler().onAppOpen();
    });
  }

  // Watches tasks, timetable, and exams for changes made by any device on this
  // account.  When a change arrives (skipping the initial snapshot), triggers a
  // debounced onAppOpen() so this device's AlarmManager alarms are rewritten to
  // match the new due-date/time stored in Firestore.
  void _listenForDataChanges(String uid) {
    _taskChangeSub?.cancel();
    _timetableChangeSub?.cancel();
    _examChangeSub?.cancel();

    bool tasksFirst     = true;
    bool timetableFirst = true;
    bool examsFirst     = true;

    _taskChangeSub = _firestore
        .collection('tasks')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (tasksFirst) { tasksFirst = false; return; }
      _scheduleNotifRefresh();
    }, onError: (_) {});

    _timetableChangeSub = _firestore
        .collection('timetable')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (timetableFirst) { timetableFirst = false; return; }
      _scheduleNotifRefresh();
    }, onError: (_) {});

    _examChangeSub = _firestore
        .collection('exams')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (examsFirst) { examsFirst = false; return; }
      _scheduleNotifRefresh();
    }, onError: (_) {});
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

  void _listenToGroupEvents() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _groupEventsSub?.cancel();
    bool groupEventsFirst = true;
    _groupEventsSub = _firestore
        .collection('user_group_events')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final isChange = !groupEventsFirst;
      groupEventsFirst = false;
      setState(() {
        _timetableStream = null; // group events changed — refresh timetable stream
        _cachedGroupEvents = snap.docs.map((doc) {
          final data = doc.data();
          final ts = data['eventDate'] as Timestamp?;
          if (ts == null) return null;
          final d = ts.toDate();
          return <String, dynamic>{
            'id': doc.id,
            'type': 'group_event',
            'title': data['title'] ?? 'Group Event',
            'eventSubType': data['eventType'] ?? 'Meeting',
            'details': data['details'] ?? '',
            'startTime': '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
            'eventDate': ts,
            'groupId': data['groupId'] ?? '',
            'groupName': data['groupName'] ?? '',
            'subject': data['subject'] ?? '',
            'senderUsername': data['senderUsername'] ?? '',
            'senderId': data['senderId'] ?? '',
            'isCompleted': data['isCompleted'] ?? false,
            'messageId': data['messageId'] ?? doc.id,
          };
        }).whereType<Map<String, dynamic>>().toList();
      });
      if (isChange) _scheduleNotifRefresh();
    }, onError: (_) {});
  }

  Future<void> _navigateToGroup(String groupId, int tab) async {
    try {
      final doc = await _firestore.collection('study_groups').doc(groupId).get();
      if (!mounted) return;
      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Group not found. It may have been deleted.',
            style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: const Color(0xFFB90000),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
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
        content: Text('Could not open group.',
            style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFFB90000),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
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

    // Start cross-device sync: reschedule local alarms whenever another device
    // edits tasks, timetable, or exams under this account.
    _listenForDataChanges(user.uid);
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
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _firestore.collection('users').doc(uid).update({'fcmToken': null});
      } catch (_) {}
    }
    await NotificationService().cancelAllNotifications();
    await GoogleCalendarService.instance.disconnect();
    await _auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
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

  Stream<List<_DotData>> _getDotsForDateStream(DateTime date) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    final checkDate = DateTime(date.year, date.month, date.day);

    bool matchesDate(DateTime d) =>
        d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day;

    return _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .asyncMap((timetableSnap) async {
      final tasksSnap = await _firestore.collection('tasks').where('userId', isEqualTo: user.uid).get();
      final examsSnap = await _firestore.collection('exams').where('userId', isEqualTo: user.uid).get();

      final dots = <_DotData>[];

      // Classes — one dot per day regardless of how many classes exist
      bool hasClass = false;
      for (final doc in timetableSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['type'] == 'exam') continue;
        final ts = data['date'] as Timestamp?;
        if (ts != null && matchesDate(ts.toDate())) {
          hasClass = true;
          break;
        }
      }
      if (hasClass) dots.add(_DotData(_kColorClass, true));

      // Exams (always solid)
      for (final doc in examsSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = data['examDate'] as Timestamp?;
        if (ts != null && matchesDate(ts.toDate())) {
          dots.add(_DotData(_kColorExam, true));
        }
      }

      // Tasks (solid = completed)
      for (final doc in tasksSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = data['dueDate'] as Timestamp?;
        if (ts != null && matchesDate(ts.toDate())) {
          dots.add(_DotData(_kColorTask, data['completed'] == true));
        }
      }

      // Study group events (solid = completed)
      for (final ge in _cachedGroupEvents) {
        final ts = ge['eventDate'] as Timestamp?;
        if (ts != null && matchesDate(ts.toDate())) {
          dots.add(_DotData(_kColorStudy, ge['isCompleted'] == true));
        }
      }

      return dots;
    }).handleError((_) => <_DotData>[]);
  }

  Stream<List<Map<String, dynamic>>> _getExamsForDateStream(DateTime date) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    final selectedDay = DateTime(date.year, date.month, date.day);

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
          final examDate = examDateTimestamp.toDate();
          final examDay  = DateTime(examDate.year, examDate.month, examDate.day);

          final isUpcoming = !examDay.isBefore(today);
          final isSelectedDay = examDay == selectedDay;

          // Show upcoming exams always; show past exams only on their exact day
          if (!isUpcoming && !isSelectedDay) continue;

          final startTime = (data['startTime'] as Timestamp).toDate();
          final endTime   = (data['endTime']   as Timestamp).toDate();

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
      // Upcoming exams first (nearest first), past exams after (most recent first)
      result.sort((a, b) {
        final aDate = (a['examDate'] as Timestamp).toDate();
        final bDate = (b['examDate'] as Timestamp).toDate();
        final aDay  = DateTime(aDate.year, aDate.month, aDate.day);
        final bDay  = DateTime(bDate.year, bDate.month, bDate.day);
        final aIsPast = aDay.isBefore(today);
        final bIsPast = bDay.isBefore(today);
        if (!aIsPast && !bIsPast) return aDate.compareTo(bDate);
        if (aIsPast && bIsPast)   return bDate.compareTo(aDate);
        return aIsPast ? 1 : -1;
      });
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
        controller: _homeScrollController,
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
              _buildGoogleCalendarSection(),
              const SizedBox(height: 24),
              _buildAssessmentsSection(),
              const SizedBox(height: 24),
              _buildStudyPlanSection(),
              const SizedBox(height: 32),
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
    if (_isLoading) return const SizedBox();
    final dateStr = DateFormat('EEEE, d MMMM').format(DateTime.now());
    final firstName = _username.split(' ').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dateStr,
          style: GoogleFonts.dmMono(
            fontSize: 13,
            color: AppColors.subtext(context),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Hi, $firstName',
              style: GoogleFonts.dmMono(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            const _WavingHand(),
          ],
        ),
      ],
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  Row(
                    children: [
                      // Info / legend button
                      GestureDetector(
                        key: _legendKey,
                        onTap: _toggleLegend,
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFFF9C4),
                            border: Border.all(color: Colors.black, width: 1.5),
                          ),
                          child: Center(
                            child: Text('i', style: GoogleFonts.dmMono(
                              fontSize: 14, fontWeight: FontWeight.bold,
                              color: Colors.black,
                            )),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.chipBg(context),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          currentMonth,
                          style: GoogleFonts.dmMono(
                            fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold,
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
                  final isToday = date.day == today.day &&
                      date.month == today.month &&
                      date.year == today.year;
                  final isSelected = date.day == _selectedDate.day &&
                      date.month == _selectedDate.month &&
                      date.year == _selectedDate.year;

                  return StreamBuilder<List<_DotData>>(
                    stream: _getDotsForDateStream(date),
                    builder: (context, snapshot) {
                      // Add GCal dots from in-memory list
                      final firestoreDots = snapshot.data ?? [];
                      final gcalDots = _gcalUpcoming.where((e) {
                        final dt = e.start?.dateTime?.toLocal();
                        if (dt == null) return false;
                        return dt.year == date.year && dt.month == date.month && dt.day == date.day;
                      }).map((_) => _DotData(_kColorGCal, true)).toList();
                      final dots = [...firestoreDots, ...gcalDots];
                      return _dateCircle(
                        date.day.toString().padLeft(2, '0'),
                        isToday,
                        isSelected,
                        dots,
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
          stream: _getStableExamsStream(),
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
                      'No assessments on this day',
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
    final navCtx = context;

    showModalBottomSheet(
      context: navCtx,
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
                            Navigator.pop(navCtx);
                            final result = await Navigator.push(
                              navCtx,
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
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.pop(context);
                            await confirmAndDeleteDialog(
                              context,
                              title: 'Delete Exam',
                              message: 'Are you sure you want to delete this exam? This cannot be undone.',
                              onDelete: () async {
                                await NotificationService()
                                    .cancelNotificationsForEvent(exam['id']);
                                await _firestore
                                    .collection('exams')
                                    .doc(exam['id'])
                                    .delete();
                                messenger.showSnackBar(SnackBar(
                                  content: Text('Exam deleted',
                                      style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
                                  backgroundColor: const Color(0xFFB90000),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  duration: const Duration(seconds: 3),
                                ));
                              },
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
    List<_DotData> dots,
    DateTime dateTime,
  ) {
    return _AnimatedTapButton(
      onTap: () {
        setState(() {
          _selectedDate = dateTime;
          _timetableStream = null;
          _examsStream = null;
        });
        _loadGcalForSelectedDate(dateTime);
      },
      child: SizedBox(
        width: 38,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Date circle
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: isToday ? const Color(0xFFB90000) : Colors.transparent,
                shape: BoxShape.circle,
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
            // Triangle arrow (selected) or same-height spacer
            SizedBox(
              height: 10,
              child: isSelected
                  ? Center(child: CustomPaint(size: const Size(10, 8), painter: TrianglePainter(color: AppColors.text(context))))
                  : null,
            ),
            // Dots row — max 6
            if (dots.isNotEmpty) const SizedBox(height: 4),
            if (dots.isNotEmpty)
              SizedBox(
                width: 38,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 2,
                  runSpacing: 2,
                  children: dots.take(6).map((d) => _EventDot(color: d.color, filled: d.filled)).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _toggleLegend() {
    if (_legendOverlay != null) {
      _legendOverlay!.remove();
      setState(() => _legendOverlay = null);
      return;
    }
    final box = _legendKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;

    _legendOverlay = OverlayEntry(builder: (_) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _legendOverlay?.remove();
              if (mounted) setState(() => _legendOverlay = null);
            },
          ),
        ),
        Positioned(
          top: pos.dy + size.height + 8,
          right: MediaQuery.of(context).size.width - pos.dx - size.width - 4,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('WHAT THE DOTS MEAN',
                    style: GoogleFonts.dmMono(fontSize: 9, fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(alpha: 0.5), letterSpacing: 1.2)),
                  const SizedBox(height: 10),
                  _legendRow(_kColorClass, true, 'Classes'),
                  _legendRow(_kColorExam,  true, 'Exams'),
                  _legendRow(_kColorTask,  true, 'Tasks'),
                  _legendRow(_kColorStudy, true, 'Study events'),
                  _legendRow(_kColorGCal,  true, 'Google Calendar'),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
                  ),
                  _legendRow(_kColorTask, false, 'hollow = pending'),
                  _legendRow(_kColorTask, true,  'solid = done'),
                ],
              ),
            ),
          ),
        ),
      ],
    ));

    Overlay.of(context).insert(_legendOverlay!);
    setState(() {});
  }

  Widget _legendRow(Color color, bool filled, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EventDot(color: color, filled: filled),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.dmMono(fontSize: 12, color: Colors.white)),
        ],
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
          stream: _getStableTimetableStream(user.uid),
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

            final events = snapshot.data ?? [];
            if (events.isEmpty) {
              return _buildEmptyState();
            }

            final sorted = List<Map<String, dynamic>>.from(events)
              ..sort((a, b) {
                if (a['type'] == 'task' && b['type'] == 'task') {
                  return (a['dueTime'] as String).compareTo(b['dueTime'] as String);
                } else if (a['type'] == 'task') {
                  return (a['dueTime'] as String).compareTo(b['startTime'] as String);
                } else if (b['type'] == 'task') {
                  return (a['startTime'] as String).compareTo(b['dueTime'] as String);
                } else {
                  return (a['startTime'] as String).compareTo(b['startTime'] as String);
                }
              });

            return Column(
              children: sorted.map((event) {
                if (event['type'] == 'task') return _buildTaskCard(event);
                if (event['type'] == 'group_event') return _buildGroupEventCard(event);
                return _buildEnhancedClassCard(event);
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> _getStableTimetableStream(String userId) {
    final d = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    if (_timetableStream == null || _timetableStreamDate != d) {
      _timetableStream = _getCombinedEventsStream(userId);
      _timetableStreamDate = d;
    }
    return _timetableStream!;
  }

  Stream<List<Map<String, dynamic>>> _getStableExamsStream() {
    final d = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    if (_examsStream == null || _examsStreamDate != d) {
      _examsStream = _getExamsForDateStream(_selectedDate);
      _examsStreamDate = d;
    }
    return _examsStream!;
  }

  Stream<List<Map<String, dynamic>>> _getCombinedEventsStream(String userId) {
    final controller = StreamController<List<Map<String, dynamic>>>();

    List<QueryDocumentSnapshot<Map<String, dynamic>>> timetableDocs = [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> tasksDocs = [];
    List<Map<String, dynamic>> groupEventMaps = List<Map<String, dynamic>>.from(_cachedGroupEvents);

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

      allEvents.addAll(groupEventMaps.where((e) {
        final ts = e['eventDate'] as Timestamp?;
        if (ts == null) return false;
        final d = ts.toDate();
        return d.year == _selectedDate.year &&
            d.month == _selectedDate.month &&
            d.day == _selectedDate.day;
      }));
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

  Widget _buildGroupEventCard(Map<String, dynamic> event) {
    const kGroup = Color(0xFF7C3AED);
    final isCompleted = event['isCompleted'] as bool? ?? false;
    final eventDate = (event['eventDate'] as Timestamp).toDate();

    return _AnimatedTapButton(
      onTap: () => _showGroupEventDetails(event),
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
                        : kGroup.withValues(alpha: 0.15),
                    AppColors.card(context),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isCompleted ? const Color(0xFF34A853) : kGroup,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isCompleted ? Icons.check_circle : Icons.groups_rounded,
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
                                event['title'] as String? ?? 'Group Event',
                                style: GoogleFonts.dmMono(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isCompleted
                                      ? AppColors.subtext(context)
                                      : AppColors.text(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!isCompleted) ...[
                              const SizedBox(width: 8),
                              _CountdownTimer(dueDate: eventDate),
                            ],
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
                                    : kGroup,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                (event['eventSubType'] as String? ?? 'Meeting').toUpperCase(),
                                style: GoogleFonts.dmMono(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ),
                            if (isCompleted) ...[
                              const SizedBox(width: 6),
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
                                    Text('COMPLETED',
                                        style: GoogleFonts.dmMono(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white)),
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
                        child: _buildDetailItem(Icons.calendar_today,
                            DateFormat('dd MMM yyyy').format(eventDate)),
                      ),
                      Expanded(
                        child: _buildDetailItem(
                            Icons.access_time,
                            event['startTime'] as String? ?? ''),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailItem(Icons.groups_outlined,
                            event['groupName'] as String? ?? ''),
                      ),
                      if ((event['subject'] as String? ?? '').isNotEmpty)
                        Expanded(
                          child: _buildDetailItem(Icons.subject,
                              event['subject'] as String? ?? ''),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupEventDetails(Map<String, dynamic> event) {
    const kGroup = Color(0xFF7C3AED);
    final eventDate = (event['eventDate'] as Timestamp).toDate();
    final stateCtx = context;

    showModalBottomSheet(
      context: stateCtx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final isCompleted = event['isCompleted'] as bool? ?? false;
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
                              'Group Event Details',
                              style: GoogleFonts.dmMono(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.text(context),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailRow('Title',
                                event['title'] as String? ?? ''),
                            if ((event['details'] as String? ?? '')
                                .isNotEmpty)
                              _buildDetailRow('Description',
                                  event['details'] as String? ?? ''),
                            _buildDetailRow('Type',
                                event['eventSubType'] as String? ?? 'Meeting'),
                            if ((event['groupName'] as String? ?? '')
                                .isNotEmpty)
                              _buildDetailRow('Group',
                                  event['groupName'] as String? ?? ''),
                            if ((event['subject'] as String? ?? '')
                                .isNotEmpty)
                              _buildDetailRow('Subject',
                                  event['subject'] as String? ?? ''),
                            _buildDetailRow('Date',
                                DateFormat('EEE, dd MMM yyyy')
                                    .format(eventDate)),
                            _buildDetailRow('Time',
                                event['startTime'] as String? ?? ''),
                            if ((event['senderUsername'] as String? ?? '')
                                .isNotEmpty)
                              _buildDetailRow('Organizer',
                                  event['senderUsername'] as String? ?? ''),
                            const SizedBox(height: 8),
                            // Status toggle
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 100,
                                    child: Text('Status',
                                        style: GoogleFonts.dmMono(
                                            fontSize: 12,
                                            color:
                                                const Color(0xFF6B7280))),
                                  ),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _AnimatedTapButton(
                                            onTap: () async {
                                              await _firestore
                                                  .collection('user_group_events')
                                                  .doc(event['id'] as String)
                                                  .update({'isCompleted': false});
                                              setModalState(() => event['isCompleted'] = false);
                                              setState(() {});
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 10),
                                              decoration: BoxDecoration(
                                                color: !isCompleted
                                                    ? const Color(0xFFFBBC05)
                                                    : AppColors.fieldBg(
                                                        context),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: !isCompleted
                                                      ? const Color(
                                                          0xFFFBBC05)
                                                      : AppColors.border(
                                                          context),
                                                  width: 2,
                                                ),
                                              ),
                                              child: Center(
                                                child: Text('Pending',
                                                    style: GoogleFonts.dmMono(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: !isCompleted
                                                            ? Colors.white
                                                            : AppColors
                                                                .subtext(
                                                                    context))),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _AnimatedTapButton(
                                            onTap: () async {
                                              await _firestore
                                                  .collection('user_group_events')
                                                  .doc(event['id'] as String)
                                                  .update({'isCompleted': true});
                                              setModalState(() => event['isCompleted'] = true);
                                              setState(() {});
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 10),
                                              decoration: BoxDecoration(
                                                color: isCompleted
                                                    ? const Color(0xFF34A853)
                                                    : AppColors.fieldBg(
                                                        context),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: isCompleted
                                                      ? const Color(
                                                          0xFF34A853)
                                                      : AppColors.border(
                                                          context),
                                                  width: 2,
                                                ),
                                              ),
                                              child: Center(
                                                child: Text('Completed',
                                                    style: GoogleFonts.dmMono(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: isCompleted
                                                            ? Colors.white
                                                            : AppColors
                                                                .subtext(
                                                                    context))),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                  Navigator.pop(stateCtx);
                                  final result = await Navigator.push(
                                    stateCtx,
                                    MaterialPageRoute(
                                      builder: (_) => EditGroupEventScreen(
                                        groupId: event['groupId'] as String? ??
                                            '',
                                        messageId:
                                            event['id'] as String? ?? '',
                                        eventData: event,
                                      ),
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
                                      color: AppColors.border(context),
                                      width: 2),
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
                                      ScaffoldMessenger.of(stateCtx);
                                  Navigator.pop(stateCtx);
                                  await confirmAndDeleteDialog(
                                    stateCtx,
                                    title: 'Delete Group Event',
                                    message:
                                        'This will remove the event from your calendar.',
                                    onDelete: () async {
                                      final geId = event['id'] as String;
                                      await NotificationService().cancelNotificationsForEvent(geId);
                                      await _firestore
                                          .collection('user_group_events')
                                          .doc(geId)
                                          .delete();
                                      messenger.showSnackBar(SnackBar(
                                        content: Text('Group event deleted',
                                            style: GoogleFonts.dmMono(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white)),
                                        backgroundColor:
                                            const Color(0xFFB90000),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        duration:
                                            const Duration(seconds: 3),
                                      ));
                                    },
                                  );
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: Text('Delete',
                                    style: GoogleFonts.dmMono()),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFB90000),
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
    final navCtx = context;

    showModalBottomSheet(
      context: navCtx,
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
                                Navigator.pop(navCtx);
                                final result = await Navigator.push(
                                  navCtx,
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
                                final messenger = ScaffoldMessenger.of(context);
                                Navigator.pop(context);
                                await confirmAndDeleteDialog(
                                  context,
                                  title: 'Delete Task',
                                  message: 'Are you sure you want to delete this task? This cannot be undone.',
                                  onDelete: () async {
                                    await NotificationService()
                                        .cancelNotificationsForEvent(task['id']);
                                    await _firestore
                                        .collection('tasks')
                                        .doc(task['id'])
                                        .delete();
                                    messenger.showSnackBar(SnackBar(
                                      content: Text('Task deleted',
                                          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
                                      backgroundColor: const Color(0xFFB90000),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      duration: const Duration(seconds: 3),
                                    ));
                                  },
                                );
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
    final navCtx = context;
    showModalBottomSheet(
      context: navCtx,
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
                          onPressed: () async {
                            Navigator.pop(navCtx);
                            final result = await Navigator.push(
                              navCtx,
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditClassScreen(classData: event),
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
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.pop(context);
                            await confirmAndDeleteDialog(
                              context,
                              title: 'Delete Class',
                              message: 'Are you sure you want to delete this class? This cannot be undone.',
                              onDelete: () async {
                                await NotificationService()
                                    .cancelNotificationsForEvent(event['id']);
                                await _firestore
                                    .collection('timetable')
                                    .doc(event['id'])
                                    .delete();
                                messenger.showSnackBar(SnackBar(
                                  content: Text('Class deleted',
                                      style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
                                  backgroundColor: const Color(0xFFB90000),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  duration: const Duration(seconds: 3),
                                ));
                              },
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

  // ════════════════════════════════════════════════════════════════════════════
  // GOOGLE CALENDAR
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _initGoogleCalendar() async {
    final svc = GoogleCalendarService.instance;
    svc.addListener(_onGcalChanged);

    // Load permission flag FIRST — determines whether auto-restore is allowed.
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await _firestore.collection('users').doc(uid).get();
        if (!mounted) return;
        setState(() {
          _calendarPermissionGranted =
              doc.data()?['calendarPermissionGranted'] as bool?;
        });
      } catch (_) {
        // Can't read the flag — don't auto-restore (safe default).
        return;
      }
    }

    // calendarPermissionGranted == false  → user chose "Skip for now" / back
    // calendarPermissionGranted == true   → user enabled during sign-up
    // calendarPermissionGranted == null   → legacy account, no preference stored
    if (_calendarPermissionGranted == false) {
      // Clear any stale account that may linger from a previous user's session.
      await svc.disconnect();
      return;
    }

    await svc.tryRestoreSession();
    if (svc.isConnected) {
      _loadGcalUpcoming();
      _loadGcalForSelectedDate(_selectedDate);
    }
  }

  void _onGcalChanged() {
    if (!mounted) return;
    final svc = GoogleCalendarService.instance;
    if (svc.isConnected) {
      _loadGcalUpcoming();
      _loadGcalForSelectedDate(_selectedDate);
    } else {
      setState(() { _gcalUpcoming = []; _selectedDateGcalEvents = []; });
    }
  }

  Future<void> _loadGcalForSelectedDate(DateTime date) async {
    if (!GoogleCalendarService.instance.isConnected) return;
    if (!mounted) return;
    setState(() => _selectedDateGcalLoading = true);
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final events = await GoogleCalendarService.instance.fetchAllEventsInRange(start, end);
    if (!mounted) return;
    setState(() {
      _selectedDateGcalEvents = events;
      _selectedDateGcalLoading = false;
    });
  }

  Future<void> _loadGcalUpcoming() async {
    if (!mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfRange = today.add(const Duration(days: 8));
    final events = await GoogleCalendarService.instance.fetchAllEventsInRange(startOfWeek, endOfRange);
    if (!mounted) return;
    setState(() => _gcalUpcoming = events);
  }

  String _gcalFormatTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    if (h == 0) return '12:$m AM';
    if (h < 12) return '$h:$m AM';
    if (h == 12) return '12:$m PM';
    return '${h - 12}:$m PM';
  }

  Widget _buildGoogleCalendarSection() {
    final svc = GoogleCalendarService.instance;
    const gcalBlue = Color(0xFF4285F4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Google Calendar',
              style: GoogleFonts.dmMono(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.text(context),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: gcalBlue,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'SYNC',
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const Spacer(),
            if (svc.isConnected)
              TextButton.icon(
                onPressed: () async {
                  await GoogleCalendarService.instance.disconnect();
                  if (!mounted) return;
                  setState(() => _calendarPermissionGranted = false);
                  try {
                    await _firestore
                        .collection('users')
                        .doc(_auth.currentUser?.uid)
                        .update({'calendarPermissionGranted': false});
                  } catch (_) {}
                },
                icon: const Icon(Icons.link_off_rounded, size: 14, color: Color(0xFF6B7280)),
                label: Text(
                  'Disconnect',
                  style: GoogleFonts.dmMono(fontSize: 11, color: const Color(0xFF6B7280)),
                ),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (!svc.isConnected) ...[
          // ── Connect prompt ─────────────────────────────────────────────────
          GestureDetector(
            onTap: () async {
              final result = await GoogleCalendarService.instance.connect();
              if (!mounted) return;
              if (result == GCalConnectResult.success) {
                setState(() => _calendarPermissionGranted = true);
                await _firestore
                    .collection('users')
                    .doc(_auth.currentUser?.uid)
                    .update({'calendarPermissionGranted': true});
                _loadGcalUpcoming();
                _loadGcalForSelectedDate(_selectedDate);
              } else if (result == GCalConnectResult.wrongAccount) {
                final expected = _auth.currentUser?.email ?? '';
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: AppColors.card(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppColors.border(context), width: 2),
                    ),
                    title: Text('Wrong Google Account',
                        style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
                    content: Text(
                      'Please sign in with $expected — the Google account linked to your BrenBox account.',
                      style: GoogleFonts.dmMono(fontSize: 12),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('OK',
                            style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border(context), width: 2),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: gcalBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _calendarPermissionGranted == false
                              ? 'Enable Google Calendar'
                              : 'Connect Google Calendar',
                          style: GoogleFonts.dmMono(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text(context),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _auth.currentUser?.email ?? 'Sync your Google Calendar events here',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            color: AppColors.subtext(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.subtext(context)),
                ],
              ),
            ),
          ),
        ] else if (_selectedDateGcalLoading) ...[
          const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(color: gcalBlue, strokeWidth: 2)),
          ),
        ] else if (_selectedDateGcalEvents.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border(context), width: 2),
            ),
            child: Column(
              children: [
                Icon(Icons.event_available_rounded, size: 36, color: AppColors.subtext(context)),
                const SizedBox(height: 10),
                Text(
                  'No events on this day',
                  style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.subtext(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  svc.accountEmail ?? '',
                  style: GoogleFonts.dmMono(fontSize: 11, color: AppColors.subtext(context)),
                ),
              ],
            ),
          ),
        ] else ...[
          // ── Account chip ────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, size: 13, color: gcalBlue),
              const SizedBox(width: 5),
              Text(
                svc.accountEmail ?? '',
                style: GoogleFonts.dmMono(fontSize: 11, color: AppColors.subtext(context)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _loadGcalForSelectedDate(_selectedDate),
                child: const Icon(Icons.refresh_rounded, size: 16, color: gcalBlue),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._selectedDateGcalEvents.map((event) => _buildGcalCard(event)),
        ],
      ],
    );
  }

  Widget _buildGcalCard(gcal.Event event) {
    const gcalBlue = Color(0xFF4285F4);
    final startDt = event.start?.dateTime?.toLocal();
    final endDt = event.end?.dateTime?.toLocal();
    final isAllDay = event.start?.date != null;

    final String timeStr;
    if (isAllDay) {
      timeStr = 'All day';
    } else {
      timeStr = startDt != null && endDt != null
          ? '${_gcalFormatTime(startDt)} - ${_gcalFormatTime(endDt)}'
          : startDt != null ? _gcalFormatTime(startDt) : '';
    }

    final location = event.location ?? '';

    return _AnimatedTapButton(
      onTap: () => _showGcalEventSheet(event),
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
                  colors: [gcalBlue.withValues(alpha: 0.15), AppColors.card(context)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: gcalBlue, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.summary ?? 'No Title',
                          style: GoogleFonts.dmMono(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text(context)),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: gcalBlue, borderRadius: BorderRadius.circular(6)),
                          child: Text('GCAL', style: GoogleFonts.dmMono(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
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
                  if (timeStr.isNotEmpty)
                    Expanded(child: _buildDetailItem(Icons.access_time, timeStr)),
                  if (location.isNotEmpty)
                    Expanded(child: _buildDetailItem(Icons.location_on_outlined, location)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGcalEventSheet(gcal.Event event) {
    final startDt = event.start?.dateTime?.toLocal();
    final endDt   = event.end?.dateTime?.toLocal();
    final startDate = event.start?.date; // all-day event

    // Time string
    String timeStr;
    if (startDt != null) {
      timeStr = endDt != null
          ? '${_gcalFormatTime(startDt)} – ${_gcalFormatTime(endDt)}'
          : _gcalFormatTime(startDt);
    } else {
      timeStr = 'All Day';
    }

    // Date string
    final dateForFormat = startDt ?? (startDate != null
        ? DateTime(startDate.year, startDate.month, startDate.day)
        : null);
    final dateStr = dateForFormat != null
        ? DateFormat('EEE, dd MMM yyyy').format(dateForFormat)
        : '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top:   BorderSide(color: AppColors.border(context), width: 2),
            left:  BorderSide(color: AppColors.border(context), width: 2),
            right: BorderSide(color: AppColors.border(context), width: 2),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                width: 40, height: 4,
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
                      'Event Details',
                      style: GoogleFonts.dmMono(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow('Title', event.summary ?? 'No Title'),
                    _buildDetailRow('Time', timeStr),
                    if (dateStr.isNotEmpty) _buildDetailRow('Date', dateStr),
                    if ((event.location ?? '').isNotEmpty)
                      _buildDetailRow('Location', event.location!),
                    if ((event.description ?? '').isNotEmpty)
                      _buildDetailRow('Description', event.description!),
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
                          Navigator.pop(ctx);
                          _showGcalEditDialog(event);
                        },
                        icon: Icon(Icons.edit_outlined, color: AppColors.text(context), size: 16),
                        label: Text('Edit', style: GoogleFonts.dmMono(
                            fontWeight: FontWeight.bold, color: AppColors.text(context))),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.border(context)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final id = event.id;
                          if (id == null) return;
                          final ok = await GoogleCalendarService.instance.deleteEvent(id);
                          if (ok && mounted) {
                            _loadGcalUpcoming();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Event deleted',
                                    style: GoogleFonts.dmMono(
                                        fontWeight: FontWeight.bold, color: Colors.white)),
                                backgroundColor: const Color(0xFFB90000),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: Text('Delete', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB90000),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showGcalEditDialog(gcal.Event event) {
    const gcalBlue = Color(0xFF4285F4);
    final startDt = event.start?.dateTime?.toLocal() ?? DateTime.now();
    final endDt = event.end?.dateTime?.toLocal() ?? startDt.add(const Duration(hours: 1));

    final titleCtrl = TextEditingController(text: event.summary ?? '');
    final descCtrl = TextEditingController(text: event.description ?? '');
    final locCtrl = TextEditingController(text: event.location ?? '');
    DateTime editDate = startDt;
    TimeOfDay editStartTime = TimeOfDay.fromDateTime(startDt);
    TimeOfDay editEndTime = TimeOfDay.fromDateTime(endDt);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          String fmtTime(TimeOfDay t) {
            final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
            final m = t.minute.toString().padLeft(2, '0');
            return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
          }

          Widget dateTile() => GestureDetector(
            onTap: () async {
              final isDark = AppColors.isDark(context);
              final picked = await showDatePicker(
                context: ctx,
                initialDate: editDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                builder: (_, child) => Theme(
                  data: isDark
                      ? ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: Color(0xFF008BB9),
                            onPrimary: Colors.white,
                            surface: Color(0xFF252D47),
                            onSurface: Colors.white,
                          ),
                        )
                      : ThemeData.light().copyWith(
                          colorScheme: const ColorScheme.light(primary: Color(0xFF008BB9)),
                        ),
                  child: child!,
                ),
              );
              if (picked != null) setS(() => editDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.input(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border(context), width: 2),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(DateFormat('EEE, dd MMM yyyy').format(editDate), style: GoogleFonts.dmMono(fontSize: 14, color: AppColors.text(context)))),
                  Icon(Icons.calendar_today, size: 18, color: AppColors.text(context)),
                ],
              ),
            ),
          );

          void showTimeError() {
            showDialog(
              context: ctx,
              builder: (_) => AlertDialog(
                backgroundColor: AppColors.card(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.border(context), width: 2),
                ),
                title: Row(children: [
                  const Icon(Icons.error_outline, color: Color(0xFFB90000), size: 24),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Invalid Time', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, fontSize: 14))),
                ]),
                content: Text('End time must be after start time.', style: GoogleFonts.dmMono(fontSize: 12)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('OK', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: AppColors.text(context))),
                  ),
                ],
              ),
            );
          }

          Widget timeTile(TimeOfDay t, void Function(TimeOfDay) onPick, {bool isStart = false}) => GestureDetector(
            onTap: () async {
              final picked = await showDialog<TimeOfDay>(context: ctx, builder: (_) => AppTimePickerDialog(initialTime: t));
              if (picked == null) return;
              if (isStart) {
                final startMins = picked.hour * 60 + picked.minute;
                final endMins = editEndTime.hour * 60 + editEndTime.minute;
                setS(() {
                  editStartTime = picked;
                  if (endMins <= startMins) {
                    editEndTime = TimeOfDay(hour: (picked.hour + 1) % 24, minute: picked.minute);
                  }
                });
              } else {
                final startMins = editStartTime.hour * 60 + editStartTime.minute;
                final endMins = picked.hour * 60 + picked.minute;
                if (endMins <= startMins) { showTimeError(); return; }
                setS(() => editEndTime = picked);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.input(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border(context), width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(fmtTime(t), style: GoogleFonts.dmMono(fontSize: 14, color: AppColors.text(context))),
                  Icon(Icons.access_time, size: 18, color: AppColors.text(context)),
                ],
              ),
            ),
          );

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: AppColors.border(context), width: 2),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: AppColors.border(context), borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Edit Event', style: GoogleFonts.dmMono(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text(context))),
                    const SizedBox(height: 16),
                    Text('Title', style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _gcalTextField(titleCtrl, 'Event title'),
                    const SizedBox(height: 14),
                    Text('Location (Optional)', style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _gcalTextField(locCtrl, 'Location'),
                    const SizedBox(height: 14),
                    Text('Description (Optional)', style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _gcalTextField(descCtrl, 'Description', maxLines: 3),
                    const SizedBox(height: 14),
                    Text('Date', style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.subtext(context))),
                    const SizedBox(height: 8),
                    dateTile(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Start Time', style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.subtext(context))),
                              const SizedBox(height: 8),
                              timeTile(editStartTime, (t) => editStartTime = t, isStart: true),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('End Time', style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.subtext(context))),
                              const SizedBox(height: 8),
                              timeTile(editEndTime, (t) => editEndTime = t),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final id = event.id;
                          if (id == null || titleCtrl.text.trim().isEmpty) return;
                          final newStart = DateTime(editDate.year, editDate.month, editDate.day, editStartTime.hour, editStartTime.minute);
                          final newEnd = DateTime(editDate.year, editDate.month, editDate.day, editEndTime.hour, editEndTime.minute);
                          if (!newEnd.isAfter(newStart)) { showTimeError(); return; }
                          Navigator.pop(ctx);
                          final updated = await GoogleCalendarService.instance.updateEvent(
                            eventId: id,
                            title: titleCtrl.text.trim(),
                            description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                            location: locCtrl.text.trim().isEmpty ? null : locCtrl.text.trim(),
                            start: newStart,
                            end: newEnd,
                          );
                          if (updated != null && mounted) {
                            _loadGcalUpcoming();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Event updated', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
                                backgroundColor: gcalBlue,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: gcalBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('Save Changes', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _gcalTextField(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: GoogleFonts.dmMono(fontSize: 14, color: AppColors.text(context)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmMono(fontSize: 14, color: AppColors.subtext(context)),
        filled: true,
        fillColor: AppColors.input(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border(context), width: 2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border(context), width: 2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border(context), width: 2)),
        contentPadding: const EdgeInsets.all(16),
      ),
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

class _BellDotState extends State<_BellDot> with WidgetsBindingObserver {
  List<QueryDocumentSnapshot> _docs = [];
  StreamSubscription<QuerySnapshot>? _sub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe(widget.userId);
    // Fallback tick every 15 s while the app is in foreground — catches
    // notifications that fire without triggering a Firestore write.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  void _subscribe(String userId) {
    _sub?.cancel();
    if (userId.isEmpty) return;
    _sub = widget.firestore
        .collection('notification_history')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen(
      (snap) {
        if (mounted) setState(() => _docs = snap.docs);
      },
      onError: (_) {},
    );
  }

  // Re-subscribe if the parent rebuilds with a different (non-empty) userId.
  // This handles the race where _auth.currentUser is null on first build.
  @override
  void didUpdateWidget(_BellDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId && widget.userId.isNotEmpty) {
      _subscribe(widget.userId);
    }
  }

  // Fires the moment the user returns to the app — no ticker delay needed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _ticker?.cancel();
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

// ── DOT DATA ─────────────────────────────────────────────────────────────────

class _DotData {
  final Color color;
  final bool filled;
  const _DotData(this.color, this.filled);
}

// ── EVENT DOT ─────────────────────────────────────────────────────────────────

class _EventDot extends StatelessWidget {
  final Color color;
  final bool filled;
  const _EventDot({required this.color, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: filled ? null : Border.all(color: color, width: 1.5),
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

class _WavingHand extends StatefulWidget {
  const _WavingHand();

  @override
  State<_WavingHand> createState() => _WavingHandState();
}

class _WavingHandState extends State<_WavingHand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _angle;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _angle = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.35), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.35, end: 0.3),  weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.3,  end: -0.3),  weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.3, end: 0.2),   weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.2,  end: 0.0),   weight: 1),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

    _ctrl.forward();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) _ctrl.forward(from: 0);
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _angle,
      builder: (_, __) => Transform.rotate(
        angle: _angle.value,
        alignment: Alignment.bottomCenter,
        child: const Icon(
          Icons.waving_hand_rounded,
          color: Color(0xFFFFA726),
          size: 22,
        ),
      ),
    );
  }
}