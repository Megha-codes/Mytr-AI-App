import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Brand: purple-dominant ─────────────────────────────────────────────────
  static const brandPurple      = Color(0xFF7C3AED); // light purple
  static const brandPurpleMid   = Color(0xFF6D28D9); // mid purple
  static const brandPurpleDeep  = Color(0xFF5B21B6); // primary purple
  static const brandAubergine   = Color(0xFF4C1D95); // deep purple
  static const brandRed         = Color(0xFFE11D2A); // red accent (.AI)
  static const brandRedDeep     = Color(0xFFB0121C); // red hover/deep

  // ── Dark section colours ───────────────────────────────────────────────────
  static const darkAubergine    = Color(0xFF1B0B3A); // headers, nav bar, CTAs
  static const darkAubergine2   = Color(0xFF2A1357); // card/button on dark
  static const phoneBg          = Color(0xFF0E0A1C); // deep screen bg

  // ── Stat number colours ────────────────────────────────────────────────────
  static const statPurple       = Color(0xFFB79CFF); // numbers on dark
  static const statRed          = Color(0xFFFF6B72); // danger numbers on dark

  // ── Page & section backgrounds ─────────────────────────────────────────────
  static const pageBg           = Color(0xFFFFFFFF);
  static const lightSectionBg   = Color(0xFFE9F1F7);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const ink              = Color(0xFF1B1430);
  static const textMuted        = Color(0xFF5E5872);
  static const textHint         = Color(0xFF9A93AB);

  // ── Glucose range (functional, not brand) ─────────────────────────────────
  static const glucoseGreen     = Color(0xFF4CAF50);
  static const glucoseOrange    = Color(0xFFFF9800);
  static const glucoseRed       = Color(0xFFE53935);
  static const glucoseDarkRed   = Color(0xFFB71C1C);
  static const glucoseDarkOrange = Color(0xFFE65100);

  static const error            = brandRed;

  // ── Compatibility aliases (keep existing call-sites compiling) ─────────────
  static const limeAccent       = brandPurple;      // nav selected icon
  static const nearBlack        = darkAubergine;    // dark surfaces
  static const sageGreen        = pageBg;           // behind nav bar
  static const cyan             = brandPurple;
  static const electricIndigo   = brandPurple;
  static const vividOrange      = Color(0xFFF97316); // activity stats (keep)
  static const cameraBackground = phoneBg;
  static const darkSurface      = darkAubergine2;
  static const showcaseBackdrop = phoneBg;
  static const cream            = lightSectionBg;
  static const surfaceWhite     = pageBg;
  static const borderLight      = Color(0xFFE2D9F3); // lavender-tinted border
  static const textSecondary    = textMuted;
}
