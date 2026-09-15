// Content Doctor native dark theme.
//
// Tokens, geometry, and motion are lifted from cdc/cd-ui.html. Existing
// public Sand* names remain so the shared native screens keep compiling.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Content Doctor dark tokens.
abstract final class SandDark {
  static const Color surfaceLowest = Color(0xFF0C1014); // --bg
  static const Color surfaceLow = Color(0xFF11161B); // --bg2
  static const Color surfaceBase = Color(0xFF191E24); // --card
  static const Color surfaceHigh = Color(0xFF232931); // --card2
  static const Color surfaceHighest = Color(0xFF2A2A30); // --line
  static const Color surfaceDim = Color(0xFF050506); // phone/media well

  static const Color primary = Color(0xFFE8202E); // --red
  static const Color primaryBright = Color(0xFFFF3D49); // --red2
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF2A0D12);
  static const Color onPrimaryContainer = Color(0xFFF4F4F6);

  // Selected controls are red in the supplied packet. Blue is retained for
  // informational states through [info].
  static const Color secondary = primary;
  static const Color secondaryBright = primaryBright;
  static const Color onSecondary = onPrimary;
  static const Color secondaryContainer = primaryContainer;
  static const Color onSecondaryContainer = onPrimaryContainer;
  static const Color info = Color(0xFF4A9EFF); // --blue

  static const Color outline = Color(0xFF2A2A30); // --line
  static const Color outlineStrong = Color(0xFF33333C);

  static const Color onSurfaceBase = Color(0xFFF4F4F6); // --ink
  static const Color onSurfaceHighest = onSurfaceBase;
  static const Color onSurfaceHigh = onSurfaceBase;
  static const Color onSurfaceLow = Color(0xFF9BA1AB); // --mut
  static const Color onSurfaceLowest = Color(0xFF858C96); // --dim

  static const Color onSurfaceBaseSubtle = onSurfaceLow;
  static const Color onSurfaceBaseDisabled = onSurfaceLowest;

  static const Color warning = Color(0xFFD99A2B); // --amber
  static const Color warningBright = warning;
  static const Color warningContainer = Color(0xFF2A2116);
  static const Color onWarning = Color(0xFF1A1204);

  static const Color success = Color(0xFF3FB96B); // --green
  static const Color error = primary;
  static const Color errorBright = primaryBright;
  static const Color errorContainer = Color(0xFF2A1917);
  static const Color onError = onPrimary;
  static const Color onErrorContainer = onPrimaryContainer;

  static const Color overlayPress = Color(0x1AE8202E); // red @ 10%
  static const Color overlayHover = Color(0x0DE8202E);
  static const Color overlayFocus = Color(0x3DE8202E);
  static const Color scrim = Color(0xDD050506);
}

/// Content Doctor geometry. Legacy names remain for native call sites.
abstract final class SandRadius {
  static const double r0 = 0;
  static const double r1 = 6; // status marks
  static const double r2 = 10; // thumbnails and compact controls
  static const double r3 = 13; // inner cards
  static const double r4 = 16; // outer cards
  static const double r5 = 26; // phone shell

  // Legacy names, revalued and aliased.
  static const double xs = r1;
  static const double base = r2;
  static const double xl = 12; // --r-btn
  static const double xxl = r3;
  static const double xxxl = r4;
  static const double xxxxl = r5;
  static const double pill = 999;
}

/// Spacing. Unchanged 4px grid, this retheme is form and colour, not layout.
abstract final class SandSpace {
  static const double unit = 4;
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
}

/// Content widths, and where the layout changes shape.
///
/// Every screen in this product was drawn as one phone-width column. Build 52
/// capped that column at [readable] and centred it, which stopped the app
/// being smeared across an iPad's glass but left 331 pt of dark ground down
/// each side of a 12.9" in landscape. Zion rejected that: he wants the width
/// used, not surrendered.
///
/// So [readable] is no longer a cap on a list of cards. It is the **breakpoint**:
/// at or above it a list becomes a grid and a detail screen becomes two panes;
/// below it — every iPhone, every Split View pane — nothing in this class does
/// anything at all, and the phone layout that shipped is the layout that runs.
///
/// It stays a genuine cap in the two places where more width is worse rather
/// than better: a modal sheet ([sheet]) and a single block of body prose.
///
/// No colour, type style, spacing unit or motion curve lives here. Every
/// number sits on the same 4 px grid as [SandSpace].
abstract final class SandLayout {
  /// The breakpoint, and the cap for a block of prose. 4 x 176.
  ///
  /// Chosen in build 52 and kept: it is above every iPhone width the app
  /// ships to (430 pt on a Pro Max) and above the widest Split View pane a
  /// test exercises (420 pt), so nothing below it can be reached by an
  /// iPhone.
  static const double readable = 704;

