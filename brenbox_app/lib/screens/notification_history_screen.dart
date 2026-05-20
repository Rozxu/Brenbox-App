import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'study_group_screen.dart';
import 'study_plan_screen.dart';
import '../app_preferences.dart';

class NotificationHistoryScreen extends StatefulWidget {
  final VoidCallback? onGoToCalendar;

  const NotificationHistoryScreen({Key? key, this.onGoToCalendar})
      : super(key: key);

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState
    extends State<NotificationHistoryScreen>
    with WidgetsBindingObserver {
  DateTime _now = DateTime.now();
  Timer? _ticker;

  // Single stable subscription — avoids re-creating the Firestore stream on
  // every setState call (which would cause a loading-spinner flash each tick).
  StreamSubscription<QuerySnapshot>? _histSub;
  List<QueryDocumentSnapshot> _docs   = [];
  bool _loading  = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _histSub = FirebaseFirestore.instance
          .collection('notification_history')
          .where('userId', isEqualTo: user.uid)
          .snapshots()
          .listen((snap) {
        if (mounted) {
          setState(() {
            _docs     = List<QueryDocumentSnapshot>.from(snap.docs);
            _loading  = false;
            _hasError = false;
          });
        }
      }, onError: (_) {
        if (mounted) setState(() { _loading = false; _hasError = true; });
      });

    } else {
      _loading = false;
    }
  }

  // Fires immediately when the user returns to the app — no ticker delay.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _now = DateTime.now());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _histSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _now = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();
    final firestore = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.dmMono(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.text(context)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Mark only already-fired (past) unread docs as read — uses the
              // cached _docs so no extra Firestore round-trip is needed.
              final batch = firestore.batch();
              for (final doc in _docs) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['isRead'] as bool? ?? false) continue;
                final ts = (data['scheduledFor'] as Timestamp?)?.toDate();
                if (ts != null && !ts.isAfter(_now)) {
                  batch.update(doc.reference, {'isRead': true});
                }
              }
              await batch.commit();
            },
            child: Text(
              'Mark all read',
              style: GoogleFonts.dmMono(
                  fontSize: 11, color: const Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
      body: _buildBody(context, firestore),
    );
  }

  Widget _buildBody(BuildContext context, FirebaseFirestore firestore) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF6B7280)));
    }

    if (_hasError) {
      return _scrollableEmpty(
        context,
        icon: Icons.error_outline,
        message: 'Could not load notifications',
        sub: 'Pull down to retry',
      );
    }

    int tsMs(QueryDocumentSnapshot d) =>
        ((d.data() as Map)['scheduledFor'] as Timestamp?)
            ?.millisecondsSinceEpoch ?? 0;

    // Only show notifications that have already fired (scheduledFor <= now).
    final fired = _docs.where((doc) {
      final ts = (doc.data() as Map<String, dynamic>)['scheduledFor'] as Timestamp?;
      return ts != null && !ts.toDate().isAfter(_now);
    }).toList()
      ..sort((a, b) => tsMs(b).compareTo(tsMs(a))); // most-recent first

    if (fired.isEmpty) {
      return _scrollableEmpty(
        context,
        icon: Icons.notifications_none,
        message: 'No notifications yet',
        sub: 'Pull down to refresh',
      );
    }

    final items = fired.take(80).map((doc) => _HistoryItem(doc)).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFFB90000),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final doc  = items[index].doc;
          final data = doc.data() as Map<String, dynamic>;
          return _NotificationCard(
            docId:        doc.id,
            title:        data['title']  ?? '',
            body:         data['body']   ?? '',
            type:         data['type']   ?? 'class',
            isRead:       data['isRead'] ?? false,
            isUpcoming:   false,
            scheduledFor: (data['scheduledFor'] as Timestamp?)?.toDate(),
            firestore:    firestore,
            onGoToCalendar: widget.onGoToCalendar,
            groupId:   data['groupId']   as String?,
            groupName: data['groupName'] as String?,
            subject:   data['subject']   as String?,
            tab:       data['tab']       as int?,
            eventId:   data['eventId']   as String?,
          );
        },
      ),
    );
  }

  Widget _scrollableEmpty(
    BuildContext context, {
    required IconData icon,
    required String message,
    required String sub,
  }) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFFB90000),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 64, color: const Color(0xFF6B7280)),
                  const SizedBox(height: 16),
                  Text(message,
                      style: GoogleFonts.dmMono(
                          fontSize: 14,
                          color: const Color(0xFF6B7280))),
                  const SizedBox(height: 8),
                  Text(sub,
                      style: GoogleFonts.dmMono(
                          fontSize: 11,
                          color: const Color(0xFF9CA3AF))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryItem {
  final QueryDocumentSnapshot doc;
  const _HistoryItem(this.doc);
}

// =============================================================================
// Notification card
// =============================================================================

class _NotificationCard extends StatelessWidget {
  final String docId;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final bool isUpcoming;
  final DateTime? scheduledFor;
  final FirebaseFirestore firestore;
  final VoidCallback? onGoToCalendar;

  // Group activity fields (null for non-group notifications)
  final String? groupId;
  final String? groupName;
  final String? subject;
  final int?    tab;

  // Invite event ID (for checking if invite was already acted on)
  final String? eventId;

  const _NotificationCard({
    required this.docId,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.isUpcoming,
    required this.scheduledFor,
    required this.firestore,
    this.onGoToCalendar,
    this.groupId,
    this.groupName,
    this.subject,
    this.tab,
    this.eventId,
  });

  bool get _isInviteType =>
      type == 'group_invite' || type == 'timetable_invite';

  bool get _isGroupActivityType =>
      type == 'group_chat'      ||
      type == 'group_event'     ||
      type == 'group_poll'      ||
      type == 'group_milestone' ||
      type == 'group_update'    ||
      type == 'group_note';

  Color get _typeColor {
    switch (type) {
      case 'class':            return const Color(0xFFB90000);
      case 'exam':             return const Color(0xFF9AB900);
      case 'task':             return const Color(0xFF008BB9);
      case 'group_invite':     return const Color(0xFF7C3AED);
      case 'timetable_invite': return const Color(0xFF0D9488);
      case 'group_chat':       return const Color(0xFF2563EB);
      case 'group_event':      return const Color(0xFF7C3AED);
      case 'group_poll':       return const Color(0xFF7C3AED);
      case 'group_milestone':  return const Color(0xFF7C3AED);
      case 'group_update':     return const Color(0xFF7C3AED);
      case 'group_note':       return const Color(0xFF7C3AED);
      case 'study_plan':       return const Color(0xFF00BCD4);
      default:                 return const Color(0xFF6B7280);
    }
  }

  IconData get _typeIcon {
    switch (type) {
      case 'class':            return Icons.school_outlined;
      case 'exam':             return Icons.assignment_outlined;
      case 'task':             return Icons.task_alt;
      case 'group_invite':     return Icons.group_add_outlined;
      case 'timetable_invite': return Icons.calendar_month_outlined;
      case 'group_chat':       return Icons.chat_bubble_outline;
      case 'group_event':      return Icons.event_outlined;
      case 'group_poll':       return Icons.poll_outlined;
      case 'group_milestone':  return Icons.check_box_outlined;
      case 'group_update':     return Icons.campaign_outlined;
      case 'group_note':       return Icons.sticky_note_2_outlined;
      case 'study_plan':       return Icons.checklist_rounded;
      default:                 return Icons.notifications_outlined;
    }
  }

  String get _typeLabel {
    switch (type) {
      case 'class':            return 'CLASS';
      case 'exam':             return 'EXAM';
      case 'task':             return 'TASK';
      case 'group_invite':     return 'INVITE';
      case 'timetable_invite': return 'SHARE';
      case 'group_chat':       return 'CHAT';
      case 'group_event':      return 'EVENT';
      case 'group_poll':       return 'POLL';
      case 'group_milestone':  return 'TASK';
      case 'group_update':     return 'UPDATE';
      case 'group_note':       return 'NOTE';
      case 'study_plan':       return 'PLAN';
      default:                 return 'INFO';
    }
  }

  Future<void> _handleTap(BuildContext context) async {
    // Mark as read
    if (!isRead) {
      await firestore
          .collection('notification_history')
          .doc(docId)
          .update({'isRead': true});
    }

    if (!context.mounted) return;

    if (type == 'study_plan') {
      if (eventId == null) return;
      final planDoc = await firestore.collection('study_plans').doc(eventId).get();
      if (!context.mounted) return;
      if (!planDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Study plan no longer exists.',
              style: GoogleFonts.dmMono(fontSize: 12)),
          backgroundColor: const Color(0xFF6B7280),
        ));
        return;
      }
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudyPlanDetailScreen(
            planId: eventId!,
            data: planDoc.data()!,
          ),
        ),
      );
    } else if (_isGroupActivityType) {
      if (groupId == null) return;
      // Check if group still exists
      final groupDoc = await firestore.collection('study_groups').doc(groupId).get();
      if (!context.mounted) return;
      if (!groupDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'This group no longer exists. It may have been deleted.',
            style: GoogleFonts.dmMono(fontSize: 12),
          ),
          backgroundColor: const Color(0xFF6B7280),
        ));
        return;
      }
      final data       = groupDoc.data()!;
      final gName      = data['name']    as String? ?? groupName ?? '';
      final gSubject   = data['subject'] as String? ?? subject   ?? '';
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudyGroupScreen(
            groupId:    groupId!,
            groupName:  gName,
            subject:    gSubject,
            initialTab: tab ?? 0,
          ),
        ),
      );
    } else if (_isInviteType) {
      // Check if invite is still pending
      final collection = type == 'group_invite' ? 'group_invitations' : 'timetable_shares';
      if (eventId != null) {
        final inviteDoc = await firestore.collection(collection).doc(eventId).get();
        if (!context.mounted) return;
        if (!inviteDoc.exists ||
            (inviteDoc.data()?['status'] as String?) != 'pending') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'You have already responded to this invite.',
              style: GoogleFonts.dmMono(fontSize: 12),
            ),
            backgroundColor: const Color(0xFF6B7280),
          ));
          return;
        }
      }
      if (onGoToCalendar != null && context.mounted) {
        Navigator.pop(context);
        onGoToCalendar!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isRead
              ? AppColors.card(context)
              : (AppColors.isDark(context)
                  ? const Color(0xFF1E3560)
                  : const Color(0xFFFFF8F8)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRead ? AppColors.border(context).withValues(alpha: 0.2) : AppColors.border(context),
            width: isRead ? 1 : 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isUpcoming
                          ? _typeColor.withValues(alpha: 0.12)
                          : (isRead ? _typeColor.withValues(alpha: 0.3) : _typeColor),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _typeIcon,
                      color: isUpcoming
                          ? _typeColor
                          : (isRead ? _typeColor : Colors.white),
                      size: 22,
                    ),
                  ),
                  if (isUpcoming)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _typeColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(Icons.schedule, color: Colors.white, size: 9),
                      ),
                    ),
                ],
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
                            color: _typeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: _typeColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(_typeLabel,
                              style: GoogleFonts.dmMono(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: _typeColor)),
                        ),
                        const Spacer(),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFB90000),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: GoogleFonts.dmMono(
                        fontSize: 13,
                        fontWeight:
                            isRead ? FontWeight.normal : FontWeight.bold,
                        color: isRead
                            ? AppColors.subtext(context)
                            : AppColors.text(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: GoogleFonts.dmMono(
                          fontSize: 11,
                          color: AppColors.subtext(context),
                          height: 1.4),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (scheduledFor != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _relativeTime(scheduledFor!),
                        style: GoogleFonts.dmMono(
                            fontSize: 10,
                            color: const Color(0xFF9CA3AF)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.isNegative) {
      // Future (upcoming)
      final ahead = dt.difference(now);
      if (ahead.inMinutes < 60) return 'in ${ahead.inMinutes}m';
      if (ahead.inHours < 24)   return 'in ${ahead.inHours}h';
      if (ahead.inDays < 7)     return 'in ${ahead.inDays}d';
      return DateFormat('dd MMM, h:mm a').format(dt);
    }
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return DateFormat('dd MMM, h:mm a').format(dt);
  }
}