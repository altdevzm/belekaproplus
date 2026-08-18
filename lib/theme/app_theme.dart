import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Industrial Midnight Obsidian Palette
  static const Color background = Color(0xFF0F0F11);
  static const Color surface = Color(0xFF161619);
  static const Color surfaceContainerLow = Color(0xFF1E1E22);
  static const Color surfaceContainer = Color(0xFF242429);
  static const Color surfaceContainerHigh = Color(0xFF2E2E35);
  static const Color surfaceContainerHighest = Color(0xFF383842);
  static const Color surfaceBright = Color(0xFF42424F);

  // Kinetic "Neon" Accents
  static const Color primary = Color(0xFFC6B4FF); // Electric Lavender
  static const Color onPrimary = Color(0xFF1A004B);
  static const Color primaryContainer = Color(0xFF320088);
  static const Color onPrimaryContainer = Color(0xFFE6DEFF);

  static const Color secondary = Color(0xFFC1F11D); // Neon Lime (Success/Action)
  static const Color onSecondary = Color(0xFF2C3900);
  static const Color secondaryContainer = Color(0xFF415100);
  static const Color onSecondaryContainer = Color(0xFFD9FF66);

  static const Color tertiary = Color(0xFFFFB3B5); // Soft Red (Danger)
  static const Color onTertiary = Color(0xFF680019);

  static const Color outline = Color(0xFF45454E); // Tighter borders
  static const Color outlineVariant = Color(0xFF2D2D35);
  static const Color onSurface = Color(0xFFF0F0F3);
  static const Color onSurfaceVariant = Color(0xFFA5A5B1);

  static const Color error = Color(0xFFFFB4AB);
  static const Color success = Color(0xFFC1F11D); // Match Neon Lime

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onTertiary,
      surface: surface,
      onSurface: onSurface,
      error: error,
      outline: outline,
      outlineVariant: outlineVariant,
    ),
    textTheme: TextTheme(
      displayLarge: GoogleFonts.manrope(
        fontSize: 64,
        fontWeight: FontWeight.w900,
        height: 1.1,
        letterSpacing: -2,
        color: onSurface,
      ),
      headlineLarge: GoogleFonts.manrope(
        fontSize: 48,
        fontWeight: FontWeight.w800,
        height: 1.2,
        letterSpacing: -1,
        color: onSurface,
      ),
      headlineMedium: GoogleFonts.manrope(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: onSurface,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: onSurface,
      ),
      labelMedium: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: onSurfaceVariant,
      ),
      labelSmall: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: outline,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: outlineVariant,
      thickness: 1,
      space: 1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: secondary,
        foregroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.all(Colors.black.withValues(alpha: 0.1)),
      ),
    ),
  );
}

