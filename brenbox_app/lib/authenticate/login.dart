import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
        Navigator.pushReplacementNamed(context, '/home');
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
        // Pause loading spinner while showing consent dialog
        if (mounted) setState(() => _isLoading = false);

        // Show data consent dialog and wait for user's decision
        final bool? userConsented = await _showDataConsentDialog(
          displayName: user.displayName ?? '',
          email: user.email ?? '',
        );

        // User dismissed dialog without choosing
        if (userConsented == null) {
          // Completely remove the Firebase Auth account so no trace is left
          await user.delete();
          return;
        }

        // User declined consent — delete auth account entirely and stay on login screen
        if (!userConsented) {
          // user.delete() removes the Firebase Auth record entirely,
          // unlike signOut() which only ends the session but leaves the account.
          // This ensures no ghost auth record exists if they try signing in again.
          await user.delete();
          _showMessage(
            'Sign-up cancelled.\n\nWe need your permission to save your data in order to create an account.',
          );
          return;
        }

        // User approved — resume loading and save data
        if (mounted) setState(() => _isLoading = true);

        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'username': user.displayName, // use Google display name as username
          'emailVerified': true,
          'provider': 'google',
          'createdAt': Timestamp.now(),
          'lastLogin': Timestamp.now(),
        });
      } else {
        // ── EXISTING USER — update last login and proceed normally ──
        await _firestore.collection('users').doc(user.uid).update({
          'lastLogin': Timestamp.now(),
          'emailVerified': true,
        });
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_firebaseErrorMessage(e.code));
    } catch (e) {
      _showMessage('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ================= DATA CONSENT DIALOG =================
  /// Shows a dialog asking the new Google user for permission to store their data.
  /// Returns:
  ///   true  → user approved
  ///   false → user declined
  ///   null  → dialog was dismissed (back button / tap outside)
  Future<bool?> _showDataConsentDialog({
    required String displayName,
    required String email,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // force an explicit choice
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BrenBox',
              style: GoogleFonts.dmMono(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Data Usage Permission',
              style: GoogleFonts.dmMono(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To create your BrenBox account, we would like to save the following information from your Google profile:',
              style: GoogleFonts.dmMono(fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Data preview card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _consentDataRow(
                    Icons.person_outline,
                    'Username',
                    displayName.isNotEmpty ? displayName : '—',
                  ),
                  const SizedBox(height: 8),
                  _consentDataRow(
                    Icons.email_outlined,
                    'Email',
                    email.isNotEmpty ? email : '—',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Text(
              'Do you allow BrenBox to store this data?',
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          // Decline button
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              'DECLINE',
              style: GoogleFonts.dmMono(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),

          // Approve button
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF292929),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'ALLOW',
              style: GoogleFonts.dmMono(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper row for the consent data preview card
  Widget _consentDataRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.dmMono(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.dmMono(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ================= SIGN OUT =================
  Future<void> _signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
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
        backgroundColor: Colors.white,
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
                        border: Border.all(color: Colors.grey.shade300),
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
                          color: _isLoading ? Colors.grey : Colors.black,
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
        fillColor: Colors.white,
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
        fillColor: Colors.white,
        hintText: 'Password',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
      ),
    );
  }
}