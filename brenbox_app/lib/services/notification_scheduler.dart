import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';

class NotificationScheduler {
  static final NotificationScheduler _instance =
      NotificationScheduler._internal();
  factory NotificationScheduler() => _instance;
  NotificationScheduler._internal();

  final _firestore = FirebaseFirestore.instance;
  final _notificationService = NotificationService();

  static const int _classBaseId = 1000;
  static const int _taskBaseId  = 5000;
  static const int _examBaseId  = 9000;

  // ── PUBLIC API ──────────────────────────────────────────────────────────────

  /// Full reschedule — call when user SAVES settings.
  /// forceFull:true wipes all existing schedules and starts clean.
  Future<void> rescheduleAllNotifications({bool forceFull = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final data = userDoc.data();
    final notificationsEnabled = data?['notificationsEnabled'] ?? true;

    if (!notificationsEnabled) {
      await _notificationService.cancelAllNotifications();
      await _notificationService.clearAllDedupeRecords(user.uid);
      return;
    }

    final settings = data?['notificationSettings'] as Map<String, dynamic>?
        ?? _defaultSettings();

    if (forceFull) {
      await _notificationService.cancelAllNotifications();
      await _notificationService.clearAllDedupeRecords(user.uid);
    }

    // Schedule FIRST, purge AFTER — never delete a key before it is used
    await _scheduleClassNotifications(user.uid, settings);
    await _scheduleTaskNotifications(user.uid, settings);
    await _scheduleExamNotifications(user.uid, settings);
    await _notificationService.purgeOldData(user.uid);
  }

  /// Lightweight call on every app open.
  /// Schedules new events and restores lost OS alarms, then purges stale data.
  Future<void> onAppOpen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final data = userDoc.data();
    final notificationsEnabled = data?['notificationsEnabled'] ?? true;
    if (!notificationsEnabled) return;

    final settings = data?['notificationSettings'] as Map<String, dynamic>?
        ?? _defaultSettings();

    // Schedule FIRST — restores OS alarms that were cleared by system
    await _scheduleClassNotifications(user.uid, settings);
    await _scheduleTaskNotifications(user.uid, settings);
    await _scheduleExamNotifications(user.uid, settings);

    // Purge AFTER — never delete a dedupe key before we have used it
    await _notificationService.purgeOldData(user.uid);
  }

  // ── DEFAULT SETTINGS ────────────────────────────────────────────────────────

  Map<String, dynamic> _defaultSettings() => {
    'classEnabled':      true,
    'classDayBefore':    true,
    'classReminderHour': 20,
    'classReminderMin':  0,
    'classHourBefore':   true,
    'class10MinBefore':  true,
    'classOnTime':       true,
    'taskEnabled':       true,
    'taskDays':          [3, 2, 1],
    'taskHourBefore':    true,
    'task10MinBefore':   true,
    'taskDueNow':        true,
    'examEnabled':       true,
    'examDays':          [3, 2, 1],
    'examHourBefore':    true,
    'exam30MinBefore':   true,
    'exam10MinBefore':   true,
    'examOnTime':        true,
  };

  // ── CLASS NOTIFICATIONS ─────────────────────────────────────────────────────