  /// A modal sheet. 4 x 140. Still a cap: a sheet is a focused question.
  static const double sheet = 560;

  /// The width one card in a grid wants to be. 4 x 105.
  ///
  /// A reel card is a 60 pt poster beside a text column; at 420 pt that text
  /// column is roughly what it is on an iPhone, which is what makes a grid of
  /// them read as the same card rather than a redrawn one.
  static const double card = 420;

  /// Where a fixed side rail earns its place beside the content it serves —
  /// the player's control deck, Team's roster. 4 x 225.
  ///
  /// Below this a rail would leave the media next to it narrower than a
  /// phone, so those two screens stay stacked.
  static const double roomy = 900;

  /// True once the app has iPad width to spend.
  static bool isWide(double width) => width >= readable;

  /// True once there is room for a fixed rail beside full content.
  static bool isRoomy(double width) => width >= roomy;

  /// How many cards sit side by side at [width].
  ///
  /// One below the breakpoint — that is the phone, unchanged. Above it, as
  /// many [card]-ish columns as fit, never more than three, because a fourth
  /// column of reel cards makes the poster the only thing you can read.
  ///
  /// MEASURED, cards per row / card width:
  ///   744 -> 2 / 372   834 -> 2 / 417   1024 -> 2 / 512
  ///  1133 -> 3 / 377  1194 -> 3 / 398   1366 -> 3 / 455
  static int columnsFor(double width) =>
      width < readable ? 1 : (width / card).round().clamp(2, 3);
}

/// Border weights. Four, and they mean different things.
///
/// A 1px hairline never indicates state. State is 1.5 -> 2 plus a colour
/// change; that step is visible at phone density, a colour-only change at 1px
/// is not, which is part of why the previous theme read as unchanged.
abstract final class SandBorder {
  static const double hairline = 1; // card edges, dividers, resting chip
  static const double interactive = 1.5; // resting border of a pressable
  static const double selected = 2; // selected/active/focused
  static const double marker = 3; // leading bar on badges and rows
}

/// Control heights.
abstract final class SandSize {
  static const double btnSm = 32;
  static const double btnMd = 44; // default (was 48, the drop is deliberate)
  static const double btnLg = 52;
  static const double chip = 30;
  static const double segment = 36;
  static const double field = 44;
  static const double stateMark = 20;
}

/// Motion.
abstract final class SandMotion {
  static const Duration micro = Duration(milliseconds: 100);
  static const Duration fast = micro;
  static const Duration base = Duration(milliseconds: 200);
  static const Duration screen = Duration(milliseconds: 300);
  static const Duration hero = Duration(milliseconds: 380);
  static const Duration progress = Duration(milliseconds: 900);
  static const Duration skeleton = Duration(milliseconds: 1400);
  static const Duration stagger = Duration(milliseconds: 60);
  static const Cubic easeOut = Cubic(0, 0, 0.2, 1);
  static const Cubic easeInOut = Cubic(0.4, 0, 0.2, 1);
  static const Cubic easeIn = Cubic(0.4, 0, 1, 1);
  static const Cubic spring = Cubic(0.34, 1.56, 0.64, 1);
}

/// Content Doctor's Inter and JetBrains Mono type families.
abstract final class SandType {
  static const String sans = 'Inter';
  static const String mono = 'JetBrains Mono';
  static const List<String> sansFallback = <String>[
    'Inter',
    '.SF Pro Text',
    'system-ui',
  ];
}

