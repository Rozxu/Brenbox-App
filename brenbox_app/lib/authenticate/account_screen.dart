import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/notification_settings_screen.dart';
import '../services/notification_service.dart';
import '../services/notification_scheduler.dart';

class AccountScreen extends StatefulWidget {
  final VoidCallback? onBackPressed;
  
  const AccountScreen({Key? key, this.onBackPressed}) : super(key: key);

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String _username = '';
  String _email = '';
  bool _notificationsEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      setState(() {
        _username = doc.data()?['username'] ?? 'User';
        _email = user.email ?? '';
        _notificationsEnabled = doc.data()?['notificationsEnabled'] ?? true;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        title: Text(
          'Log Out',
          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: GoogleFonts.dmMono(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmMono(color: Colors.black),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB90000),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Log Out',
              style: GoogleFonts.dmMono(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await _auth.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'notificationsEnabled': value,
      });
      setState(() {
        _notificationsEnabled = value;
      });
    } catch (e) {
      print('Error updating notifications: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _buildHeader(),
                const SizedBox(height: 32),
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF6B7280),
                    ),
                  )
                else ...[
                  _buildProfileSection(),
                  const SizedBox(height: 24),
                  _buildMenuItems(),
                  const SizedBox(height: 24),
                  _buildLogoutButton(),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        if (widget.onBackPressed != null)
          _AnimatedTapButton(
            onTap: widget.onBackPressed!,
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 40, 40, 40),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        if (widget.onBackPressed != null) const SizedBox(width: 16),
        Text(
          'Account',
          style: GoogleFonts.dmMono(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: const Icon(
              Icons.person,
              size: 40,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _username,
            style: GoogleFonts.dmMono(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _email,
            style: GoogleFonts.dmMono(
              fontSize: 12,
              color: const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItems() {
    return Column(
      children: [
        _buildMenuItem(
          icon: Icons.person_outline,
          title: 'Profile',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditProfileScreen(
                  username: _username,
                  email: _email,
                ),
              ),
            ).then((_) => _loadUserData());
          },
        ),
        const SizedBox(height: 12),
        _buildNotificationMenuItem(),
        const SizedBox(height: 12),
        _buildMenuItem(
          icon: Icons.info_outline,
          title: 'About',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return _AnimatedTapButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Colors.black),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Color(0xFF6B7280),
            ),
          ],
        ),
      ),
    );
  }

Widget _buildNotificationMenuItem() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black, width: 2),
    ),
    child: Row(
      children: [
        const Icon(Icons.notifications_outlined,
            size: 24, color: Colors.black),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            'Notification',
            style: GoogleFonts.dmMono(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // Master on/off toggle
        Switch(
          value: _notificationsEnabled,
          onChanged: (v) async {
            await _toggleNotifications(v);
            // Reschedule or cancel all
            if (v) {
              await NotificationScheduler().rescheduleAllNotifications();
            } else {
              await NotificationService().cancelAllNotifications();
            }
          },
          activeColor: const Color(0xFF34A853),
          activeTrackColor: const Color(0xFF34A853).withOpacity(0.5),
        ),
        // Arrow to open detailed settings
        if (_notificationsEnabled)
          _AnimatedTapButton(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                Icons.tune,
                size: 20,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
      ],
    ),
  );
}

  Widget _buildLogoutButton() {
    return _AnimatedTapButton(
      onTap: _logout,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFB90000),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Log Out',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmMono(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// Edit Profile Screen
class EditProfileScreen extends StatefulWidget {
  final String username;
  final String email;

  const EditProfileScreen({
    Key? key,
    required this.username,
    required this.email,
  }) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;

  bool _isLoading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.username);
    _emailController = TextEditingController(text: widget.email);
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Update username
      if (_usernameController.text.trim() != widget.username) {
        await _firestore.collection('users').doc(user.uid).update({
          'username': _usernameController.text.trim(),
        });
      }

      // Update email
      if (_emailController.text.trim() != widget.email) {
        await user.verifyBeforeUpdateEmail(_emailController.text.trim());
      }

      // Update password if provided
      if (_newPasswordController.text.isNotEmpty) {
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: _currentPasswordController.text,
        );
        await user.reauthenticateWithCredential(credential);
        await user.updatePassword(_newPasswordController.text);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile updated successfully',
              style: GoogleFonts.dmMono(),
            ),
            backgroundColor: const Color(0xFF34A853),
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred';
      if (e.code == 'wrong-password') {
        message = 'Current password is incorrect';
      } else if (e.code == 'weak-password') {
        message = 'New password is too weak';
      } else if (e.code == 'email-already-in-use') {
        message = 'Email is already in use';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: GoogleFonts.dmMono()),
            backgroundColor: const Color(0xFFB90000),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          'Edit Profile',
          style: GoogleFonts.dmMono(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Username'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _usernameController,
                hint: 'Enter username',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Username is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildLabel('Email'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _emailController,
                hint: 'Enter email',
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!value.contains('@')) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Change Password (Optional)',
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 16),
              _buildLabel('Current Password'),
              const SizedBox(height: 8),
              _buildPasswordField(
                controller: _currentPasswordController,
                hint: 'Enter current password',
                obscureText: _obscureCurrentPassword,
                onToggle: () {
                  setState(() => _obscureCurrentPassword = !_obscureCurrentPassword);
                },
              ),
              const SizedBox(height: 16),
              _buildLabel('New Password'),
              const SizedBox(height: 8),
              _buildPasswordField(
                controller: _newPasswordController,
                hint: 'Enter new password',
                obscureText: _obscureNewPassword,
                onToggle: () {
                  setState(() => _obscureNewPassword = !_obscureNewPassword);
                },
                validator: (value) {
                  if (value != null && value.isNotEmpty && value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildLabel('Confirm New Password'),
              const SizedBox(height: 8),
              _buildPasswordField(
                controller: _confirmPasswordController,
                hint: 'Confirm new password',
                obscureText: _obscureConfirmPassword,
                onToggle: () {
                  setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                },
                validator: (value) {
                  if (_newPasswordController.text.isNotEmpty &&
                      value != _newPasswordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save Changes',
                          style: GoogleFonts.dmMono(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.dmMono(
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.dmMono(fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmMono(fontSize: 14, color: Colors.grey),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB90000), width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB90000), width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscureText,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: GoogleFonts.dmMono(fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmMono(fontSize: 14, color: Colors.grey),
        filled: true,
        fillColor: Colors.white,
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility_off : Icons.visibility,
            size: 20,
            color: const Color(0xFF6B7280),
          ),
          onPressed: onToggle,
        ),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB90000), width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB90000), width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}

// About Screen
class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
          'About',
          style: GoogleFonts.dmMono(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B7280),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.calendar_today,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'BrenBox',
                    style: GoogleFonts.dmMono(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version 0.5.0',
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildInfoSection(
              'About BrenBox',
              'BrenBox is a comprehensive timetable and task management application designed to help students organize their academic life. Keep track of classes, assignments, exams, and deadlines all in one place.',
            ),
            const SizedBox(height: 16),
            _buildInfoSection(
              'Features',
              '• Weekly timetable view\n'
                  '• Task management with reminders\n'
                  '• Exam scheduling\n'
                  '• Monthly calendar\n'
                  '• Real-time countdown timers\n'
                  '• Event indicators',
            ),
            const SizedBox(height: 16),
            _buildInfoSection(
              'Developer',
              'Developed as a student project to enhance academic productivity and organization.',
            ),
            const SizedBox(height: 16),
            _buildInfoSection(
              'Contact',
              'For feedback and support, please contact through the email: support@brenbox.com',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmMono(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: GoogleFonts.dmMono(
              fontSize: 12,
              color: const Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedTapButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Duration duration;

  const _AnimatedTapButton({
    required this.child,
    required this.onTap,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<_AnimatedTapButton> createState() => _AnimatedTapButtonState();
}

class _AnimatedTapButtonState extends State<_AnimatedTapButton> {
  bool _isTapped = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isTapped = true),
      onTapUp: (_) => setState(() => _isTapped = false),
      onTapCancel: () => setState(() => _isTapped = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isTapped ? 0.95 : 1.0,
        duration: widget.duration,
        child: widget.child,
      ),
    );
  }
}