import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── Colour Tokens ──────────────────────────────────────────────────────────
  // Lightened one step across the board (2026-08-09): dark sections moved up
  // the same violet scale rather than toward gray, so they stay recognizably
  // "dark chrome" — just less heavy. Text colors (textPrimary/textOnDark)
  // deliberately left alone: lightening reading text works against the
  // "bolder" half of the same request by cutting contrast.
  static const Color backgroundDark    = Color(0xFF2E1065); // was 1B0B3A — one step up the violet scale
  static const Color backgroundDark2   = Color(0xFF4C1D95); // was 2A1357
  static const Color backgroundCream   = Color(0xFFF0F6FA); // was E9F1F7
  static const Color backgroundWhite   = Color(0xFFFFFFFF); // page bg
  static const Color backgroundSurface = Color(0xFFF7F5FF); // was F5F3FF

  static const Color borderLight       = Color(0xFFEDE6F7); // was E2D9F3
  static const Color borderDark        = Color(0xFF5B3A9E); // was 3D2070

  // Brand purple (replaces green — same symbol names kept for compatibility)
  static const Color brandGreen        = Color(0xFF8B5CF6); // was 7C3AED
  static const Color brandGreenDark    = Color(0xFF5B21B6); // was 4C1D95
  static const Color brandGreenLight   = Color(0xFFF5F3FF); // was EDE9FE

  // Explicit new brand tokens
  static const Color brandPurple       = Color(0xFF8B5CF6); // was 7C3AED
  static const Color brandPurpleMid    = Color(0xFF7C3AED); // was 6D28D9
  static const Color brandPurpleDeep   = Color(0xFF6D28D9); // was 5B21B6
  static const Color brandRed          = Color(0xFFEF4444); // was E11D2A
  static const Color brandRedDeep      = Color(0xFFDC2626); // was B0121C

  // Accent (cyan alias → purple for compatibility)
  static const Color accentCyan        = Color(0xFF8B5CF6); // was 7C3AED
  static const Color accentCyanLight   = Color(0xFFF5F3FF); // was EDE9FE
  static const Color accentOrange      = Color(0xFFFB923C); // was F97316, activity/calories
  static const Color accentOrangeDark  = Color(0xFFC2410C); // was 9A450D
  static const Color accentOrangeLight = Color(0xFFFFFAF3); // was FFF7ED

  // Glucose functional colours — lightened one step too, kept conservative
  // since these carry clinical meaning (still clearly distinct low/high/
  // hypo/hyper at a glance, just softer).
  static const Color glucoseHigh       = Color(0xFFFB923C); // was F97316
  static const Color glucoseHyper      = Color(0xFFF87171); // was EF4444
  static const Color glucoseLow        = Color(0xFFFDBA74); // was FB923C
  static const Color glucoseHypo       = Color(0xFFDC2626); // was B91C1C
  static const Color glucoseTarget     = brandPurple;

  // Text
  static const Color textPrimary       = Color(0xFF1B1430); // unchanged — see note above
  static const Color textSecondary     = Color(0xFF7A7390); // was 5E5872
  static const Color textHint          = Color(0xFFB5AFC4); // was 9A93AB
  static const Color textOnDark        = Color(0xFFFFFFFF);
  static const Color textOnDarkMuted   = Color(0xFFC9B6FF); // was B79CFF

  // XP gradient: purple → red
  static const Color xpGradientStart   = Color(0xFF8B5CF6); // was 7C3AED
  static const Color xpGradientEnd     = Color(0xFFEF4444); // was E11D2A

  // ── Typography Tokens (Inter) ──────────────────────────────────────────────
  // Bumped one size and one weight step across the board (2026-08-09).
  static TextStyle get displayLarge => GoogleFonts.inter(
    fontSize: 54,
    fontWeight: FontWeight.w900,
    color: textPrimary,
    letterSpacing: -1,
  );

  static TextStyle get displayMedium => GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: textPrimary,
  );

  static TextStyle get titleLarge => GoogleFonts.inter(
    fontSize: 23,
    fontWeight: FontWeight.w800,
    color: textPrimary,
  );

  static TextStyle get titleMedium => GoogleFonts.inter(
    fontSize: 21,
    fontWeight: FontWeight.w800,
    color: textPrimary,
  );

  static TextStyle get labelLarge => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: textPrimary,
  );

  static TextStyle get labelSmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w900,
    color: textSecondary,
    letterSpacing: 1.5,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
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
      scaffoldBackgroundColor: backgroundWhite,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandPurpleDeep,
        primary: brandPurpleDeep,
        secondary: brandRed,
        surface: backgroundWhite,
        brightness: Brightness.light,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).copyWith(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        labelLarge: labelLarge,
        labelSmall: labelSmall,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          borderSide: const BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          borderSide: const BorderSide(color: brandPurple, width: 2),
        ),
        hintStyle: GoogleFonts.inter(color: textHint, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandPurpleDeep,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(pillRadius),
          ),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundDark,
      colorScheme: const ColorScheme.dark(
        primary: brandPurple,
        secondary: brandRed,
        surface: backgroundDark,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
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