/// The Material text theme.
///
/// Native type scale aligned to the supplied Content Doctor packet.
TextTheme _sandTextTheme(Color onSurface, Color onSurfaceVariant) {
  TextStyle s(
    double size,
    double height,
    FontWeight weight, {
    double tracking = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: SandType.sans,
    fontFamilyFallback: SandType.sansFallback,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: tracking,
    color: color ?? onSurface,
  );

  return TextTheme(
    displayLarge: s(40, 1.05, FontWeight.w700, tracking: -1.2),
    displayMedium: s(32, 1.13, FontWeight.w700, tracking: -0.8),
    displaySmall: s(26, 1.19, FontWeight.w600, tracking: -0.6),
    headlineLarge: s(26, 1.19, FontWeight.w600, tracking: -0.6),
    headlineMedium: s(22, 1.27, FontWeight.w600, tracking: -0.4),
    headlineSmall: s(19, 1.32, FontWeight.w600, tracking: -0.3),
    titleLarge: s(19, 1.32, FontWeight.w600, tracking: -0.3),
    titleMedium: s(17, 1.41, FontWeight.w600, tracking: -0.2),
    titleSmall: s(15, 1.47, FontWeight.w600),
    bodyLarge: s(16, 1.50, FontWeight.w400),
    bodyMedium: s(15, 1.47, FontWeight.w400),
    bodySmall: s(
      13,
      1.38,
      FontWeight.w400,
      tracking: 0.1,
      color: onSurfaceVariant,
    ),
    // Buttons: 15 / w600 / +0.2.
    labelLarge: s(15, 1.20, FontWeight.w600, tracking: 0.2),
    // Chips and tabs: 13 / w500 / +0.2.
    labelMedium: s(13, 1.23, FontWeight.w500, tracking: 0.2),
    // State marks, eyebrows, timestamps: 11 / w700 / +0.4.
    labelSmall: s(11, 1.27, FontWeight.w700, tracking: 0.4),
  );
}

/// The Content Doctor scheme as a Material 3 `ColorScheme`.
const ColorScheme sandIronScheme = ColorScheme(
  brightness: Brightness.dark,

  primary: SandDark.primary,
  onPrimary: SandDark.onPrimary,
  primaryContainer: SandDark.primaryContainer,
  onPrimaryContainer: SandDark.onPrimaryContainer,

  // The packet uses red for selected controls.
  secondary: SandDark.secondary,
  onSecondary: SandDark.onSecondary,
  secondaryContainer: SandDark.secondaryContainer,
  onSecondaryContainer: SandDark.onSecondaryContainer,

  // Warning rides the tertiary slot; there is no third brand hue.
  tertiary: SandDark.warning,
  onTertiary: SandDark.onWarning,
  tertiaryContainer: SandDark.warningContainer,
  onTertiaryContainer: SandDark.warningBright,

  error: SandDark.error,
  onError: SandDark.onError,
  errorContainer: SandDark.errorContainer,
  onErrorContainer: SandDark.onErrorContainer,

  surface: SandDark.surfaceLowest,
  onSurface: SandDark.onSurfaceBase,
  onSurfaceVariant: SandDark.onSurfaceLow,

  // surfaceDim is the media well, BELOW the ground, not above it.
  surfaceDim: SandDark.surfaceDim,
  surfaceBright: SandDark.surfaceHighest,
  surfaceContainerLowest: SandDark.surfaceLowest,
  surfaceContainerLow: SandDark.surfaceLow,
  surfaceContainer: SandDark.surfaceBase,
  surfaceContainerHigh: SandDark.surfaceHigh,
  surfaceContainerHighest: SandDark.surfaceHighest,

  outline: SandDark.outlineStrong,
  outlineVariant: SandDark.outline,

  // No light inverse plate: a white slab in a dark app is the "glass/soft
  // card" look STYLESEED forbids, and it flares on OLED.
  inverseSurface: SandDark.surfaceHigh,
  onInverseSurface: SandDark.onSurfaceBase,
  inversePrimary: SandDark.primaryContainer,

  // Elevation tint is switched off everywhere; this is only a fallback.
  surfaceTint: Color(0x00000000),

  shadow: Color(0xFF000000),
  scrim: SandDark.scrim,
);

/// The app theme. Dark only.
ThemeData sandIronTheme() {
  final TextTheme text = _sandTextTheme(
    SandDark.onSurfaceBase,
    SandDark.onSurfaceLow,
  );

  // --- Button shapes ----------------------------------------------------
  final RoundedRectangleBorder controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(SandRadius.r2),
  );

  return ThemeData(
    useMaterial3: true,
    platform: TargetPlatform.iOS,
    brightness: Brightness.dark,
    colorScheme: sandIronScheme,
    scaffoldBackgroundColor: SandDark.surfaceLowest,
    canvasColor: SandDark.surfaceLowest,
    dividerColor: SandDark.outline,
    textTheme: text,
    primaryTextTheme: text,

    // No shadows anywhere. Depth is a surface step plus a hairline.
    applyElevationOverlayColor: false,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: SandDark.overlayPress,
    hoverColor: SandDark.overlayHover,
    focusColor: SandDark.overlayFocus,

    cupertinoOverrideTheme: const CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: SandDark.primary,
      scaffoldBackgroundColor: SandDark.surfaceLowest,
      barBackgroundColor: SandDark.surfaceLow,
      primaryContrastingColor: SandDark.onPrimary,
    ),

    // App bar sits on the ground colour so there is no seam.
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: SandDark.surfaceLowest,
      foregroundColor: SandDark.onSurfaceBase,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.3,
        color: SandDark.onSurfaceBase,
      ),
      iconTheme: const IconThemeData(color: SandDark.onSurfaceLow, size: 22),
      actionsIconTheme: const IconThemeData(
        color: SandDark.onSurfaceLow,
        size: 22,
      ),
    ),

    // Cards: one step above the ground, radius 10, hairline, no shadow.
    // Bottom margin 12 (was 16), the tighter list rhythm reads as a
    // different app.
    cardTheme: CardThemeData(
      color: SandDark.surfaceBase,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: SandSpace.x3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SandRadius.r3),
        side: const BorderSide(
          color: SandDark.outline,
          width: SandBorder.hairline,
        ),
      ),
    ),

    // Primary actions use Content Doctor red.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.disabled)) return SandDark.surfaceBase;
          if (s.contains(WidgetState.pressed)) return SandDark.primaryBright;
          return SandDark.primary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.disabled)) return SandDark.onSurfaceLowest;
          return SandDark.onPrimary;
        }),
        side: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.disabled)) {
            return const BorderSide(
              color: SandDark.outline,
              width: SandBorder.hairline,
            );
          }
          return BorderSide.none;
        }),
        iconColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.disabled)) return SandDark.onSurfaceLowest;
          return SandDark.onPrimary;
        }),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        minimumSize: const WidgetStatePropertyAll<Size>(
          Size(SandSize.btnMd, SandSize.btnMd),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 18),
        ),
        elevation: const WidgetStatePropertyAll<double>(0),
        shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        shape: WidgetStatePropertyAll<OutlinedBorder>(controlShape),
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
        splashFactory: NoSplash.splashFactory,
      ),
    ),

    // Secondary actions retain the packet's compact outlined treatment.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.pressed)) {
            return SandDark.secondaryContainer;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.disabled)) return SandDark.onSurfaceLowest;
          return SandDark.secondaryBright;
        }),
        iconColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.disabled)) return SandDark.onSurfaceLowest;
          return SandDark.secondaryBright;
        }),
        side: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.disabled)) {
            return const BorderSide(
              color: SandDark.outline,
              width: SandBorder.interactive,
            );
          }
          if (s.contains(WidgetState.pressed)) {
            return const BorderSide(
              color: SandDark.secondaryBright,
              width: SandBorder.interactive,
            );
          }
          return const BorderSide(
            color: SandDark.secondary,
            width: SandBorder.interactive,
          );
        }),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        minimumSize: const WidgetStatePropertyAll<Size>(
          Size(SandSize.btnMd, SandSize.btnMd),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 18),
        ),
        elevation: const WidgetStatePropertyAll<double>(0),
        shape: WidgetStatePropertyAll<OutlinedBorder>(controlShape),
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
        splashFactory: NoSplash.splashFactory,
      ),
    ),

    // Tertiary actions are neutral and visually quieter than primary actions.
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.pressed)) return SandDark.surfaceBase;
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.disabled)) return SandDark.onSurfaceLowest;
          return SandDark.onSurfaceBase;
        }),
        iconColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.disabled)) return SandDark.onSurfaceLowest;
          return SandDark.onSurfaceBase;
        }),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        minimumSize: const WidgetStatePropertyAll<Size>(
          Size(SandSize.btnMd, SandSize.btnMd),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(controlShape),
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
        splashFactory: NoSplash.splashFactory,
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.disabled)) return SandDark.onSurfaceLowest;
          return SandDark.onSurfaceLow;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) {
          if (s.contains(WidgetState.pressed)) return SandDark.surfaceBase;
          return Colors.transparent;
        }),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        minimumSize: const WidgetStatePropertyAll<Size>(Size(44, 44)),
        iconSize: const WidgetStatePropertyAll<double>(20),
        shape: WidgetStatePropertyAll<OutlinedBorder>(controlShape),
        splashFactory: NoSplash.splashFactory,
      ),
    ),

    // Fields keep the packet's dark surface and red selected state.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SandDark.surfaceBase,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: text.bodyMedium?.copyWith(color: SandDark.onSurfaceLowest),
      labelStyle: text.labelMedium?.copyWith(
        fontSize: 12,
        letterSpacing: 0.3,
        color: SandDark.onSurfaceLow,
      ),
      floatingLabelStyle: text.labelMedium?.copyWith(
        fontSize: 12,
        letterSpacing: 0.3,
        color: SandDark.secondaryBright,
      ),
      helperStyle: text.bodySmall?.copyWith(
        fontSize: 12,
        color: SandDark.onSurfaceLowest,
      ),
      errorStyle: text.bodySmall?.copyWith(fontSize: 12, color: SandDark.error),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SandRadius.r2),
        borderSide: const BorderSide(
          color: SandDark.outline,
          width: SandBorder.interactive,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SandRadius.r2),
        borderSide: const BorderSide(
          color: SandDark.outline,
          width: SandBorder.interactive,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SandRadius.r2),
        borderSide: const BorderSide(
          color: SandDark.secondary,
          width: SandBorder.selected,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SandRadius.r2),
        borderSide: const BorderSide(
          color: SandDark.error,
          width: SandBorder.interactive,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SandRadius.r2),
        borderSide: const BorderSide(
          color: SandDark.errorBright,
          width: SandBorder.selected,
        ),
      ),
    ),

    // Cursor and selection use the primary red.
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: SandDark.primary,
      selectionHandleColor: SandDark.primary,
      selectionColor: Color(0x47E8833A), // primary @ 28%
    ),

    // Sheet: top corners 16, bottom 0, top hairline.
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: SandDark.surfaceLow,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: SandDark.surfaceLow,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: SandDark.outlineStrong,
      dragHandleSize: Size(36, 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SandRadius.r4),
        ),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: SandDark.surfaceBase,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      barrierColor: SandDark.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SandRadius.r3),
        side: const BorderSide(
          color: SandDark.outline,
          width: SandBorder.hairline,
        ),
      ),
      titleTextStyle: text.titleLarge?.copyWith(
        fontSize: 18,
        letterSpacing: -0.2,
      ),
      contentTextStyle: text.bodyMedium?.copyWith(
        height: 1.45,
        color: SandDark.onSurfaceLow,
      ),
    ),

    // Snackbar: surface-3 plate, NOT an inverse light one.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: SandDark.surfaceHigh,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: SandDark.onSurfaceBase,
      ),
      actionTextColor: SandDark.primaryBright,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SandRadius.r2),
        side: const BorderSide(
          color: SandDark.outlineStrong,
          width: SandBorder.hairline,
        ),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: SandDark.onSurfaceLow,
      textColor: SandDark.onSurfaceBase,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodyMedium?.copyWith(
        fontSize: 13,
        color: SandDark.onSurfaceLow,
      ),
      selectedColor: SandDark.secondaryBright,
      selectedTileColor: SandDark.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SandRadius.r2),
      ),
    ),

    // CHIPS, the biggest single change. Rectangles at radius 2, fixed
    // height 30, never a stadium/pill shape. The selected bar is drawn by
    // `SandChip` in the widget layer; the theme carries everything else.
    chipTheme: ChipThemeData(
      backgroundColor: SandDark.surfaceBase,
      selectedColor: SandDark.secondaryContainer,
      disabledColor: SandDark.surfaceLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      side: const BorderSide(
        color: SandDark.outline,
        width: SandBorder.hairline,
      ),
      labelStyle: text.labelMedium!.copyWith(color: SandDark.onSurfaceLow),
      secondaryLabelStyle: text.labelMedium!.copyWith(
        color: SandDark.secondaryBright,
        fontWeight: FontWeight.w600,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SandRadius.r1),
      ),
      showCheckmark: false,
    ),

    dividerTheme: const DividerThemeData(
      color: SandDark.outline,
      thickness: SandBorder.hairline,
      space: 1,
    ),

    // Linear tracks are 3px with square ends.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: SandDark.primary,
      circularTrackColor: SandDark.surfaceHigh,
      linearTrackColor: SandDark.surfaceHigh,
      linearMinHeight: 3,
      borderRadius: BorderRadius.zero,
    ),

    // Sliders use the primary red.
    sliderTheme: const SliderThemeData(
      activeTrackColor: SandDark.primary,
      inactiveTrackColor: SandDark.surfaceHigh,
      thumbColor: SandDark.primary,
      overlayColor: SandDark.overlayPress,
      valueIndicatorColor: SandDark.surfaceHigh,
      trackHeight: 3,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> s) => s.contains(WidgetState.selected)
            ? SandDark.onSecondary
            : SandDark.onSurfaceLowest,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> s) => s.contains(WidgetState.selected)
            ? SandDark.secondary
            : SandDark.surfaceHigh,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> s) => s.contains(WidgetState.selected)
            ? SandDark.secondary
            : SandDark.outlineStrong,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll<double>(
        SandBorder.hairline,
      ),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      splashRadius: 0,
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> s) => s.contains(WidgetState.selected)
            ? SandDark.secondary
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll<Color>(SandDark.onSecondary),
      side: const BorderSide(
        color: SandDark.outlineStrong,
        width: SandBorder.interactive,
      ),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      splashRadius: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SandRadius.r1),
      ),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> s) => s.contains(WidgetState.selected)
            ? SandDark.secondary
            : SandDark.outlineStrong,
      ),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      splashRadius: 0,
    ),

    // Segments use the shared selected-state treatment.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) => s.contains(WidgetState.selected)
              ? SandDark.secondaryContainer
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) => s.contains(WidgetState.selected)
              ? SandDark.secondaryBright
              : SandDark.onSurfaceLow,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) => s.contains(WidgetState.selected)
              ? SandDark.secondaryBright
              : SandDark.onSurfaceLow,
        ),
        textStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) => s.contains(WidgetState.selected)
              ? text.labelMedium?.copyWith(fontWeight: FontWeight.w600)
              : text.labelMedium,
        ),
        side: const WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: SandDark.outline, width: SandBorder.hairline),
        ),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        elevation: const WidgetStatePropertyAll<double>(0),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SandRadius.r2),
          ),
        ),
        splashFactory: NoSplash.splashFactory,
      ),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: SandDark.surfaceHighest,
        border: Border.all(
          color: SandDark.outlineStrong,
          width: SandBorder.hairline,
        ),
        borderRadius: BorderRadius.circular(SandRadius.r2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: text.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: SandDark.onSurfaceBase,
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: SandDark.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SandRadius.r3),
        side: const BorderSide(
          color: SandDark.outline,
          width: SandBorder.hairline,
        ),
      ),
      textStyle: text.bodyMedium,
    ),

    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Lifecycle state marks (the old "lane badges").
