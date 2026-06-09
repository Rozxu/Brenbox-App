import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_scheduler.dart';
import '../services/notification_service.dart';
import 'package:intl/intl.dart';
import '../app_preferences.dart';

class EditGroupEventScreen extends StatefulWidget {
  final String groupId;
  final String messageId;
  final Map<String, dynamic> eventData;

  const EditGroupEventScreen({
    Key? key,
    required this.groupId,
    required this.messageId,
    required this.eventData,
  }) : super(key: key);

  @override
  State<EditGroupEventScreen> createState() => _EditGroupEventScreenState();
}

class _EditGroupEventScreenState extends State<EditGroupEventScreen> {
  static const kGroup = Color(0xFF7C3AED);

  late TextEditingController _titleController;
  late TextEditingController _detailsController;
  String? _selectedType;
  late DateTime _eventDate;
  late TimeOfDay _eventTime;
  bool _isSaving = false;

  final List<String> _eventTypes = [
    'Meeting',
    'Presentation',
    'Study Session',
    'Workshop',
    'Discussion',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.eventData['title'] as String? ?? '',
    );
    _detailsController = TextEditingController(
      text: widget.eventData['details'] as String? ?? '',
    );
    _selectedType = widget.eventData['eventSubType'] as String? ??
        widget.eventData['eventType'] as String? ??
        'Meeting';
    final ts = widget.eventData['eventDate'] as Timestamp?;
    final dt = ts?.toDate() ?? DateTime.now();
    _eventDate = dt;
    _eventTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final isDark = AppColors.isDark(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (_, child) => Theme(
        data: isDark
            ? ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: kGroup,
                  onPrimary: Colors.white,
                  surface: Color(0xFF252D47),
                  onSurface: Colors.white,
                ),
              )
            : ThemeData.light().copyWith(
                colorScheme: const ColorScheme.light(primary: kGroup),
              ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _eventDate = picked);
  }

  Future<void> _selectTime() async {
    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (_) => _CustomTimePickerDialog(initialTime: _eventTime),
    );
    if (picked != null && mounted) setState(() => _eventTime = picked);
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      _showError('Validation Error', 'Please enter a title');
      return;
    }
    if (_selectedType == null) {
      _showError('Validation Error', 'Please select an event type');
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final dt = DateTime(
        _eventDate.year,
        _eventDate.month,
        _eventDate.day,
        _eventTime.hour,
        _eventTime.minute,
      );
      await FirebaseFirestore.instance
          .collection('user_group_events')
          .doc(widget.messageId)
          .update({
        'title': _titleController.text.trim(),
        'details': _detailsController.text.trim(),
        'eventType': _selectedType,
        'eventDate': Timestamp.fromDate(dt),
      });
      // Cancel stale alarms/history for this event so fresh ones are created
      // immediately with the new time — avoids history-screen delay or blanks.
      await NotificationService().cancelNotificationsForEvent(widget.messageId);
      NotificationScheduler().scheduleGroupEventsOnly().catchError((_) {});
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.card(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.border(context), width: 2),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Updated!',
                    style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Text('Group event has been successfully updated.',
              style: GoogleFonts.dmMono(fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('OK',
                  style: GoogleFonts.dmMono(
                      fontWeight: FontWeight.bold,
                      color: AppColors.text(context))),
            ),
          ],
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) _showError('Update Error', 'Failed to update. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border(context), width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.error_outline,
                color: Color(0xFFB90000), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: GoogleFonts.dmMono(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ],
        ),
        content: Text(message, style: GoogleFonts.dmMono(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK',
                style: GoogleFonts.dmMono(
                    fontWeight: FontWeight.bold,
                    color: AppColors.text(context))),
          ),
        ],
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.chipBg(context),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        title: Text(
          'EDIT GROUP EVENT',
          style: GoogleFonts.dmMono(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            _buildLabel('Event Type'),
            const SizedBox(height: 8),
            _buildTypeSelector(),
            const SizedBox(height: 16),

            _buildLabel('Title'),
            const SizedBox(height: 8),
            _buildTextField(_titleController, 'Event title'),
            const SizedBox(height: 16),

            _buildLabel('Description (Optional)'),
            const SizedBox(height: 8),
            _buildMultilineTextField(_detailsController, 'Event description'),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Date'),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _selectDate,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.input(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.border(context), width: 2),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat('EEE, dd MMM yyyy')
                                      .format(_eventDate),
                                  style: GoogleFonts.dmMono(fontSize: 14),
                                ),
                              ),
                              const Icon(Icons.calendar_today, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Time'),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _selectTime,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.input(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.border(context), width: 2),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatTimeOfDay(_eventTime),
                                  style: GoogleFonts.dmMono(fontSize: 14)),
                              const Icon(Icons.access_time, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                          color: AppColors.border(context), width: 2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancel',
                        style: GoogleFonts.dmMono(
                            color: AppColors.text(context),
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGroup,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text('Update Group Event',
                            style: GoogleFonts.dmMono(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text,
        style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.bold));
  }

  Widget _buildTextField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: GoogleFonts.dmMono(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmMono(
            fontSize: 14, color: AppColors.subtext(context)),
        filled: true,
        fillColor: AppColors.input(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border(context), width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border(context), width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border(context), width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildMultilineTextField(
      TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: GoogleFonts.dmMono(fontSize: 14),
      maxLines: 5,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmMono(
            fontSize: 14, color: AppColors.subtext(context)),
        filled: true,
        fillColor: AppColors.input(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border(context), width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border(context), width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border(context), width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) {
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
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text('Select Event Type',
                          style: GoogleFonts.dmMono(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      itemCount: _eventTypes.length,
                      itemBuilder: (context, index) {
                        final type = _eventTypes[index];
                        return ListTile(
                          title: Text(type,
                              style: GoogleFonts.dmMono(fontSize: 14)),
                          trailing: _selectedType == type
                              ? const Icon(Icons.check, color: kGroup)
                              : null,
                          onTap: () {
                            setState(() => _selectedType = type);
                            Navigator.pop(context);
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
            Expanded(
              child: Text(
                _selectedType ?? 'Event Type',
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  color: _selectedType != null
                      ? AppColors.text(context)
                      : AppColors.subtext(context),
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Custom Time Picker Dialog
// =============================================================================

class _CustomTimePickerDialog extends StatefulWidget {
  final TimeOfDay? initialTime;
  const _CustomTimePickerDialog({this.initialTime});

  @override
  State<_CustomTimePickerDialog> createState() =>
      _CustomTimePickerDialogState();
}

class _CustomTimePickerDialogState extends State<_CustomTimePickerDialog> {
  static const _kAccent = Color(0xFF7C3AED);

  late int _hour;
  late int _minute;
  late bool _isAm;
  bool _editingHour = false;
  bool _editingMinute = false;
  late TextEditingController _hourCtrl;
  late TextEditingController _minuteCtrl;
  late FocusNode _hourFocus;
  late FocusNode _minuteFocus;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTime ?? TimeOfDay.now();
    _isAm = t.period == DayPeriod.am;
    _hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    _minute = t.minute;
    _hourCtrl = TextEditingController(text: _hour.toString().padLeft(2, '0'));
    _minuteCtrl =
        TextEditingController(text: _minute.toString().padLeft(2, '0'));
    _hourFocus = FocusNode()
      ..addListener(() {
        if (_hourFocus.hasFocus) {
          _hourCtrl.selection =
              TextSelection(baseOffset: 0, extentOffset: _hourCtrl.text.length);
          setState(() => _editingHour = true);
        } else {
          _commitHour();
          setState(() => _editingHour = false);
        }
      });
    _minuteFocus = FocusNode()
      ..addListener(() {
        if (_minuteFocus.hasFocus) {
          _minuteCtrl.selection = TextSelection(
              baseOffset: 0, extentOffset: _minuteCtrl.text.length);
          setState(() => _editingMinute = true);
        } else {
          _commitMinute();
          setState(() => _editingMinute = false);
        }
      });
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  void _commitHour() {
    final v = int.tryParse(_hourCtrl.text);
    if (v != null && v >= 1 && v <= 12) setState(() => _hour = v);
    _hourCtrl.text = _hour.toString().padLeft(2, '0');
  }

  void _commitMinute() {
    final v = int.tryParse(_minuteCtrl.text);
    if (v != null && v >= 0 && v <= 59) setState(() => _minute = v);
    _minuteCtrl.text = _minute.toString().padLeft(2, '0');
  }

  TimeOfDay _toTimeOfDay() {
    int h = _hour % 12;
    if (!_isAm) h += 12;
    return TimeOfDay(hour: h, minute: _minute);
  }

  void _incrementHour(int delta) {
    setState(() {
      _hour = ((_hour - 1 + delta) % 12 + 12) % 12 + 1;
      _hourCtrl.text = _hour.toString().padLeft(2, '0');
    });
  }

  void _incrementMinute(int delta) {
    setState(() {
      _minute = (_minute + delta + 60) % 60;
      _minuteCtrl.text = _minute.toString().padLeft(2, '0');
    });
  }

  Future<void> _openDial() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTimeOfDay(),
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: _kAccent,
            onPrimary: Colors.white,
            surface: AppColors.card(context),
            onSurface: AppColors.text(context),
          ),
          timePickerTheme: TimePickerThemeData(
            backgroundColor: AppColors.card(context),
            dialHandColor: _kAccent,
            dialBackgroundColor: AppColors.fieldBg(context),
            hourMinuteTextColor: AppColors.text(context),
            hourMinuteColor: AppColors.fieldBg(context),
            dayPeriodTextColor: AppColors.text(context),
            dayPeriodColor: AppColors.fieldBg(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.border(context), width: 2),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _isAm = picked.period == DayPeriod.am;
        _hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
        _minute = picked.minute;
        _hourCtrl.text = _hour.toString().padLeft(2, '0');
        _minuteCtrl.text = _minute.toString().padLeft(2, '0');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _hour.toString().padLeft(2, '0');
    final m = _minute.toString().padLeft(2, '0');
    final period = _isAm ? 'AM' : 'PM';

    return Dialog(
      backgroundColor: AppColors.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border(context), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select Time',
                style: GoogleFonts.dmMono(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _openDial,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.fieldBg(context),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.border(context), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.access_time, size: 20, color: _kAccent),
                    const SizedBox(width: 10),
                    Text('$h:$m $period',
                        style: GoogleFonts.dmMono(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.touch_app,
                              size: 12, color: _kAccent),
                          const SizedBox(width: 4),
                          Text('Use dial',
                              style: GoogleFonts.dmMono(
                                  fontSize: 10, color: _kAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Divider(color: AppColors.border(context))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('or type manually',
                      style: GoogleFonts.dmMono(
                          fontSize: 10, color: AppColors.subtext(context))),
                ),
                Expanded(child: Divider(color: AppColors.border(context))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GESpinnerField(
                  controller: _hourCtrl,
                  focusNode: _hourFocus,
                  label: 'HH',
                  onUp: () => _incrementHour(1),
                  onDown: () => _incrementHour(-1),
                  onSubmitted: (_) {
                    _commitHour();
                    _minuteFocus.requestFocus();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(':',
                      style: GoogleFonts.dmMono(
                          fontSize: 28, fontWeight: FontWeight.bold)),
                ),
                _GESpinnerField(
                  controller: _minuteCtrl,
                  focusNode: _minuteFocus,
                  label: 'MM',
                  onUp: () => _incrementMinute(1),
                  onDown: () => _incrementMinute(-1),
                  onSubmitted: (_) => _commitMinute(),
                ),
                const SizedBox(width: 14),
                _GEAmPmToggle(
                    isAm: _isAm, onChanged: (v) => setState(() => _isAm = v)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side:
                          BorderSide(color: AppColors.border(context), width: 2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Cancel',
                        style: GoogleFonts.dmMono(
                            color: AppColors.text(context),
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (_editingHour) _commitHour();
                      if (_editingMinute) _commitMinute();
                      Navigator.pop(context, _toTimeOfDay());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Confirm',
                        style: GoogleFonts.dmMono(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Spinner field
// =============================================================================

class _GESpinnerField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ValueChanged<String> onSubmitted;

  const _GESpinnerField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.onUp,
    required this.onDown,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GEArrowBtn(icon: Icons.keyboard_arrow_up, onTap: onUp),
        const SizedBox(height: 4),
        SizedBox(
          width: 68,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 2,
            onSubmitted: onSubmitted,
            style: GoogleFonts.dmMono(
                fontSize: 26, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              counterText: '',
              hintText: label,
              hintStyle: GoogleFonts.dmMono(
                  fontSize: 18, color: AppColors.subtext(context)),
              filled: true,
              fillColor: AppColors.input(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: AppColors.border(context), width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: AppColors.border(context), width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: Color(0xFF7C3AED), width: 2.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _GEArrowBtn(icon: Icons.keyboard_arrow_down, onTap: onDown),
      ],
    );
  }
}

class _GEArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GEArrowBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 68,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.fieldBg(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Icon(icon, size: 22, color: AppColors.subtext(context)),
      ),
    );
  }
}

// =============================================================================
// AM / PM toggle
// =============================================================================

class _GEAmPmToggle extends StatelessWidget {
  final bool isAm;
  final ValueChanged<bool> onChanged;
  const _GEAmPmToggle({required this.isAm, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GEPeriodBtn(
            label: 'AM', selected: isAm, onTap: () => onChanged(true)),
        const SizedBox(height: 6),
        _GEPeriodBtn(
            label: 'PM', selected: !isAm, onTap: () => onChanged(false)),
      ],
    );
  }
}

class _GEPeriodBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _GEPeriodBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const kAccent = Color(0xFF7C3AED);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? kAccent : AppColors.input(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? kAccent : AppColors.border(context),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.dmMono(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : AppColors.subtext(context),
          ),
        ),
      ),
    );
  }
}
