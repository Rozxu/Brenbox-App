import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'authenticate/login.dart';
import 'authenticate/signup.dart';
import 'authenticate/account_created_screen.dart';
import 'homepage.dart';
import 'authenticate/auth_gate.dart';
import 'authenticate/forgot_password_screen.dart';

// ✅ ADD THESE TWO IMPORTS
import 'services/notification_service.dart';
import 'services/notification_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ Initialize notification service
  await NotificationService().initialize();

  // ✅ Reschedule notifications if user is already logged in
  if (FirebaseAuth.instance.currentUser != null) {
    await NotificationScheduler().rescheduleAllNotifications();
  }

  runApp(const BrenBoxApp());
}

class BrenBoxApp extends StatelessWidget {
  const BrenBoxApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrenBox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.dmMonoTextTheme(),
      ),
      home: const AuthGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/success': (_) => const AccountCreatedScreen(),
        '/home': (_) => const HomePage(),
        '/forgot-password': (context) => const ForgotPasswordScreen(),
      },
    );
  }
}