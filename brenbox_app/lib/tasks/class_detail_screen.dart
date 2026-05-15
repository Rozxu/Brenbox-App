import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../app_preferences.dart';

class ClassDetailScreen extends StatelessWidget {
  final String classId;
  final String className;
  final String room;
  final String building;
  final String lecturerName;
  final String startTime;
  final String endTime;

  const ClassDetailScreen({
    Key? key,
    required this.classId,
    required this.className,
    required this.room,
    required this.building,
    required this.lecturerName,
    required this.startTime,
    required this.endTime,
  }) : super(key: key);

  Future<void> _deleteClass(BuildContext context) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card(context),
        title: Text(
          'Delete Class',
          style: GoogleFonts.dmMono(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete this class?',
          style: GoogleFonts.dmMono(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmMono(color: AppColors.subtext(context)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: GoogleFonts.dmMono(
                fontWeight: FontWeight.bold,
                color: const Color(0xFFB90000),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('timetable')
            .doc(classId)
            .delete();

        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Class deleted successfully',
                style: GoogleFonts.dmMono(),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error deleting class: ${e.toString()}',
                style: GoogleFonts.dmMono(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
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
                  Text(
                    'Class Details',
                    style: GoogleFonts.dmMono(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border(context), width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(context, 'Class', className),
                      const SizedBox(height: 16),
                      _buildDetailRow(context, 'Room', room.isEmpty ? '-' : room),
                      const SizedBox(height: 16),
                      _buildDetailRow(context, 'Building', building.isEmpty ? '-' : building),
                      const SizedBox(height: 16),
                      _buildDetailRow(context, 'Lecturer', lecturerName.isEmpty ? '-' : lecturerName),
                      const SizedBox(height: 16),
                      _buildDetailRow(context, 'Time', '$startTime - $endTime'),
                      const SizedBox(height: 32),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                // TODO: Implement edit functionality
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Edit functionality coming soon',
                                      style: GoogleFonts.dmMono(),
                                    ),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: BorderSide(color: AppColors.border(context), width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Edit',
                                style: GoogleFonts.dmMono(
                                  color: AppColors.text(context),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _deleteClass(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB90000),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Delete',
                                style: GoogleFonts.dmMono(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.dmMono(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.subtext(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.dmMono(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}