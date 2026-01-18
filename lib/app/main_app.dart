import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/l10n/l10n.dart';
import 'package:stacked_services/stacked_services.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Design System Colors
    const primary = Color(0xFF3B82F6);
    const secondary = Color(0xFF60A5FA);
    const background = Color(0xFFF8FAFC);
    const text = Color(0xFF1E293B);

    return MaterialApp(
      title: 'Offline RAG Sync',
      theme:
          FlexThemeData.light(
            colors: const FlexSchemeColor(
              primary: primary,
              secondary: secondary,
              appBarColor: secondary,
            ),
            surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
            blendLevel: 7,
            subThemesData: const FlexSubThemesData(
              blendOnLevel: 10,
              useMaterial3Typography: true,
              useM2StyleDividerInM3: true,
              defaultRadius: 12,
              elevatedButtonSchemeColor: SchemeColor.primary,
              elevatedButtonSecondarySchemeColor: SchemeColor.surface,
              outlinedButtonOutlineSchemeColor: SchemeColor.primary,
              toggleButtonsBorderSchemeColor: SchemeColor.primary,
              segmentedButtonSchemeColor: SchemeColor.primary,
              segmentedButtonBorderSchemeColor: SchemeColor.primary,
              unselectedToggleIsColored: true,
              sliderValueTinted: true,
              inputDecoratorSchemeColor: SchemeColor.primary,
              inputDecoratorBackgroundAlpha: 31,
              inputDecoratorUnfocusedHasBorder: false,
              inputDecoratorFocusedBorderWidth: 1,
              inputDecoratorPrefixIconSchemeColor: SchemeColor.primary,
              fabUseShape: true,
              fabAlwaysCircular: true,
              chipSchemeColor: SchemeColor.primary,
              cardElevation: 1,
            ),
            keyColors: const FlexKeyColors(
              useSecondary: true,
              useTertiary: true,
            ),
            fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
          ).copyWith(
            scaffoldBackgroundColor: background,
            textTheme: GoogleFonts.plusJakartaSansTextTheme().apply(
              bodyColor: text,
              displayColor: text,
            ),
          ),
      darkTheme:
          FlexThemeData.dark(
            colors: const FlexSchemeColor(
              primary: primary,
              secondary: secondary,
            ),
            surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
            blendLevel: 13,
            subThemesData: const FlexSubThemesData(
              blendOnLevel: 20,
              useMaterial3Typography: true,
              useM2StyleDividerInM3: true,
              defaultRadius: 12,
              elevatedButtonSchemeColor: SchemeColor.primary,
              elevatedButtonSecondarySchemeColor: SchemeColor.surface,
              outlinedButtonOutlineSchemeColor: SchemeColor.primary,
              toggleButtonsBorderSchemeColor: SchemeColor.primary,
              segmentedButtonSchemeColor: SchemeColor.primary,
              segmentedButtonBorderSchemeColor: SchemeColor.primary,
              unselectedToggleIsColored: true,
              sliderValueTinted: true,
              inputDecoratorSchemeColor: SchemeColor.primary,
              inputDecoratorBackgroundAlpha: 43,
              inputDecoratorUnfocusedHasBorder: false,
              inputDecoratorFocusedBorderWidth: 1,
              inputDecoratorPrefixIconSchemeColor: SchemeColor.primary,
              fabUseShape: true,
              fabAlwaysCircular: true,
              chipSchemeColor: SchemeColor.primary,
              cardElevation: 1,
            ),
            keyColors: const FlexKeyColors(
              useSecondary: true,
              useTertiary: true,
            ),
            fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
          ).copyWith(
            textTheme: GoogleFonts.plusJakartaSansTextTheme(
              ThemeData.dark().textTheme,
            ),
          ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      initialRoute: Routes.startupView,
      onGenerateRoute: StackedRouter().onGenerateRoute,
      navigatorKey: StackedService.navigatorKey,
    );
  }
}