//
// Rule: FILLED = settled, OUTLINE = in flight. `LaneColors` keeps its
// positional signature and gains a fourth field, `filled`, so `_StateMark`
// knows which of the two forms to draw. `reelLane(String)` in main.dart keeps
// its signature and mapping logic unchanged; only these values move.
// ---------------------------------------------------------------------------

@immutable
class LaneColors {
  const LaneColors(
    this.foreground,
    this.container,
    this.outline, {
    this.filled = true,
  });

  /// The marker bar and the label share this hue.
  final Color foreground;

  /// Badge fill. Ignored when [filled] is false.
  final Color container;

  /// Hairline, drawn only when [filled] is false.
  final Color outline;

  /// Settled states are filled; in-flight states are outlined.
  final bool filled;
}

abstract final class SandLanes {
  /// Waiting on a human. Content Doctor red.
  static const LaneColors ready = LaneColors(
    SandDark.primaryBright,
    SandDark.primaryContainer,
    SandDark.outline,
  );

  /// Approved. Content Doctor green.
  static const LaneColors approved = LaneColors(
    SandDark.success,
    Color(0xFF152A1C),
    SandDark.outline,
  );

  /// Revision requested, or on hold. Queued, not failed, warning, not error.
  static const LaneColors revisions = LaneColors(
    SandDark.warning,
    SandDark.warningContainer,
    SandDark.outline,
  );

