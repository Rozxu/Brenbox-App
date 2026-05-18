import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final _firestore = FirebaseFirestore.instance;

  static GlobalKey<NavigatorState>? _navigatorKey;

  static const String _classChannelId     = 'class_channel';
  static const String _taskChannelId      = 'task_channel';
  static const String _examChannelId      = 'exam_channel';
  static const String _inviteChannelId    = 'invite_channel';
  static const String _groupChannelId     = 'group_channel';
  static const String _studyPlanChannelId = 'study_plan_channel';

  void setNavigatorKey(GlobalKey<NavigatorState> key) => _navigatorKey = key;

  Future<void> initialize() async {
    tz.initializeTimeZones();
    _setLocalTimezone();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(
      initSettings,
      // onDidReceiveNotificationResponse fires when:
      //   (a) the user taps the notification, OR
      //   (b) the notification is shown while the app is in foreground.
      // Tapping a notification marks it as read in Firestore.
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );

    await _createNotificationChannels();
    await _requestPermissions();
  }

  // ── TIMEZONE ────────────────────────────────────────────────────────────────
  // Derives the IANA timezone name directly from the platform's timezone string
  // (e.g. "Asia/Kuala_Lumpur") reported by DateTime.now().timeZoneName.
  // This works correctly regardless of DST and does not require the
  // flutter_timezone package — the timezone package already ships all IANA data.

  void _setLocalTimezone() {
    try {
      // DateTime.timeZoneName returns the IANA name on Android/iOS (e.g. "Asia/Kuala_Lumpur").
      // On some devices it returns an abbreviation like "MYT" — we handle that fallback below.
      final String tzNameRaw = DateTime.now().timeZoneName;

      // Try the raw name first (works on most Android/iOS devices)
      try {
        final location = tz.getLocation(tzNameRaw);
        tz.setLocalLocation(location);
        print('[NotificationService] Timezone (direct) → $tzNameRaw');
        return;
      } catch (_) {
        // Raw name was an abbreviation or unknown — fall through to offset map
      }

      // Fallback: map UTC offset → IANA name (covers abbreviations like "MYT", "WIB" etc.)
      final int offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
      const Map<int, String> offsetToTimezone = {
        -720: 'Pacific/Niue',
        -660: 'Pacific/Samoa',
        -600: 'Pacific/Honolulu',
        -570: 'Pacific/Marquesas',
        -540: 'America/Anchorage',
        -480: 'America/Los_Angeles',
        -420: 'America/Denver',
        -360: 'America/Chicago',
        -300: 'America/New_York',
        -270: 'America/Caracas',
        -240: 'America/Halifax',
        -210: 'America/St_Johns',
        -180: 'America/Sao_Paulo',
        -120: 'Atlantic/South_Georgia',
        -60:  'Atlantic/Azores',
        0:    'Europe/London',
        60:   'Europe/Paris',
        120:  'Europe/Helsinki',
        180:  'Europe/Moscow',
        210:  'Asia/Tehran',
        240:  'Asia/Dubai',
        270:  'Asia/Kabul',
        300:  'Asia/Karachi',
        330:  'Asia/Kolkata',
        345:  'Asia/Kathmandu',
        360:  'Asia/Dhaka',
        390:  'Asia/Yangon',
        420:  'Asia/Bangkok',
        480:  'Asia/Kuala_Lumpur', // UTC+8 — Malaysia, Singapore, China, HK
        540:  'Asia/Tokyo',
        570:  'Australia/Adelaide',
        600:  'Australia/Sydney',
        630:  'Pacific/Norfolk',
        660:  'Pacific/Noumea',
        720:  'Pacific/Auckland',
        765:  'Pacific/Chatham',
        780:  'Pacific/Tongatapu',
        840:  'Pacific/Kiritimati',
      };

      final String tzName = offsetToTimezone[offsetMinutes] ?? 'UTC';
      tz.setLocalLocation(tz.getLocation(tzName));
      print('[NotificationService] Timezone (offset fallback) → $tzName (${offsetMinutes}min)');
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('UTC'));
      print('[NotificationService] Timezone hard fallback UTC: $e');
    }
  }

  // ── CHANNEL SETUP ──────────────────────────────────────────────────────────

  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel classChannel = AndroidNotificationChannel(
      _classChannelId,
      'Class Notifications',
      description: 'Notifications for upcoming classes',
      importance: Importance.high,
    );
    const AndroidNotificationChannel taskChannel = AndroidNotificationChannel(
      _taskChannelId,
      'Task Notifications',
      description: 'Notifications for upcoming task deadlines',
      importance: Importance.high,
    );
    const AndroidNotificationChannel examChannel = AndroidNotificationChannel(
      _examChannelId,
      'Exam Notifications',
      description: 'Notifications for upcoming exams',
      importance: Importance.max,
    );
    const AndroidNotificationChannel inviteChannel = AndroidNotificationChannel(
      _inviteChannelId,
      'Invite Notifications',
      description: 'Notifications for timetable shares and group invites',
      importance: Importance.high,
    );
    const AndroidNotificationChannel groupChannel = AndroidNotificationChannel(
      _groupChannelId,
      'Group Activity',
      description: 'Notifications for study group activity',
      importance: Importance.high,
    );
    const AndroidNotificationChannel studyPlanChannel = AndroidNotificationChannel(
      _studyPlanChannelId,
      'Study Plan Notifications',
      description: 'Daily reminders to complete study plans before exams',
      importance: Importance.high,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(classChannel);
      await androidPlugin.createNotificationChannel(taskChannel);
      await androidPlugin.createNotificationChannel(examChannel);
      await androidPlugin.createNotificationChannel(inviteChannel);
      await androidPlugin.createNotificationChannel(groupChannel);
      await androidPlugin.createNotificationChannel(studyPlanChannel);
    }
  }

  Future<void> _requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
    }
  }

  // ── NOTIFICATION TAP ───────────────────────────────────────────────────────

  static void _onNotificationResponse(NotificationResponse response) {
    // Fires when the user taps a notification.
    _handleNotificationTap(response.payload);
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    _handleNotificationTap(response.payload);
  }

  static Future<void> _handleNotificationTap(String? payload) async {
    if (payload == null) return;

    if (payload.startsWith('group:')) {
      // format: group:{groupId}:{tab}:{historyDocId}
      final rest = payload.substring('group:'.length);
      final firstColon = rest.indexOf(':');
      final secondColon = firstColon != -1 ? rest.indexOf(':', firstColon + 1) : -1;
      if (firstColon == -1 || secondColon == -1) return;

      final groupId     = rest.substring(0, firstColon);
      final tab         = int.tryParse(rest.substring(firstColon + 1, secondColon)) ?? 0;
      final historyDocId = rest.substring(secondColon + 1);

      try {
        await FirebaseFirestore.instance
            .collection('notification_history')
            .doc(historyDocId)
            .update({'isRead': true});
      } catch (_) {}

      if (_navigatorKey?.currentState != null) {
        _navigatorKey!.currentState!.pushNamedAndRemoveUntil(
          '/home',
          (route) => false,
          arguments: {'groupId': groupId, 'tab': tab},
        );
      }
    } else if (payload.startsWith('study_plan:')) {
      // format: study_plan:{planId}:{historyDocId}
      final rest = payload.substring('study_plan:'.length);
      final colonIdx = rest.indexOf(':');
      if (colonIdx == -1) return;
      final planId       = rest.substring(0, colonIdx);
      final historyDocId = rest.substring(colonIdx + 1);
      try {
        await FirebaseFirestore.instance
            .collection('notification_history')
            .doc(historyDocId)
            .update({'isRead': true});
      } catch (_) {}
      if (_navigatorKey?.currentState != null) {
        _navigatorKey!.currentState!.pushNamedAndRemoveUntil(
          '/home',
          (route) => false,
          arguments: {'planId': planId},
        );
      }
    } else if (payload.startsWith('calendar:')) {
      final docId = payload.substring('calendar:'.length);
      try {
        await FirebaseFirestore.instance
            .collection('notification_history')
            .doc(docId)
            .update({'isRead': true});
      } catch (_) {}

      if (_navigatorKey?.currentState != null) {
        _navigatorKey!.currentState!.pushNamedAndRemoveUntil(
          '/home',
          (route) => false,
          arguments: {'navIndex': 1},
        );
      }
    } else {
      // Regular scheduled notification (class / exam / task)
      try {
        await FirebaseFirestore.instance
            .collection('notification_history')
            .doc(payload)
            .update({'isRead': true});
      } catch (_) {}
    }
  }

  // ── INVITE NOTIFICATIONS ───────────────────────────────────────────────────

  /// Shows an immediate (non-scheduled) notification for a timetable share or
  /// group invite. Writes a notification_history row with scheduledFor = now
  /// so it appears in the bell feed instantly, then fires the phone notification.
  Future<void> showInviteNotification({
    required String userId,
    required String title,
    required String body,
    required String type,    // 'group_invite' or 'timetable_invite'
    required String eventId,
  }) async {
    // Write history row — scheduledFor = now so it shows immediately
    final docRef = await _firestore.collection('notification_history').add({
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      'eventId': eventId,
      'isRead': false,
      'createdAt': Timestamp.now(),
      'scheduledFor': Timestamp.now(),
    });

    // Unique ID in the 70000–89999 range (avoids class/task/exam ranges)
    final int id = (eventId.hashCode.abs() % 20000) + 70000;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _inviteChannelId,
      'Invite Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: 'calendar:${docRef.id}',
    );
  }

  // ── FCM TOKEN & FOREGROUND HANDLER ────────────────────────────────────────

  Future<void> saveFcmToken(String userId) async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(userId).update({'fcmToken': token});
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _firestore.collection('users').doc(userId).update({'fcmToken': newToken});
      });
    } catch (_) {}
  }

  /// Shows a local notification when FCM arrives while the app is in the
  /// foreground (Android does not auto-display FCM in foreground).
  /// Builds the correct payload so tapping it navigates to the right screen.
  Future<void> handleForegroundFcmMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final data = message.data;
    final type = data['type'] as String? ?? '';

    // Don't show a notification to the user who triggered it
    final senderId  = data['senderId'] as String? ?? '';
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (senderId.isNotEmpty && senderId == currentUid) return;

    final String channelId;
    final String channelName;
    String? payload;

    if (type.startsWith('group_')) {
      channelId   = _groupChannelId;
      channelName = 'Group Activity';
      final groupId      = data['groupId']      ?? '';
      final tab          = data['tab']           ?? '0';
      final historyDocId = data['historyDocId']  ?? '';
      payload = 'group:$groupId:$tab:$historyDocId';
    } else if (type == 'group_invite' || type == 'timetable_invite') {
      channelId   = _inviteChannelId;
      channelName = 'Invite Notifications';
      final historyDocId = data['historyDocId'] ?? '';
      payload = 'calendar:$historyDocId';
    } else {
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      channelId, channelName,
      importance: Importance.high, priority: Priority.high,
    );
    final id = DateTime.now().millisecondsSinceEpoch % 100000;
    await _plugin.show(
      id, notification.title, notification.body,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  // ── GROUP ACTIVITY NOTIFICATIONS ──────────────────────────────────────────

  /// Shows an immediate notification when activity happens in a study group.
  /// Stores groupId, groupName, subject, and tab in notification_history so
  /// the history screen can navigate directly to the right tab when tapped.
  Future<void> showGroupActivityNotification({
    required String userId,
    required String groupId,
    required String groupName,
    required String subject,
    required String title,
    required String body,
    required String type,   // 'group_chat', 'group_event', 'group_poll', etc.
    required int tab,       // 0=chat, 1=milestones, 2=updates, 3=notes
  }) async {
    final docRef = await _firestore.collection('notification_history').add({
      'userId':    userId,
      'title':     title,
      'body':      body,
      'type':      type,
      'groupId':   groupId,
      'groupName': groupName,
      'subject':   subject,
      'tab':       tab,
      'isRead':    false,
      'createdAt':    Timestamp.now(),
      'scheduledFor': Timestamp.now(),
    });

    final int id = (docRef.id.hashCode.abs() % 10000) + 90000;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _groupChannelId,
      'Group Activity',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: 'group:$groupId:$tab:${docRef.id}',
    );
  }

  // ── CORE SCHEDULE METHOD ───────────────────────────────────────────────────

  /// Converts a plain Dart [DateTime] (device local time) to a [tz.TZDateTime]
  /// that is guaranteed to be in the same timezone as the device.
  /// This is the ONLY place we touch timezone conversion so it's easy to audit.
  /// Converts a local [DateTime] to [tz.TZDateTime] for scheduling.
  /// Strategy: convert to UTC first, then wrap in TZDateTime(utc).
  /// This is the most reliable approach — it does not depend on tz.local
  /// being set correctly, and works regardless of DST or timezone name issues.
  tz.TZDateTime _toTZDateTime(DateTime localDt) {
    // localDt is always a plain local DateTime (from DateTime.now() arithmetic).
    // .toUtc() gives us the correct UTC instant.
    // We then wrap it in a TZDateTime(UTC) so flutter_local_notifications
    // schedules at the exact right moment on any device worldwide.
    final utc = localDt.toUtc();
    return tz.TZDateTime.utc(
      utc.year, utc.month, utc.day,
      utc.hour, utc.minute, utc.second,
    );
  }

  /// Schedules a local alarm for [scheduledTime] if:
  ///   (a) the time is still in the future, AND
  ///   (b) it hasn't already been registered (checked via [dedupeKey] in Firestore).
  ///
  /// The dedupe record is written ONLY when a future notification is registered.
  /// Past-time calls return false without writing anything, so closer slots
  /// (e.g. 1-day-before) can still fire even if 3-day-before already passed.
  ///
  /// [scheduledTime] must be **device local time** (plain DateTime arithmetic).
  Future<bool> scheduleNotificationIfNeeded({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String type,
    required String eventId,
    required String userId,
    required String dedupeKey,
  }) async {
    final now = DateTime.now();

    // 1. Past — skip silently, do NOT write dedupe so closer slots still fire
    if (scheduledTime.isBefore(now)) return false;

    // 2. Dedupe — if this key exists the alarm is already registered; skip
    final dedupeDoc =
        _firestore.collection('scheduled_notifications').doc(dedupeKey);
    try {
      final existing = await dedupeDoc.get();
      if (existing.exists) {
        // Re-register the local alarm anyway in case it was lost (app reinstall /
        // OS cleared alarms) — but DON'T add another notification_history row.
        final ed = existing.data()!;
        final existingHistoryId = ed['historyDocId'] as String?;
        final existingEventId   = ed['eventId']     as String?;
        final String? reregPayload = (ed['type'] == 'study_plan' &&
                existingEventId != null &&
                existingHistoryId != null)
            ? 'study_plan:$existingEventId:$existingHistoryId'
            : existingHistoryId;
        await _registerLocalAlarm(id, title, body, scheduledTime, type, reregPayload);
        return false;
      }
    } catch (e) {
      print('Dedupe check error: $e');
    }

    // 3. Write notification_history row (shown in the bell feed when it fires).
    // Use Timestamp.now() (client time) instead of FieldValue.serverTimestamp()
    // so createdAt is never null locally — serverTimestamp() is null until the
    // server round-trip completes, and purgeOldData running in the same session
    // would incorrectly delete the freshly-written row.
    final docRef = await _firestore.collection('notification_history').add({
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      'eventId': eventId,
      'isRead': false,
      'createdAt': Timestamp.now(),
      'scheduledFor': Timestamp.fromDate(scheduledTime),
    });
    // The history entry is written now. Both the bell dot and history screen
    // show it only once scheduledFor <= now (checked client-side every second).

    // 4. Write dedupe record — includes historyDocId so we can reuse payload
    await dedupeDoc.set({
      'userId': userId,
      'eventId': eventId,
      'type': type,
      'notificationId': id,
      'historyDocId': docRef.id,
      'scheduledFor': Timestamp.fromDate(scheduledTime),
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 5. Register the local alarm
    final String notifPayload = type == 'study_plan'
        ? 'study_plan:$eventId:${docRef.id}'
        : docRef.id;
    await _registerLocalAlarm(id, title, body, scheduledTime, type, notifPayload);

    print('[Scheduled] "$title" at $scheduledTime (key: $dedupeKey)');
    return true;
  }

  /// Registers (or re-registers) the OS-level alarm. Safe to call multiple
  /// times — the plugin simply overwrites the alarm for the same [id].
  /// Returns immediately if scheduledTime is already in the past.
  Future<void> _registerLocalAlarm(
    int id,
    String title,
    String body,
    DateTime scheduledTime,
    String type,
    String? payload,
  ) async {
    // Never register an alarm for a time that has already passed
    if (scheduledTime.isBefore(DateTime.now())) return;

    final String channelId = type == 'class'
        ? _classChannelId
        : type == 'exam'
            ? _examChannelId
            : type == 'study_plan'
                ? _studyPlanChannelId
                : _taskChannelId;

    final tz.TZDateTime tzScheduled = _toTZDateTime(scheduledTime);

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      _getChannelName(type),
      importance: type == 'exam' ? Importance.max : Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(body),
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduled,
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  String _getChannelName(String type) {
    switch (type) {
      case 'class':       return 'Class Notifications';
      case 'exam':        return 'Exam Notifications';
      case 'study_plan':  return 'Study Plan Notifications';
      default:            return 'Task Notifications';
    }
  }

  // ── STUDY PLAN SETTINGS CONFIRMATION ──────────────────────────────────────

  /// Fires an immediate local notification confirming study plan reminders are
  /// configured. Shown right after the user saves notification settings so they
  /// know the system is working without having to wait until the scheduled time.
  Future<void> showStudyPlanSettingsConfirmation({required String timeLabel}) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _studyPlanChannelId,
      'Study Plan Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      999998,
      '📖 Study Plan Notifications Active!',
      'Your daily study plan reminders are set for $timeLabel. '
      'You\'ll receive motivational progress updates for each active plan.',
      const NotificationDetails(android: androidDetails),
    );
  }

  // ── CANCEL ─────────────────────────────────────────────────────────────────

  Future<void> cancelNotificationsForEvent(String eventId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final dedupeSnap = await _firestore
        .collection('scheduled_notifications')
        .where('eventId', isEqualTo: eventId)
        .where('userId', isEqualTo: userId)
        .get();
    for (var doc in dedupeSnap.docs) {
      final notifId = doc.data()['notificationId'] as int?;
      if (notifId != null) await _plugin.cancel(notifId);
      await doc.reference.delete();
    }

    // Also remove unread history for this event
    final historySnap = await _firestore
        .collection('notification_history')
        .where('eventId', isEqualTo: eventId)
        .where('isRead', isEqualTo: false)
        .where('userId', isEqualTo: userId)
        .get();
    for (var doc in historySnap.docs) {
      await doc.reference.delete();
    }
  }

  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }

  Future<void> clearAllDedupeRecords(String userId) async {
    final now = DateTime.now();
    final snap = await _firestore
        .collection('scheduled_notifications')
        .where('userId', isEqualTo: userId)
        .get();

    for (var doc in snap.docs) {
      final data = doc.data();
      final historyDocId = data['historyDocId'] as String?;
      final scheduledFor = (data['scheduledFor'] as Timestamp?)?.toDate();

      // Delete the notification_history entry ONLY if it hasn't fired yet.
      // This prevents phantom unread dots for future rescheduled notifications.
      // Already-fired (past) history entries stay so the user's log is intact.
      if (historyDocId != null &&
          scheduledFor != null &&
          scheduledFor.isAfter(now)) {
        try {
          await _firestore
              .collection('notification_history')
              .doc(historyDocId)
              .delete();
        } catch (_) {}
      }
      await doc.reference.delete();
    }
  }

  // ── PURGE OLD DATA ─────────────────────────────────────────────────────────

  /// Purges stale data to keep Firestore lean.
  ///
  /// Rules:
  ///   - notification_history: delete rows where createdAt > 7 days ago
  ///   - scheduled_notifications (dedupe): delete ONLY rows whose scheduledFor
  ///     is in the PAST (already fired). NEVER delete future dedupe keys —
  ///     doing so would cause days-before notifications to never fire.
  ///
  /// Uses single-field queries — no composite Firestore index needed.
  Future<void> purgeOldData(String userId) async {
    final historyCutoff = DateTime.now().subtract(const Duration(days: 7));
    final now           = DateTime.now();

    try {
      // 1. notification_history — delete rows older than 7 days
      final historySnap = await _firestore
          .collection('notification_history')
          .where('userId', isEqualTo: userId)
          .get();

      int historyDeleted = 0;
      for (var doc in historySnap.docs) {
        final raw     = doc.data()['createdAt'];
        final docDate = raw is Timestamp ? raw.toDate() : null;
        // IMPORTANT: if createdAt is null the doc was just written (serverTimestamp
        // hasn't resolved yet) — treat as "just now" and never delete it.
        if (docDate != null && docDate.isBefore(historyCutoff)) {
          await doc.reference.delete();
          historyDeleted++;
        }
      }

      // 2. scheduled_notifications — ONLY delete records that have already fired
      //    (scheduledFor is in the past). Future records are kept so the
      //    dedupe check on next app open can still find them and restore the
      //    OS alarm if needed.
      final dedupeSnap = await _firestore
          .collection('scheduled_notifications')
          .where('userId', isEqualTo: userId)
          .get();

      int dedupeDeleted = 0;
      for (var doc in dedupeSnap.docs) {
        final raw           = doc.data()['scheduledFor'];
        final scheduledDate = raw is Timestamp ? raw.toDate() : null;
        // Only delete if it has already fired (scheduledFor < now)
        if (scheduledDate != null && scheduledDate.isBefore(now)) {
          await doc.reference.delete();
          dedupeDeleted++;
        }
        // If scheduledDate is null (bad data), also clean it up
        if (scheduledDate == null) {
          await doc.reference.delete();
          dedupeDeleted++;
        }
      }

      print('[Purge] $historyDeleted history + $dedupeDeleted dedupe records removed');
    } catch (e) {
      print('[Purge] Non-fatal error: $e');
    }
  }

  // ── PERMISSIONS ────────────────────────────────────────────────────────────

  Future<bool> areNotificationsEnabled() async {
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return false;
    return await androidPlugin.areNotificationsEnabled() ?? false;
  }
}