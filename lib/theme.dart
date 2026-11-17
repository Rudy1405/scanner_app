// Design tokens from design/tokens.json (iOS / Cupertino look, also on Android).
import 'package:flutter/cupertino.dart';

class AppColors {
  static const accent = Color(0xFF00B4D8);
  static const accentDark = Color(0xFF0089A7); // accent text on light
  static const accentLight = Color(0xFF48CAE4); // accent on dark
  static const accentTint = Color(0xFFE0F5FA);
  static const background = Color(0xFFF4F6F8);
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF1F2933);
  // Darkened from the mock (#7B8794 / #9AA5B1) to pass 4.5:1 on white and #F4F6F8.
  static const muted = Color(0xFF5F6B7A);
  static const tertiary = Color(0xFF68737F);
  static const alertBody = Color(0xFF52606D);
  static const separator = Color(0xFFE1E5EA);
  static const grabber = Color(0xFFC5CBD3);
  static const darkBg = Color(0xFF15181C);
  static const darkPanel = Color(0xFF1E2227);
  static const viewerBg = Color(0xFF2A2F35);
  static const destructive = Color(0xFFFF3B30);
  static const destructiveOnDark = Color(0xFFFF6B61);
  static const destructiveTint = Color(0xFFFFE9E7);
  static const fillQuaternary = Color(0x1A767680); // #767680 @10%
  static const scrim = Color(0xFF0B0F14);
  static const primaryGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [accent, accentDark]);
  static const logoGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF48CAE4), Color(0xFF0089A7)]);
}

CupertinoThemeData buildTheme() => const CupertinoThemeData(
      primaryColor: AppColors.accent,
      scaffoldBackgroundColor: AppColors.background,
      brightness: Brightness.light,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
            inherit: false,
            fontSize: 17,
            color: AppColors.text,
            decoration: TextDecoration.none),
      ),
    );

/// Text style shortcut: size / weight / colour.
TextStyle ts(double size, FontWeight weight, [Color color = AppColors.text, double? height]) =>
    TextStyle(
        inherit: false,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        decoration: TextDecoration.none);

const w400 = FontWeight.w400;
const w600 = FontWeight.w600;
const w700 = FontWeight.w700;