  /// Scheduled but not yet out. In flight -> outline.
  static const LaneColors scheduled = LaneColors(
    SandDark.info,
    Colors.transparent,
    SandDark.outline,
    filled: false,
  );

  /// Publishing right now. In flight -> outline.
  static const LaneColors inflight = LaneColors(
    SandDark.primary,
    Colors.transparent,
    SandDark.outline,
    filled: false,
  );

  /// Retained name for the "Publishing" mapping in `reelLane`.
  static const LaneColors generated = inflight;

  /// Published, done, and deliberately quiet.
  static const LaneColors published = LaneColors(
    SandDark.onSurfaceLowest,
    SandDark.surfaceBase,
    SandDark.outline,
  );

  /// A real failure, not a queued change.
  static const LaneColors failed = LaneColors(
    SandDark.errorBright,
    SandDark.errorContainer,
    SandDark.outline,
  );
}

// ---------------------------------------------------------------------------
// Backward-compatible aliases.
//
// `app_experience.dart` exports these and the widget tests call
// `studioTheme()`. Keeping them means no test edit was needed.
// ---------------------------------------------------------------------------

/// The page ground.
const Color studioBackground = SandDark.surfaceLowest;

/// One step up, cards, fields, tiles.
const Color studioSurface = SandDark.surfaceBase;

