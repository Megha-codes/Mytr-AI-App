import 'package:flutter/material.dart';
import '../app_colors.dart';

enum ButtonVariant { primary, secondary, tertiary }

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = ButtonVariant.primary,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;

    switch (variant) {
      case ButtonVariant.primary:
        backgroundColor = AppColors.limeAccent;
        textColor = AppColors.nearBlack;
        break;
      case ButtonVariant.secondary:
        backgroundColor = AppColors.cyan;
        textColor = Colors.white;
        break;
      case ButtonVariant.tertiary:
        backgroundColor = AppColors.nearBlack;
        textColor = Colors.white;
        break;
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.5),
          disabledForegroundColor: textColor.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
          elevation: 0,
        ),
        child: isLoading 
            ? SizedBox(
                width: 20, 
                height: 20, 
                child: CircularProgressIndicator(color: textColor, strokeWidth: 2)
              )
            : Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
