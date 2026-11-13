import 'package:flutter/material.dart';

/// 𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 design system — the HUD palette: arc-reactor cyan on
/// near-black, serif typography, thin luminous borders.
class AppTheme {
  AppTheme._();

  // HUD palette
  static const hudCyan = Color(0xFF42E8FF);
  static const hudCyanDim = Color(0xFF2EC7E6);
  static const hudInk = Color(0xFF01060C);
  static const hudPanel = Color(0xFF06131F);
  static const hudAmber = Color(0xFFFFB74A);
  static const hudGreen = Color(0xFF5AFFA8);

  // Slate palette (legacy aliases, kept for existing widgets)
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);

  // Brand accents
  static const indigo = hudCyan;
  static const indigoLight = hudCyan;
  static const success = hudGreen;
  static const danger = Color(0xFFFF6B6B);
  static const warning = hudAmber;

  /// Android resolves the generic `serif` family to Noto Serif, the
  /// closest system match to the HUD's Times New Roman / Source Serif 4.
  static const String serif = 'serif';

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: hudCyan,
      brightness: Brightness.dark,
      surface: hudInk,
    ).copyWith(
      primary: hudCyan,
      onPrimary: hudInk,
      secondary: hudAmber,
      surface: hudInk,
      surfaceContainerHighest: const Color(0xFF0A1926),
      onSurface: const Color(0xFFDFF9FF),
      onSurfaceVariant: const Color(0xFF8FB9C9),
      outline: const Color(0xFF1B3E52),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: hudInk,
      cardColor: const Color(0xFF06131F),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: hudCyan,
      brightness: Brightness.light,
      surface: const Color(0xFFF3FBFF),
    ).copyWith(
      primary: hudCyanDim,
      onPrimary: hudInk,
      secondary: hudAmber,
      surface: const Color(0xFFF3FBFF),
      surfaceContainerHighest: Colors.white,
      onSurface: const Color(0xFF04121B),
      onSurfaceVariant: const Color(0xFF4A6B7A),
      outline: const Color(0xFFB9DCE8),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF3FBFF),
      cardColor: Colors.white,
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: serif,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.primary,
        titleTextStyle: TextStyle(
          color: scheme.primary,
          fontFamily: serif,
          fontSize: 20,
          fontWeight: FontWeight.w400,
          letterSpacing: 2.4,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.22)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.primary.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF06202E),
        contentTextStyle: TextStyle(
          fontFamily: serif,
          color: scheme.primary,
          letterSpacing: 0.8,
          fontSize: 12.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.primary.withValues(alpha: 0.15),
        thickness: 1,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withValues(alpha: 0.15),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.18),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? const Color(0xFF01121A)
              : const Color(0xFF5E8494),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.primary.withValues(alpha: 0.16),
        ),
        trackOutlineColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.35),
        ),
      ),
    );

    // Serif text everywhere — the HUD reads like a printed dossier.
    final text = base.textTheme;
    return base.copyWith(
      textTheme: text
          .apply(fontFamily: serif)
          .copyWith(
            titleLarge: text.titleLarge?.copyWith(
              fontFamily: serif,
              color: scheme.onSurface,
              letterSpacing: 1.2,
            ),
            titleMedium: text.titleMedium?.copyWith(
              fontFamily: serif,
              color: scheme.onSurface,
              letterSpacing: 0.9,
            ),
            bodyMedium: text.bodyMedium?.copyWith(
              fontFamily: serif,
              color: scheme.onSurface,
            ),
            bodySmall: text.bodySmall?.copyWith(
              fontFamily: serif,
              color: scheme.onSurfaceVariant,
            ),
          ),
    );
  }
}
