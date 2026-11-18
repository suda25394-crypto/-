import 'package:material_ui/material_ui.dart';

const paper = Color(0xFFFAF6EC);
const warmSurface = Color(0xFFFFFCF4);
const ink = Color(0xFF192E2C);
const quiet = Color(0xFF53615B);
const pine = Color(0xFF123F40);
const mist = Color(0xFFE1E9DF);
const amber = Color(0xFFA1412A);
const amberWash = Color(0xFFF5E2CD);
const purplePaper = Color(0xFFECE8F0);
const edge = Color(0xFFCCC9B9);

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
  );
  const field = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
    borderSide: BorderSide(color: edge),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    dividerColor: edge,
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: ink,
        fontFamily: 'serif',
        fontSize: 22,
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
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: pine, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
    ),
  );
}