  Future<void> _scheduleClassNotifications(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    if (!(settings['classEnabled'] ?? true)) return;

    final now      = DateTime.now();
    final snapshot = await _firestore
        .collection('timetable')
        .where('userId', isEqualTo: userId)
        .get();

    final int reminderHour = settings['classReminderHour'] ?? 20;
    final int reminderMin  = settings['classReminderMin']  ?? 0;

    for (var doc in snapshot.docs) {
      try {
        final data      = doc.data();
        final timestamp = data['date'] as Timestamp?;
        if (timestamp == null) continue;

        final classDateRaw = timestamp.toDate();
        final classDate    = DateTime(
            classDateRaw.year, classDateRaw.month, classDateRaw.day);
        final className = data['className'] ?? 'Your Class';
        final startTime = data['startTime'] ?? '00:00';
        final room      = data['room']      ?? '';
        final building  = data['building']  ?? '';

        final parts      = startTime.split(':');
        final classStart = DateTime(
          classDate.year, classDate.month, classDate.day,
          int.tryParse(parts[0]) ?? 0,
          int.tryParse(parts[1]) ?? 0,
        );

        if (classStart.isBefore(now)) continue;

        final locationText = _buildLocationText(room, building);
        final baseId       = (doc.id.hashCode.abs() % 90000) + _classBaseId;

        if (settings['classDayBefore'] ?? true) {
          // Days-before: fire exactly N*24h before classStart.
          // The user-chosen reminderHour/Min is used ONLY as a fallback label;
          // the actual trigger time is classStart minus the duration so the
          // notification arrives at precisely the right moment relative to the
          // event, regardless of what time of day the class is.
          await _trySchedule(
            dedupeKey: '${doc.id}_class_3d',
            id: baseId + 0,
            title: '📚 Class in 3 Days',
            body: '$className starts at ${_fmt12(startTime)} on'
                ' ${_fmtDateShort(classDate)}.$locationText',
            scheduledTime: classStart.subtract(const Duration(days: 3)),
            type: 'class', eventId: doc.id, userId: userId,
          );
          await _trySchedule(
            dedupeKey: '${doc.id}_class_2d',
            id: baseId + 1,
            title: '📚 Class in 2 Days',
            body: '$className starts at ${_fmt12(startTime)} on'
                ' ${_fmtDateShort(classDate)}.$locationText',
            scheduledTime: classStart.subtract(const Duration(days: 2)),
            type: 'class', eventId: doc.id, userId: userId,
          );
          await _trySchedule(
            dedupeKey: '${doc.id}_class_1d',
            id: baseId + 2,
            title: '📚 Class Tomorrow!',
            body: "Don't forget — $className starts at"
                ' ${_fmt12(startTime)} tomorrow.$locationText',
            scheduledTime: classStart.subtract(const Duration(days: 1)),
            type: 'class', eventId: doc.id, userId: userId,
          );
        }

        if (settings['classHourBefore'] ?? true) {
          await _trySchedule(
            dedupeKey: '${doc.id}_class_1hr',
            id: baseId + 3,
            title: '⏰ Class in 1 Hour!',
            body: '$className starts at ${_fmt12(startTime)}.$locationText Get ready!',
            scheduledTime: classStart.subtract(const Duration(hours: 1)),
            type: 'class', eventId: doc.id, userId: userId,
          );
        }

        if (settings['class10MinBefore'] ?? true) {
          await _trySchedule(
            dedupeKey: '${doc.id}_class_10min',
            id: baseId + 4,
            title: '🔔 Class Starting Soon!',
            body: '$className starts in 10 minutes.$locationText Head over now!',
            scheduledTime: classStart.subtract(const Duration(minutes: 10)),
            type: 'class', eventId: doc.id, userId: userId,
          );
        }

        if (settings['classOnTime'] ?? true) {
          await _trySchedule(
            dedupeKey: '${doc.id}_class_now',
            id: baseId + 5,
            title: '🏫 Class is Starting!',
            body: '$className is starting now.$locationText',
            scheduledTime: classStart,
            type: 'class', eventId: doc.id, userId: userId,
          );
        }
      } catch (e) {
        print('Class notification error: $e');
      }
    }
  }

  // ── TASK NOTIFICATIONS ──────────────────────────────────────────────────────

