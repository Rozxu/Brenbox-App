import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ================= SIGN IN WITH EMAIL VERIFICATION CHECK =================
  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showMessage('Please enter email and password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 🔐 Firebase Auth
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = userCredential.user;

      if (user == null) {
        _showMessage('Authentication failed');
        return;
      }

      // ✅ CHECK EMAIL VERIFICATION
      await user.reload(); // Refresh user data
      final updatedUser = _auth.currentUser;

      if (updatedUser != null && !updatedUser.emailVerified) {
        // Email not verified
        await _auth.signOut();
        _showMessage(
          'Email not verified!\n\nPlease check your email and verify your account before logging in.',
        );
        setState(() => _isLoading = false);
        return;
      }

      // 🔥 Firestore check
      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (!doc.exists) {
        _showMessage('User record not found in database');
        await _auth.signOut();
        return;
      }

      // Update last login and email verified status in Firestore
      await _firestore.collection('users').doc(user.uid).update({
        'lastLogin': Timestamp.now(),
        'emailVerified': true,
      });

      // ✅ SUCCESS → HOME
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_firebaseErrorMessage(e.code));
    } catch (e) {
      _showMessage('Unexpected error occurred');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ================= RESET PASSWORD - NAVIGATE TO FORGOT PASSWORD =================
  void _navigateToForgotPassword() {
    Navigator.pushNamed(context, '/forgot-password');
  }

  // ================= ERROR HANDLER =================
  String _firebaseErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'invalid-credential':
        return 'Invalid email or password';
      default:
        return 'Authentication error';
    }
  }

  // ================= DIALOG =================
  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'BrenBox',
          style: GoogleFonts.dmMono(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.dmMono(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: GoogleFonts.dmMono(
                color: Colors.black,
                fontWeight: FontWeight.bold,
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LOGO
                Center(
                  child: Image.asset(
                    'assets/images/BrenboxLogo.png',
                    width: 120,
                  ),
                ),
                const SizedBox(height: 32),

                // TITLE
                Text(
                  'Welcome',
                  style: GoogleFonts.dmMono(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'to BrenBox !!!',
                  style: GoogleFonts.dmMono(fontSize: 18),
                ),
                const SizedBox(height: 48),

                // EMAIL
                Text('Email', style: GoogleFonts.dmMono()),
                const SizedBox(height: 8),
                _inputField(_emailController, false, 'your@gmail.com'),

                const SizedBox(height: 24),

                // PASSWORD
                Text('Password', style: GoogleFonts.dmMono()),
                const SizedBox(height: 8),
                _inputField(_passwordController, true, 'Min 6 characters'),

                // FORGOT PASSWORD - NAVIGATE TO RESET FLOW
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading ? null : _navigateToForgotPassword,
                    child: Text(
                      'forgot password?',
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // SIGN IN BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF292929),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                          )
                        : Text(
                            'SIGN IN',
                            style: GoogleFonts.dmMono(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 32),

                // SIGN UP LINK
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Dont have an account? ',
                      style: GoogleFonts.dmMono(fontSize: 13),
                    ),
                    InkWell(
                      onTap: _isLoading
                          ? null
                          : () {
                              Navigator.pushNamed(context, '/signup');
                            },
                      child: Text(
                        'SIGN UP',
                        style: GoogleFonts.dmMono(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _isLoading ? Colors.grey : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // FIREBASE STATUS
                //Center(
                //  child: Text(
                //    'Firebase Status: Connected ✓',
                //   style: GoogleFonts.dmMono(
                //      fontSize: 11,
                //      color: Colors.green,
                //    ),
                //  ),
               // ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= COMPONENTS =================
  Widget _inputField(
    TextEditingController controller,
    bool obscure,
    String hint,
  ) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: GoogleFonts.dmMono(),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}