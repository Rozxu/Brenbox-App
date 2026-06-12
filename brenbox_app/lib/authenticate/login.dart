import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../app_preferences.dart';
import '../services/google_calendar_service.dart';

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
  final _googleSignIn = GoogleSignIn();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ================= SIGN IN WITH EMAIL =================
  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showMessage('Please enter email and password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = userCredential.user;

      if (user == null) {
        _showMessage('Authentication failed');
        return;
      }

      await user.reload();
      final updatedUser = _auth.currentUser;

      if (updatedUser != null && !updatedUser.emailVerified) {
        await _auth.signOut();
        _showMessage(
          'Email not verified!\n\nPlease check your email and verify your account before logging in.',
        );
        setState(() => _isLoading = false);
        return;
      }

      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (!doc.exists) {
        _showMessage('User record not found in database');
        await _auth.signOut();
        return;
      }

      await _firestore.collection('users').doc(user.uid).update({
        'lastLogin': Timestamp.now(),
        'emailVerified': true,
      });

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_firebaseErrorMessage(e.code));
    } catch (e) {
      _showMessage('Unexpected error occurred');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ================= SIGN IN WITH GOOGLE =================
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      // Force account picker to always appear
      await _googleSignIn.signOut();
      await _googleSignIn.disconnect().catchError((_) {});

      // Trigger Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      // User cancelled
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get auth details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create Firebase credential
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      final user = userCredential.user;

      if (user == null) {
        _showMessage('Google sign-in failed');
        return;
      }

      // Check Firestore for existing user
      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (!doc.exists) {
        // ── NEW GOOGLE USER ──
        // Google's native OAuth already collected consent — save directly
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'username': user.displayName,
          'emailVerified': true,
          'provider': 'google',
          'createdAt': Timestamp.now(),
          'lastLogin': Timestamp.now(),
        });

        // Ask for Google Calendar permission
        bool calendarGranted = false;
        if (mounted) setState(() => _isLoading = false);
        if (mounted) {
          calendarGranted = await _showCalendarPermissionSheet(
            user.uid,
            user.email ?? '',
          );
        }
        await _firestore
            .collection('users')
            .doc(user.uid)
            .update({'calendarPermissionGranted': calendarGranted});
        if (mounted) setState(() => _isLoading = true);
      } else {
        // ── EXISTING USER — update last login and proceed normally ──
        await _firestore.collection('users').doc(user.uid).update({
          'lastLogin': Timestamp.now(),
          'emailVerified': true,
        });
      }

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_firebaseErrorMessage(e.code));
    } catch (e) {
      _showMessage('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ================= CALENDAR PERMISSION SHEET =================
  Future<bool> _showCalendarPermissionSheet(String uid, String email) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: AppColors.border(context), width: 2),
            left: BorderSide(color: AppColors.border(context), width: 2),
            right: BorderSide(color: AppColors.border(context), width: 2),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.calendar_month_rounded,
                      color: Color(0xFF4285F4), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Google Calendar',
                          style: GoogleFonts.dmMono(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Optional sync',
                          style: GoogleFonts.dmMono(
                              fontSize: 11,
                              color: AppColors.subtext(context))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Allow BrenBox to sync your Google Calendar so your events appear alongside your classes and tasks.',
              style: GoogleFonts.dmMono(
                  fontSize: 12, color: AppColors.subtext(context), height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              'Account: $email',
              style: GoogleFonts.dmMono(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text(context)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final result = await GoogleCalendarService.instance.connect();
                  if (ctx.mounted) {
                    Navigator.pop(ctx, result == GCalConnectResult.success);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Enable Google Calendar',
                    style: GoogleFonts.dmMono(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Skip for now',
                    style: GoogleFonts.dmMono(
                        color: AppColors.subtext(context), fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  // ================= SIGN OUT =================
  Future<void> _signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  // ================= FORGOT PASSWORD =================
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
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method';
      default:
        return 'Authentication error';
    }
  }

  // ================= DIALOG =================
  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card(context),
        title: Text(
          'BrenBox',
          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
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
                color: AppColors.text(context),
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
      backgroundColor: AppColors.bg(context),
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
                    AppColors.isDark(context)
                        ? 'assets/images/BrenboxLogoWhite.png'
                        : 'assets/images/BrenboxLogo.png',
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
                _passwordField(),

                // FORGOT PASSWORD
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading ? null : _navigateToForgotPassword,
                    child: Text(
                      'forgot password?',
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        color: AppColors.text(context),
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
                      backgroundColor: AppColors.chipBg(context),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
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

                // DIVIDER WITH LOGIN WITH TEXT
                Row(
                  children: [
                    const Expanded(child: Divider(thickness: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'LOGIN WITH',
                        style: GoogleFonts.dmMono(fontSize: 12),
                      ),
                    ),
                    const Expanded(child: Divider(thickness: 1)),
                  ],
                ),

                const SizedBox(height: 16),

                // GOOGLE SIGN IN BUTTON
                Center(
                  child: InkWell(
                    onTap: _isLoading ? null : _signInWithGoogle,
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: AppColors.border(context)),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(
                        'assets/images/google_icon.png',
                        fit: BoxFit.contain,
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
                          : () => Navigator.pushNamed(context, '/signup'),
                      child: Text(
                        'SIGN UP',
                        style: GoogleFonts.dmMono(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _isLoading ? AppColors.subtext(context) : AppColors.text(context),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
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
        fillColor: AppColors.input(context),
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: GoogleFonts.dmMono(),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.input(context),
        hintText: 'Password',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: AppColors.subtext(context),
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
      ),
    );
  }
}