  Future<void> _scheduleTaskNotifications(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    if (!(settings['taskEnabled'] ?? true)) return;

    final now      = DateTime.now();
    final snapshot = await _firestore
        .collection('tasks')
        .where('userId', isEqualTo: userId)
        .where('completed', isEqualTo: false)
        .get();

    final taskDays = List<int>.from(settings['taskDays'] ?? [3, 2, 1]);

    for (var doc in snapshot.docs) {
      try {
        final data      = doc.data();
        final timestamp = data['dueDate'] as Timestamp?;
        if (timestamp == null) continue;

        final dueDate = timestamp.toDate();
        if (dueDate.isBefore(now)) continue;

        final taskTitle  = data['taskTitle'] ?? 'Your Task';
        final subject    = data['subject']   ?? '';
        final taskType   = data['taskType']  ?? 'Task';
        final subjectTxt = subject.isNotEmpty ? ' ($subject)' : '';
        final baseId     = (doc.id.hashCode.abs() % 90000) + _taskBaseId;

        for (int i = 0; i < taskDays.length; i++) {
          final days     = taskDays[i];
          // Fire exactly N*24h before the due date+time — not at a fixed 9 AM.
          // Example: task due 12 PM Friday → 1-day alert fires 12 PM Thursday.
          final notifyTime = dueDate.subtract(Duration(days: days));
          final daysText   = days == 1 ? '1 day' : '$days days';
          final emoji      = days <= 1 ? '🚨' : days <= 2 ? '⚠️' : '📝';

          await _trySchedule(
            dedupeKey: '${doc.id}_task_${days}d',
            id: baseId + i,
            title: '$emoji $taskType Due in $daysText!',
            body: '"$taskTitle"$subjectTxt is due'
                ' ${_fmtDateTime(dueDate)}. $daysText left!',
            scheduledTime: notifyTime,
            type: 'task', eventId: doc.id, userId: userId,
          );
        }

        if (settings['taskHourBefore'] ?? true) {
          await _trySchedule(
            dedupeKey: '${doc.id}_task_1hr',
            id: baseId + 10,
            title: '🚨 Submission in 1 Hour!',
            body: 'Last chance! "$taskTitle"$subjectTxt is due at'
                ' ${_fmt12hm(dueDate.hour, dueDate.minute)}. Submit now!',
            scheduledTime: dueDate.subtract(const Duration(hours: 1)),
            type: 'task', eventId: doc.id, userId: userId,
          );
        }

        if (settings['task10MinBefore'] ?? true) {
          await _trySchedule(
            dedupeKey: '${doc.id}_task_10min',
            id: baseId + 11,
            title: '⚠️ Due in 10 Minutes!',
            body: '"$taskTitle"$subjectTxt is due in 10 minutes! Submit ASAP!',
            scheduledTime: dueDate.subtract(const Duration(minutes: 10)),
            type: 'task', eventId: doc.id, userId: userId,
          );
        }

        if (settings['taskDueNow'] ?? true) {
          await _trySchedule(
            dedupeKey: '${doc.id}_task_due',
            id: baseId + 12,
            title: '🔴 Submission Closing Now!',
            body: '"$taskTitle"$subjectTxt is due RIGHT NOW! Submit immediately!',
            scheduledTime: dueDate,
            type: 'task', eventId: doc.id, userId: userId,
          );
        }
      } catch (e) {
        print('Task notification error: $e');
      }
    }
  }

  // ── EXAM NOTIFICATIONS ──────────────────────────────────────────────────────

