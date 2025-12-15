import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'account_created_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  // ================= CONTROLLERS =================
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ================= SIGN UP =================
  Future<void> _signUp() async {
    // ❌ stop if validation fails
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': _emailController.text.trim(),
        'username': _usernameController.text.trim(),
        'createdAt': Timestamp.now(),
        'lastLogin': Timestamp.now(),
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const AccountCreatedScreen(),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Signup failed');
    } finally {
      setState(() => _isLoading = false);
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),

                // BACK BUTTON
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF333333),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                const SizedBox(height: 32),

                // TITLE
                Text(
                  'Create',
                  style: GoogleFonts.dmMono(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'a new Account.',
                  style: GoogleFonts.dmMono(fontSize: 18),
                ),
                const SizedBox(height: 48),

                // EMAIL
                _label('Email'),
                _lineInput(_emailController),
                const SizedBox(height: 24),

                // USERNAME
                _label('Username'),
                _lineInput(_usernameController, isUsername: true),
                const SizedBox(height: 24),

                // PASSWORD
                _label('Password'),
                _lineInput(
                  _passwordController,
                  isPassword: true,
                ),
                const SizedBox(height: 24),

                // CONFIRM PASSWORD
                _label('Re-Type Password'),
                _lineInput(
                  _confirmPasswordController,
                  isPassword: true,
                  isConfirm: true,
                ),
                const SizedBox(height: 40),

                // SIGN UP BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF292929),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'SIGN UP',
                            style: GoogleFonts.dmMono(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 32),

                // LOGIN LINK
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text.rich(
                      TextSpan(
                        text: 'Already have an account? ',
                        style: GoogleFonts.dmMono(fontSize: 12, color: Colors.black,),
                        children: [
                          TextSpan(
                            text: 'LOG IN',
                            style: GoogleFonts.dmMono(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= COMPONENTS =================
  Widget _label(String text) {
    return Text(text, style: GoogleFonts.dmMono(fontSize: 13));
  }

  Widget _lineInput(
    TextEditingController controller, {
    bool isPassword = false,
    bool isConfirm = false,
    bool isUsername = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword
          ? (isConfirm ? !_confirmPasswordVisible : !_passwordVisible)
          : false,
      style: GoogleFonts.dmMono(),

      // ✅ FIELD-SPECIFIC ERROR MESSAGES
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'This field cannot be empty';
        }

        if (!isPassword && !isUsername) {
          if (!value.contains('@')) {
            return 'Enter a valid email address';
          }
        }

        if (isUsername && value.length < 3) {
          return 'Username must be at least 3 characters';
        }

        if (isPassword && value.length < 6) {
          return 'Password must be at least 6 characters';
        }

        if (isConfirm && value != _passwordController.text) {
          return 'Passwords do not match';
        }

        return null;
      },

      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        errorStyle: GoogleFonts.dmMono(fontSize: 11),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red, width: 2),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  isConfirm
                      ? (_confirmPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off)
                      : (_passwordVisible
                          ? Icons.visibility
                          : Icons.visibility_off),
                  color: Colors.black,
                ),
                onPressed: () {
                  setState(() {
                    if (isConfirm) {
                      _confirmPasswordVisible =
                          !_confirmPasswordVisible;
                    } else {
                      _passwordVisible = !_passwordVisible;
                    }
                  });
                },
              )
            : null,
      ),
    );
  }
}
