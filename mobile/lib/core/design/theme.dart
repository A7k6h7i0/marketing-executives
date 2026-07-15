import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

class BestieTheme {
  static ThemeData light() {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
    final text = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: BestieTokens.cText,
      displayColor: BestieTokens.cText,
    );

    return base.copyWith(
      scaffoldBackgroundColor: BestieTokens.cBg,
      colorScheme: ColorScheme.fromSeed(seedColor: BestieTokens.cBrand).copyWith(
        primary: BestieTokens.cBrand,
        onPrimary: BestieTokens.cTextInvert,
        surface: BestieTokens.cSurface,
        onSurface: BestieTokens.cText,
      ),
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: BestieTokens.cSurface.withValues(alpha: 0.92),
        foregroundColor: BestieTokens.cText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: BestieTokens.cSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rLg),
          side: const BorderSide(color: BestieTokens.cBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BestieTokens.cSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: const BorderSide(color: BestieTokens.cBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: const BorderSide(color: BestieTokens.cBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: const BorderSide(color: BestieTokens.cBrand, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BestieTokens.cBrand,
          foregroundColor: BestieTokens.cTextInvert,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BestieTokens.rSm)),
          textStyle: const TextStyle(fontWeight: BestieTokens.fwSemibold),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: BestieTokens.cSurface,
        elevation: 0,
        height: 64,
        indicatorColor: BestieTokens.cBrandSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? BestieTokens.fwSemibold : BestieTokens.fwMedium,
            color: selected ? BestieTokens.cBrandStrong : BestieTokens.cTextMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? BestieTokens.cBrandStrong : BestieTokens.cTextMuted,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: BestieTokens.cText,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: BestieTokens.fwMedium),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BestieTokens.rSm)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: BestieTokens.cBrand),
    );
  }
}
