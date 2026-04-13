import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AccountCreatedScreen extends StatelessWidget {
  const AccountCreatedScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.check, color: Colors.white, size: 60),
              ),

              const SizedBox(height: 40),

              Text('Account Created!',
                  style: GoogleFonts.dmMono(
                      fontSize: 24, fontWeight: FontWeight.bold)),

              const SizedBox(height: 16),

              Text(
                'Congratulations! Your account has been\nsuccessfully created.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmMono(fontSize: 13, height: 1.5),
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                        context, '/login', (_) => false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF292929),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                  ),
                  child: Text('CONFIRM',
                      style: GoogleFonts.dmMono(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