  Future<void> _scheduleExamNotifications(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    if (!(settings['examEnabled'] ?? true)) return;

    final now      = DateTime.now();
    final snapshot = await _firestore
        .collection('exams')
        .where('userId', isEqualTo: userId)
        .get();

    final examDays = List<int>.from(settings['examDays'] ?? [3, 2, 1]);

    for (var doc in snapshot.docs) {
      try {
        final data        = doc.data();
        final examDateTs  = data['examDate']  as Timestamp?;
        final startTimeTs = data['startTime'] as Timestamp?;
        if (examDateTs == null || startTimeTs == null) continue;

        final examDateRaw = examDateTs.toDate();
        final examDate    = DateTime(
            examDateRaw.year, examDateRaw.month, examDateRaw.day);
        final startTime   = startTimeTs.toDate();

        if (startTime.isBefore(now)) continue;

        final examName   = data['examName'] ?? 'Your Exam';
        final subject    = data['subject']  ?? '';
        final venue      = data['venue']    ?? '';
        final mode       = data['mode']     ?? 'In Person';
        final subjectTxt = subject.isNotEmpty ? ' ($subject)' : '';
        final venueTxt   = mode == 'Online'
            ? ' (Online)'
            : venue.isNotEmpty ? ' at $venue' : '';
        final baseId = (doc.id.hashCode.abs() % 90000) + _examBaseId;

        for (int i = 0; i < examDays.length; i++) {
          final days     = examDays[i];
          // Fire exactly N*24h before exam startTime.
          // Example: exam at 9 AM Wednesday → 1-day alert fires 9 AM Tuesday.
          final notifyTime = startTime.subtract(Duration(days: days));
          final daysText   = days == 1 ? 'tomorrow' : 'in $days days';
          final studyEmoji = days >= 3 ? '📖' : days == 2 ? '✏️' : '🎯';

          await _trySchedule(
            dedupeKey: '${doc.id}_exam_${days}d',
            id: baseId + i,
            title: '$studyEmoji Exam $daysText!',
            body: '"$examName"$subjectTxt is $daysText$venueTxt at'
                ' ${_fmt12hm(startTime.hour, startTime.minute)}. Time to study!',
            scheduledTime: notifyTime,
            type: 'exam', eventId: doc.id, userId: userId,
          );
        }

        if (settings['examHourBefore'] ?? true) {
          await _trySchedule(
            dedupeKey: '${doc.id}_exam_1hr',
            id: baseId + 10,
            title: '⏰ Exam in 1 Hour!',
            body: '"$examName"$subjectTxt starts at'
                ' ${_fmt12hm(startTime.hour, startTime.minute)}$venueTxt. You\'ve got this! 💪',
            scheduledTime: startTime.subtract(const Duration(hours: 1)),
            type: 'exam', eventId: doc.id, userId: userId,
          );
        }

        if (settings['exam30MinBefore'] ?? true) {
          await _trySchedule(
            dedupeKey: '${doc.id}_exam_30min',
            id: baseId + 11,
            title: '🔔 30 Minutes to Exam!',
            body: '"$examName" starts soon$venueTxt. Head over now — good luck! 🍀',
            scheduledTime: startTime.subtract(const Duration(minutes: 30)),
            type: 'exam', eventId: doc.id, userId: userId,
          );
        }

        if (settings['exam10MinBefore'] ?? true) {
          await _trySchedule(
            dedupeKey: '${doc.id}_exam_10min',
            id: baseId + 12,
            title: '⚠️ Exam in 10 Minutes!',
            body: '"$examName"$subjectTxt starts in 10 minutes$venueTxt. Get seated!',
            scheduledTime: startTime.subtract(const Duration(minutes: 10)),
            type: 'exam', eventId: doc.id, userId: userId,
          );
        }

        if (settings['examOnTime'] ?? true) {
          await _trySchedule(
            dedupeKey: '${doc.id}_exam_now',
            id: baseId + 13,
            title: '📝 Exam Starting Now!',
            body: '"$examName"$subjectTxt is starting NOW$venueTxt. Good luck! 🍀',
            scheduledTime: startTime,
            type: 'exam', eventId: doc.id, userId: userId,
          );
        }
      } catch (e) {
        print('Exam notification error: $e');
      }
    }
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────────

  Future<void> _trySchedule({
    required String dedupeKey,
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String type,
    required String eventId,
    required String userId,
  }) async {
    await _notificationService.scheduleNotificationIfNeeded(
      id: id, title: title, body: body,
      scheduledTime: scheduledTime,
      type: type, eventId: eventId,
      userId: userId, dedupeKey: dedupeKey,
    );
  }

  DateTime _atTime(DateTime base, int dayOffset, int hour, int minute) {
    final baseDay   = DateTime(base.year, base.month, base.day);
    final targetDay = baseDay.add(Duration(days: dayOffset));
    return DateTime(
        targetDay.year, targetDay.month, targetDay.day, hour, minute);
  }

  String _fmt12(String time24) {
    try {
      final p = time24.split(':');
      final h = int.parse(p[0]);
      final m = p[1];
      if (h == 0)  return '12:$m AM';
      if (h < 12)  return '$h:$m AM';
      if (h == 12) return '12:$m PM';
      return '${h - 12}:$m PM';
    } catch (_) { return time24; }
  }

  String _fmt12hm(int h, int m) {
    final mm = m.toString().padLeft(2, '0');
    if (h == 0)  return '12:$mm AM';
    if (h < 12)  return '$h:$mm AM';
    if (h == 12) return '12:$mm PM';
    return '${h - 12}:$mm PM';
  }

  String _fmtDateTime(DateTime dt) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${mo[dt.month - 1]} at ${_fmt12hm(dt.hour, dt.minute)}';
  }

  String _fmtDateShort(DateTime dt) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${mo[dt.month - 1]}';
  }

  String _buildLocationText(String room, String building) {
    if (room.isEmpty && building.isEmpty) return '';
    if (room.isNotEmpty && building.isNotEmpty) return ' at $room, $building';
    return ' at ${room.isNotEmpty ? room : building}';
  }
}