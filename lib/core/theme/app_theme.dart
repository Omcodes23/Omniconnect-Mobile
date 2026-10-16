import 'package:flutter/material.dart';

class AppTheme {
  // Professional Dark Theme - Solid, Dark, Clean (No AI-like purple gradients)
  static const Color background = Color(0xFF0a0d14); // Darkest background
  static const Color surface = Color(0xFF13161d); // Card / Sidebar surface
  static const Color surfaceElevated = Color(0xFF1a1e27); // Elevated card / Input field
  static const Color cardHover = Color(0xFF21252e); // Hover / Highlighted item
  static const Color borderSubtle = Color(0xFF2a2f3a); // Subtle border
  static const Color borderStrong = Color(0xFF3d4454); // Strong border

  static const Color primaryBlue = Color(0xFF3b82f6); // Solid clean primary blue
  static const Color primaryHover = Color(0xFF2563eb);
  static const Color primaryPressed = Color(0xFF1d4ed8);

  static const Color textPrimary = Color(0xFFe4e6eb); // Clear crisp primary text
  static const Color textSecondary = Color(0xFF8b92a5); // Subdued secondary text
  static const Color textMuted = Color(0xFF5a5f6f); // Muted caption text

  static const Color success = Color(0xFF10b981); // Emerald green
  static const Color error = Color(0xFFef4444); // Clean red
  static const Color warning = Color(0xFFf59e0b); // Clean amber

  // Compatibility aliases
  static const Color primaryColor = primaryBlue;
  static const Color secondaryColor = surface;
  static const Color accentColor = primaryBlue;
  static const Color backgroundColor = background;
  static const Color errorColor = error;
  static const Color primaryIndigo = primaryBlue;
  static const Color primaryPurple = primaryBlue;
  static const Color secondary = primaryBlue;

  /// Solid decoration instead of blurry glassmorphism
  static BoxDecoration cardDecoration({
    double radius = 10,
    Color? color,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: color ?? surfaceElevated,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? borderSubtle,
        width: 1,
      ),
    );
  }

  /// Backward-compatible wrapper for glassDecoration - now returns a clean solid card decoration
  static BoxDecoration glassDecoration({
    double blur = 0,
    double radius = 10,
  }) {
    return cardDecoration(radius: radius);
  }

  /// Single solid color gradient for places expecting a gradient
  static LinearGradient linearGradient() {
    return const LinearGradient(
      colors: [primaryBlue, primaryHover],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  }

  /// Global dark theme matching Desktop Avalonia theme
  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        primaryColor: primaryBlue,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: primaryBlue,
          secondary: primaryBlue,
          surface: surface,
          error: error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: textPrimary),
          shape: Border(
            bottom: BorderSide(color: borderSubtle, width: 1),
          ),
        ),
        cardTheme: CardThemeData(
          color: surfaceElevated,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: borderSubtle, width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceElevated,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: primaryBlue, width: 1.5),
          ),
          labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
          hintStyle: const TextStyle(color: textMuted, fontSize: 13),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryBlue,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: textPrimary,
          iconColor: textSecondary,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surface,
          selectedItemColor: primaryBlue,
          unselectedItemColor: textMuted,
          elevation: 0,
        ),
        dividerTheme: const DividerThemeData(
          color: borderSubtle,
          thickness: 1,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return primaryBlue;
            return textMuted;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return primaryBlue.withValues(alpha: 0.3);
            }
            return textMuted.withValues(alpha: 0.2);
          }),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primaryBlue,
        ),
      );
}
