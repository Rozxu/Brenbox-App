import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // ================= LOAD USERNAME =================
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

  // ================= LOGOUT =================
  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // ================= GET WEEK DATES =================
  List<DateTime> _getWeekDates() {
    DateTime now = DateTime.now();
    // Find the Monday of current week
    int currentWeekday = now.weekday; // 1 = Monday, 7 = Sunday
    DateTime monday = now.subtract(Duration(days: currentWeekday - 1));
    
    // Generate 7 days starting from Monday
    List<DateTime> weekDates = [];
    for (int i = 0; i < 7; i++) {
      weekDates.add(monday.add(Duration(days: i)));
    }
    return weekDates;
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    DateTime today = DateTime.now();
    List<DateTime> weekDates = _getWeekDates();
    String currentMonth = DateFormat('MMMM').format(today);

    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ===== HEADER =====
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'HOME',
                    style: GoogleFonts.dmMono(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  // LOGOUT BUTTON
                  GestureDetector(
                    onTap: _logout,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6B7280),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.logout,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ===== SCHEDULE TITLE =====
              Text(
                'Schedule',
                style: GoogleFonts.dmMono(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              // ===== CALENDAR CARD =====
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.black,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    // ===== THIS WEEK & SEE ALL =====
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
                        GestureDetector(
                          onTap: () {
                            // Navigate to full calendar view
                            print('See all clicked');
                          },
                          child: Text(
                            'See all',
                            style: GoogleFonts.dmMono(
                              fontSize: 14,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ===== MONTH BADGE =====
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

                    const SizedBox(height: 16),

                    // ===== WEEKDAY LABELS =====
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

                    // ===== DATE NUMBERS =====
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: weekDates.map((date) {
                        bool isToday = date.day == today.day &&
                            date.month == today.month &&
                            date.year == today.year;

                        return _dateCircle(
                          date.day.toString().padLeft(2, '0'),
                          isToday,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ===== GREETING (Optional) =====
              _isLoading
                  ? const CircularProgressIndicator()
                  : Text(
                      'Hi, $_username !!!',
                      style: GoogleFonts.dmMono(
                        fontSize: 16,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== WEEKDAY LABEL WIDGET =====
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

  // ===== DATE CIRCLE WIDGET =====
  Widget _dateCircle(String date, bool isToday) {
    return SizedBox(
      width: 38,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Date circle
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isToday ? const Color.fromARGB(253, 185, 0, 0) : Colors.transparent,
              shape: BoxShape.circle,
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
          // Triangle indicator below (positioned absolutely)
          if (isToday)
            Positioned(
              top: 36,
              child: CustomPaint(
                size: const Size(10, 8),
                painter: TrianglePainter(),
              ),
            ),
        ],
      ),
    );
  }
}

// ===== TRIANGLE PAINTER FOR TODAY INDICATOR =====
class TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0) // Bottom center
      ..lineTo(0, size.height) // Top left
      ..lineTo(size.width, size.height) // Top right
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}