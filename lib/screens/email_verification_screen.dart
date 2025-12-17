import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'account_created_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;

  const EmailVerificationScreen({
    Key? key,
    required this.email,
  }) : super(key: key);

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  
  bool _isVerified = false;
  bool _isResending = false;
  Timer? _timer;
  int _resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    _startVerificationCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ================= CHECK EMAIL VERIFICATION =================
  void _startVerificationCheck() {
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _checkEmailVerified();
    });
  }

  Future<void> _checkEmailVerified() async {
    final user = _auth.currentUser;
    
    if (user == null) return;

    // Reload user to get latest emailVerified status
    await user.reload();
    final updatedUser = _auth.currentUser;

    if (updatedUser != null && updatedUser.emailVerified) {
      _timer?.cancel();
      
      // Update Firestore
      await _firestore.collection('users').doc(user.uid).update({
        'emailVerified': true,
        'lastLogin': Timestamp.now(),
      });

      setState(() => _isVerified = true);

      // Navigate to success screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const AccountCreatedScreen(),
          ),
        );
      }
    }
  }

  // ================= RESEND VERIFICATION EMAIL =================
  Future<void> _resendVerificationEmail() async {
    if (_resendCountdown > 0) return;

    setState(() => _isResending = true);

    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        
        _showMessage('Verification email sent! Please check your inbox.');
        
        // Start countdown
        setState(() => _resendCountdown = 60);
        Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_resendCountdown > 0) {
            setState(() => _resendCountdown--);
          } else {
            timer.cancel();
          }
        });
      }
    } catch (e) {
      _showMessage('Failed to resend email. Please try again.');
    } finally {
      setState(() => _isResending = false);
    }
  }

  // ================= DIALOG =================
  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('BrenBox', style: GoogleFonts.dmMono()),
        content: Text(message, style: GoogleFonts.dmMono(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: GoogleFonts.dmMono(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // EMAIL ICON
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: const Icon(
                  Icons.email_outlined,
                  size: 50,
                  color: Colors.black,
                ),
              ),

              const SizedBox(height: 32),

              // TITLE
              Text(
                'Verify Your Email',
                style: GoogleFonts.dmMono(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // MESSAGE
              Text(
                'We sent a verification link to:',
                style: GoogleFonts.dmMono(fontSize: 14),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                widget.email,
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              Text(
                'Click the link in the email to verify your account.',
                style: GoogleFonts.dmMono(fontSize: 12),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              // CHECKING STATUS
              if (!_isVerified)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Checking verification status...',
                      style: GoogleFonts.dmMono(fontSize: 11),
                    ),
                  ],
                ),

              const SizedBox(height: 40),

              // RESEND BUTTON
              TextButton(
                onPressed: _resendCountdown > 0 || _isResending
                    ? null
                    : _resendVerificationEmail,
                child: _isResending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _resendCountdown > 0
                            ? 'Resend in ${_resendCountdown}s'
                            : 'Resend Verification Email',
                        style: GoogleFonts.dmMono(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _resendCountdown > 0
                              ? Colors.grey
                              : Colors.black,
                          decoration: TextDecoration.underline,
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              // BACK TO LOGIN
              TextButton(
                onPressed: () async {
                  // Sign out and go back to login
                  await _auth.signOut();
                  if (mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  }
                },
                child: Text(
                  'Back to Login',
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}