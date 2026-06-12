import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import '../tasks/edit_class_screen.dart';
import '../tasks/edit_task_screen.dart';
import '../tasks/edit_exam_screen.dart';
import '../tasks/edit_group_event_screen.dart';
import '../services/notification_service.dart';
import '../services/google_calendar_service.dart';
import '../widgets/app_time_picker_dialog.dart';
import 'subject_detail_screen.dart';
import '../app_preferences.dart';

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
  String _selectedSemester =
      'All'; // All, Semester 1, Semester 2, etc., Non Semester

  List<Map<String, dynamic>> _cachedGroupEvents = [];
  StreamSubscription<QuerySnapshot>? _groupEventsSub;

  Map<String, bool> _subjectHasUnread = {};
  StreamSubscription<QuerySnapshot>? _groupsUnreadSub;
  Stream<List<Map<String, dynamic>>>? _subjectsStream;

  List<Map<String, dynamic>> _cachedTaskDocs = [];
  List<Map<String, dynamic>> _cachedExamDocs = [];
  List<Map<String, dynamic>> _cachedTimetableDocs = [];
  StreamSubscription<QuerySnapshot>? _tasksSub;
  StreamSubscription<QuerySnapshot>? _examsSub;
  StreamSubscription<QuerySnapshot>? _timetableSub;

  // Google Calendar
  List<gcal.Event> _gcalEvents = [];     // events for selected date (filtered locally)
  List<gcal.Event> _gcalAllEvents = [];  // all events for the loaded year range
  bool _gcalLoading = false;

  // Event-type dot colors
  static const Color _kColorClass = Color(0xFFB90000);
  static const Color _kColorExam  = Color(0xFF9AB900);
  static const Color _kColorTask  = Color(0xFF008BB9);
  static const Color _kColorStudy = Color(0xFF7C3AED);
  static const Color _kColorGCal  = Color(0xFF4285F4);

  // Legend overlay
  final GlobalKey _legendKey = GlobalKey();
  OverlayEntry? _legendOverlay;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _listenToGroupEvents();
    _listenToFirestoreData();
    _listenToGroupsUnread();
    final uid = _auth.currentUser?.uid;
    if (uid != null) _subjectsStream = _getSubjectsStream(uid);
    GoogleCalendarService.instance.addListener(_onGcalChanged);
    _loadGcalAllEvents();
  }

  @override
  void dispose() {
    _legendOverlay?.remove();
    _groupEventsSub?.cancel();
    _tasksSub?.cancel();
    _examsSub?.cancel();
    _timetableSub?.cancel();
    _groupsUnreadSub?.cancel();
    GoogleCalendarService.instance.removeListener(_onGcalChanged);
    super.dispose();
  }

  void _toggleLegend() {
    if (_legendOverlay != null) {
      _legendOverlay!.remove();
      _legendOverlay = null;
      return;
    }
    final box = _legendKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    _legendOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () { _legendOverlay?.remove(); _legendOverlay = null; },
            ),
          ),
          Positioned(
            top: pos.dy + box.size.height + 8,
            right: MediaQuery.of(context).size.width - pos.dx - box.size.width,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _legendRow(_kColorClass, true, 'Class'),
                    const SizedBox(height: 8),
                    _legendRow(_kColorExam, true, 'Exam'),
                    const SizedBox(height: 8),
                    _legendRow(_kColorTask, true, 'Task'),
                    const SizedBox(height: 8),
                    _legendRow(_kColorStudy, true, 'Study Event'),
                    const SizedBox(height: 8),
                    _legendRow(_kColorGCal, true, 'Google Calendar'),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: Colors.white24, height: 1),
                    ),
                    _legendRow(_kColorTask, false, 'Pending'),
                    const SizedBox(height: 8),
                    _legendRow(_kColorTask, true, 'Completed'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_legendOverlay!);
  }

  Widget _legendRow(Color color, bool filled, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9, height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.transparent,
            border: filled ? null : Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.dmMono(fontSize: 12, color: Colors.white)),
      ],
    );
  }

  void _onGcalChanged() {
    if (!mounted) return;
    if (GoogleCalendarService.instance.isConnected) {
      _loadGcalAllEvents();
    } else {
      setState(() { _gcalEvents = []; _gcalAllEvents = []; });
    }
  }

  /// Fetches all Google Calendar events for a 3-year window (last year → next year)
  /// using pagination, then filters locally for dots and selected-date lists.
  Future<void> _loadGcalAllEvents() async {
    if (!GoogleCalendarService.instance.isConnected) return;
    setState(() => _gcalLoading = true);
    final now = DateTime.now();
    final start = DateTime(now.year - 1, 1, 1);
    final end   = DateTime(now.year + 2, 1, 1);
    final events =
        await GoogleCalendarService.instance.fetchAllEventsInRange(start, end);
    if (!mounted) return;
    final selected = _selectedDate ?? now;
    setState(() {
      _gcalAllEvents = events;
      _gcalEvents = events.where((e) => _gcalEventOnDate(e, selected)).toList();
      _gcalLoading = false;
    });
  }

  void _updateGcalEventsForDate(DateTime date) {
    setState(() {
      _gcalEvents = _gcalAllEvents.where((e) => _gcalEventOnDate(e, date)).toList();
    });
  }

  void _listenToGroupsUnread() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _groupsUnreadSub?.cancel();
    _groupsUnreadSub = _firestore
        .collection('study_groups')
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final Map<String, bool> unread = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final subject = data['subject'] as String? ?? '';
        if (subject.isEmpty) continue;
        final lastMessageAt = data['lastMessageAt'] as Timestamp?;
        final lastReadAt =
            (data['lastReadAt'] as Map<String, dynamic>?)?[uid] as Timestamp?;
        if (lastMessageAt != null &&
            (lastReadAt == null ||
                lastMessageAt.compareTo(lastReadAt) > 0)) {
          unread[subject] = true;
        }
      }
      setState(() => _subjectHasUnread = unread);
    }, onError: (_) {});
  }

  void _listenToFirestoreData() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _timetableSub?.cancel();
    _timetableSub = _firestore
        .collection('timetable')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _cachedTimetableDocs = snap.docs.map((d) => d.data()).toList();
      });
    }, onError: (_) {});

    _tasksSub?.cancel();
    _tasksSub = _firestore
        .collection('tasks')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _cachedTaskDocs = snap.docs.map((d) => d.data()).toList();
      });
    }, onError: (_) {});

    _examsSub?.cancel();
    _examsSub = _firestore
        .collection('exams')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _cachedExamDocs = snap.docs.map((d) => d.data()).toList();
      });
    }, onError: (_) {});
  }

  void _listenToGroupEvents() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _groupEventsSub?.cancel();
    _groupEventsSub = _firestore
        .collection('user_group_events')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
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
    }, onError: (_) {});
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
          final hasNonSemester = snapshot.docs.any(
            (doc) =>
                doc.data()['semester'] == null ||
                doc.data()['academicYear'] == null,
          );

          if (hasNonSemester) {
            semesters.add('Non Semester');
          }

          List<String> semesterList = semesters.toList()
            ..sort((a, b) {
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
        })
        .handleError((_) {});
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

  List<_DotData> _getDotsForDate(DateTime date) {
    final checkDate = DateTime(date.year, date.month, date.day);
    final List<_DotData> dots = [];

    // Classes
    final hasClass = _cachedTimetableDocs.any((data) {
      final ts = data['date'] as Timestamp?;
      if (ts == null) return false;
      final d = ts.toDate();
      return d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day;
    });
    if (hasClass) dots.add(const _DotData(_kColorClass, true));

    // Tasks
    final taskDocs = _cachedTaskDocs.where((data) {
      final ts = data['dueDate'] as Timestamp?;
      if (ts == null) return false;
      final d = ts.toDate();
      return d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day;
    }).toList();
    if (taskDocs.isNotEmpty) {
      final allDone = taskDocs.every((data) => data['completed'] == true);
      dots.add(_DotData(_kColorTask, allDone));
    }

    // Exams
    final hasExam = _cachedExamDocs.any((data) {
      final ts = data['examDate'] as Timestamp?;
      if (ts == null) return false;
      final d = ts.toDate();
      return d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day;
    });
    if (hasExam) dots.add(const _DotData(_kColorExam, true));

    // Group events
    final geDocs = _cachedGroupEvents.where((ge) {
      final ts = ge['eventDate'] as Timestamp?;
      if (ts == null) return false;
      final d = ts.toDate();
      return d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day;
    }).toList();
    if (geDocs.isNotEmpty) {
      final allDone = geDocs.every((ge) => ge['isCompleted'] == true);
      dots.add(_DotData(_kColorStudy, allDone));
    }

    return dots;
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
      backgroundColor: AppColors.bg(context),
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
                _buildInvitationsSection(),
                _buildTimetableSharesSection(),
                const SizedBox(height: 4),
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
      style: GoogleFonts.dmMono(fontSize: 24, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildCalendar(List<DateTime> days) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context), width: 2),
      ),
      child: Column(
        children: [
          // Month selector with arrows
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.chipBg(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      DateFormat('MMMM, yyyy').format(_currentMonth),
                      style: GoogleFonts.dmMono(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                        child: Text('i', style: GoogleFonts.dmMono(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _AnimatedTapButton(
                    onTap: _previousMonth,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border(context), width: 2),
                      ),
                      child: Icon(
                        Icons.chevron_left,
                        size: 20,
                        color: AppColors.text(context),
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
                        color: AppColors.card(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border(context), width: 2),
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppColors.text(context),
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
              childAspectRatio: 0.69,
              crossAxisSpacing: 8,
              mainAxisSpacing: 2,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final date = days[index];
              final isCurrentMonth = _isCurrentMonth(date);
              final isToday = _isToday(date);
              final isSelected = _isSelected(date);

              final firestoreDots = _getDotsForDate(date);
              final checkDate = DateTime(date.year, date.month, date.day);
              final gcalDots = _gcalAllEvents
                  .where((e) => _gcalEventOnDate(e, checkDate))
                  .map((_) => const _DotData(_kColorGCal, true))
                  .toList();
              final dots = [...firestoreDots, ...gcalDots];
              return _buildDateCell(date, isCurrentMonth, isToday, isSelected, dots);
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
    List<_DotData> dots,
  ) {
    Color textColor = AppColors.text(context);
    if (isToday) textColor = Colors.white;
    if (!isCurrentMonth) textColor = AppColors.subtext(context);

    return _AnimatedTapButton(
      onTap: () {
        setState(() => _selectedDate = date);
        _updateGcalEventsForDate(date);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isToday ? const Color(0xFFB90000) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                date.day.toString().padLeft(2, '0'),
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          // Triangle slot — fixed height so all cells align
          SizedBox(
            height: 7,
            child: isSelected
                ? Center(child: CustomPaint(size: const Size(10, 7), painter: TrianglePainter(color: AppColors.text(context))))
                : null,
          ),
          if (dots.isNotEmpty) ...[
            const SizedBox(height: 2),
            SizedBox(
              width: 36,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 3,
                children: dots.take(5).map((d) => _EventDot(color: d.color, filled: d.filled)).toList(),
              ),
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
          color: AppColors.text(context),
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
          style: GoogleFonts.dmMono(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getCombinedEventsStream(user.uid, _selectedDate!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Color(0xFF6B7280)),
                ),
              );
            }

            final events = snapshot.data ?? [];

            if (events.isEmpty && _gcalEvents.isEmpty) {
              return _buildEmptyState();
            }

            // Sort Firebase events by time
            final sorted = List<Map<String, dynamic>>.from(events)
              ..sort((a, b) {
                String timeA;
                String timeB;
                if (a['type'] == 'task') {
                  timeA = a['dueTime'] as String;
                } else if (a['eventType'] == 'exam') {
                  final ts = a['startTime'] as Timestamp;
                  final dt = ts.toDate();
                  timeA = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                } else {
                  timeA = a['startTime'] as String;
                }
                if (b['type'] == 'task') {
                  timeB = b['dueTime'] as String;
                } else if (b['eventType'] == 'exam') {
                  final ts = b['startTime'] as Timestamp;
                  final dt = ts.toDate();
                  timeB = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                } else {
                  timeB = b['startTime'] as String;
                }
                return timeA.compareTo(timeB);
              });

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...sorted.map((event) {
                  if (event['type'] == 'task') return _buildTaskCard(event);
                  if (event['eventType'] == 'exam') return _buildExamCard(event);
                  if (event['type'] == 'group_event') return _buildGroupEventCard(event);
                  return _buildClassCard(event);
                }),
                if (_gcalEvents.isNotEmpty) ...[
                  if (sorted.isNotEmpty) const SizedBox(height: 6),
                  ..._gcalEvents.map(_buildGCalEventCard),
                ] else if (_gcalLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF4285F4), strokeWidth: 2)),
                  )
                else if (GoogleCalendarService.instance.isConnected)
                  const SizedBox(),
              ],
            );
          },
        ),
        // Connect-Google-Calendar prompt when not linked
        if (!GoogleCalendarService.instance.isConnected)
          _buildGCalConnectBanner(),
      ],
    );
  }

  Widget _buildGCalConnectBanner() {
    const gcalBlue = Color(0xFF4285F4);
    return GestureDetector(
      onTap: () async {
        final result = await GoogleCalendarService.instance.connect();
        if (result == GCalConnectResult.success && mounted) {
          _loadGcalAllEvents();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context), width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: gcalBlue, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Connect Google Calendar to see all your events here',
                style: GoogleFonts.dmMono(fontSize: 12, color: AppColors.subtext(context)),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.subtext(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildGCalEventCard(gcal.Event event) {
    const gcalBlue = Color(0xFF4285F4);
    final startDt = event.start?.dateTime?.toLocal();
    final endDt = event.end?.dateTime?.toLocal();

    String timeStr = '';
    if (startDt != null && endDt != null) {
      timeStr = '${_gcalFmt(startDt)} - ${_gcalFmt(endDt)}';
    }
    final location = event.location ?? '';

    return _AnimatedTapButton(
      onTap: () => _showGCalSheet(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: gcalBlue, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: gcalBlue, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: gcalBlue, borderRadius: BorderRadius.circular(4)),
                        child: Text('GCAL', style: GoogleFonts.dmMono(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.summary ?? 'No Title',
                          style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeStr.isNotEmpty
                        ? (location.isNotEmpty ? '$timeStr • $location' : timeStr)
                        : (location.isNotEmpty ? location : ''),
                    style: GoogleFonts.dmMono(fontSize: 10, color: const Color(0xFF6B7280)),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _gcalEventOnDate(gcal.Event e, DateTime checkDate) {
    // Timed event — show only on its start day
    final dt = e.start?.dateTime?.toLocal();
    if (dt != null) {
      return dt.year == checkDate.year &&
          dt.month == checkDate.month &&
          dt.day == checkDate.day;
    }
    // All-day event — start.date is a DateTime (no time component)
    final startDate = e.start?.date;
    if (startDate == null) return false;
    final startDay =
        DateTime(startDate.year, startDate.month, startDate.day);
    final endDate = e.end?.date;
    if (endDate != null) {
      // Multi-day: end is exclusive, so event covers [startDay, endDay)
      final endDay = DateTime(endDate.year, endDate.month, endDate.day);
      return !checkDate.isBefore(startDay) && checkDate.isBefore(endDay);
    }
    return checkDate == startDay;
  }

  String _gcalFmt(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    if (h == 0) return '12:$m AM';
    if (h < 12) return '$h:$m AM';
    if (h == 12) return '12:$m PM';
    return '${h - 12}:$m PM';
  }

  void _showGCalSheet(gcal.Event event) {
    const gcalBlue = Color(0xFF4285F4);
    final startDt = event.start?.dateTime?.toLocal();
    final endDt = event.end?.dateTime?.toLocal();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.border(context), width: 2),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 28),
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
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: gcalBlue, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(event.summary ?? 'No Title', style: GoogleFonts.dmMono(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.text(context))),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (startDt != null) ...[
              _gcalRow(Icons.access_time_rounded, '${_gcalFmt(startDt)}${endDt != null ? ' – ${_gcalFmt(endDt)}' : ''}'),
              const SizedBox(height: 8),
              _gcalRow(Icons.calendar_today_rounded, DateFormat('EEE, dd MMM yyyy').format(startDt)),
              const SizedBox(height: 8),
            ],
            if ((event.location ?? '').isNotEmpty) ...[
              _gcalRow(Icons.location_on_outlined, event.location!),
              const SizedBox(height: 8),
            ],
            if ((event.description ?? '').isNotEmpty) ...[
              _gcalRow(Icons.notes_rounded, event.description!),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () { Navigator.pop(ctx); _showGCalEditSheet(event); },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text('Edit', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: gcalBlue,
                      side: const BorderSide(color: gcalBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                        _loadGcalAllEvents();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Event deleted', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
                          backgroundColor: const Color(0xFFB90000),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ));
                      }
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: Text('Delete', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB90000),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _gcalRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.subtext(context)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: GoogleFonts.dmMono(fontSize: 13, color: AppColors.text(context)))),
      ],
    );
  }

  void _showGCalEditSheet(gcal.Event event) {
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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
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
                    _gcalField(titleCtrl, 'Event title'),
                    const SizedBox(height: 14),
                    Text('Location (Optional)', style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _gcalField(locCtrl, 'Location'),
                    const SizedBox(height: 14),
                    Text('Description (Optional)', style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _gcalField(descCtrl, 'Description', maxLines: 3),
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
                            _loadGcalAllEvents();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Event updated', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
                              backgroundColor: gcalBlue,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ));
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

  Widget _gcalField(TextEditingController ctrl, String hint, {int maxLines = 1}) {
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

  Stream<List<Map<String, dynamic>>> _getCombinedEventsStream(
    String userId,
    DateTime date,
  ) {
    // Use real-time snapshots for ALL three collections so that
    // deleting a task or exam immediately removes it from the UI.
    final timetableStream = _firestore
        .collection('timetable')
        .where('userId', isEqualTo: userId)
        .snapshots();
    final tasksStream = _firestore
        .collection('tasks')
        .where('userId', isEqualTo: userId)
        .snapshots();
    final examsStream = _firestore
        .collection('exams')
        .where('userId', isEqualTo: userId)
        .snapshots();

    return _mergeCalendarStreams(
      userId,
      date,
      timetableStream,
      tasksStream,
      examsStream,
    );
  }

  Stream<List<Map<String, dynamic>>> _mergeCalendarStreams(
    String userId,
    DateTime date,
    Stream<QuerySnapshot> timetableStream,
    Stream<QuerySnapshot> tasksStream,
    Stream<QuerySnapshot> examsStream,
  ) {
    QuerySnapshot? latestTimetable;
    QuerySnapshot? latestTasks;
    QuerySnapshot? latestExams;
    List<Map<String, dynamic>> latestGroupEvents = _cachedGroupEvents.where((e) {
      final ts = e['eventDate'] as Timestamp?;
      if (ts == null) return false;
      final d = ts.toDate();
      return d.year == date.year && d.month == date.month && d.day == date.day;
    }).toList();

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    List<Map<String, dynamic>> buildEvents() {
      final List<Map<String, dynamic>> allEvents = [];

      for (var doc in (latestTimetable?.docs ?? [])) {
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
                'semester': data['semester'],
                'academicYear': data['academicYear'],
              });
            }
          }
        } catch (_) {}
      }

      for (var doc in (latestTasks?.docs ?? [])) {
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
        } catch (_) {}
      }

      for (var doc in (latestExams?.docs ?? [])) {
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
                'eventType': 'exam',
                'type': data['type'] ?? 'Exam',
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
        } catch (_) {}
      }

      allEvents.addAll(latestGroupEvents);
      return allEvents;
    }

    final sub1 = timetableStream.listen((snap) {
      latestTimetable = snap;
      if (!controller.isClosed) controller.add(buildEvents());
    }, onError: (_) {});
    final sub2 = tasksStream.listen((snap) {
      latestTasks = snap;
      if (!controller.isClosed) controller.add(buildEvents());
    }, onError: (_) {});
    final sub3 = examsStream.listen((snap) {
      latestExams = snap;
      if (!controller.isClosed) controller.add(buildEvents());
    }, onError: (_) {});

    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
      sub3.cancel();
      if (!controller.isClosed) controller.close();
    };

    return controller.stream;
  }

  Widget _buildGroupEventCard(Map<String, dynamic> event) {
    const kGroup = Color(0xFF7C3AED);
    final isCompleted = event['isCompleted'] as bool? ?? false;

    return _AnimatedTapButton(
      onTap: () => _showGroupEventDetails(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCompleted ? const Color(0xFF34A853) : kGroup,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCompleted ? const Color(0xFF34A853) : kGroup,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isCompleted ? Icons.check_circle : Icons.groups_rounded,
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
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? const Color(0xFF34A853)
                              : kGroup,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          (event['eventSubType'] as String? ?? 'Meeting').toUpperCase(),
                          style: GoogleFonts.dmMono(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event['title'] as String? ?? 'Group Event',
                          style: GoogleFonts.dmMono(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isCompleted
                                ? AppColors.subtext(context)
                                : AppColors.text(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatTime(event['startTime'] as String? ?? '')} • ${event['eventSubType'] as String? ?? 'Meeting'} • ${event['groupName'] as String? ?? ''}',
                    style: GoogleFonts.dmMono(
                        fontSize: 10,
                        color: AppColors.subtext(context)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Group Event Details',
                                style: GoogleFonts.dmMono(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.text(context))),
                            const SizedBox(height: 16),
                            _buildDetailRow('Title',
                                event['title'] as String? ?? ''),
                            if ((event['details'] as String? ?? '').isNotEmpty)
                              _buildDetailRow('Description',
                                  event['details'] as String? ?? ''),
                            _buildDetailRow('Type',
                                event['eventSubType'] as String? ?? 'Meeting'),
                            if ((event['groupName'] as String? ?? '').isNotEmpty)
                              _buildDetailRow('Group',
                                  event['groupName'] as String? ?? ''),
                            if ((event['subject'] as String? ?? '').isNotEmpty)
                              _buildDetailRow('Subject',
                                  event['subject'] as String? ?? ''),
                            _buildDetailRow('Date',
                                DateFormat('EEE, dd MMM yyyy').format(eventDate)),
                            _buildDetailRow('Time',
                                event['startTime'] as String? ?? ''),
                            if ((event['senderUsername'] as String? ?? '')
                                .isNotEmpty)
                              _buildDetailRow('Organizer',
                                  event['senderUsername'] as String? ?? ''),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 100,
                                    child: Text('Status',
                                        style: GoogleFonts.dmMono(
                                            fontSize: 12,
                                            color: const Color(0xFF6B7280))),
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
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: !isCompleted
                                                    ? const Color(0xFFFBBC05)
                                                    : AppColors.fieldBg(context),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: !isCompleted
                                                      ? const Color(0xFFFBBC05)
                                                      : AppColors.border(context),
                                                  width: 2,
                                                ),
                                              ),
                                              child: Center(
                                                child: Text('Pending',
                                                    style: GoogleFonts.dmMono(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: !isCompleted
                                                            ? Colors.white
                                                            : AppColors.subtext(context))),
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
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: isCompleted
                                                    ? const Color(0xFF34A853)
                                                    : AppColors.fieldBg(context),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: isCompleted
                                                      ? const Color(0xFF34A853)
                                                      : AppColors.border(context),
                                                  width: 2,
                                                ),
                                              ),
                                              child: Center(
                                                child: Text('Completed',
                                                    style: GoogleFonts.dmMono(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: isCompleted
                                                            ? Colors.white
                                                            : AppColors.subtext(context))),
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
                        padding: const EdgeInsets.symmetric(horizontal: 24),
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
                                        groupId: event['groupId'] as String? ?? '',
                                        messageId: event['id'] as String? ?? '',
                                        eventData: event,
                                      ),
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
                                      ScaffoldMessenger.of(stateCtx);
                                  Navigator.pop(stateCtx);
                                  await confirmAndDeleteDialog(
                                    stateCtx,
                                    title: 'Delete Group Event',
                                    message:
                                        'This will remove the event from your calendar.',
                                    onDelete: () async {
                                      await _firestore
                                          .collection('user_group_events')
                                          .doc(event['id'] as String)
                                          .delete();
                                      messenger.showSnackBar(SnackBar(
                                        content: Text('Group event deleted',
                                            style: GoogleFonts.dmMono(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white)),
                                        backgroundColor: const Color(0xFFB90000),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        duration: const Duration(seconds: 3),
                                      ));
                                    },
                                  );
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: Text('Delete', style: GoogleFonts.dmMono()),
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
      },
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final isCompleted = task['completed'] ?? false;

    return _AnimatedTapButton(
      onTap: () => _showTaskDetails(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
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
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF9AB900), width: 2),
          ),
          child: Text(
            exam['examName'] ?? 'Exam',
            style: GoogleFonts.dmMono(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }

      return _AnimatedTapButton(
        onTap: () => _showExamDetails(exam),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card(context),
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
          color: AppColors.card(context),
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
          color: AppColors.card(context),
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
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context), width: 2),
      ),
      child: Column(
        children: [
          Icon(
            Icons.event_note_outlined,
            size: 48,
            color: AppColors.subtext(context),
          ),
          const SizedBox(height: 12),
          Text(
            'No events scheduled',
            style: GoogleFonts.dmMono(fontSize: 13, color: AppColors.subtext(context)),
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
          style: GoogleFonts.dmMono(fontSize: 20, fontWeight: FontWeight.bold),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border(context), width: 2),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _subjectStatus == 'On-Going'
                      ? const Color(0xFF75E1D1)
                      : AppColors.card(context),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _subjectStatus == 'On-Going'
                        ? const Color(0xFF006E5E)
                        : AppColors.border(context),
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
                        : AppColors.text(context),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _subjectStatus == 'Ended'
                      ? const Color(0xFF75E1D1)
                      : AppColors.card(context),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _subjectStatus == 'Ended'
                        ? const Color(0xFF006E5E)
                        : AppColors.border(context),
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
                        : AppColors.text(context),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Subjects Grid
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _subjectsStream ?? _getSubjectsStream(user.uid),
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
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFF34A853),
                                )
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
        .asyncMap((snapshot) async {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          // Step 1: Build subject map from timetable (classes)
          // Track the latest date seen across classes + tasks + exams
          final Map<String, Map<String, dynamic>> subjectsMap = {};

          for (var doc in snapshot.docs) {
            final data = doc.data();
            final className = data['className'] ?? 'Untitled';
            final timestamp = data['date'] as Timestamp?;
            if (timestamp == null) continue;

            final eventDateOnly = _dateOnly(timestamp.toDate());

            // Filter by semester
            if (_selectedSemester != 'All') {
              if (_selectedSemester == 'Non Semester') {
                if (data['semester'] != null || data['academicYear'] != null)
                  continue;
              } else {
                final semNum = int.tryParse(
                  _selectedSemester.replaceAll('Semester ', ''),
                );
                if (semNum == null || data['semester'] != semNum) continue;
              }
            }

            if (!subjectsMap.containsKey(className)) {
              subjectsMap[className] = {
                'className': className,
                'semester': data['semester'],
                'academicYear': data['academicYear'],
                'latestDate': eventDateOnly,
              };
            } else {
              final existing =
                  subjectsMap[className]!['latestDate'] as DateTime;
              if (eventDateOnly.isAfter(existing)) {
                subjectsMap[className]!['latestDate'] = eventDateOnly;
              }
            }
          }

          // Step 2: Also check tasks for each subject name
          // A subject is only "Ended" if ALL of classes, tasks, AND exams are in the past
          if (subjectsMap.isNotEmpty) {
            final subjectNames = subjectsMap.keys.toList();

            // Tasks — query by userId only (Firestore doesn't support 'in' with
            // compound filters without an index), filter by subject name in Dart
            final tasksSnap = await _firestore
                .collection('tasks')
                .where('userId', isEqualTo: userId)
                .get();

            for (var doc in tasksSnap.docs) {
              final data = doc.data();
              final subject = data['subject'] as String? ?? '';
              final timestamp = data['dueDate'] as Timestamp?;
              if (timestamp == null) continue;
              if (!subjectsMap.containsKey(subject)) continue;

              // Semester filter for tasks
              if (_selectedSemester != 'All' &&
                  _selectedSemester != 'Non Semester') {
                final semNum = int.tryParse(
                  _selectedSemester.replaceAll('Semester ', ''),
                );
                final tSem = subjectsMap[subject]?['semester'];
                if (semNum != null && tSem != semNum) continue;
              }

              final dueDateOnly = _dateOnly(timestamp.toDate());
              final existing = subjectsMap[subject]!['latestDate'] as DateTime;
              if (dueDateOnly.isAfter(existing)) {
                subjectsMap[subject]!['latestDate'] = dueDateOnly;
              }
            }

            // Exams
            final examsSnap = await _firestore
                .collection('exams')
                .where('userId', isEqualTo: userId)
                .get();

            for (var doc in examsSnap.docs) {
              final data = doc.data();
              final subject = data['subject'] as String? ?? '';
              final timestamp = data['examDate'] as Timestamp?;
              if (timestamp == null) continue;
              if (!subjectsMap.containsKey(subject)) continue;

              // Semester filter for exams
              if (_selectedSemester != 'All' &&
                  _selectedSemester != 'Non Semester') {
                final semNum = int.tryParse(
                  _selectedSemester.replaceAll('Semester ', ''),
                );
                final tSem = subjectsMap[subject]?['semester'];
                if (semNum != null && tSem != semNum) continue;
              }

              // Use endTime if available, otherwise examDate, so exam is
              // only considered "past" after the exam ends
              final endTs = data['endTime'] as Timestamp?;
              final effectiveTs = endTs ?? timestamp;
              final examDateOnly = _dateOnly(effectiveTs.toDate());
              final existing = subjectsMap[subject]!['latestDate'] as DateTime;
              if (examDateOnly.isAfter(existing)) {
                subjectsMap[subject]!['latestDate'] = examDateOnly;
              }
            }
          }

          // Step 3: Filter by On-Going / Ended
          // Ended = latestDate (across classes + tasks + exams) is before today
          final filtered = subjectsMap.values.where((subject) {
            final latestDate = subject['latestDate'] as DateTime;
            final isEnded = latestDate.isBefore(today);
            return (_subjectStatus == 'On-Going' && !isEnded) ||
                (_subjectStatus == 'Ended' && isEnded);
          }).toList();

          filtered.sort(
            (a, b) =>
                (a['className'] as String).compareTo(b['className'] as String),
          );

          return filtered;
        })
        .handleError((_) {});
  }

  /// Returns midnight of the given date for clean date-only comparisons
  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Widget _buildSubjectCard(Map<String, dynamic> subject) {
    final hasUnread = _subjectHasUnread[subject['className']] == true;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _confirmDeleteSubject(subject);
          },
          child: _AnimatedTapButton(
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
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border(context), width: 2),
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
          ),
        ),
        Positioned(
          top: -7,
          right: -7,
          child: AnimatedScale(
            scale: hasUnread ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.elasticOut,
            child: AnimatedOpacity(
              opacity: hasUnread ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF7043),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmDeleteSubject(Map<String, dynamic> subject) {
    final className = subject['className'] as String;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border(context), width: 2),
        ),
        title: Text(
          'Delete "$className"?',
          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will permanently delete all classes, tasks, and exams for this subject, and remove you from any associated study groups.',
          style: GoogleFonts.dmMono(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmMono(color: const Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteSubject(subject);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB90000),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Delete', style: GoogleFonts.dmMono()),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSubject(Map<String, dynamic> subject) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final className    = subject['className'] as String;
    final semester     = subject['semester'];
    final academicYear = subject['academicYear'];
    final messenger    = ScaffoldMessenger.of(context);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppColors.card(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.border(context), width: 2),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Deleting...', style: GoogleFonts.dmMono(fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }
    try {
      // Build timetable query with optional filters
      Query<Map<String, dynamic>> timetableQuery = _firestore
          .collection('timetable')
          .where('userId', isEqualTo: user.uid)
          .where('className', isEqualTo: className);
      if (semester != null) timetableQuery = timetableQuery.where('semester', isEqualTo: semester);
      if (academicYear != null) timetableQuery = timetableQuery.where('academicYear', isEqualTo: academicYear);

      // 1. Fetch all three collections in parallel
      final results = await Future.wait([
        timetableQuery.get(),
        _firestore.collection('tasks').where('userId', isEqualTo: user.uid).where('subject', isEqualTo: className).get(),
        _firestore.collection('exams').where('userId', isEqualTo: user.uid).where('subject', isEqualTo: className).get(),
      ]);

      final timetableSnap = results[0];
      final tasksSnap     = results[1];
      final examsSnap     = results[2];

      // Grab subjectId for study-group lookup
      String? subjectId;
      for (final doc in timetableSnap.docs) {
        subjectId = doc.data()['subjectId'] as String?;
        if (subjectId != null) break;
      }

      final allDocs = [...timetableSnap.docs, ...tasksSnap.docs, ...examsSnap.docs];

      // 2. Cancel all notifications in parallel — failures don't block the delete
      await Future.wait(
        allDocs.map((doc) =>
            NotificationService().cancelNotificationsForEvent(doc.id).catchError((_) {})),
      );

      // 3. Batch delete all documents in one round trip
      final batch = _firestore.batch();
      for (final doc in allDocs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // 4. Leave any study groups linked to this subject
      if (subjectId != null) {
        final groupsSnap = await _firestore
            .collection('study_groups')
            .where('subjectId', isEqualTo: subjectId)
            .get();
        final memberGroups = groupsSnap.docs.where(
          (doc) => (List<String>.from(doc.data()['memberIds'] ?? [])).contains(user.uid),
        );
        await Future.wait(
          memberGroups.map((doc) => doc.reference.update({
            'memberIds': FieldValue.arrayRemove([user.uid]),
          })),
        );
      }

      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(
          content: Text('"$className" deleted',
              style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: const Color(0xFFB90000),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(
          content: Text('Failed to delete subject',
              style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: const Color(0xFFB90000),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  Widget _buildEmptySubjectsState() {
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
          Icon(Icons.school_outlined, size: 48, color: AppColors.subtext(context)),
          const SizedBox(height: 12),
          Text(
            _subjectStatus == 'On-Going'
                ? 'No ongoing subjects'
                : 'No ended subjects',
            style: GoogleFonts.dmMono(fontSize: 13, color: AppColors.subtext(context)),
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
    final stateCtx = context;
    final dueDate = (task['dueDate'] as Timestamp).toDate();

    showModalBottomSheet(
      context: stateCtx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final isCompleted = task['completed'] ?? false;

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
                                Navigator.pop(stateCtx);
                                final result = await Navigator.push(
                                  stateCtx,
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
                                foregroundColor: AppColors.text(context),
                                side: BorderSide(
                                  color: AppColors.border(context),
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
                                Navigator.pop(stateCtx);
                                final messenger = ScaffoldMessenger.of(stateCtx);
                                bool deleted = false;
                                await confirmAndDeleteDialog(
                                  stateCtx,
                                  title: 'Delete Task',
                                  message: 'Are you sure you want to delete this task? This cannot be undone.',
                                  onDelete: () async {
                                    await _firestore.collection('tasks').doc(task['id']).delete();
                                    deleted = true;
                                  },
                                );
                                if (deleted) {
                                  messenger.showSnackBar(SnackBar(
                                    content: Text('Task deleted',
                                        style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
                                    backgroundColor: const Color(0xFFB90000),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    duration: const Duration(seconds: 3),
                                  ));
                                }
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

  // Status toggle for task
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
                            : AppColors.fieldBg(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !isCompleted
                              ? const Color(0xFF008BB9)
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

  // Show exam details modal
  void _showExamDetails(Map<String, dynamic> exam) {
    final stateCtx = context;
    final examDate = (exam['examDate'] as Timestamp).toDate();
    final startTime = (exam['startTime'] as Timestamp).toDate();
    final endTime = (exam['endTime'] as Timestamp).toDate();

    showModalBottomSheet(
      context: stateCtx,
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
                            Navigator.pop(stateCtx);
                            final result = await Navigator.push(
                              stateCtx,
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
                            foregroundColor: AppColors.text(context),
                            side: BorderSide(
                              color: AppColors.border(context),
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
                            Navigator.pop(stateCtx);
                            final messenger = ScaffoldMessenger.of(stateCtx);
                            bool deleted = false;
                            await confirmAndDeleteDialog(
                              stateCtx,
                              title: 'Delete Exam',
                              message: 'Are you sure you want to delete this exam? This cannot be undone.',
                              onDelete: () async {
                                await _firestore.collection('exams').doc(exam['id']).delete();
                                final linkedPlans = await _firestore
                                    .collection('study_plans')
                                    .where('userId', isEqualTo: _auth.currentUser!.uid)
                                    .where('examId', isEqualTo: exam['id'])
                                    .get();
                                for (final plan in linkedPlans.docs) {
                                  await plan.reference.delete();
                                }
                                deleted = true;
                              },
                            );
                            if (deleted) {
                              messenger.showSnackBar(SnackBar(
                                content: Text('Exam deleted',
                                    style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
                                backgroundColor: const Color(0xFFB90000),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                duration: const Duration(seconds: 3),
                              ));
                            }
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
    final stateCtx = context;
    showModalBottomSheet(
      context: stateCtx,
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
                            Navigator.pop(stateCtx);
                            final result = await Navigator.push(
                              stateCtx,
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
                            foregroundColor: AppColors.text(context),
                            side: BorderSide(
                              color: AppColors.border(context),
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
                            Navigator.pop(stateCtx);
                            final messenger = ScaffoldMessenger.of(stateCtx);
                            bool deleted = false;
                            await confirmAndDeleteDialog(
                              stateCtx,
                              title: 'Delete Class',
                              message: 'Are you sure you want to delete this class? This cannot be undone.',
                              onDelete: () async {
                                await _firestore.collection('timetable').doc(event['id']).delete();
                                deleted = true;
                              },
                            );
                            if (deleted) {
                              messenger.showSnackBar(SnackBar(
                                content: Text('Class deleted',
                                    style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
                                backgroundColor: const Color(0xFFB90000),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                duration: const Duration(seconds: 3),
                              ));
                            }
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

  // ══════════════════════════════════════════════════════════════════════════
  // STUDY GROUP INVITATION SECTION  ← only new code below this line
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildInvitationsSection() {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('group_invitations')
          .where('inviteeId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .handleError((_) {}),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox();
        }

        final invites = snapshot.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Group Invitations',
              style: GoogleFonts.dmMono(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...invites.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final classes = List<Map<String, dynamic>>.from(
                data['classes'] ?? [],
              );
              final tasks = List<Map<String, dynamic>>.from(
                data['tasks'] ?? [],
              );
              final exams = List<Map<String, dynamic>>.from(
                data['exams'] ?? [],
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF7C3AED), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header: group info + sender ──────────────────────
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE9FE),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.group,
                              color: Color(0xFF7C3AED),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['groupName'] ?? 'Study Group',
                                  style: GoogleFonts.dmMono(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  data['subject'] ?? '',
                                  style: GoogleFonts.dmMono(
                                    fontSize: 11,
                                    color: const Color(0xFF7C3AED),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.person_outline,
                                      size: 12,
                                      color: Color(0xFF6B7280),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Invited by ${data['inviterUsername'] ?? 'Someone'}',
                                      style: GoogleFonts.dmMono(
                                        fontSize: 10,
                                        color: const Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Class schedule from sender ────────────────────────
                    if (classes.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF3859FF).withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    size: 12,
                                    color: Color(0xFF3859FF),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${data['inviterUsername'] ?? 'Sender'}\'s schedule  •  ${classes.length} class${classes.length == 1 ? '' : 'es'}',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF3859FF),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...classes.map((cls) {
                                final ts = cls['date'] as Timestamp?;
                                final dateStr = ts != null
                                    ? DateFormat('EEE, dd MMM').format(ts.toDate())
                                    : '—';
                                final start = cls['startTime'] ?? '';
                                final end = cls['endTime'] ?? '';
                                final room = cls['room'] ?? '';
                                final building = cls['building'] ?? '';
                                final loc = [room, building]
                                    .where((s) => (s as String).isNotEmpty)
                                    .join(', ');
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF3859FF),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '$dateStr  •  ${_formatTime(start)} – ${_formatTime(end)}'
                                          '${loc.isNotEmpty ? '  •  $loc' : ''}',
                                          style: GoogleFonts.dmMono(
                                            fontSize: 10,
                                            color: const Color(0xFF374151),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // ── Tasks from sender ─────────────────────────────────
                    if (tasks.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEBF5FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF008BB9).withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.task_alt, size: 12, color: Color(0xFF008BB9)),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${tasks.length} task${tasks.length == 1 ? '' : 's'}',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF008BB9),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...tasks.map((task) {
                                final ts = task['dueDate'] as Timestamp?;
                                final due = ts != null
                                    ? DateFormat('EEE, dd MMM').format(ts.toDate())
                                    : '—';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF008BB9),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${task['taskTitle'] ?? '—'}  •  Due $due',
                                          style: GoogleFonts.dmMono(
                                            fontSize: 10,
                                            color: const Color(0xFF374151),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // ── Exams from sender ─────────────────────────────────
                    if (exams.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEFFE6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF9AB900).withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.assignment_outlined, size: 12, color: Color(0xFF9AB900)),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${exams.length} exam${exams.length == 1 ? '' : 's'}',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF9AB900),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...exams.map((exam) {
                                final ts = exam['examDate'] as Timestamp?;
                                final dateStr = ts != null
                                    ? DateFormat('EEE, dd MMM').format(ts.toDate())
                                    : '—';
                                // startTime/endTime are stored as Timestamps
                                final startTs = exam['startTime'] as Timestamp?;
                                final endTs = exam['endTime'] as Timestamp?;
                                String timeStr = '';
                                if (startTs != null && endTs != null) {
                                  final s = startTs.toDate();
                                  final e = endTs.toDate();
                                  final sStr = '${s.hour.toString().padLeft(2,'0')}:${s.minute.toString().padLeft(2,'0')}';
                                  final eStr = '${e.hour.toString().padLeft(2,'0')}:${e.minute.toString().padLeft(2,'0')}';
                                  timeStr = '  •  ${_formatTime(sStr)} – ${_formatTime(eStr)}';
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF9AB900),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${exam['examName'] ?? '—'}  •  $dateStr$timeStr',
                                          style: GoogleFonts.dmMono(
                                            fontSize: 10,
                                            color: const Color(0xFF374151),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // ── Accept / Decline ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _AnimatedTapButton(
                              onTap: () => _acceptInvitation(doc),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF34A853),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    'Accept',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _AnimatedTapButton(
                              onTap: () => _declineInvitation(doc),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.card(context),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFB90000),
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'Decline',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFB90000),
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
            }),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Future<void> _acceptInvitation(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final data = doc.data() as Map<String, dynamic>;
    final groupId = data['groupId'] as String;
    final groupName = data['groupName'] ?? 'group';
    final inviterUsername = data['inviterUsername'] ?? 'Someone';
    final incomingClasses = List<Map<String, dynamic>>.from(
      data['classes'] ?? [],
    );

    // Load recipient's existing timetable for clash detection
    final existingSnap = await _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .get();

    // Group existing classes by day key
    final Map<String, List<Map<String, dynamic>>> existingByDay = {};
    for (var d in existingSnap.docs) {
      final dd = d.data();
      final ts = dd['date'] as Timestamp?;
      if (ts == null) continue;
      final dayKey = DateFormat('yyyy-MM-dd').format(ts.toDate());
      existingByDay.putIfAbsent(dayKey, () => []).add({
        'id': d.id,
        'className': dd['className'] ?? '',
        'startTime': dd['startTime'] ?? '',
        'endTime': dd['endTime'] ?? '',
        'date': ts,
      });
    }

    // Separate clashing vs non-clashing
    final List<Map<String, dynamic>> noClash = [];
    final List<Map<String, dynamic>> clashGroups = [];

    for (final cls in incomingClasses) {
      final ts = cls['date'] as Timestamp?;
      if (ts == null) {
        noClash.add(cls);
        continue;
      }
      final dayKey = DateFormat('yyyy-MM-dd').format(ts.toDate());
      final existing = existingByDay[dayKey] ?? [];

      // Exact duplicate → skip clash check; _joinGroupAndMarkAccepted shows it as "already have"
      final isDuplicate = existing.any(
        (ex) =>
            ex['className'] == cls['className'] &&
            ex['startTime'] == cls['startTime'] &&
            ex['endTime'] == cls['endTime'],
      );
      if (isDuplicate) {
        noClash.add(cls);
        continue;
      }

      final inStart = _timeToMinutes(cls['startTime'] ?? '');
      final inEnd = _timeToMinutes(cls['endTime'] ?? '');
      final clashing = existing.where((ex) {
        final s = _timeToMinutes(ex['startTime'] ?? '');
        final e = _timeToMinutes(ex['endTime'] ?? '');
        return inStart < e && inEnd > s;
      }).toList();

      if (clashing.isEmpty) {
        noClash.add(cls);
      } else {
        clashGroups.add({'incoming': cls, 'existing': clashing});
      }
    }

    if (clashGroups.isEmpty) {
      // No clashes — _joinGroupAndMarkAccepted handles the preview internally
      await _joinGroupAndMarkAccepted(
        doc,
        user,
        groupId,
        groupName,
        incomingClasses,
      );
    } else {
      // Has clashes — show resolution dialog first
      final chosen = await _showClashDialog(
        inviterUsername: inviterUsername,
        groupName: groupName,
        noClashClasses: noClash,
        clashGroups: clashGroups,
      );
      if (chosen != null && mounted) {
        await _joinGroupAndMarkAccepted(doc, user, groupId, groupName, chosen);
      }
    }
  }

  int _timeToMinutes(String time) {
    try {
      final p = time.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    } catch (_) {
      return 0;
    }
  }

  Future<bool?> _showClassPreviewDialog({
    required String inviterUsername,
    required String groupName,
    required List<Map<String, dynamic>> classesToAdd,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.border(context), width: 2),
        ),
        title: Text(
          'Join $groupName?',
          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accepting adds ${classesToAdd.length} class${classesToAdd.length == 1 ? '' : 'es'} from $inviterUsername to your timetable:',
                style: GoogleFonts.dmMono(
                  fontSize: 12,
                  color: const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 12),
              ...classesToAdd.map((cls) {
                final ts = cls['date'] as Timestamp?;
                final dateStr = ts != null
                    ? DateFormat('EEE, dd MMM').format(ts.toDate())
                    : '—';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF3859FF).withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cls['className'] ?? '',
                          style: GoogleFonts.dmMono(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$dateStr  •  ${_formatTime(cls['startTime'] ?? '')} – ${_formatTime(cls['endTime'] ?? '')}',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmMono(color: const Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF34A853),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Accept & Add Classes',
              style: GoogleFonts.dmMono(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>?> _showClashDialog({
    required String inviterUsername,
    required String groupName,
    required List<Map<String, dynamic>> noClashClasses,
    required List<Map<String, dynamic>> clashGroups,
    String confirmLabel = 'Confirm & Join',
    List<Map<String, dynamic>> newTasks = const [],
    List<Map<String, dynamic>> alreadyHasTasks = const [],
    List<Map<String, dynamic>> newExams = const [],
    List<Map<String, dynamic>> alreadyHasExams = const [],
  }) {
    final Map<int, String> selections = {
      for (int i = 0; i < clashGroups.length; i++) i: 'incoming',
    };

    return showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            backgroundColor: AppColors.card(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: AppColors.border(context), width: 2),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Class Time Clash',
                  style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Choose which class to keep for each clash',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...clashGroups.asMap().entries.map((entry) {
                    final i = entry.key;
                    final group = entry.value;
                    final incoming = group['incoming'] as Map<String, dynamic>;
                    final existing =
                        group['existing'] as List<Map<String, dynamic>>;
                    final ts = incoming['date'] as Timestamp?;
                    final dateStr = ts != null
                        ? DateFormat('EEE, dd MMM').format(ts.toDate())
                        : '—';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i > 0) const Divider(height: 24),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3F3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFB90000).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                size: 14,
                                color: Color(0xFFB90000),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Clash on $dateStr',
                                style: GoogleFonts.dmMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFB90000),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // New class option
                        Text(
                          'New class (from $inviterUsername):',
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => setS(() => selections[i] = 'incoming'),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: selections[i] == 'incoming'
                                  ? const Color(0xFF3859FF).withOpacity(0.08)
                                  : AppColors.card(context),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selections[i] == 'incoming'
                                    ? const Color(0xFF3859FF)
                                    : AppColors.border(context),
                                width: selections[i] == 'incoming' ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selections[i] == 'incoming'
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 18,
                                  color: const Color(0xFF3859FF),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        incoming['className'] ?? '',
                                        style: GoogleFonts.dmMono(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${_formatTime(incoming['startTime'] ?? '')} – ${_formatTime(incoming['endTime'] ?? '')}',
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
                        const SizedBox(height: 6),

                        // Existing class options
                        Text(
                          'Your current class:',
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...existing.map((ex) {
                          final selKey = 'existing_${ex['id']}';
                          return GestureDetector(
                            onTap: () => setS(() => selections[i] = selKey),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: selections[i] == selKey
                                    ? const Color(0xFF34A853).withOpacity(0.08)
                                    : AppColors.card(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selections[i] == selKey
                                      ? const Color(0xFF34A853)
                                      : AppColors.border(context),
                                  width: selections[i] == selKey ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selections[i] == selKey
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                    size: 18,
                                    color: const Color(0xFF34A853),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ex['className'] ?? '',
                                          style: GoogleFonts.dmMono(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '${_formatTime(ex['startTime'] ?? '')} – ${_formatTime(ex['endTime'] ?? '')}',
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
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                    );
                  }),

                  // No-clash classes
                  if (noClashClasses.isNotEmpty) ...[
                    const Divider(height: 20),
                    Text(
                      'These will be added automatically (no clash):',
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...noClashClasses.map((cls) {
                      final ts = cls['date'] as Timestamp?;
                      final dateStr = ts != null
                          ? DateFormat('EEE, dd MMM').format(ts.toDate())
                          : '—';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FFF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF34A853).withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            '${cls['className'] ?? ''}  •  $dateStr  •  ${_formatTime(cls['startTime'] ?? '')} – ${_formatTime(cls['endTime'] ?? '')}',
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              color: const Color(0xFF374151),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                  // ── Task / exam summary ─────────────────────────────
                  if (newTasks.isNotEmpty || alreadyHasTasks.isNotEmpty ||
                      newExams.isNotEmpty || alreadyHasExams.isNotEmpty) ...[
                    const Divider(height: 20),
                    Text(
                      'Tasks & Exams:',
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (newTasks.isNotEmpty)
                      Text(
                        '  • ${newTasks.length} new task${newTasks.length == 1 ? '' : 's'} will be added',
                        style: GoogleFonts.dmMono(fontSize: 11, color: const Color(0xFF34A853)),
                      ),
                    if (alreadyHasTasks.isNotEmpty)
                      Text(
                        '  • ${alreadyHasTasks.length} task${alreadyHasTasks.length == 1 ? '' : 's'} already owned (skipped)',
                        style: GoogleFonts.dmMono(fontSize: 11, color: const Color(0xFF9CA3AF)),
                      ),
                    if (newExams.isNotEmpty)
                      Text(
                        '  • ${newExams.length} new exam${newExams.length == 1 ? '' : 's'} will be added',
                        style: GoogleFonts.dmMono(fontSize: 11, color: const Color(0xFF34A853)),
                      ),
                    if (alreadyHasExams.isNotEmpty)
                      Text(
                        '  • ${alreadyHasExams.length} exam${alreadyHasExams.length == 1 ? '' : 's'} already owned (skipped)',
                        style: GoogleFonts.dmMono(fontSize: 11, color: const Color(0xFF9CA3AF)),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.dmMono(color: const Color(0xFF6B7280)),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  final List<Map<String, dynamic>> finalList = [
                    ...noClashClasses,
                  ];
                  for (int i = 0; i < clashGroups.length; i++) {
                    if (selections[i] == 'incoming') {
                      finalList.add(
                        clashGroups[i]['incoming'] as Map<String, dynamic>,
                      );
                    }
                    // If 'existing_*' chosen — skip the incoming class
                  }
                  Navigator.pop(ctx, finalList);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF34A853),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  confirmLabel,
                  style: GoogleFonts.dmMono(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _joinGroupAndMarkAccepted(
    DocumentSnapshot doc,
    User user,
    String groupId,
    String groupName,
    List<Map<String, dynamic>> classesToInsert,
  ) async {
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] ?? 'Unknown';

    final inviteData = doc.data() as Map<String, dynamic>;
    final subjectId = inviteData['subjectId'] as String?;

    // ── Check which classes recipient already has ─────────────────────────────
    List<Map<String, dynamic>> newClasses = [];
    List<Map<String, dynamic>> alreadyHasClasses = [];

    final existingClassesSnap = await _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .get();

    final Map<String, List<Map<String, dynamic>>> existingByDay = {};
    for (final d in existingClassesSnap.docs) {
      final dd = d.data();
      final ts = dd['date'] as Timestamp?;
      if (ts == null) continue;
      final dayKey = DateFormat('yyyy-MM-dd').format(ts.toDate());
      existingByDay.putIfAbsent(dayKey, () => []).add({
        'className': dd['className'] ?? '',
        'startTime': dd['startTime'] ?? '',
        'endTime': dd['endTime'] ?? '',
      });
    }

    for (final cls in classesToInsert) {
      final ts = cls['date'] as Timestamp?;
      final dayKey = ts != null ? DateFormat('yyyy-MM-dd').format(ts.toDate()) : '';
      final existing = existingByDay[dayKey] ?? [];
      final isDuplicate = existing.any(
        (ex) =>
            ex['className'] == cls['className'] &&
            ex['startTime'] == cls['startTime'] &&
            ex['endTime'] == cls['endTime'],
      );
      (isDuplicate ? alreadyHasClasses : newClasses).add(cls);
    }

    // ── Upfront task/exam dedup ───────────────────────────────────────────────
    final tasks = List<Map<String, dynamic>>.from(inviteData['tasks'] ?? []);
    final exams = List<Map<String, dynamic>>.from(inviteData['exams'] ?? []);

    final List<Map<String, dynamic>> newTasks = [];
    final List<Map<String, dynamic>> alreadyHasTasks = [];
    final List<Map<String, dynamic>> newExams = [];
    final List<Map<String, dynamic>> alreadyHasExams = [];

    if (tasks.isNotEmpty) {
      final existingTasksSnap = await _firestore
          .collection('tasks')
          .where('userId', isEqualTo: user.uid)
          .get();
      final existingTaskKeys = existingTasksSnap.docs.map((d) {
        final dd = d.data();
        return '${dd['taskTitle']}__${(dd['dueDate'] as Timestamp?)?.millisecondsSinceEpoch}';
      }).toSet();
      for (final task in tasks) {
        final key =
            '${task['taskTitle']}__${(task['dueDate'] as Timestamp?)?.millisecondsSinceEpoch}';
        (existingTaskKeys.contains(key) ? alreadyHasTasks : newTasks).add(task);
      }
    }

    if (exams.isNotEmpty) {
      final existingExamsSnap = await _firestore
          .collection('exams')
          .where('userId', isEqualTo: user.uid)
          .get();
      final existingExamKeys = existingExamsSnap.docs.map((d) {
        final dd = d.data();
        return '${dd['examName']}__${(dd['examDate'] as Timestamp?)?.millisecondsSinceEpoch}';
      }).toSet();
      for (final exam in exams) {
        final key =
            '${exam['examName']}__${(exam['examDate'] as Timestamp?)?.millisecondsSinceEpoch}';
        (existingExamKeys.contains(key) ? alreadyHasExams : newExams).add(exam);
      }
    }

    // ── Show preview with already-have vs new split ──────────────────────────
    if (alreadyHasClasses.isNotEmpty || newClasses.isNotEmpty ||
        alreadyHasTasks.isNotEmpty || newTasks.isNotEmpty ||
        alreadyHasExams.isNotEmpty || newExams.isNotEmpty) {
      final confirm = await _showJoinPreviewDialog(
        groupName: groupName,
        newClasses: newClasses,
        alreadyHasClasses: alreadyHasClasses,
        confirmLabel: newClasses.isEmpty && newTasks.isEmpty && newExams.isEmpty
            ? 'Join Group'
            : 'Join & Add',
        newTasks: newTasks,
        alreadyHasTasks: alreadyHasTasks,
        newExams: newExams,
        alreadyHasExams: alreadyHasExams,
      );
      if (confirm != true) return;
    }

    // ── Join the group ───────────────────────────────────────────────────────
    await _firestore.collection('study_groups').doc(groupId).update({
      'memberIds': FieldValue.arrayUnion([user.uid]),
      'members': FieldValue.arrayUnion([
        {'uid': user.uid, 'username': username},
      ]),
    });

    // ── Insert only the new (non-duplicate) classes ──────────────────────────
    final batch = _firestore.batch();

    for (final cls in newClasses) {
      final ref = _firestore.collection('timetable').doc();
      batch.set(ref, {
        'userId': user.uid,
        'className': cls['className'] ?? '',
        'startTime': cls['startTime'] ?? '',
        'endTime': cls['endTime'] ?? '',
        'room': cls['room'] ?? '',
        'building': cls['building'] ?? '',
        'lecturerName': cls['lecturerName'] ?? '',
        'date': cls['date'],
        'semester': cls['semester'],
        'academicYear': cls['academicYear'],
        'type': 'class',
        if (subjectId != null && subjectId.isNotEmpty) 'subjectId': subjectId,
      });
    }

    // ── Insert new tasks ──────────────────────────────────────────────────────
    for (final task in newTasks) {
      batch.set(_firestore.collection('tasks').doc(), {
        'userId': user.uid,
        'taskTitle': task['taskTitle'] ?? '',
        'taskDetails': task['taskDetails'] ?? '',
        'taskType': task['taskType'] ?? '',
        'subject': task['subject'] ?? '',
        'dueDate': task['dueDate'],
        'completed': false,
      });
    }

    // ── Insert new exams ──────────────────────────────────────────────────────
    for (final exam in newExams) {
      batch.set(_firestore.collection('exams').doc(), {
        'userId': user.uid,
        'examName': exam['examName'] ?? '',
        'subject': exam['subject'] ?? '',
        'type': exam['type'] ?? 'Exam',
        'mode': exam['mode'] ?? 'In Person',
        'venue': exam['venue'] ?? '',
        'examDate': exam['examDate'],
        'startTime': exam['startTime'],
        'endTime': exam['endTime'],
      });
    }

    await batch.commit();

    // ── Mark invitation accepted ─────────────────────────────────────────────
    await doc.reference.update({'status': 'accepted'});

    if (mounted) {
      final parts = <String>[];
      if (newClasses.isNotEmpty)
        parts.add('${newClasses.length} class${newClasses.length == 1 ? '' : 'es'}');
      if (newTasks.isNotEmpty)
        parts.add('${newTasks.length} task${newTasks.length == 1 ? '' : 's'}');
      if (newExams.isNotEmpty)
        parts.add('${newExams.length} exam${newExams.length == 1 ? '' : 's'}');
      final summary = parts.isEmpty ? '' : ' (${parts.join(', ')} added)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined $groupName!$summary',
              style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: const Color(0xFF34A853),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<bool?> _showJoinPreviewDialog({
    required String groupName,
    required List<Map<String, dynamic>> newClasses,
    required List<Map<String, dynamic>> alreadyHasClasses,
    String? dialogTitle,
    String? confirmLabel,
    List<Map<String, dynamic>> newTasks = const [],
    List<Map<String, dynamic>> alreadyHasTasks = const [],
    List<Map<String, dynamic>> newExams = const [],
    List<Map<String, dynamic>> alreadyHasExams = const [],
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.border(context), width: 2),
        ),
        title: Text(
          dialogTitle ?? 'Join $groupName?',
          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Classes being added ─────────────────────────────────
              if (newClasses.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.add_circle_outline,
                      size: 14,
                      color: Color(0xFF34A853),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${newClasses.length} class${newClasses.length == 1 ? '' : 'es'} will be added',
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF34A853),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...newClasses.map(
                  (cls) => _previewClassTile(
                    cls,
                    borderColor: const Color(0xFF34A853),
                    bgColor: const Color(0xFFF0FFF4),
                    icon: Icons.add_circle_outline,
                    iconColor: const Color(0xFF34A853),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Classes already in calendar ──────────────────────────
              if (alreadyHasClasses.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: Color(0xFF6B7280),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${alreadyHasClasses.length} class${alreadyHasClasses.length == 1 ? '' : 'es'} already in your timetable',
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'These will not be added again:',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 8),
                ...alreadyHasClasses.map(
                  (cls) => _previewClassTile(
                    cls,
                    borderColor: AppColors.border(context),
                    bgColor: AppColors.input(context),
                    icon: Icons.check_circle_outline,
                    iconColor: AppColors.subtext(context),
                    dimmed: true,
                  ),
                ),
              ],

              // ── Tasks being added ───────────────────────────────────
              if (newTasks.isNotEmpty) ...[
                if (newClasses.isNotEmpty || alreadyHasClasses.isNotEmpty)
                  const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF34A853)),
                    const SizedBox(width: 6),
                    Text(
                      '${newTasks.length} task${newTasks.length == 1 ? '' : 's'} will be added',
                      style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF34A853)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...newTasks.map((task) {
                  final dueTs = task['dueDate'] as Timestamp?;
                  final dueStr = dueTs != null ? DateFormat('EEE, dd MMM').format(dueTs.toDate()) : '—';
                  final type = (task['taskType'] ?? '') as String;
                  return Opacity(
                    opacity: 1.0,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FFF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF34A853)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.assignment_outlined, size: 16, color: Color(0xFF34A853)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(task['taskTitle'] ?? '', style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold)),
                                Text('Due: $dueStr${type.isNotEmpty ? '  •  $type' : ''}', style: GoogleFonts.dmMono(fontSize: 10, color: const Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
              ],

              // ── Tasks already owned ──────────────────────────────────
              if (alreadyHasTasks.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF6B7280)),
                    const SizedBox(width: 6),
                    Text(
                      '${alreadyHasTasks.length} task${alreadyHasTasks.length == 1 ? '' : 's'} already in your list',
                      style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('These will not be added again:', style: GoogleFonts.dmMono(fontSize: 11, color: const Color(0xFF9CA3AF))),
                const SizedBox(height: 8),
                ...alreadyHasTasks.map((task) {
                  final dueTs = task['dueDate'] as Timestamp?;
                  final dueStr = dueTs != null ? DateFormat('EEE, dd MMM').format(dueTs.toDate()) : '—';
                  return Opacity(
                    opacity: 0.6,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.input(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border(context)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, size: 16, color: AppColors.subtext(context)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(task['taskTitle'] ?? '', style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold)),
                                Text('Due: $dueStr', style: GoogleFonts.dmMono(fontSize: 10, color: const Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
              ],

              // ── Exams being added ────────────────────────────────────
              if (newExams.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF34A853)),
                    const SizedBox(width: 6),
                    Text(
                      '${newExams.length} exam${newExams.length == 1 ? '' : 's'} will be added',
                      style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF34A853)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...newExams.map((exam) {
                  final examTs = exam['examDate'] as Timestamp?;
                  final examStr = examTs != null ? DateFormat('EEE, dd MMM').format(examTs.toDate()) : '—';
                  final startVal = exam['startTime'];
                  final endVal = exam['endTime'];
                  final start = startVal is Timestamp ? DateFormat('HH:mm').format(startVal.toDate()) : (startVal as String? ?? '');
                  final end = endVal is Timestamp ? DateFormat('HH:mm').format(endVal.toDate()) : (endVal as String? ?? '');
                  return Opacity(
                    opacity: 1.0,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FFF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF34A853)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.quiz_outlined, size: 16, color: Color(0xFF34A853)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(exam['examName'] ?? '', style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold)),
                                Text('$examStr${start.isNotEmpty && end.isNotEmpty ? '  •  ${_formatTime(start)} – ${_formatTime(end)}' : ''}', style: GoogleFonts.dmMono(fontSize: 10, color: const Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
              ],

              // ── Exams already owned ──────────────────────────────────
              if (alreadyHasExams.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF6B7280)),
                    const SizedBox(width: 6),
                    Text(
                      '${alreadyHasExams.length} exam${alreadyHasExams.length == 1 ? '' : 's'} already in your list',
                      style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('These will not be added again:', style: GoogleFonts.dmMono(fontSize: 11, color: const Color(0xFF9CA3AF))),
                const SizedBox(height: 8),
                ...alreadyHasExams.map((exam) {
                  final examTs = exam['examDate'] as Timestamp?;
                  final examStr = examTs != null ? DateFormat('EEE, dd MMM').format(examTs.toDate()) : '—';
                  return Opacity(
                    opacity: 0.6,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.input(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border(context)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, size: 16, color: AppColors.subtext(context)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(exam['examName'] ?? '', style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.bold)),
                                Text(examStr, style: GoogleFonts.dmMono(fontSize: 10, color: const Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
              ],

              if (newClasses.isEmpty && newTasks.isEmpty && newExams.isEmpty &&
                  (alreadyHasClasses.isNotEmpty || alreadyHasTasks.isNotEmpty || alreadyHasExams.isNotEmpty)) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF3859FF).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Color(0xFF3859FF),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'None of these items are new for you.',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            color: const Color(0xFF3859FF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmMono(color: const Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF34A853),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              confirmLabel ??
                  (newClasses.isEmpty && newTasks.isEmpty && newExams.isEmpty
                      ? 'Join Group'
                      : 'Join & Add'),
              style: GoogleFonts.dmMono(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewClassTile(
    Map<String, dynamic> cls, {
    required Color borderColor,
    required Color bgColor,
    required IconData icon,
    required Color iconColor,
    bool dimmed = false,
  }) {
    final ts = cls['date'] as Timestamp?;
    final dateStr = ts != null
        ? DateFormat('EEE, dd MMM').format(ts.toDate())
        : '—';
    final start = cls['startTime'] ?? '';
    final end = cls['endTime'] ?? '';
    final room = cls['room'] ?? '';
    final building = cls['building'] ?? '';
    final loc = [
      room,
      building,
    ].where((s) => (s as String).isNotEmpty).join(', ');

    return Opacity(
      opacity: dimmed ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cls['className'] ?? '',
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateStr  •  ${_formatTime(start)} – ${_formatTime(end)}'
                    '${loc.isNotEmpty ? '  •  $loc' : ''}',
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
    );
  }
  // ════════════════════════════════════════════════════════════════════════
  // TIMETABLE SHARE SECTION
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildTimetableSharesSection() {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('timetable_shares')
          .where('recipientId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .handleError((_) {}),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox();
        }
        final shares = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Shared Timetables',
              style: GoogleFonts.dmMono(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...shares.map((doc) => _buildShareCard(doc)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildShareCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final sender = data['senderUsername'] ?? 'Someone';
    final subject = data['subject'] ?? '';
    final classes = List<Map<String, dynamic>>.from(data['classes'] ?? []);
    final tasks = List<Map<String, dynamic>>.from(data['tasks'] ?? []);
    final exams = List<Map<String, dynamic>>.from(data['exams'] ?? []);
    final ts = (data['createdAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB90000), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFB90000).withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB90000).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_month,
                    color: Color(0xFFB90000),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject,
                        style: GoogleFonts.dmMono(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 13,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Shared by $sender',
                            style: GoogleFonts.dmMono(
                              fontSize: 11,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                      if (ts != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 13,
                              color: Color(0xFF9CA3AF),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat(
                                'EEE, dd MMM yyyy  •  h:mm a',
                              ).format(ts),
                              style: GoogleFonts.dmMono(
                                fontSize: 10,
                                color: const Color(0xFF9CA3AF),
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

          // ── Summary chips ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (classes.isNotEmpty)
                  _summaryChip(
                    Icons.school_outlined,
                    '${classes.length} Class${classes.length == 1 ? '' : 'es'}',
                    const Color(0xFFB90000),
                  ),
                if (tasks.isNotEmpty)
                  _summaryChip(
                    Icons.task_alt,
                    '${tasks.length} Task${tasks.length == 1 ? '' : 's'}',
                    const Color(0xFF008BB9),
                  ),
                if (exams.isNotEmpty)
                  _summaryChip(
                    Icons.assignment_outlined,
                    '${exams.length} Exam${exams.length == 1 ? '' : 's'}',
                    const Color(0xFF9AB900),
                  ),
              ],
            ),
          ),

          // ── Preview classes list ───────────────────────────────────────────
          if (classes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFB90000).withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 13,
                          color: Color(0xFFB90000),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Class Schedule Preview',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFB90000),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...classes.map((cls) {
                      final dateTs = cls['date'] as Timestamp?;
                      final dateStr = dateTs != null
                          ? DateFormat(
                              'EEE, dd MMM yyyy',
                            ).format(dateTs.toDate())
                          : '—';
                      final start = cls['startTime'] ?? '';
                      final end = cls['endTime'] ?? '';
                      final room = cls['room'] ?? '';
                      final building = cls['building'] ?? '';
                      final loc = [
                        room,
                        building,
                      ].where((s) => (s as String).isNotEmpty).join(', ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFFB90000),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cls['className'] ?? subject,
                                    style: GoogleFonts.dmMono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$dateStr${_formatTime(start)} – ${_formatTime(end)}'
                                    '${loc.isNotEmpty ? '  •  $loc' : ''}',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 10,
                                      color: const Color(0xFF6B7280),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],

          // ── Tasks preview ──────────────────────────────────────────────────
          if (tasks.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4FD),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF008BB9).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.task_alt,
                          size: 13,
                          color: Color(0xFF008BB9),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Tasks',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF008BB9),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...tasks.map((task) {
                      final dueDateTs = task['dueDate'] as Timestamp?;
                      final dateStr = dueDateTs != null
                          ? DateFormat(
                              'EEE, dd MMM yyyy',
                            ).format(dueDateTs.toDate())
                          : '—';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF008BB9),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task['taskTitle'] ?? '',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$dateStr  •  ${task['taskType'] ?? ''}',
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
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── Exams preview ───────────────────────────────────────────────────
          if (exams.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBE6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF9AB900).withOpacity(0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.assignment_outlined,
                          size: 13,
                          color: Color(0xFF9AB900),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Exams',
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF9AB900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...exams.map((exam) {
                      final examDateTs = exam['examDate'] as Timestamp?;
                      final startTs = exam['startTime'] as Timestamp?;
                      final endTs = exam['endTime'] as Timestamp?;
                      final dateStr = examDateTs != null
                          ? DateFormat(
                              'EEE, dd MMM yyyy',
                            ).format(examDateTs.toDate())
                          : '—';
                      final timeStr = startTs != null && endTs != null
                          ? '${DateFormat('h:mm a').format(startTs.toDate())} – ${DateFormat('h:mm a').format(endTs.toDate())}'
                          : '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF9AB900),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    exam['examName'] ?? '',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$dateStr${timeStr.isNotEmpty ? '  •  $timeStr' : ''}  •  ${exam['type'] ?? ''}',
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
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── Accept / Decline ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _AnimatedTapButton(
                    onTap: () => _acceptTimetableShare(doc),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34A853),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          'Accept & Add to Timetable',
                          style: GoogleFonts.dmMono(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _AnimatedTapButton(
                  onTap: () => _declineTimetableShare(doc),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFB90000),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      'Decline',
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFB90000),
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

  Widget _summaryChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptTimetableShare(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final data = doc.data() as Map<String, dynamic>;
    final classes = List<Map<String, dynamic>>.from(data['classes'] ?? []);
    final tasks = List<Map<String, dynamic>>.from(data['tasks'] ?? []);
    final exams = List<Map<String, dynamic>>.from(data['exams'] ?? []);
    final subject = data['subject'] ?? '';
    final sender = data['senderUsername'] ?? 'Someone';

    // Load recipient's existing timetable for clash detection
    final existingSnap = await _firestore
        .collection('timetable')
        .where('userId', isEqualTo: user.uid)
        .get();

    // Build day → existing classes map
    final Map<String, List<Map<String, dynamic>>> existingByDay = {};
    for (var d in existingSnap.docs) {
      final dd = d.data();
      final ts = dd['date'] as Timestamp?;
      if (ts == null) continue;
      final key = DateFormat('yyyy-MM-dd').format(ts.toDate());
      existingByDay.putIfAbsent(key, () => []).add({
        'id': d.id,
        'className': dd['className'] ?? '',
        'startTime': dd['startTime'] ?? '',
        'endTime': dd['endTime'] ?? '',
        'date': ts,
      });
    }

    // Separate no-clash from clashing, and track exact duplicates
    final List<Map<String, dynamic>> noClash = [];
    final List<Map<String, dynamic>> clashGroups = [];
    final List<Map<String, dynamic>> alreadyHas = [];

    for (final cls in classes) {
      final ts = cls['date'] as Timestamp?;
      if (ts == null) {
        noClash.add(cls);
        continue;
      }
      final key = DateFormat('yyyy-MM-dd').format(ts.toDate());
      final existing = existingByDay[key] ?? [];
      final inStart = _timeToMinutes(cls['startTime'] ?? '');
      final inEnd = _timeToMinutes(cls['endTime'] ?? '');

      // Check exact duplicate first — same class name same day same time
      final isDuplicate = existing.any(
        (ex) =>
            ex['className'] == cls['className'] &&
            ex['startTime'] == cls['startTime'] &&
            ex['endTime'] == cls['endTime'],
      );
      if (isDuplicate) { alreadyHas.add(cls); continue; }

      final clashing = existing.where((ex) {
        final s = _timeToMinutes(ex['startTime'] ?? '');
        final e = _timeToMinutes(ex['endTime'] ?? '');
        return inStart < e && inEnd > s;
      }).toList();

      if (clashing.isEmpty) {
        noClash.add(cls);
      } else {
        clashGroups.add({'incoming': cls, 'existing': clashing});
      }
    }

    // ── Upfront task duplicate detection ────────────────────────────────────
    final existingTasksSnap = await _firestore
        .collection('tasks')
        .where('userId', isEqualTo: user.uid)
        .get();
    final existingTaskKeys = existingTasksSnap.docs.map((d) {
      final dd = d.data();
      return '${dd['taskTitle']}__${(dd['dueDate'] as Timestamp?)?.millisecondsSinceEpoch}';
    }).toSet();
    final List<Map<String, dynamic>> newTasks = [];
    final List<Map<String, dynamic>> alreadyHasTasks = [];
    for (final task in tasks) {
      final key =
          '${task['taskTitle']}__${(task['dueDate'] as Timestamp?)?.millisecondsSinceEpoch}';
      (existingTaskKeys.contains(key) ? alreadyHasTasks : newTasks).add(task);
    }

    // ── Upfront exam duplicate detection ────────────────────────────────────
    final existingExamsSnap = await _firestore
        .collection('exams')
        .where('userId', isEqualTo: user.uid)
        .get();
    final existingExamKeys = existingExamsSnap.docs.map((d) {
      final dd = d.data();
      return '${dd['examName']}__${(dd['examDate'] as Timestamp?)?.millisecondsSinceEpoch}';
    }).toSet();
    final List<Map<String, dynamic>> newExams = [];
    final List<Map<String, dynamic>> alreadyHasExams = [];
    for (final exam in exams) {
      final key =
          '${exam['examName']}__${(exam['examDate'] as Timestamp?)?.millisecondsSinceEpoch}';
      (existingExamKeys.contains(key) ? alreadyHasExams : newExams).add(exam);
    }

    if (classes.isEmpty) {
      // No classes — show task/exam split dialog then accept
      final confirm = await _showJoinPreviewDialog(
        groupName: subject,
        newClasses: [],
        alreadyHasClasses: [],
        dialogTitle: 'Timetable from $sender',
        confirmLabel: 'Add to Timetable',
        newTasks: newTasks,
        alreadyHasTasks: alreadyHasTasks,
        newExams: newExams,
        alreadyHasExams: alreadyHasExams,
      );
      if (confirm == true) {
        await _insertClassesAndMarkAccepted(doc, user, [], newTasks, newExams, sender);
      }
      return;
    }

    if (clashGroups.isEmpty) {
      if (noClash.isEmpty && alreadyHas.isNotEmpty) {
        // All classes already owned — show full split so user sees everything
        final confirm = await _showJoinPreviewDialog(
          groupName: subject,
          newClasses: [],
          alreadyHasClasses: alreadyHas,
          dialogTitle: 'Timetable from $sender',
          confirmLabel: 'Accept',
          newTasks: newTasks,
          alreadyHasTasks: alreadyHasTasks,
          newExams: newExams,
          alreadyHasExams: alreadyHasExams,
        );
        if (confirm == true) {
          await _insertClassesAndMarkAccepted(doc, user, [], newTasks, newExams, sender);
        }
      } else if (alreadyHas.isNotEmpty) {
        // Mix: some classes new, some already owned
        final confirm = await _showJoinPreviewDialog(
          groupName: subject,
          newClasses: noClash,
          alreadyHasClasses: alreadyHas,
          dialogTitle: 'Timetable from $sender',
          confirmLabel: 'Add to Timetable',
          newTasks: newTasks,
          alreadyHasTasks: alreadyHasTasks,
          newExams: newExams,
          alreadyHasExams: alreadyHasExams,
        );
        if (confirm == true) {
          await _insertClassesAndMarkAccepted(doc, user, noClash, newTasks, newExams, sender);
        }
      } else {
        // All classes new — show full preview with task/exam split
        final confirm = await _showJoinPreviewDialog(
          groupName: subject,
          newClasses: noClash,
          alreadyHasClasses: [],
          dialogTitle: 'Timetable from $sender',
          confirmLabel: 'Add to Timetable',
          newTasks: newTasks,
          alreadyHasTasks: alreadyHasTasks,
          newExams: newExams,
          alreadyHasExams: alreadyHasExams,
        );
        if (confirm == true) {
          await _insertClassesAndMarkAccepted(doc, user, noClash, newTasks, newExams, sender);
        }
      }
    } else {
      // Has clashes — show clash resolution dialog with task/exam summary
      final chosen = await _showClashDialog(
        inviterUsername: sender,
        groupName: subject,
        noClashClasses: noClash,
        clashGroups: clashGroups,
        confirmLabel: 'Confirm & Accept',
        newTasks: newTasks,
        alreadyHasTasks: alreadyHasTasks,
        newExams: newExams,
        alreadyHasExams: alreadyHasExams,
      );
      if (chosen != null) {
        await _insertClassesAndMarkAccepted(
          doc,
          user,
          chosen,
          newTasks,
          newExams,
          sender,
        );
      }
    }
  }


  Future<void> _insertClassesAndMarkAccepted(
    DocumentSnapshot doc,
    User user,
    List<Map<String, dynamic>> classes,
    List<Map<String, dynamic>> tasks,
    List<Map<String, dynamic>> exams,
    String sender,
  ) async {
    final batch = _firestore.batch();

    // Insert timetable classes
    for (final cls in classes) {
      final ref = _firestore.collection('timetable').doc();
      batch.set(ref, {
        'userId': user.uid,
        'className': cls['className'] ?? '',
        'startTime': cls['startTime'] ?? '',
        'endTime': cls['endTime'] ?? '',
        'room': cls['room'] ?? '',
        'building': cls['building'] ?? '',
        'lecturerName': cls['lecturerName'] ?? '',
        'date': cls['date'],
        'semester': cls['semester'],
        'academicYear': cls['academicYear'],
        'type': 'class',
      });
    }

    // Insert tasks — skip duplicates with same title and due date
    final existingTasksSnap = await _firestore
        .collection('tasks')
        .where('userId', isEqualTo: user.uid)
        .get();
    final existingTaskKeys = existingTasksSnap.docs.map((d) {
      final dd = d.data();
      return '${dd['taskTitle']}__${(dd['dueDate'] as Timestamp?)?.millisecondsSinceEpoch}';
    }).toSet();

    for (final task in tasks) {
      final dueDateTs = task['dueDate'] as Timestamp?;
      final key = '${task['taskTitle']}__${dueDateTs?.millisecondsSinceEpoch}';
      if (existingTaskKeys.contains(key)) continue; // skip duplicate
      final ref = _firestore.collection('tasks').doc();
      batch.set(ref, {
        'userId': user.uid,
        'taskTitle': task['taskTitle'] ?? '',
        'taskDetails': task['taskDetails'] ?? '',
        'taskType': task['taskType'] ?? '',
        'subject': task['subject'] ?? '',
        'dueDate': task['dueDate'],
        'completed': false,
      });
    }

    // Insert exams — skip duplicates with same name and exam date
    final existingExamsSnap = await _firestore
        .collection('exams')
        .where('userId', isEqualTo: user.uid)
        .get();
    final existingExamKeys = existingExamsSnap.docs.map((d) {
      final dd = d.data();
      return '${dd['examName']}__${(dd['examDate'] as Timestamp?)?.millisecondsSinceEpoch}';
    }).toSet();

    for (final exam in exams) {
      final examDateTs = exam['examDate'] as Timestamp?;
      final key = '${exam['examName']}__${examDateTs?.millisecondsSinceEpoch}';
      if (existingExamKeys.contains(key)) continue; // skip duplicate
      final ref = _firestore.collection('exams').doc();
      batch.set(ref, {
        'userId': user.uid,
        'examName': exam['examName'] ?? '',
        'subject': exam['subject'] ?? '',
        'type': exam['type'] ?? 'Exam',
        'mode': exam['mode'] ?? 'In Person',
        'venue': exam['venue'] ?? '',
        'examDate': exam['examDate'],
        'startTime': exam['startTime'],
        'endTime': exam['endTime'],
      });
    }

    await batch.commit();
    await doc.reference.update({'status': 'accepted'});

    if (mounted) {
      final parts = <String>[];
      if (classes.isNotEmpty)
        parts.add('${classes.length} class${classes.length == 1 ? '' : 'es'}');
      if (tasks.isNotEmpty)
        parts.add('${tasks.length} task${tasks.length == 1 ? '' : 's'}');
      if (exams.isNotEmpty)
        parts.add('${exams.length} exam${exams.length == 1 ? '' : 's'}');
      final summary = parts.isEmpty ? '' : ' (${parts.join(', ')})';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Timetable from $sender accepted!$summary',
            style: GoogleFonts.dmMono(),
          ),
          backgroundColor: const Color(0xFF34A853),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _declineTimetableShare(DocumentSnapshot doc) async {
    await doc.reference.update({'status': 'declined'});
    if (mounted) {
      final data = doc.data() as Map<String, dynamic>;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Timetable from ${data['senderUsername'] ?? 'Someone'} declined.',
            style: GoogleFonts.dmMono(),
          ),
          backgroundColor: const Color(0xFF6B7280),
        ),
      );
    }
  }

  Future<void> _declineInvitation(DocumentSnapshot doc) async {
    await doc.reference.update({'status': 'declined'});
    if (mounted) {
      final data = doc.data() as Map<String, dynamic>;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invitation to ${data['groupName'] ?? 'group'} declined.',
            style: GoogleFonts.dmMono(),
          ),
          backgroundColor: const Color(0xFF6B7280),
        ),
      );
    }
  }
}

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

class _DotData {
  final Color color;
  final bool filled;
  const _DotData(this.color, this.filled);
}

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

class TrianglePainter extends CustomPainter {
  final Color color;
  const TrianglePainter({required this.color});

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
