import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({Key? key}) : super(key: key);

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState
    extends State<NotificationHistoryScreen> {
  // _now is updated on pull-to-refresh so newly-fired notifications
  // (scheduledFor <= _now) appear immediately after a swipe-down.
  DateTime _now = DateTime.now();

  Future<void> _refresh() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _now = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();
    final firestore = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.dmMono(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final batch = firestore.batch();
              final snapshot = await firestore
                  .collection('notification_history')
                  .where('userId', isEqualTo: user.uid)
                  .where('isRead', isEqualTo: false)
                  .get();
              for (var doc in snapshot.docs) {
                // Only mark docs whose scheduledFor has already passed
                final ts =
                    (doc.data()['scheduledFor'] as Timestamp?)?.toDate();
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
      body: StreamBuilder<QuerySnapshot>(
        // Single-field query — no composite index needed.
        // The stream is real-time: any new doc written by NotificationService
        // appears here immediately. We sort client-side.
        stream: firestore
            .collection('notification_history')
            .where('userId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF6B7280)));
          }

          if (snapshot.hasError) {
            return _scrollableEmpty(
              context,
              icon: Icons.error_outline,
              message: 'Could not load notifications',
              sub: 'Pull down to retry',
            );
          }

          final allDocs = List<QueryDocumentSnapshot>.from(
              snapshot.data?.docs ?? []);

          // Only show notifications that have already fired
          // Use _now (updated on refresh) so swipe-down reveals new notifications
          final fired = allDocs.where((doc) {
            final ts = (doc.data()
                    as Map<String, dynamic>)['scheduledFor'] as Timestamp?;
            if (ts == null) return false;
            return !ts.toDate().isAfter(_now);
          }).toList();

          if (fired.isEmpty) {
            return _scrollableEmpty(
              context,
              icon: Icons.notifications_none,
              message: 'No notifications yet',
              sub: 'Pull down to refresh',
            );
          }

          // Sort most-recent first
          fired.sort((a, b) {
            final aMs =
                ((a.data() as Map)['scheduledFor'] as Timestamp?)
                        ?.millisecondsSinceEpoch ??
                    0;
            final bMs =
                ((b.data() as Map)['scheduledFor'] as Timestamp?)
                        ?.millisecondsSinceEpoch ??
                    0;
            return bMs.compareTo(aMs);
          });

          return RefreshIndicator(
            onRefresh: _refresh,
            color: const Color(0xFFB90000),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: fired.take(50).length,
              itemBuilder: (context, index) {
                final data =
                    fired[index].data() as Map<String, dynamic>;
                return _NotificationCard(
                  docId: fired[index].id,
                  title: data['title'] ?? '',
                  body: data['body'] ?? '',
                  type: data['type'] ?? 'class',
                  isRead: data['isRead'] ?? false,
                  scheduledFor:
                      (data['scheduledFor'] as Timestamp?)?.toDate(),
                  firestore: firestore,
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// A scrollable empty state so RefreshIndicator works even when empty.
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

// =============================================================================
// Notification card
// =============================================================================

class _NotificationCard extends StatelessWidget {
  final String docId;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime? scheduledFor;
  final FirebaseFirestore firestore;

  const _NotificationCard({
    required this.docId,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.scheduledFor,
    required this.firestore,
  });

  Color get _typeColor {
    switch (type) {
      case 'class': return const Color(0xFFB90000);
      case 'exam':  return const Color(0xFF9AB900);
      case 'task':  return const Color(0xFF008BB9);
      default:      return const Color(0xFF6B7280);
    }
  }

  IconData get _typeIcon {
    switch (type) {
      case 'class': return Icons.school_outlined;
      case 'exam':  return Icons.assignment_outlined;
      case 'task':  return Icons.task_alt;
      default:      return Icons.notifications_outlined;
    }
  }

  String get _typeLabel {
    switch (type) {
      case 'class': return 'CLASS';
      case 'exam':  return 'EXAM';
      case 'task':  return 'TASK';
      default:      return 'INFO';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (!isRead) {
          await firestore
              .collection('notification_history')
              .doc(docId)
              .update({'isRead': true});
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFFFF8F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRead ? Colors.black.withOpacity(0.2) : Colors.black,
            width: isRead ? 1 : 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isRead
                      ? _typeColor.withOpacity(0.3)
                      : _typeColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_typeIcon,
                    color: isRead ? _typeColor : Colors.white, size: 22),
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
                            color: _typeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: _typeColor.withOpacity(0.5)),
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
                            ? const Color(0xFF6B7280)
                            : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: GoogleFonts.dmMono(
                          fontSize: 11,
                          color: const Color(0xFF6B7280),
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
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM, h:mm a').format(dt);
  }
}