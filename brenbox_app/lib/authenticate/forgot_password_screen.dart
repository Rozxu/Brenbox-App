// ==========================================
// 1. FORGOT PASSWORD SCREEN (Enter Email)
// ==========================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendPasswordResetEmail() async {
    if (_emailController.text.isEmpty) {
      _showMessage('Please enter your email');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      
      // Check if user exists in Firestore
      final users = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      if (users.docs.isEmpty) {
        _showMessage('No account found with this email');
        setState(() => _isLoading = false);
        return;
      }

      // Send password reset email via Firebase
      await _auth.sendPasswordResetEmail(email: email);

      // Navigate to email sent screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PasswordResetEmailSentScreen(email: email),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email';
          break;
        case 'invalid-email':
          message = 'Invalid email address';
          break;
        default:
          message = 'Error sending reset email. Please try again.';
      }
      _showMessage(message);
    } catch (e) {
      _showMessage('Error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('BrenBox', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold)),
        content: Text(message, style: GoogleFonts.dmMono(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.dmMono(fontWeight: FontWeight.bold, color: Colors.black)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back Button
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF6B7280),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Title
                    Text(
                      'Forgot password',
                      style: GoogleFonts.dmMono(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    Text(
                      'Please enter your email to reset\npassword',
                      style: GoogleFonts.dmMono(fontSize: 13),
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Email Label
                    Text('Email', style: GoogleFonts.dmMono(fontSize: 13)),
                    
                    const SizedBox(height: 12),
                    
                    // Email Input
                    TextField(
                      controller: _emailController,
                      style: GoogleFonts.dmMono(),
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.black, width: 2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.black, width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.black, width: 2),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // Reset Password Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _sendPasswordResetEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF292929),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'RESET PASSWORD',
                                style: GoogleFonts.dmMono(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. PASSWORD RESET EMAIL SENT SCREEN
// ==========================================
class PasswordResetEmailSentScreen extends StatelessWidget {
  final String email;

  const PasswordResetEmailSentScreen({
    Key? key,
    required this.email,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                
                // Email Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                    color: Colors.white,
                  ),
                  child: const Icon(
                    Icons.email_outlined,
                    size: 60,
                    color: Colors.black,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Title
                Text(
                  'Check Your Email',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmMono(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Message
                Text(
                  'We sent a password reset link to:',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmMono(fontSize: 13),
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmMono(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                Text(
                  'Click the link in the email to reset your\npassword. Check your spam folder if you\ndon\'t see it.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmMono(fontSize: 12, height: 1.5),
                ),
                
                const SizedBox(height: 40),
                
                // Resend Email Button
                TextButton(
                  onPressed: () async {
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Email sent again!',
                              style: GoogleFonts.dmMono(),
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Error sending email',
                              style: GoogleFonts.dmMono(),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(
                    'Resend Verification Email',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmMono(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Back to Login Button
                TextButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  },
                  child: Text(
                    'Back to Login',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmMono(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}