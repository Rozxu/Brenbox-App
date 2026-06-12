import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

enum GCalConnectResult { success, cancelled, wrongAccount }

class GoogleCalendarService extends ChangeNotifier {
  static final GoogleCalendarService instance = GoogleCalendarService._();
  GoogleCalendarService._();

  static const _scope = 'https://www.googleapis.com/auth/calendar';

  final _signIn = GoogleSignIn(scopes: [_scope]);
  GoogleSignInAccount? _account;

  bool get isConnected => _account != null;
  String? get accountEmail => _account?.email;

  // Attempt silent sign-in on app start — reconnects if the user connected before
  Future<void> tryRestoreSession() async {
    // If already connected (e.g. connected during sign-up in the same session),
    // don't overwrite with signInSilently — it may return null due to a race
    // condition where the token hasn't fully persisted yet.
    if (_account != null) return;

    _account = await _signIn.signInSilently();
    if (_account == null) return;

    final expectedEmail =
        FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    if (expectedEmail != null &&
        _account!.email.toLowerCase() != expectedEmail) {
      await _signIn.signOut();
      _account = null;
      return;
    }

    notifyListeners();
  }

  Future<GCalConnectResult> connect() async {
    try {
      // Sign out first so signIn() always presents a fresh account-picker +
      // consent screen. Unlike disconnect(), signOut() does NOT revoke OAuth
      // tokens (so Firebase Auth is unaffected) but it clears the cached
      // account, preventing Android from silently reusing a session that may
      // not yet have the calendar scope granted.
      try { await _signIn.signOut(); } catch (_) {}
      _account = await _signIn.signIn();
      if (_account == null) return GCalConnectResult.cancelled;

      final expectedEmail =
          FirebaseAuth.instance.currentUser?.email?.toLowerCase();
      if (expectedEmail != null &&
          _account!.email.toLowerCase() != expectedEmail) {
        await _signIn.signOut();
        _account = null;
        return GCalConnectResult.wrongAccount;
      }

      notifyListeners();
      return GCalConnectResult.success;
    } catch (_) {
      return GCalConnectResult.cancelled;
    }
  }

  Future<void> disconnect() async {
    await _signIn.signOut();
    _account = null;
    notifyListeners();
  }

  Future<gcal.CalendarApi?> _api() async {
    if (_account == null) return null;
    try {
      final headers = await _account!.authHeaders;
      return gcal.CalendarApi(_AuthClient(headers));
    } catch (_) {
      return null;
    }
  }

  // ── Fetch ────────────────────────────────────────────────────────────────────

  Future<List<gcal.Event>> fetchEventsForDate(DateTime date) async {
    final api = await _api();
    if (api == null) return [];
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    try {
      final result = await api.events.list(
        'primary',
        timeMin: start.toUtc(),
        timeMax: end.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );
      return (result.items ?? [])
          .where((e) => e.status != 'cancelled')
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<gcal.Event>> fetchEventsForRange(DateTime start, DateTime end) async {
    final api = await _api();
    if (api == null) return [];
    try {
      final result = await api.events.list(
        'primary',
        timeMin: start.toUtc(),
        timeMax: end.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );
      return (result.items ?? [])
          .where((e) => e.status != 'cancelled')
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches all events across ALL of the user's calendars (primary, holidays,
  /// shared, subscribed) for a date range, following pagination on each calendar.
  Future<List<gcal.Event>> fetchAllEventsInRange(
      DateTime start, DateTime end) async {
    final api = await _api();
    if (api == null) return [];

    // Build calendar ID list — fall back to primary only if listing fails
    List<String> calendarIds;
    try {
      final calList = await api.calendarList.list();
      calendarIds = (calList.items ?? [])
          .map((c) => c.id)
          .whereType<String>()
          .toList();
    } catch (_) {
      calendarIds = ['primary'];
    }
    if (calendarIds.isEmpty) calendarIds = ['primary'];

    final allEvents = <gcal.Event>[];

    for (final calendarId in calendarIds) {
      try {
        String? pageToken;
        do {
          final result = await api.events.list(
            calendarId,
            timeMin: start.toUtc(),
            timeMax: end.toUtc(),
            singleEvents: true,
            orderBy: 'startTime',
            maxResults: 2500,
            pageToken: pageToken,
          );
          allEvents.addAll(
            (result.items ?? []).where((e) => e.status != 'cancelled'),
          );
          pageToken = result.nextPageToken;
        } while (pageToken != null);
      } catch (_) {
        // Skip any calendar we can't access
        continue;
      }
    }

    return allEvents;
  }

  Future<List<gcal.Event>> fetchUpcomingEvents({int days = 7}) async {
    final api = await _api();
    if (api == null) return [];
    final now = DateTime.now();
    try {
      final result = await api.events.list(
        'primary',
        timeMin: now.toUtc(),
        timeMax: now.add(Duration(days: days)).toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 15,
      );
      return (result.items ?? [])
          .where((e) => e.status != 'cancelled')
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Create ───────────────────────────────────────────────────────────────────

  Future<gcal.Event?> createEvent({
    required String title,
    String? description,
    String? location,
    required DateTime start,
    required DateTime end,
  }) async {
    final api = await _api();
    if (api == null) return null;
    try {
      return await api.events.insert(
        gcal.Event(
          summary: title,
          description: description,
          location: location,
          start: gcal.EventDateTime(dateTime: start.toUtc()),
          end: gcal.EventDateTime(dateTime: end.toUtc()),
        ),
        'primary',
      );
    } catch (_) {
      return null;
    }
  }

  // ── Update ───────────────────────────────────────────────────────────────────

  Future<gcal.Event?> updateEvent({
    required String eventId,
    required String title,
    String? description,
    String? location,
    required DateTime start,
    required DateTime end,
  }) async {
    final api = await _api();
    if (api == null) return null;
    try {
      final result = await api.events.update(
        gcal.Event(
          summary: title,
          description: description,
          location: location,
          start: gcal.EventDateTime(dateTime: start.toUtc()),
          end: gcal.EventDateTime(dateTime: end.toUtc()),
        ),
        'primary',
        eventId,
      );
      notifyListeners();
      return result;
    } catch (_) {
      return null;
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────────

  Future<bool> deleteEvent(String eventId) async {
    final api = await _api();
    if (api == null) return false;
    try {
      await api.events.delete('primary', eventId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}

// Injects Google auth headers into every outgoing request
class _AuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final _inner = http.Client();
  _AuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
