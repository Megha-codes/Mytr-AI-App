import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final Color backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;

  const AppCard({
    super.key,
    required this.child,
    this.backgroundColor = AppTheme.backgroundWhite,
    this.borderColor,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(AppTheme.cardPadding),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius ?? AppTheme.cardRadius),
        border: Border.all(
          color: borderColor ?? AppTheme.borderLight,
          width: 1.5,
        ),
      ),
      child: child,
    );
  }
}

