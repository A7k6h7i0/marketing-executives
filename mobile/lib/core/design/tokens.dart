import 'package:flutter/material.dart';

/// Bestie / MyTaskKing design tokens (mirrors bestie shared_design_system).
class BestieTokens {
  static const cBg = Color(0xFFF4F6FB);
  static const cSurface = Color(0xFFFFFFFF);
  static const cSurface2 = Color(0xFFF1F4FA);
  static const cBorder = Color(0xFFE4E7EF);
  static const cBorderSoft = Color(0xFFEEF0F6);
  static const cText = Color(0xFF0B0E13);
  static const cTextSoft = Color(0xFF424A5B);
  static const cTextMuted = Color(0xFF828A9B);
  static const cTextFaint = Color(0xFFB4BAC6);
  static const cTextInvert = Color(0xFFFFFFFF);
  static const cBrand = Color(0xFF3A6DF0);
  static const cBrandSoft = Color(0xFFE7EEFF);
  static const cBrandStrong = Color(0xFF2A55C8);
  static const cAccent = Color(0xFF7C5CFF);
  static const cSuccess = Color(0xFF10B981);
  static const cSuccessSoft = Color(0xFFDCFCE7);
  static const cWarning = Color(0xFFF59E0B);
  static const cDanger = Color(0xFFEF4444);
  static const cDangerSoft = Color(0xFFFEE2E2);
  static const cInfo = Color(0xFF0EA5E9);

  static const gBrand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C5CFF), Color(0xFF3A6DF0), Color(0xFF3AA1FF)],
    stops: [0.0, 0.55, 1.0],
  );

  static const gLoginBackdrop = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C5CFF), Color(0xFF5B8CFF), Color(0xFF3AA1FF)],
  );

  static const rSm = 10.0;
  static const rMd = 14.0;
  static const rLg = 18.0;
  static const rXl = 24.0;
  static const rPill = 999.0;

  static const s1 = 8.0;
  static const s2 = 12.0;
  static const s3 = 16.0;
  static const s4 = 20.0;
  static const s5 = 24.0;
  static const s6 = 32.0;

  static const fwMedium = FontWeight.w500;
  static const fwSemibold = FontWeight.w600;
  static const fwBold = FontWeight.w700;
}
