import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Builds the Aetherfin "Nocturne" (dark) theme.
///
/// Per design spec §11.5:
///   - Material ripple is OFF globally (use scale/tint press states).
///   - Bouncy physics is OFF globally (use [ClampingScrollPhysics]).
///   - All text is theme-driven; no hard-coded colors in widgets.
ThemeData buildNocturneTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AfColors.surfaceCanvas,
    canvasColor: AfColors.surfaceCanvas,

    colorScheme: const ColorScheme.dark(
      primary: AfColors.indigo600,
      onPrimary: AfColors.textOnPrimary,
      primaryContainer: AfColors.indigo800,
      onPrimaryContainer: AfColors.textOnPrimary,

      secondary: AfColors.indigo300,
      onSecondary: AfColors.surfaceCanvas,
      secondaryContainer: AfColors.indigo900,
      onSecondaryContainer: AfColors.textPrimary,

      tertiary: AfColors.indigo400,
      onTertiary: AfColors.textOnPrimary,

      surface: AfColors.surfaceBase,
      onSurface: AfColors.textPrimary,
      onSurfaceVariant: AfColors.textSecondary,

      surfaceContainerLowest: AfColors.surfaceCanvas,
      surfaceContainerLow: AfColors.surfaceLow,
      surfaceContainer: AfColors.surfaceBase,
      surfaceContainerHigh: AfColors.surfaceRaised,
      surfaceContainerHighest: AfColors.surfaceHigh,

      error: AfColors.semanticError,
      onError: AfColors.textOnPrimary,

      outline: AfColors.surfaceMax,
      outlineVariant: AfColors.surfaceHigh,
    ),

    textTheme: AfTypography.textTheme,
    primaryTextTheme: AfTypography.textTheme,

    // No Material ripple. Anywhere.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,

    // No bouncy physics on iOS-style scroll. Audio-coupled feel
    // demands clamped motion.
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(AfColors.surfaceMax),
      thickness: WidgetStatePropertyAll(3),
      radius: AfRadii.rPill,
      crossAxisMargin: 2,
    ),

    iconTheme: const IconThemeData(
      color: AfColors.textPrimary,
      size: 24,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AfColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: null,
      centerTitle: true,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AfColors.surfaceHigh.withValues(alpha: 0.80),
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AfColors.surfaceHigh.withValues(alpha: 0.80),
      modalBarrierColor: AfColors.surfaceScrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: AfRadii.rXl,
          topRight: AfRadii.rXl,
        ),
      ),
      showDragHandle: true,
      dragHandleColor: AfColors.surfaceMax,
      dragHandleSize: const Size(32, 4),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AfColors.surfaceHigh.withValues(alpha: 0.85),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: AfRadii.borderXl,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AfColors.surfaceHigh,
      contentTextStyle: AfTypography.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
    ),

    dividerTheme: const DividerThemeData(
      color: AfColors.surfaceLow,
      thickness: 1,
      space: 0,
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AfColors.indigo300,
      linearTrackColor: AfColors.surfaceHigh,
      circularTrackColor: AfColors.surfaceHigh,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AfColors.surfaceBase,
      hintStyle: AfTypography.bodyLarge.copyWith(
        color: AfColors.textTertiary,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s16,
        vertical: AfSpacing.s16,
      ),
      border: const OutlineInputBorder(
        borderRadius: AfRadii.borderLg,
        borderSide: BorderSide(color: AfColors.surfaceHigh, width: 1),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: AfRadii.borderLg,
        borderSide: BorderSide(color: AfColors.surfaceHigh, width: 1),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: AfRadii.borderLg,
        borderSide: BorderSide(color: AfColors.indigo500, width: 1),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: AfRadii.borderLg,
        borderSide: BorderSide(color: AfColors.semanticError, width: 1),
      ),
      labelStyle: AfTypography.bodyMedium.copyWith(
        color: AfColors.textSecondary,
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AfColors.indigo600,
        foregroundColor: AfColors.textOnPrimary,
        textStyle: AfTypography.titleSmall,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: AfRadii.borderPill,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s24,
          vertical: AfSpacing.s16,
        ),
        minimumSize: const Size(0, AfSpacing.minHitTarget),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AfColors.textPrimary,
        textStyle: AfTypography.titleSmall,
        shape: const RoundedRectangleBorder(
          borderRadius: AfRadii.borderPill,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s12,
        ),
        minimumSize: const Size(0, AfSpacing.minHitTarget),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AfColors.textPrimary,
        minimumSize: const Size(AfSpacing.minHitTarget, AfSpacing.minHitTarget),
        padding: const EdgeInsets.all(AfSpacing.s12),
      ),
    ),

    listTileTheme: const ListTileThemeData(
      iconColor: AfColors.textSecondary,
      textColor: AfColors.textPrimary,
      tileColor: AfColors.surfaceBase,
      selectedTileColor: AfColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: AfRadii.borderMd),
    ),

    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _AfHorizontalSlideTransition(),
        TargetPlatform.iOS:     _AfHorizontalSlideTransition(),
        TargetPlatform.fuchsia: _AfHorizontalSlideTransition(),
      },
    ),

    // M3 Switch/Slider ignore global splashColor — force overlay off.
    switchTheme: const SwitchThemeData(
      overlayColor: WidgetStatePropertyAll(Colors.transparent),
      splashRadius: 0,
    ),

    sliderTheme: const SliderThemeData(
      overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
    ),
  );
}

/// Push: new page slides in from the right at `easeStandard / 240ms`.
/// Pop: current page slides out to the right.
/// See `aetherfin-motion.md` §5.7.
class _AfHorizontalSlideTransition extends PageTransitionsBuilder {
  const _AfHorizontalSlideTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced) {
      return FadeTransition(opacity: animation, child: child);
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: AfCurves.easeStandard,
      reverseCurve: AfCurves.easeStandard,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }
}
