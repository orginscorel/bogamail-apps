import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _font = 'packages/boga_ortak/Poppins';
const _gosterimFont = 'packages/boga_ortak/Jakarta';

/// Bogahost görsel kimliği: marka moru #5443D2, indigo, gök mavisi; gece laciverti açılış zemini.
class Marka {
  static const mor = Color(0xFF5443D2);
  static const morAcik = Color(0xFF6D5EF2);
  static const indigo = Color(0xFF4F46E5);
  static const mavi = Color(0xFF2563EB);
  static const gok = Color(0xFF38BDF8);
  static const lacivert0 = Color(0xFF0B0A24);
  static const lacivert1 = Color(0xFF1A1760);
  static const lacivert2 = Color(0xFF2E3A9E);
  static const zumrut = Color(0xFF10B981);
  static const lavanta = Color(0xFFA78BFA);
  static const gul = Color(0xFFE11D48);
  static const kehribar = Color(0xFFF59E0B);

  static const grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [morAcik, mor, mavi],
    stops: [0, .5, 1],
  );
  static const gece = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [lacivert0, lacivert1, lacivert2],
    stops: [0, .6, 1],
  );
}

/// Açık/koyu temaya göre yüzey renkleri: `context.r.kart` gibi.
class Renkler {
  const Renkler({
    required this.zemin,
    required this.kart,
    required this.kenar,
    required this.ic,
    required this.metin,
    required this.soluk,
    required this.silik,
    required this.birincil,
    required this.birincilYumusak,
    required this.koyu,
  });

  final Color zemin, kart, kenar, ic, metin, soluk, silik, birincil, birincilYumusak;
  final bool koyu;

  static const acik = Renkler(
    zemin: Color(0xFFF5F6FB),
    kart: Colors.white,
    kenar: Color(0xFFE6E8F2),
    ic: Color(0xFFEEF0F8),
    metin: Color(0xFF0F172A),
    soluk: Color(0xFF475569),
    silik: Color(0xFF64748B),
    birincil: Marka.mor,
    birincilYumusak: Color(0xFFEEECFC),
    koyu: false,
  );
  static const karanlik = Renkler(
    zemin: Color(0xFF0B0A1F),
    kart: Color(0xFF15142E),
    kenar: Color(0xFF26244A),
    ic: Color(0xFF1E1C44),
    metin: Color(0xFFF1F5F9),
    soluk: Color(0xFFB4BCD0),
    silik: Color(0xFF8B93AB),
    birincil: Color(0xFFA59CF7),
    birincilYumusak: Color(0x425443D2),
    koyu: true,
  );

  List<BoxShadow> get golge => koyu
      ? const [BoxShadow(color: Color(0xB3000000), blurRadius: 28, offset: Offset(0, 10), spreadRadius: -16)]
      : const [BoxShadow(color: Color(0x401C1863), blurRadius: 28, offset: Offset(0, 10), spreadRadius: -18)];
}

extension RenkX on BuildContext {
  Renkler get r => Theme.of(this).brightness == Brightness.dark ? Renkler.karanlik : Renkler.acik;
  bool get genis => MediaQuery.sizeOf(this).width >= 900;
}

/// Kullanıcının tema seçimi (sistem / açık / koyu).
final temaKipi = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Büyük rakam/başlık yazı stili (Plus Jakarta).
TextStyle gosterim(double boyut, {FontWeight agirlik = FontWeight.w800, Color? renk, double? satir}) => TextStyle(
      fontFamily: _gosterimFont,
      fontSize: boyut,
      fontWeight: agirlik,
      fontVariations: [FontVariation('wght', agirlik.value.toDouble())],
      letterSpacing: -0.02 * boyut,
      height: satir,
      color: renk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData temaKur(Brightness parlaklik) {
  final r = parlaklik == Brightness.dark ? Renkler.karanlik : Renkler.acik;
  final temel = ThemeData(
    useMaterial3: true,
    brightness: parlaklik,
    fontFamily: _font,
    scaffoldBackgroundColor: r.zemin,
    colorScheme: ColorScheme.fromSeed(seedColor: Marka.mor, brightness: parlaklik).copyWith(
      primary: r.koyu ? Marka.morAcik : Marka.mor,
      surface: r.kart,
    ),
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
  return temel.copyWith(
    textTheme: temel.textTheme.apply(bodyColor: r.metin, displayColor: r.metin),
    appBarTheme: AppBarTheme(
      backgroundColor: r.zemin,
      surfaceTintColor: Colors.transparent,
      foregroundColor: r.metin,
      elevation: 0,
      scrolledUnderElevation: .5,
      centerTitle: false,
      titleTextStyle: gosterim(20, renk: r.metin, agirlik: FontWeight.w700),
      systemOverlayStyle: r.koyu ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: r.kart,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: r.kenar)),
    ),
    dividerTheme: DividerThemeData(color: r.kenar, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: r.ic,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: r.birincil, width: 2),
      ),
      labelStyle: TextStyle(color: r.soluk, fontWeight: FontWeight.w500),
      hintStyle: TextStyle(color: r.silik),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        side: BorderSide(color: r.kenar),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: r.ic,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(color: r.metin, fontFamily: _font, fontSize: 13),
    ),
    listTileTheme: ListTileThemeData(iconColor: r.soluk),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: r.kart,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: r.kart,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: r.kart,
      surfaceTintColor: Colors.transparent,
      indicatorColor: r.birincilYumusak,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontFamily: _font, fontSize: 11.5, color: r.soluk, fontWeight: FontWeight.w500)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: r.kart,
      indicatorColor: r.birincilYumusak,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: r.kart, surfaceTintColor: Colors.transparent),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Marka.mor,
      foregroundColor: Colors.white,
      shape: StadiumBorder(),
    ),
  );
}
