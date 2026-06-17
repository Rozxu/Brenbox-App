import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'authenticate/login.dart';
import 'authenticate/signup.dart';
import 'authenticate/account_created_screen.dart';
import 'homepage.dart';
import 'authenticate/auth_gate.dart';
import 'authenticate/forgot_password_screen.dart';

import 'services/notification_service.dart';
import 'app_preferences.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // OS shows the notification automatically from the FCM payload.
  // Navigation happens when the user taps — nothing to do here.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Keep more decoded images in memory so re-entering screens is instant
  PaintingBinding.instance.imageCache.maximumSizeBytes = 150 * 1024 * 1024; // 150 MB

  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

  // Initialize notification service and register navigator key for tap navigation
  await NotificationService().initialize();
  NotificationService().setNavigatorKey(navigatorKey);

  runApp(const BrenBoxApp());
}

class BrenBoxApp extends StatelessWidget {
  const BrenBoxApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: darkModeNotifier,
      builder: (_, isDark, __) => ValueListenableBuilder<double>(
        valueListenable: fontScaleNotifier,
        builder: (_, scale, __) => MaterialApp(
          title: 'BrenBox',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFE5E7EB),
            textTheme: GoogleFonts.dmMonoTextTheme(),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF1B2238),
            textTheme: GoogleFonts.dmMonoTextTheme(ThemeData.dark().textTheme),
            colorScheme: const ColorScheme.dark(
              surface: Color(0xFF252D47),
              onSurface: Colors.white,
            ),
          ),
          builder: (ctx, widget) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: widget!,
          ),
          home: const AuthGate(),
          routes: {
            '/login': (ctx) => MediaQuery(
                  data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(0.8)),
                  child: const LoginScreen(),
                ),
            '/signup': (ctx) => MediaQuery(
                  data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(0.9)),
                  child: const SignupScreen(),
                ),
            '/success': (_) => const AccountCreatedScreen(),
            '/home': (_) => const HomePage(),
            '/forgot-password': (ctx) => MediaQuery(
                  data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(0.9)),
                  child: const ForgotPasswordScreen(),
                ),
          },
        ),
      ),
    );
  }
}