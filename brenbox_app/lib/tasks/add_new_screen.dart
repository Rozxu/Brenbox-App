import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'add_class_screen.dart';
import 'add_task_screen.dart';
import 'add_exam_screen.dart';

class AddNewScreen extends StatefulWidget {
  const AddNewScreen({Key? key}) : super(key: key);

  @override
  State<AddNewScreen> createState() => _AddNewScreenState();
}

class _AddNewScreenState extends State<AddNewScreen> {
  int _selectedTab = 0; // 0 = Classes, 1 = Task, 2 = Exams

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  // Back Button
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6B7280),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Title
                  Text(
                    'ADD NEW',
                    style: GoogleFonts.dmMono(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Tab Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Row(
                  children: [
                    _buildTab('CLASSES', 0),
                    _buildTab('TASK', 1),
                    _buildTab('EXAMS', 2),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Content
            Expanded(
              child: _selectedTab == 0
                  ? const AddClassScreen()
                  : _selectedTab == 1
                      ? const AddTaskScreen()
                      : const AddExamScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    
    // Define colors based on tab
    Color fillColor;
    Color borderColor;
    
    if (index == 0) {
      // Classes tab colors
      fillColor = isSelected ? const Color(0xFFFFEBEE) : Colors.transparent;
      borderColor = isSelected ? const Color(0xFFB90000) : Colors.transparent;
    } else if (index == 1) {
      // Task tab colors
      fillColor = isSelected ? const Color(0xFFEBF5FF) : Colors.transparent;
      borderColor = isSelected ? const Color(0xFF008BB9) : Colors.transparent;
    } else {
      // Exams tab colors
      fillColor = isSelected ? const Color(0xFFFEFFE6) : Colors.transparent;
      borderColor = isSelected ? const Color(0xFF9AB900) : Colors.transparent;
    }
    
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: borderColor, width: 2)
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmMono(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}