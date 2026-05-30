import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';
import '../utils/oklch.dart';

/// Builds the Aetherfin "Nocturne" (dark) theme.
///
/// Per design spec §11.5:
///   - Material ripple is OFF globally (use scale/tint press states).
///   - Bouncy physics is OFF globally (use [ClampingScrollPhysics]).
///   - All text is theme-driven; no hard-coded colors in widgets.
ThemeData buildNocturneTheme() {
  return _buildTheme(AfColors.indigo600);
}

/// Same as [buildNocturneTheme] but substitutes the given [accent] colour
/// as the primary accent instead of the static indigo palette. Used when
/// a pastel colour from the current artwork is available.
ThemeData buildNocturneThemeFromAccent(Color accent) {
  // Convert accent to OKLCH and derive a full pastel palette from its hue.
  final oklch = srgbToOklch(accent);
  final triple = buildPastelTriple(oklch.h);
  return _buildTheme(accent, secondaryAccent: triple.muted);
}

ThemeData _buildTheme(Color primary, {Color? secondaryAccent}) {
  final secondary = secondaryAccent ?? primary;

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AfColors.surfaceCanvas,
    canvasColor: AfColors.surfaceCanvas,

    colorScheme: ColorScheme.dark(
      primary: primary,
      onPrimary: AfColors.textOnPrimary,
      primaryContainer: primary.withValues(alpha: 0.25),
      onPrimaryContainer: AfColors.textOnPrimary,
      secondary: secondary,
      onSecondary: AfColors.surfaceCanvas,
      secondaryContainer: secondary.withValues(alpha: 0.20),
      onSecondaryContainer: AfColors.textPrimary,
      tertiary: secondary,
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

    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) {
          return AfColors.indigo400;
        }
        if (states.contains(WidgetState.hovered)) {
          return AfColors.indigo300.withValues(alpha: 0.7);
        }
        return AfColors.surfaceMax.withValues(alpha: 0.6);
      }),
      trackColor: WidgetStatePropertyAll(
        AfColors.surfaceCanvas.withValues(alpha: 0.25),
      ),
      trackVisibility: const WidgetStatePropertyAll(false),
      thickness: const WidgetStatePropertyAll(10),
      radius: AfRadii.rPill,
      crossAxisMargin: 2,
      mainAxisMargin: 2,
    ),

    iconTheme: const IconThemeData(color: AfColors.textPrimary, size: 24),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AfColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: null,
      centerTitle: true,
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: Colors.transparent,
      modalBarrierColor: AfColors.surfaceScrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: AfRadii.rXl,
          topRight: AfRadii.rXl,
        ),
      ),
      showDragHandle: false,
    ),

    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AfRadii.borderXl),
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

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: AfColors.surfaceHigh,
      circularTrackColor: AfColors.surfaceHigh,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AfColors.surfaceBase,
      hintStyle: AfTypography.bodyLarge.copyWith(color: AfColors.textTertiary),
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
      focusedBorder: OutlineInputBorder(
        borderRadius: AfRadii.borderLg,
        borderSide: BorderSide(color: primary, width: 1),
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
        backgroundColor: primary,
        foregroundColor: AfColors.textOnPrimary,
        textStyle: AfTypography.titleSmall,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderPill),
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
        shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderPill),
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
        TargetPlatform.iOS: _AfHorizontalSlideTransition(),
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
