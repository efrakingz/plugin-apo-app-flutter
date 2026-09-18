import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design token system for APO Remote Studio.
/// All colors, typography, and decoration constants live here.
class AppTheme {
  AppTheme._();

  // ── Palette ──────────────────────────────────────────────────────────
  static const Color bgDeep    = Color(0xFF05070F);
  static const Color bgSurface = Color(0xFF0C1120);
  static const Color bgCard    = Color(0xFF101828);
  static const Color bgCardAlt = Color(0xFF141E2E);

  static const Color cyan       = Color(0xFF00EEFF);
  static const Color cyanBright = Color(0xFF80F8FF);
  static const Color cyanDim    = Color(0x3500EEFF);
  static const Color cyanGlow   = Color(0x1800EEFF);

  static const Color magenta    = Color(0xFFFF0090);
  static const Color magentaDim = Color(0x40FF0090);

  static const Color green      = Color(0xFF00FFB2);
  static const Color greenDim   = Color(0x3500FFB2);

  static const Color amber      = Color(0xFFFFAA00);
  static const Color amberDim   = Color(0x40FFAA00);

  static const Color textPrimary   = Color(0xFFDDE8FF);
  static const Color textSecondary = Color(0xFF6A82A0);
  static const Color textMuted     = Color(0xFF2E3F56);

  static const Color border     = Color(0xFF1B2840);
  static const Color borderGlow = Color(0x2800EEFF);

  // ── Theme ─────────────────────────────────────────────────────────────
  static ThemeData get dark {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: bgDeep,
      colorScheme: const ColorScheme.dark(
        primary: cyan,
        secondary: green,
        surface: bgSurface,
        error: magenta,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    );
  }

  // ── Text Styles ────────────────────────────────────────────────────────
  static TextStyle labelXs = GoogleFonts.inter(
    fontSize: 8,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.4,
    color: textSecondary,
  );

  static TextStyle labelSm = GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    color: textSecondary,
  );

  static TextStyle labelMd = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle heading = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
    color: textPrimary,
  );

  static TextStyle mono = GoogleFonts.spaceMono(
    fontSize: 10,
    color: textSecondary,
  );

  static TextStyle monoSm = GoogleFonts.spaceMono(
    fontSize: 8,
    color: textMuted,
  );

  // ── Decorations ────────────────────────────────────────────────────────
  static BoxDecoration cardDecor({Color? borderColor, bool glow = false}) =>
      BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? border, width: 1),
        boxShadow: glow
            ? [BoxShadow(color: cyanGlow, blurRadius: 24, spreadRadius: -4)]
            : null,
      );

  static BoxDecoration glowCard = BoxDecoration(
    color: bgCard,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: borderGlow, width: 1),
    boxShadow: [BoxShadow(color: cyanGlow, blurRadius: 28, spreadRadius: -6)],
  );

  // ── Gradients ─────────────────────────────────────────────────────────
  static const LinearGradient cyanGradient = LinearGradient(
    colors: [Color(0xFF00EEFF), Color(0xFF0080FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const RadialGradient bgRadial = RadialGradient(
    center: Alignment(-0.6, -0.8),
    radius: 1.6,
    colors: [Color(0x2000EEFF), Color(0xFF05070F)],
  );
}
