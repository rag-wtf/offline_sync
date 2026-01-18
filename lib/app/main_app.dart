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
    return MaterialApp(
      title: 'Offline RAG Sync',
      theme: FlexThemeData.light(
        colors: const FlexSchemeColor(
          primary: Color(0xFF3B82F6),
          primaryContainer: Color(0xFFDBEAFE),
          secondary: Color(0xFF60A5FA),
          secondaryContainer: Color(0xFFDBEAFE),
          tertiary: Color(0xFFF97316),
          tertiaryContainer: Color(0xFFFFEDD5),
          appBarColor: Color(0xFFF97316),
          error: Color(0xFFB00020),
        ),
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 7,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 10,
          useM2StyleDividerInM3: true,
          defaultRadius: 12,
          elevatedButtonSchemeColor: SchemeColor.onPrimaryContainer,
          elevatedButtonSecondarySchemeColor: SchemeColor.primaryContainer,
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
          cardRadius: 12,
          popupMenuRadius: 8,
          popupMenuElevation: 3,
          alignedDropdown: true,
          useInputDecoratorThemeInDialogs: true,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      ),
      darkTheme: FlexThemeData.dark(
        colors: const FlexSchemeColor(
          primary: Color(0xFF3B82F6),
          primaryContainer: Color(0xFF1E3A8A),
          secondary: Color(0xFF60A5FA),
          secondaryContainer: Color(0xFF1E40AF),
          tertiary: Color(0xFFF97316),
          tertiaryContainer: Color(0xFF9A3412),
          appBarColor: Color(0xFF9A3412),
          error: Color(0xFFCF6679),
        ),
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 13,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 20,
          useM2StyleDividerInM3: true,
          defaultRadius: 12,
          elevatedButtonSchemeColor: SchemeColor.onPrimaryContainer,
          elevatedButtonSecondarySchemeColor: SchemeColor.primaryContainer,
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
          cardRadius: 12,
          popupMenuRadius: 8,
          popupMenuElevation: 3,
          alignedDropdown: true,
          useInputDecoratorThemeInDialogs: true,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      initialRoute: Routes.startupView,
      onGenerateRoute: StackedRouter().onGenerateRoute,
      navigatorKey: StackedService.navigatorKey,
    );
  }
}
