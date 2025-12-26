import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';

import 'screens/login.dart';
import 'screens/signup.dart';
import 'screens/account_created_screen.dart';
import 'screens/homepage.dart';
import 'screens/auth_gate.dart';
import 'screens/forgot_password_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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

      // 🔐 AUTH-BASED ENTRY
      home: const AuthGate(),

      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/success': (_) => const AccountCreatedScreen(),
        '/home': (_) => const HomePage(),
        '/forgot-password': (context) => const ForgotPasswordScreen()
      },
    );
  }
}


//git add .
//git commit -m "first draft"
//git push -u origin main
