import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Lightened one step across the board (2026-08-09), same rule as
  // AppTheme: moved up the same hue's scale rather than toward gray, so
  // dark sections stay recognizably dark, just less heavy. `ink` (primary
  // reading text) deliberately left alone — see AppTheme's note.

  // ── Brand: purple-dominant ─────────────────────────────────────────────────
  static const brandPurple      = Color(0xFF8B5CF6); // was 7C3AED
  static const brandPurpleMid   = Color(0xFF7C3AED); // was 6D28D9
  static const brandPurpleDeep  = Color(0xFF6D28D9); // was 5B21B6
  static const brandAubergine   = Color(0xFF5B21B6); // was 4C1D95
  static const brandRed         = Color(0xFFEF4444); // was E11D2A
  static const brandRedDeep     = Color(0xFFDC2626); // was B0121C

  // ── Dark section colours ───────────────────────────────────────────────────
  static const darkAubergine    = Color(0xFF2E1065); // was 1B0B3A
  static const darkAubergine2   = Color(0xFF4C1D95); // was 2A1357
  static const phoneBg          = Color(0xFF1B0B3A); // was 0E0A1C

  // ── Stat number colours ────────────────────────────────────────────────────
  static const statPurple       = Color(0xFFC9B6FF); // was B79CFF
  static const statRed          = Color(0xFFFF9098); // was FF6B72

  // ── Page & section backgrounds ─────────────────────────────────────────────
  static const pageBg           = Color(0xFFFFFFFF);
  static const lightSectionBg   = Color(0xFFF0F6FA); // was E9F1F7

  // ── Text ──────────────────────────────────────────────────────────────────
  static const ink              = Color(0xFF1B1430);
  static const textMuted        = Color(0xFF7A7390); // was 5E5872
  static const textHint         = Color(0xFFB5AFC4); // was 9A93AB

  // ── Glucose range (functional, not brand) ─────────────────────────────────
  static const glucoseGreen     = Color(0xFF66BB6A); // was 4CAF50
  static const glucoseOrange    = Color(0xFFFFA726); // was FF9800
  static const glucoseRed       = Color(0xFFEF5350); // was E53935
  static const glucoseDarkRed   = Color(0xFFC62828); // was B71C1C
  static const glucoseDarkOrange = Color(0xFFEF6C00); // was E65100

  static const error            = brandRed;

  // ── Compatibility aliases (keep existing call-sites compiling) ─────────────
  static const limeAccent       = brandPurple;      // nav selected icon
  static const nearBlack        = darkAubergine;    // dark surfaces
  static const sageGreen        = pageBg;           // behind nav bar
  static const cyan             = brandPurple;
  static const electricIndigo   = brandPurple;
  static const vividOrange      = Color(0xFFFB923C); // was F97316, activity stats
  static const cameraBackground = phoneBg;
  static const darkSurface      = darkAubergine2;
  static const showcaseBackdrop = phoneBg;
  static const cream            = lightSectionBg;
  static const surfaceWhite     = pageBg;
  static const borderLight      = Color(0xFFEDE6F7); // was E2D9F3
  static const textSecondary    = textMuted;
}
