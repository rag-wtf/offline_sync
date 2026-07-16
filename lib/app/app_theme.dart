import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App theme configuration using flex_color_scheme for a modern RAG chat app.
class AppTheme {
  AppTheme._();

  // Custom colors based on UI Pro Max design system
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _secondaryBlue = Color(0xFF3B82F6);
  static const Color _accentOrange = Color(0xFFF97316);
  static const Color _backgroundLight = Color(0xFFF8FAFC);
  static const Color _backgroundDark = Color(0xFF0F172A);
  static const Color _textDark = Color(0xFF1E293B);

  /// Light theme
  static ThemeData get lightTheme {
    return FlexThemeData.light(
      colors: const FlexSchemeColor(
        primary: _primaryBlue,
        primaryContainer: Color(0xFFDBEAFE),
        secondary: _secondaryBlue,
        secondaryContainer: Color(0xFFBFDBFE),
        tertiary: _accentOrange,
        tertiaryContainer: Color(0xFFFED7AA),
      ),
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 7,
      scaffoldBackground: _backgroundLight,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        useM2StyleDividerInM3: true,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: 16,
        chipRadius: 12,
        cardRadius: 16,
        fabRadius: 16,
        dialogRadius: 20,
        appBarScrolledUnderElevation: 4,
        elevatedButtonRadius: 12,
        outlinedButtonRadius: 12,
        textButtonRadius: 12,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      fontFamily: GoogleFonts.inter().fontFamily,
    ).copyWith(
      textTheme: _buildTextTheme(Brightness.light),
    );
  }

  /// Dark theme
  static ThemeData get darkTheme {
    return FlexThemeData.dark(
      colors: const FlexSchemeColor(
        primary: Color(0xFF60A5FA),
        primaryContainer: Color(0xFF1E40AF),
        secondary: Color(0xFF93C5FD),
        secondaryContainer: Color(0xFF1D4ED8),
        tertiary: Color(0xFFFB923C),
        tertiaryContainer: Color(0xFFC2410C),
      ),
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 13,
      scaffoldBackground: _backgroundDark,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 20,
        useM2StyleDividerInM3: true,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: 16,
        chipRadius: 12,
        cardRadius: 16,
        fabRadius: 16,
        dialogRadius: 20,
        appBarScrolledUnderElevation: 4,
        elevatedButtonRadius: 12,
        outlinedButtonRadius: 12,
        textButtonRadius: 12,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      fontFamily: GoogleFonts.inter().fontFamily,
    ).copyWith(
      textTheme: _buildTextTheme(Brightness.dark),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    final baseColor = brightness == Brightness.light ? _textDark : Colors.white;
    return GoogleFonts.interTextTheme().copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        color: baseColor,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        color: baseColor,
      ),
      displaySmall: GoogleFonts.inter(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: baseColor,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: baseColor,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: baseColor,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: baseColor,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: baseColor,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: baseColor,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: baseColor.withValues(alpha: 0.7),
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: baseColor,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: baseColor,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: baseColor.withValues(alpha: 0.7),
      ),
    );
  }
}
