import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum NeoSnackBarVariant { success, error }

class NeoSnackBar {
  NeoSnackBar._();

  static const Color successColor = Color(0xFF06D6A0);
  static const Color errorColor = Color(0xFFFF5D5D);
  static const Color borderColor = Colors.black;

  static void show(
    BuildContext context,
    String message, {
    required NeoSnackBarVariant variant,
    IconData? icon,
    Duration? duration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        build(message, variant: variant, icon: icon, duration: duration),
      );
  }

  static void success(
    BuildContext context,
    String message, {
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message,
      variant: NeoSnackBarVariant.success,
      icon: icon,
      duration: duration,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    IconData? icon,
    Duration duration = const Duration(seconds: 4),
  }) {
    show(
      context,
      message,
      variant: NeoSnackBarVariant.error,
      icon: icon,
      duration: duration,
    );
  }

  static SnackBar build(
    String message, {
    required NeoSnackBarVariant variant,
    IconData? icon,
    Duration? duration,
  }) {
    final isSuccess = variant == NeoSnackBarVariant.success;
    final backgroundColor = isSuccess ? successColor : errorColor;
    final resolvedIcon =
        icon ??
        (isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded);

    return SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: duration ?? Duration(seconds: isSuccess ? 3 : 4),
      content: Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: const [
              BoxShadow(
                color: borderColor,
                offset: Offset(4, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Icon(resolvedIcon, color: borderColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.itim(
                    color: borderColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
