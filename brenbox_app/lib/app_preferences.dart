import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final ValueNotifier<double> fontScaleNotifier = ValueNotifier(1.0);
final ValueNotifier<bool>   darkModeNotifier  = ValueNotifier(false);

const double kMinFontScale     = 0.5;
const double kMaxFontScale     = 1.5;
const double kDefaultFontScale = 1.0;

double sliderPosToScale(double pos) => 0.5 + pos / 100.0;
double scaleToSliderPos(double scale) => ((scale - 0.5) * 100.0).clamp(0.0, 100.0);

class AppColors {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  // Backgrounds
  static Color bg(BuildContext context) =>
      isDark(context) ? const Color(0xFF1B2238) : const Color(0xFFE5E7EB);
  static Color card(BuildContext context) =>
      isDark(context) ? const Color(0xFF252D47) : Colors.white;
  static Color input(BuildContext context) =>
      isDark(context) ? const Color(0xFF2A3352) : Colors.white;
  static Color fieldBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF354270) : const Color(0xFFE5E7EB);

  // Text
  static Color text(BuildContext context) =>
      isDark(context) ? Colors.white : Colors.black;
  static Color subtext(BuildContext context) =>
      isDark(context) ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

  // Borders
  static Color border(BuildContext context) =>
      isDark(context) ? const Color(0xFF3D4A6B) : Colors.black;

  // Dark chip / button background — visible dark blue in dark, near-black in light
  static Color chipBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF3D4A6B) : const Color(0xFF292929);

  // Navigation bar
  static Color navBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E2848) : Colors.white;

  // Slider
  static Color sliderActive(BuildContext context) =>
      isDark(context) ? Colors.white : Colors.black;
  static Color sliderInactive(BuildContext context) =>
      isDark(context) ? const Color(0xFF3D4A6B) : const Color(0xFFE5E7EB);
}

/// Single dialog that transitions from confirm → loading state for delete operations.
/// Avoids the "showDialog after await" BuildContext invalidation issue.
Future<void> confirmAndDeleteDialog(
  BuildContext context, {
  String title = 'Delete',
  String message = 'Are you sure you want to delete this? This action cannot be undone.',
  required Future<void> Function() onDelete,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dlgCtx) {
      bool loading = false;
      return PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (dlgCtx, setState) {
            if (loading) {
              return AlertDialog(
                backgroundColor: AppColors.card(dlgCtx),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.border(dlgCtx), width: 2),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Deleting...', style: GoogleFonts.dmMono(fontSize: 14)),
                  ],
                ),
              );
            }
            return AlertDialog(
              backgroundColor: AppColors.card(dlgCtx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.border(dlgCtx), width: 2),
              ),
              title: Text(
                title,
                style: GoogleFonts.dmMono(
                  fontWeight: FontWeight.bold,
                  color: AppColors.text(dlgCtx),
                ),
              ),
              content: Text(
                message,
                style: GoogleFonts.dmMono(
                  fontSize: 13,
                  color: AppColors.subtext(dlgCtx),
                  height: 1.5,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dlgCtx),
                  child: Text('Cancel',
                      style: GoogleFonts.dmMono(color: AppColors.subtext(dlgCtx))),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    setState(() => loading = true);
                    await onDelete();
                    if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text('Delete', style: GoogleFonts.dmMono()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB90000),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

/// Shows a red-accented confirmation dialog before a destructive action.
/// Returns true if the user confirmed, false if cancelled.
Future<bool> confirmDeleteDialog(
  BuildContext context, {
  String title = 'Delete',
  String message = 'Are you sure you want to delete this? This action cannot be undone.',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card(ctx),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border(ctx), width: 2),
      ),
      title: Text(
        title,
        style: GoogleFonts.dmMono(
          fontWeight: FontWeight.bold,
          color: AppColors.text(ctx),
        ),
      ),
      content: Text(
        message,
        style: GoogleFonts.dmMono(
          fontSize: 13,
          color: AppColors.subtext(ctx),
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel',
              style: GoogleFonts.dmMono(color: AppColors.subtext(ctx))),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: Text('Delete', style: GoogleFonts.dmMono()),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFB90000),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
