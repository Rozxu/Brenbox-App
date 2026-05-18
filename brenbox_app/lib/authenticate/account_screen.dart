import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/notification_settings_screen.dart';
import '../services/notification_service.dart';
import '../services/notification_scheduler.dart';
import '../app_preferences.dart';

// ignore_for_file: use_build_context_synchronously

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
  double _fontScale = kDefaultFontScale;
  bool _isDarkMode = false;

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
      final scale   = (doc.data()?['fontScale'] as num?)?.toDouble() ?? kDefaultFontScale;
      final darkMode = doc.data()?['darkMode'] as bool? ?? false;
      setState(() {
        _username              = doc.data()?['username'] ?? 'User';
        _email                 = user.email ?? '';
        _notificationsEnabled  = doc.data()?['notificationsEnabled'] ?? true;
        _fontScale             = scale;
        _isDarkMode            = darkMode;
        _isLoading             = false;
      });
      fontScaleNotifier.value  = scale;
      darkModeNotifier.value   = darkMode;
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
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border(context), width: 2),
        ),
        title: Text(
          'Log Out',
          style: GoogleFonts.dmMono(
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
          ),
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: GoogleFonts.dmMono(
            fontSize: 13,
            color: AppColors.text(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmMono(color: AppColors.text(context)),
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

  Future<void> _updateFontScale(double scale) async {
    setState(() => _fontScale = scale);
    fontScaleNotifier.value = scale;
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).update({'fontScale': scale});
  }

  Future<void> _updateDarkMode(bool value) async {
    setState(() => _isDarkMode = value);
    darkModeNotifier.value = value;
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).update({'darkMode': value});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
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
              decoration: BoxDecoration(
                color: AppColors.chipBg(context),
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
            color: AppColors.text(context),
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
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context), width: 2),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.fieldBg(context),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border(context), width: 2),
            ),
            child: Icon(
              Icons.person,
              size: 40,
              color: AppColors.subtext(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _username,
            style: GoogleFonts.dmMono(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.text(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _email,
            style: GoogleFonts.dmMono(
              fontSize: 12,
              color: AppColors.subtext(context),
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
        _buildDarkModeItem(),
        const SizedBox(height: 12),
        _buildFontSizeSlider(),
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

  Widget _buildDarkModeItem() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context), width: 2),
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            transitionBuilder: (child, anim) => RotationTransition(
              turns: Tween<double>(begin: 0.5, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeInOut),
              ),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(
              _isDarkMode ? Icons.nightlight_round : Icons.wb_sunny_rounded,
              key: ValueKey<bool>(_isDarkMode),
              color: _isDarkMode
                  ? const Color(0xFF9CA3AF)
                  : const Color(0xFFFBBC05),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Dark Mode',
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.text(context),
              ),
            ),
          ),
          Switch(
            value: _isDarkMode,
            onChanged: _updateDarkMode,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF34A853).withValues(alpha: 0.8),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFE5E7EB),
          ),
        ],
      ),
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
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context), width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: AppColors.text(context)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text(context),
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppColors.subtext(context),
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
      color: AppColors.card(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border(context), width: 2),
    ),
    child: Row(
      children: [
        Icon(Icons.notifications_outlined,
            size: 24, color: AppColors.text(context)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            'Notification',
            style: GoogleFonts.dmMono(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.text(context),
            ),
          ),
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
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.tune,
                size: 20,
                color: AppColors.subtext(context),
              ),
            ),
          ),
        // Master on/off toggle
        Switch(
          value: _notificationsEnabled,
          onChanged: (v) async {
            await _toggleNotifications(v);
            if (v) {
              await NotificationScheduler().rescheduleAllNotifications();
            } else {
              await NotificationService().cancelAllNotifications();
            }
          },
          activeThumbColor: Colors.white,
          activeTrackColor: const Color(0xFF34A853).withValues(alpha: 0.8),
          inactiveThumbColor: Colors.white,
        ),
      ],
    ),
  );
}

  Widget _buildFontSizeSlider() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.text_fields, size: 24, color: AppColors.text(context)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Font Size',
                  style: GoogleFonts.dmMono(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text(context),
                  ),
                ),
              ),
              Text(
                '${scaleToSliderPos(_fontScale).round()}',
                style: GoogleFonts.dmMono(
                  fontSize: 13,
                  color: AppColors.subtext(context),
                ),
              ),
            ],
          ),
          Slider(
            value: scaleToSliderPos(_fontScale),
            min: 0,
            max: 100,
            activeColor: AppColors.sliderActive(context),
            inactiveColor: AppColors.sliderInactive(context),
            onChanged: (pos) => _updateFontScale(sliderPosToScale(pos)),
            onChangeEnd: (pos) => _updateFontScale(sliderPosToScale(pos)),
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
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;

  bool _isLoading = false;
  bool _isDeleting = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  bool get _hasChanges =>
      _usernameController.text.trim() != widget.username ||
      _newPasswordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.username);
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _usernameController.addListener(() => setState(() {}));
    _newPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _usernameController.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Profile updated successfully', style: GoogleFonts.dmMono()),
          backgroundColor: const Color(0xFF34A853),
        ));
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Current password is incorrect';
      } else if (e.code == 'weak-password') {
        message = 'New password is too weak';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message, style: GoogleFonts.dmMono()),
          backgroundColor: const Color(0xFFB90000),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Deletes documents from a collection where [field] == [uid], in batches of 100
  Future<void> _deleteCollectionByUser(String collection, String field, String uid) async {
    QuerySnapshot snapshot;
    do {
      snapshot = await _firestore
          .collection(collection)
          .where(field, isEqualTo: uid)
          .limit(100)
          .get();
      if (snapshot.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (snapshot.docs.length == 100);
  }

  Future<void> _deleteAccount() async {
    // ── First confirmation ──
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border(ctx), width: 2),
        ),
        title: Text('Delete Account',
            style: GoogleFonts.dmMono(
                fontWeight: FontWeight.bold, color: AppColors.text(ctx))),
        content: Text(
          'Are you sure you want to delete your account?\n\nAll your classes, tasks, exams, grades, certificates, and study group data will be permanently deleted.',
          style: GoogleFonts.dmMono(fontSize: 13, color: AppColors.subtext(ctx), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.dmMono(color: AppColors.subtext(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB90000),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Continue', style: GoogleFonts.dmMono(color: Colors.white)),
          ),
        ],
      ),
    );
    if (first != true) return;

    // ── Second confirmation ──
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFB90000), width: 2),
        ),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB90000), size: 22),
          const SizedBox(width: 8),
          Text('Final Warning',
              style: GoogleFonts.dmMono(
                  fontWeight: FontWeight.bold, color: const Color(0xFFB90000))),
        ]),
        content: Text(
          'This action is permanent and cannot be undone.\n\nYour account and every piece of data associated with it will be deleted forever. Are you absolutely sure?',
          style: GoogleFonts.dmMono(fontSize: 13, color: AppColors.subtext(ctx), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('No, Keep My Account',
                style: GoogleFonts.dmMono(color: AppColors.subtext(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB90000),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Yes, Delete Forever', style: GoogleFonts.dmMono(color: Colors.white)),
          ),
        ],
      ),
    );
    if (second != true) return;

    setState(() => _isDeleting = true);

    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;

    try {
      // Delete all user-owned collections
      await _deleteCollectionByUser('tasks', 'userId', uid);
      await _deleteCollectionByUser('timetable', 'userId', uid);
      await _deleteCollectionByUser('exams', 'userId', uid);
      await _deleteCollectionByUser('grade_results', 'userId', uid);
      await _deleteCollectionByUser('notification_history', 'userId', uid);
      await _deleteCollectionByUser('scheduled_notifications', 'userId', uid);

      // Delete grade settings (keyed by uid)
      await _firestore.collection('grade_settings').doc(uid).delete().catchError((_) {});

      // Leave or delete study groups
      final groups = await _firestore
          .collection('study_groups')
          .where('memberIds', arrayContains: uid)
          .get();
      for (final group in groups.docs) {
        final data = group.data();
        final members = List<String>.from(data['memberIds'] ?? []);
        if (data['createdBy'] == uid && members.length <= 1) {
          await group.reference.delete();
        } else {
          members.remove(uid);
          await group.reference.update({'memberIds': members});
        }
      }

      // Delete user Firestore document
      await _firestore.collection('users').doc(uid).delete();

      // Delete Firebase Auth account
      await user.delete();

      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'Please log out and log back in, then try deleting your account again.',
              style: GoogleFonts.dmMono(),
            ),
            backgroundColor: const Color(0xFFB90000),
            duration: const Duration(seconds: 5),
          ));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to delete account. Please try again.',
              style: GoogleFonts.dmMono()),
          backgroundColor: const Color(0xFFB90000),
        ));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Edit Profile',
          style: GoogleFonts.dmMono(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
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
              const SizedBox(height: 24),
              Text(
                'Change Password (Optional)',
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.subtext(context),
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
                maxLength: 25,
                onToggle: () {
                  setState(() => _obscureNewPassword = !_obscureNewPassword);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  if (value.length < 6) { return 'Password must be at least 6 characters'; }
                  if (value.length > 25) { return 'Password must be at most 25 characters'; }
                  if (!RegExp(r'[A-Z]').hasMatch(value)) { return 'Must contain at least 1 uppercase letter'; }
                  if (!RegExp(r'[0-9]').hasMatch(value)) { return 'Must contain at least 1 number'; }
                  if (!RegExp(r'[^a-zA-Z0-9]').hasMatch(value)) { return 'Must contain at least 1 symbol (e.g. !@#\$)'; }
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
                maxLength: 25,
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
              // Save Changes — only active when something has changed
              IgnorePointer(
                ignoring: _isLoading || !_hasChanges,
                child: AnimatedOpacity(
                  opacity: (_isLoading || !_hasChanges) ? 0.4 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: _AnimatedTapButton(
                    onTap: _saveChanges,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B7280),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isLoading
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Save Changes',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.dmMono(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Delete Account
              IgnorePointer(
                ignoring: _isLoading || _isDeleting,
                child: _AnimatedTapButton(
                  onTap: _deleteAccount,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB90000),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _isDeleting
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.delete_forever_outlined,
                                  color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Delete User Account',
                                style: GoogleFonts.dmMono(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.dmMono(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: AppColors.text(context),
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
      style: GoogleFonts.dmMono(fontSize: 14, color: AppColors.text(context)),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmMono(fontSize: 14, color: AppColors.subtext(context)),
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
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      maxLength: maxLength,
      style: GoogleFonts.dmMono(fontSize: 14, color: AppColors.text(context)),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        counterText: maxLength != null ? '' : null,
        hintStyle: GoogleFonts.dmMono(fontSize: 14, color: AppColors.subtext(context)),
        filled: true,
        fillColor: AppColors.input(context),
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility_off : Icons.visibility,
            size: 20,
            color: AppColors.subtext(context),
          ),
          onPressed: onToggle,
        ),
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
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'About',
          style: GoogleFonts.dmMono(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.text(context),
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
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border(context), width: 2),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.subtext(context),
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
                      color: AppColors.text(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version 0.5.0',
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      color: AppColors.subtext(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildInfoSection(context, 'About BrenBox',
              'BrenBox is a comprehensive timetable and task management application designed to help students organize their academic life. Keep track of classes, assignments, exams, and deadlines all in one place.',
            ),
            const SizedBox(height: 16),
            _buildInfoSection(context, 'Features',
              '• Weekly timetable view\n'
                  '• Task management with reminders\n'
                  '• Exam scheduling\n'
                  '• Monthly calendar\n'
                  '• Real-time countdown timers\n'
                  '• Event indicators',
            ),
            const SizedBox(height: 16),
            _buildInfoSection(context, 'Developer',
              'Developed as a student project to enhance academic productivity and organization.',
            ),
            const SizedBox(height: 16),
            _buildInfoSection(context, 'Contact',
              'For feedback and support, please contact through the email: support@brenbox.com',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, String title, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmMono(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.text(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: GoogleFonts.dmMono(
              fontSize: 12,
              color: AppColors.subtext(context),
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