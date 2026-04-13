// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brenbox_app/main.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BrenBoxApp());

    // Verify that the login screen elements are present.
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('to BrenBox !!!'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text('forgot password?'), findsOneWidget);

    // Verify text fields are present
    expect(find.byType(TextField), findsNWidgets(2)); // Username and Password fields
  });

  testWidgets('Sign in button tap test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BrenBoxApp());

    // Find the SIGN IN button
    final signInButton = find.text('SIGN IN');
    expect(signInButton, findsOneWidget);

    // Tap the SIGN IN button
    await tester.tap(signInButton);
    await tester.pump();

    // The button should still be present after tapping
    expect(signInButton, findsOneWidget);
  });
}