/// The Content Doctor primary action colour.
const Color studioAccent = SandDark.primary;

/// Legacy names from `main.dart`, repointed at the new ramp.
const Color bg = SandDark.surfaceLowest;
const Color panel = SandDark.surfaceBase;
const Color line = SandDark.outline;
const Color ink = SandDark.onSurfaceBase;
const Color muted = SandDark.onSurfaceLow;
const Color accent = SandDark.primary;

/// Drop-in replacement for the old `studioTheme()`.
ThemeData studioTheme() => sandIronTheme();

// ---------------------------------------------------------------------------
// COMPONENTS THE THEME CANNOT EXPRESS.
//
// Flutter's *Theme classes carry colour, shape and type, but none of them can
// draw a leading marker bar, a per-slot tab rule, or an underline flush to a
// segment's bottom edge. Those are exactly the changes the owner asked to be
// able to SEE, so they live here, beside the tokens, rather than being
// re-invented in each feature file.
// ---------------------------------------------------------------------------

/// A lifecycle state mark, the square badge that replaced the pill.
///
/// Geometry per spec: height 20, radius 2, a 3px leading bar in the state
/// hue, label 11 / w700 / +0.4. FILLED = settled, OUTLINE = in flight.
///
/// Passing a null [lane] renders the neutral non-lane label (the account
/// name): surface-3, no border, and NO marker bar, the absence of the bar is
/// what says "this is a label, not a state".
class SandStateMark extends StatelessWidget {
  const SandStateMark({super.key, required this.text, this.lane});

