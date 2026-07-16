import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color background = Color(0xFF0B0813);
  static const Color surface = Color(0xFF15121d);
  static const Color surfaceDim = Color(0xFF15121d);
  static const Color surfaceContainerLowest = Color(0xFF100c18);
  static const Color surfaceContainerLow = Color(0xFF1d1a26);
  static const Color surfaceContainer = Color(0xFF211e2a);
  static const Color surfaceContainerHigh = Color(0xFF2c2834);
  static const Color surfaceContainerHighest = Color(0xFF373340);
  static const Color onSurface = Color(0xFFe7dff0);
  static const Color onSurfaceVariant = Color(0xFFccc2d9);
  static const Color outline = Color(0xFF968da2);
  static const Color outlineVariant = Color(0xFF4a4456);
  static const Color primary = Color(0xFFd2bcff);
  static const Color primaryContainer = Color(0xFF7a22ff);
  static const Color onPrimary = Color(0xFF3e008e);
  static const Color onPrimaryContainer = Color(0xFFe8daff);
  static const Color onPrimaryFixedVariant = Color(0xFF5900c7);
  static const Color secondary = Color(0xFFd3bbff);
  static const Color secondaryContainer = Color(0xFF592da2);
  static const Color onSecondaryContainer = Color(0xFFc8aaff);
  static const Color tertiary = Color(0xFF4cd7f6);
  static const Color onTertiary = Color(0xFF003640);
  static const Color tertiaryContainer = Color(0xFF006d80);
  static const Color onTertiaryContainer = Color(0xFFa4ebff);
  static const Color error = Color(0xFFffb4ab);
  static const Color errorContainer = Color(0xFF93000a);
  static const Color onError = Color(0xFF690005);
  static const Color onErrorContainer = Color(0xFFffdad6);
  static final Color glassBackground = Color.fromRGBO(28, 22, 46, 0.7);
  static final Color glassBorder = Color.fromRGBO(255, 255, 255, 0.1);
  static final Color neonVioletGlow = Color.fromRGBO(122, 34, 255, 0.5);
  static final Color neonCyanGlow = Color.fromRGBO(76, 215, 246, 0.4);
  static final Color neonVioletGlowLight = Color.fromRGBO(122, 34, 255, 0.2);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onPrimaryContainer,
        secondary: AppColors.secondary,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: AppColors.onSecondaryContainer,
        tertiary: AppColors.tertiary,
        onTertiary: AppColors.onTertiary,
        tertiaryContainer: AppColors.tertiaryContainer,
        onTertiaryContainer: AppColors.onTertiaryContainer,
        error: AppColors.error,
        errorContainer: AppColors.errorContainer,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.hankenGrotesk(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          height: 56 / 48,
          letterSpacing: -0.96,
          color: AppColors.onSurface,
        ),
        displayMedium: GoogleFonts.hankenGrotesk(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 40 / 32,
          color: AppColors.onSurface,
        ),
        headlineMedium: GoogleFonts.hankenGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 32 / 24,
          color: AppColors.onSurface,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          height: 28 / 18,
          color: AppColors.onSurface,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 24 / 16,
          color: AppColors.onSurface,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 16 / 12,
          letterSpacing: 0.6,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final double blurAmount;
  final Color? borderColor;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.padding,
    this.backgroundColor,
    this.blurAmount = 20,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.glassBackground,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor ?? AppColors.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

class NeonGlowBox extends StatelessWidget {
  final Widget child;
  final Color glowColor;
  final double blurRadius;
  final BorderRadius? borderRadius;

  const NeonGlowBox({
    super.key,
    required this.child,
    this.glowColor = const Color(0x807A22FF),
    this.blurRadius = 20,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: glowColor, blurRadius: blurRadius)],
      ),
      child: child,
    );
  }
}
