import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Central color palette for the whole application.
///
/// Every screen must consume these values (directly or through
/// [ColorScheme]) instead of hard-coding its own `Color(0x...)` literals.
class AppColors {
  const AppColors._();

  // Brand
  static const Color primary = Color(0xFF1F2937);
  static const Color primaryLight = Color(0xFF374151);
  static const Color accent = Color(0xFFF59E0B);
  static const Color accentDark = Color(0xFFB45309);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Neutrals (light theme)
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F5F9);
  static const Color divider = Color(0xFFE2E8F0);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);

  // Neutrals (dark theme)
  static const Color darkBackground = Color(0xFF111827);
  static const Color darkSurface = Color(0xFF1F2937);
  static const Color darkSurfaceMuted = Color(0xFF273449);
  static const Color darkDivider = Color(0xFF374151);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFFCBD5E1);

  // Semantic
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF0284C7);
  static const Color neutral = Color(0xFF6B7280);

  /// Status colors used by bookings/agenda badges.
  static Color forStatus(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return success;
      case 'confirmed':
        return info;
      case 'pending':
        return warning;
      case 'cancelled':
      case 'canceled':
        return danger;
      case 'no_show':
      case 'no-show':
        return neutral;
      default:
        return textSecondary;
    }
  }
}

/// Standard spacing scale (8pt grid).
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Standard corner radii.
class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
}

/// Standard typography scale (family + weights + sizes).
class AppTypography {
  const AppTypography._();

  /// Single font family used across the app, resolved per platform so the
  /// UI looks native everywhere without shipping extra font assets.
  static String? get fontFamily {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return '.SF Pro Text';
      case TargetPlatform.windows:
        return 'Segoe UI';
      case TargetPlatform.linux:
        return 'Ubuntu';
      default:
        return 'Roboto';
    }
  }

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// Builds the shared [TextTheme]; every screen inherits it through
  /// `Theme.of(context).textTheme`, so no screen should declare raw sizes.
  static TextTheme textTheme(Color primaryText, Color secondaryText) {
    final TextStyle base = TextStyle(
      fontFamily: fontFamily,
      color: primaryText,
      height: 1.35,
    );

    return TextTheme(
      // Display / marketing
      displaySmall: base.copyWith(fontSize: 32, fontWeight: bold, height: 1.2),
      // Page titles
      headlineLarge: base.copyWith(fontSize: 28, fontWeight: bold, height: 1.2),
      headlineMedium: base.copyWith(fontSize: 24, fontWeight: bold, height: 1.25),
      // Section titles
      headlineSmall: base.copyWith(fontSize: 20, fontWeight: bold, height: 1.3),
      titleLarge: base.copyWith(fontSize: 18, fontWeight: semiBold),
      // Card / list titles
      titleMedium: base.copyWith(fontSize: 16, fontWeight: semiBold),
      titleSmall: base.copyWith(fontSize: 14, fontWeight: semiBold),
      // Body copy
      bodyLarge: base.copyWith(fontSize: 16, fontWeight: regular),
      bodyMedium: base.copyWith(fontSize: 14, fontWeight: regular),
      bodySmall: base.copyWith(
        fontSize: 12,
        fontWeight: regular,
        color: secondaryText,
      ),
      // Buttons / labels
      labelLarge: base.copyWith(fontSize: 14, fontWeight: semiBold),
      labelMedium: base.copyWith(fontSize: 12, fontWeight: medium),
      labelSmall: base.copyWith(
        fontSize: 11,
        fontWeight: medium,
        color: secondaryText,
      ),
    );
  }
}

class AppTheme {
  const AppTheme._();

  static const Color primary = AppColors.primary;
  static const Color accent = AppColors.accent;

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final ColorScheme colorScheme = isDark
        ? ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: Brightness.dark,
          ).copyWith(
            primary: AppColors.accent,
            onPrimary: AppColors.primary,
            secondary: AppColors.accent,
            surface: AppColors.darkSurface,
            surfaceContainerHighest: AppColors.darkSurfaceMuted,
            outlineVariant: AppColors.darkDivider,
            error: AppColors.danger,
          )
        : ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: Brightness.light,
          ).copyWith(
            primary: AppColors.primary,
            onPrimary: AppColors.onPrimary,
            secondary: AppColors.accent,
            onSecondary: AppColors.primary,
            surface: AppColors.surface,
            surfaceContainerHighest: AppColors.surfaceMuted,
            outlineVariant: AppColors.divider,
            error: AppColors.danger,
          );

    final Color primaryText = isDark
        ? AppColors.darkTextPrimary
        : AppColors.textPrimary;
    final Color secondaryText = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    final TextTheme textTheme = AppTypography.textTheme(
      primaryText,
      secondaryText,
    );

    final RoundedRectangleBorder fieldShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.background,
      canvasColor: isDark ? AppColors.darkBackground : AppColors.background,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: primaryText, size: 22),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkDivider : AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: isDark
            ? AppColors.darkSurface
            : AppColors.surface,
        foregroundColor: primaryText,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: AppTypography.semiBold,
        ),
        iconTheme: IconThemeData(color: primaryText),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkDivider : AppColors.divider,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: isDark ? AppColors.accent : AppColors.primary,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceMuted : AppColors.surfaceMuted,
        labelStyle: textTheme.bodyMedium?.copyWith(color: secondaryText),
        hintStyle: textTheme.bodyMedium?.copyWith(color: secondaryText),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.labelLarge,
          shape: fieldShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.labelLarge,
          shape: fieldShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.labelLarge,
          shape: fieldShape,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.onPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        iconColor: secondaryText,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        indicatorColor: isDark
            ? AppColors.accent.withValues(alpha: 0.24)
            : AppColors.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
          textTheme.labelMedium?.copyWith(
            fontWeight: AppTypography.semiBold,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? AppColors.accent : AppColors.primary,
      ),
    );
  }
}
