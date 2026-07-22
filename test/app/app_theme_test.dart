import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:offline_sync/app/app_theme.dart';

final String Function() _defaultGoogleFontsFamilyBuilder =
    AppTheme.googleFontsFamilyBuilder;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AppTheme', () {
    setUp(() {
      AppTheme.useGoogleFonts = false;
      AppTheme.googleFontsFamilyOverride = null;
      AppTheme.googleFontsFamilyBuilder = () => 'Inter';
      AppTheme.googleFontsTextStyleBuilder =
          ({
            required fontSize,
            required fontWeight,
            required color,
          }) => TextStyle(
            fontFamily: 'Inter',
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
          );
      AppTheme.googleFontsTextThemeBuilder = () => const TextTheme();
    });

    tearDown(() {
      AppTheme.useGoogleFonts = false;
      AppTheme.googleFontsFamilyOverride = null;
      AppTheme.googleFontsFamilyBuilder = () => 'Inter';
      AppTheme.googleFontsTextStyleBuilder =
          ({
            required fontSize,
            required fontWeight,
            required color,
          }) => TextStyle(
            fontFamily: 'Inter',
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
          );
      AppTheme.googleFontsTextThemeBuilder = () => const TextTheme();
    });

    test('lightTheme configures expected palette and typography', () {
      final theme = AppTheme.lightTheme;

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
      expect(theme.colorScheme.primary, const Color(0xFF2563EB));
      expect(theme.textTheme.titleLarge?.color, const Color(0xFF1E293B));
      expect(theme.textTheme.bodySmall?.color?.a, closeTo(0.7, 0.001));
    });

    test('darkTheme configures expected palette and typography', () {
      final theme = AppTheme.darkTheme;

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0F172A));
      expect(theme.colorScheme.primary, const Color(0xFF60A5FA));
      expect(theme.textTheme.titleLarge?.color, Colors.white);
      expect(theme.textTheme.labelSmall?.color?.a, closeTo(0.7, 0.001));
    });

    test('supports the Google Fonts code path', () {
      AppTheme.useGoogleFonts = true;
      AppTheme.googleFontsFamilyOverride = 'GoogleInter';
      AppTheme.googleFontsTextStyleBuilder =
          ({
            required fontSize,
            required fontWeight,
            required color,
          }) => TextStyle(
            fontFamily: 'GoogleInter',
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
          );
      AppTheme.googleFontsTextThemeBuilder = () => const TextTheme();

      final lightTheme = AppTheme.lightTheme;
      final darkTheme = AppTheme.darkTheme;

      expect(lightTheme.textTheme.bodyMedium?.fontFamily, 'GoogleInter');
      expect(darkTheme.textTheme.titleLarge?.fontFamily, 'GoogleInter');
    });

    test('uses Google Fonts family builder when no override is provided', () {
      AppTheme.useGoogleFonts = true;
      AppTheme.googleFontsFamilyBuilder = () => 'BuilderInter';
      AppTheme.googleFontsTextStyleBuilder =
          ({
            required fontSize,
            required fontWeight,
            required color,
          }) => TextStyle(
            fontFamily: 'BuilderInter',
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
          );
      AppTheme.googleFontsTextThemeBuilder = () => const TextTheme();

      final theme = AppTheme.lightTheme;

      expect(theme.textTheme.bodyLarge?.fontFamily, 'BuilderInter');
    });

    test('default Google Fonts family builder resolves a fallback family', () {
      AppTheme.useGoogleFonts = true;
      AppTheme.googleFontsFamilyBuilder = _defaultGoogleFontsFamilyBuilder;

      expect(AppTheme.googleFontsFamilyBuilder(), isNotEmpty);
    });

    test(
      'private constructor is intentionally unreachable except coverage seam',
      AppTheme.instantiateForCoverage,
    );
  });
}
