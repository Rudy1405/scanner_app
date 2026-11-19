// Design tokens from design/tokens.json (iOS / Cupertino look, also on Android).
import 'package:flutter/cupertino.dart';

/// Colours. The accent and the always-dark screens (camera, crop, filter) are
/// constants; the rest follow the system light / dark setting.
class AppColors {
  /// Set from the system brightness at the app root (see main.dart).
  static bool dark = false;
  static Color _c(int light, int dk) => Color(dark ? dk : light);

  static const accent = Color(0xFF00B4D8);
  /// Accent for fills that carry white text (buttons, badges).
  static const accentFill = Color(0xFF0089A7);
  static const accentLight = Color(0xFF48CAE4); // accent on dark
  /// Accent for text and icons: darker on light, lighter on dark.
  static Color get accentDark => _c(0xFF0089A7, 0xFF48CAE4);
  static Color get accentTint => _c(0xFFE0F5FA, 0xFF12333B);
  static Color get background => _c(0xFFF4F6F8, 0xFF0E1114);
  static Color get surface => _c(0xFFFFFFFF, 0xFF1A1E23);
  static Color get text => _c(0xFF1F2933, 0xFFF2F4F6);
  // Light values darkened from the mock to pass 4.5:1 on white and #F4F6F8.
  static Color get muted => _c(0xFF5F6B7A, 0xFF9AA5B1);
  static Color get tertiary => _c(0xFF68737F, 0xFF8A95A1);
  static Color get alertBody => _c(0xFF52606D, 0xFFB4BDC8);
  static Color get separator => _c(0xFFE1E5EA, 0xFF2C323A);
  static Color get grabber => _c(0xFFC5CBD3, 0xFF4A535D);
  /// Shadow colour: black in dark mode (a light shadow would glow).
  static Color get shadow => dark ? const Color(0xFF000000) : text;
  /// Frosted-glass fill and edge for the light-screen controls.
  static Color get glass => dark ? const Color(0xCC1E2227) : const Color(0xCCFFFFFF);
  static Color get glassEdge => dark ? const Color(0x1AFFFFFF) : const Color(0xFFFFFFFF);
  static const darkBg = Color(0xFF15181C);
  static const darkPanel = Color(0xFF1E2227);
  static const viewerBg = Color(0xFF2A2F35);
  static const destructive = Color(0xFFFF3B30);
  static const destructiveOnDark = Color(0xFFFF6B61);
  static Color get destructiveTint => _c(0xFFFFE9E7, 0xFF3A1D1B);
  static Color get fillQuaternary => dark ? const Color(0x33767680) : const Color(0x1A767680);
  static const scrim = Color(0xFF0B0F14);
  static const primaryGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [accent, accentFill]);
  static const logoGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF48CAE4), Color(0xFF0089A7)]);
}

CupertinoThemeData buildTheme() => CupertinoThemeData(
      primaryColor: AppColors.accent,
      scaffoldBackgroundColor: AppColors.background,
      brightness: AppColors.dark ? Brightness.dark : Brightness.light,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
            inherit: false,
            fontSize: 17,
            color: AppColors.text,
            decoration: TextDecoration.none),
      ),
    );

/// Text style shortcut: size / weight / colour.
TextStyle ts(double size, FontWeight weight, [Color? color, double? height]) =>
    TextStyle(
        inherit: false,
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.text,
        height: height,
        decoration: TextDecoration.none);

const w400 = FontWeight.w400;
const w600 = FontWeight.w600;
const w700 = FontWeight.w700;
