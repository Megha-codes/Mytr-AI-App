import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── Colour Tokens ──────────────────────────────────────────────────────────
  static const Color backgroundDark    = Color(0xFF111111);
  static const Color backgroundCream   = Color(0xFFF8F3EC);
  static const Color backgroundWhite   = Color(0xFFFFFFFF);
  static const Color backgroundSurface = Color(0xFFFAFAFA);
  static const Color borderLight       = Color(0xFFDDD5C5);
  static const Color borderDark        = Color(0xFFC0B8A8);

  static const Color brandGreen        = Color(0xFF6DC534);
  static const Color brandGreenDark    = Color(0xFF2D5A14);
  static const Color brandGreenLight   = Color(0xFFE4E9DE);

  static const Color accentCyan        = Color(0xFF00C2E0);
  static const Color accentCyanLight   = Color(0xFFE0F7FA);

  static const Color accentOrange      = Color(0xFFF97316);
  static const Color accentOrangeDark  = Color(0xFF9A450D);
  static const Color accentOrangeLight = Color(0xFFFFF7ED);

  static const Color glucoseHigh       = Color(0xFFF97316);
  static const Color glucoseHyper      = Color(0xFFEF4444);
  static const Color glucoseLow        = Color(0xFFFB923C);
  static const Color glucoseHypo       = Color(0xFFB91C1C);
  static const Color glucoseTarget     = brandGreen;

  static const Color textPrimary       = Color(0xFF111111);
  static const Color textSecondary     = Color(0xFFB0A898);
  static const Color textHint          = Color(0xFFD1D1D1);
  static const Color textOnDark        = Color(0xFFFFFFFF);
  static const Color textOnDarkMuted   = Color(0xFFB0B0B0);

  static const Color xpGradientStart   = Color(0xFF00C2E0);
  static const Color xpGradientEnd     = Color(0xFF6DC534);

  // ── Typography Tokens ──────────────────────────────────────────────────────
  static TextStyle get displayLarge => GoogleFonts.plusJakartaSans(
    fontSize: 48,
    fontWeight: FontWeight.w800,
    color: textPrimary,
    letterSpacing: -1,
  );

  static TextStyle get displayMedium => GoogleFonts.plusJakartaSans(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: textPrimary,
  );

  static TextStyle get titleLarge => GoogleFonts.plusJakartaSans(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static TextStyle get titleMedium => GoogleFonts.plusJakartaSans(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static TextStyle get labelLarge => GoogleFonts.plusJakartaSans(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static TextStyle get labelSmall => GoogleFonts.plusJakartaSans(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    color: textSecondary,
    letterSpacing: 1.5,
  );

  static TextStyle get bodyMedium => GoogleFonts.plusJakartaSans(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  static TextStyle get bodyLarge => GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get bodySmall => GoogleFonts.plusJakartaSans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  // ── Spacing Tokens ─────────────────────────────────────────────────────────
  static const double screenPadding = 24.0;
  static const double cardPadding   = 16.0;
  static const double cardRadius    = 16.0;
  static const double pillRadius    = 100.0;
  static const double avatarRadius  = 24.0;

  // ── Main Theme ─────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundCream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandGreen,
        primary: brandGreen,
        surface: backgroundWhite,
      ),
      textTheme: TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        labelLarge: labelLarge,
        labelSmall: labelSmall,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundDark,
      colorScheme: const ColorScheme.dark(
        primary: brandGreen,
        surface: backgroundDark,
      ),
      textTheme: TextTheme(
        displayLarge: displayLarge.copyWith(color: textOnDark),
        displayMedium: displayMedium.copyWith(color: textOnDark),
        titleLarge: titleLarge.copyWith(color: textOnDark),
        titleMedium: titleMedium.copyWith(color: textOnDark),
        labelLarge: labelLarge.copyWith(color: textOnDark),
        labelSmall: labelSmall.copyWith(color: textOnDarkMuted),
        bodyMedium: bodyMedium.copyWith(color: textOnDark),
        bodySmall: bodySmall.copyWith(color: textOnDarkMuted),
      ),
    );
  }
}