  final String text;
  final LaneColors? lane;

  @override
  Widget build(BuildContext context) {
    final LaneColors? l = lane;

    // Neutral label: no marker, no border.
    if (l == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: SandDark.surfaceHigh,
          borderRadius: BorderRadius.circular(SandRadius.r1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            height: SandSize.stateMark,
            child: Center(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.27,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: SandDark.onSurfaceLow,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: l.filled ? l.container : Colors.transparent,
        borderRadius: BorderRadius.circular(SandRadius.r1),
        border: l.filled
            ? null
            : Border.all(color: l.outline, width: SandBorder.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SandRadius.r1),
        child: SizedBox(
          height: SandSize.stateMark,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // The 3px leading bar, full badge height.
              Container(width: SandBorder.marker, color: l.foreground),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: l.foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact chip with a 2px primary leading bar when selected.
///
/// `ChipThemeData` gives the rectangle, the radius-2 shape, the fill and the
/// label; it cannot draw the leading bar, so the bar is overlaid here. Height
/// is pinned to 30 rather than left to padding, per spec.
class SandChip extends StatelessWidget {
  const SandChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.choice = false,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  /// `true` renders a `ChoiceChip` (one-of-many), `false` a `FilterChip`.
  final bool choice;

  @override
  Widget build(BuildContext context) {
    void handle(bool value) {
      HapticFeedback.selectionClick();
      onSelected(value);
    }

    final Text text = Text(label);
    final Widget chip = choice
        ? ChoiceChip(
            label: text,
            selected: selected,
            onSelected: handle,
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            side: BorderSide(
              color: selected ? SandDark.secondary : SandDark.outline,
              width: selected ? SandBorder.interactive : SandBorder.hairline,
            ),
          )
        : FilterChip(
            label: text,
            selected: selected,
            onSelected: handle,
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            side: BorderSide(
              color: selected ? SandDark.secondary : SandDark.outline,
              width: selected ? SandBorder.interactive : SandBorder.hairline,
            ),
          );

    return SizedBox(
      height: SandSize.chip,
      child: Stack(
        children: <Widget>[
          chip,
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: SandBorder.selected,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: SandDark.secondary,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(SandRadius.r1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One option in a [SandSegmented].
@immutable
class SandSegment<T> {
  const SandSegment({required this.value, required this.label, this.tooltip});
  final T value;
  final String label;
  final String? tooltip;
}

/// The segmented control: a hairline container with a 2px primary underline
/// flush to the bottom edge of the selected segment.
///
/// This is the ONLY control the Focused/Full density preference may use. It
/// is a preference, not a mode: both segments are always enabled, always
/// reachable, there is no lock glyph and no confirmation, and choosing one
/// changes nothing about what is fetched or which routes are shown.
class SandSegmented<T> extends StatelessWidget {
  const SandSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<SandSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];

    for (int i = 0; i < segments.length; i++) {
      final SandSegment<T> s = segments[i];
      final bool selected = s.value == value;

      // 1px divider between two adjacent UNSELECTED segments only; a selected
      // segment already separates itself with fill and underline.
      if (i > 0) {
        final bool previousSelected = segments[i - 1].value == value;
        children.add(
          Container(
            width: SandBorder.hairline,
            height: 16,
            color: (selected || previousSelected)
                ? Colors.transparent
                : SandDark.outline,
          ),
        );
      }

      Widget segment = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged(s.value);
              },
        child: AnimatedContainer(
          duration: SandMotion.fast,
          curve: SandMotion.easeOut,
          decoration: BoxDecoration(
            color: selected ? SandDark.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.23,
                        letterSpacing: 0.2,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected
                            ? SandDark.primaryBright
                            : SandDark.onSurfaceLow,
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: SandBorder.selected,
                    child: const ColoredBox(color: SandDark.primary),
                  ),
              ],
            ),
          ),
        ),
      );

      if (s.tooltip != null) {
        segment = Tooltip(message: s.tooltip!, child: segment);
      }

      children.add(Semantics(selected: selected, button: true, child: segment));
    }

    return Container(
      height: SandSize.segment,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: SandDark.surfaceLow,
        borderRadius: BorderRadius.circular(SandRadius.r2),
        border: Border.all(color: SandDark.outline, width: SandBorder.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// The bottom tab bar, with a 2px primary rule across the top of the active
/// tab's slot.
///
/// `CupertinoTabBar` has no per-slot decoration hook, so the rule is drawn as
/// an overlay positioned from the active index and the slot count. The bar is
/// 100% opaque: the old `.95` alpha over dark content produced the very seam
/// the previous theme was trying to fix.
class SandTabBar extends StatelessWidget {
  const SandTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<BottomNavigationBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        CupertinoTabBar(
          backgroundColor: SandDark.surfaceLow,
          activeColor: SandDark.primary,
          inactiveColor: SandDark.onSurfaceLowest,
          iconSize: 24,
          border: const Border(
            top: BorderSide(
              color: SandDark.outline,
              width: SandBorder.hairline,
            ),
          ),
          currentIndex: currentIndex,
          onTap: onTap,
          items: items,
        ),
        // The active-slot rule, drawn OVER the hairline.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: SandBorder.selected,
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int count = items.length;
                if (count == 0) return const SizedBox.shrink();
                final double slot = constraints.maxWidth / count;
                return Stack(
                  children: <Widget>[
                    Positioned(
                      left: slot * currentIndex,
                      width: slot,
                      top: 0,
                      bottom: 0,
                      child: const ColoredBox(color: SandDark.primary),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The media well shown when a poster or a video will not load.
///
/// NOTE: the reason this is on screen today is the media-401 credential
/// defect (`Image.network` / `VideoPlayerController.networkUrl` send no
/// Authorization header), which is OUT OF SCOPE for this retheme and is NOT
/// fixed here. It is styled anyway, because it is what the owner currently
/// sees on every tile, and it should at least look designed until the token
/// plumbing lands.
class SandMediaPlaceholder extends StatelessWidget {
  const SandMediaPlaceholder({
    super.key,
    this.caption,
    this.compact = false,
    this.icon = CupertinoIcons.film,
  });

  final String? caption;

  /// Glyph only, for small leading thumbnails where a caption will not fit.
  final bool compact;

  /// Swapped for a lock when the session, not the file, is the reason.
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: SandDark.surfaceDim,
      borderRadius: BorderRadius.circular(SandRadius.r2),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: compact ? 24 : 28, color: SandDark.onSurfaceLowest),
          if (!compact && caption != null) ...<Widget>[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                caption!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: SandDark.onSurfaceLowest,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
