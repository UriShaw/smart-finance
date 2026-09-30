import 'package:flutter/material.dart';

/// Design tokens: trắng + xanh dương (giữ màu của app cũ TingGo) trên nền kính lỏng.
class AppColors {
  const AppColors._();

  // Màu gốc của app cũ.
  static const primary = Color(0xFF0056D2);
  static const sky = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFFDBEAFE);
  static const textPrimary = Color(0xFF1E293B);
  static const textSecondary = Color(0xFF64748B);
  static const hint = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const borderSoft = Color(0xFFF1F5F9);
  static const greenSoft = Color(0xFFF0FDF4);
  static const redSoft = Color(0xFFFEF2F2);

  /// Giữ tên cũ để các màn hình khác dùng được.
  static const seed = primary;
  static const cyan = Color(0xFF0EA5E9);
  static const pink = Color(0xFFEC4899);
  static const sun = Color(0xFFD97706);
  static const violet = Color(0xFF7C3AED);

  static const income = Color(0xFF16A34A);
  static const expense = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);

  /// Nền sáng / tối (dưới các vệt màu chuyển động).
  static const lightBase = Color(0xFFF8FAFF);
  static const darkBase = Color(0xFF0B1220);

  /// Vệt màu nền "chất lỏng": các sắc xanh nhạt.
  static const blobs = [
    Color(0xFF93C5FD),
    Color(0xFFBAE6FD),
    Color(0xFF60A5FA),
    Color(0xFFC7D2FE),
    Color(0xFFA5F3FC),
  ];

  static const heroGradient = [Color(0xFF0056D2), Color(0xFF2563EB), Color(0xFF3B82F6)];
  static const incomeGradient = [Color(0xFF22C55E), Color(0xFF16A34A)];
  static const expenseGradient = [Color(0xFFF87171), Color(0xFFEF4444)];
  static const accentGradient = [Color(0xFF0056D2), Color(0xFF3B82F6)];
}

class AppRadius {
  const AppRadius._();
  static const double sm = 14;
  static const double md = 22;
  static const double lg = 30;
}

class AppSpacing {
  const AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Khoảng trống cuối danh sách để không bị thanh điều hướng nổi che.
  static const double bottomNav = 120;
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final base0 = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: b,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    final scheme = dark
        ? base0.copyWith(primary: const Color(0xFF60A5FA), onPrimary: const Color(0xFF0B1220))
        : base0.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            secondary: AppColors.textSecondary,
            tertiary: AppColors.income,
            surface: Colors.white,
            onSurface: AppColors.textPrimary,
            onSurfaceVariant: AppColors.textSecondary,
            outline: AppColors.hint,
            outlineVariant: AppColors.border,
          );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.14) : AppColors.border),
    );
    final base = ThemeData(brightness: b, useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: dark ? const Color(0xFF111A2E) : Colors.white,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.85),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: scheme.primary,
          foregroundColor: dark ? const Color(0xFF0B1220) : Colors.white,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
          backgroundColor: Colors.white.withValues(alpha: dark ? 0.04 : 0.35),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        highlightElevation: 10,
        shape: StadiumBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: dark ? 0.08 : 0.5),
        side: BorderSide(color: Colors.white.withValues(alpha: dark ? 0.14 : 0.7)),
        shape: const StadiumBorder(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.primary : null),
      ),
      listTileTheme: const ListTileThemeData(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm))),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
      }),
      // Hộp thoại, menu, bảng dưới: bề mặt kính trong, bo góc lớn, viền sáng.
      dialogTheme: DialogThemeData(
        backgroundColor: dark
            ? const Color(0xFF15203A).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: Colors.white.withValues(alpha: dark ? 0.14 : 0.9)),
        ),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: dark
            ? const Color(0xFF15203A).withValues(alpha: 0.97)
            : Colors.white.withValues(alpha: 0.97),
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: dark ? 0.14 : 0.9)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: dark ? Colors.white.withValues(alpha: 0.09) : Colors.black.withValues(alpha: 0.08),
        thickness: 0.6,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }
}
