import 'package:material_ui/material_ui.dart';

const paper = Color(0xFFFFFFFF);
const warmSurface = Color(0xFFFFFFFF);
const ink = Color(0xFF242328);
const quiet = Color(0xFF64626B);
const pine = Color(0xFF8038A0);
const mist = Color(0xFFF1E7F6);
const amber = Color(0xFF71308D);
const amberWash = Color(0xFFFAF4FC);
const purplePaper = Color(0xFFF7F0FA);
const edge = Color(0xFFE9E8EC);

const editionMeta = TextStyle(
  color: quiet,
  fontSize: 12,
  fontWeight: FontWeight.w600,
  letterSpacing: .4,
);
const editionFolio = TextStyle(
  color: amber,
  fontSize: 14,
  fontFamily: 'monospace',
  fontWeight: FontWeight.w600,
);

ThemeData coupleTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: pine).copyWith(
    primary: pine,
    onPrimary: warmSurface,
    secondary: amber,
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: quiet,
    outlineVariant: edge,
    secondaryContainer: mist,
    onSecondaryContainer: pine,
    primaryContainer: mist,
    onPrimaryContainer: ink,
    tertiary: pine,
    surfaceTint: Colors.transparent,
  );
  const field = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: edge),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    cardTheme: const CardThemeData(
      color: paper,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: edge,
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 63,
      elevation: 0,
      backgroundColor: paper,
      indicatorColor: mist,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: warmSurface,
      border: field,
      enabledBorder: field,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: pine, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
  );
}
