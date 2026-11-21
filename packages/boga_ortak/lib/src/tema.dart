import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Posta web postasıyla aynı yazı tipini (Geist) kullanır; yönetim Poppins + Plus Jakarta'da kalır.
String get _font => kimlik == Kimlik.posta ? 'packages/boga_ortak/Geist' : 'packages/boga_ortak/Poppins';
String get _gosterimFont => kimlik == Kimlik.posta ? 'packages/boga_ortak/Geist' : 'packages/boga_ortak/Jakarta';

/// Uygulamanın gövde yazı tipi ailesi (ör. HTML gövde ya da özel TextStyle'lar için).
String get govdeYaziTipi => _font;

/// Hangi uygulama: renk kimliği buna göre ayrılır (posta → Bogahost indigosu, yönetim → grafit + yeşil).
enum Kimlik { posta, yonetim }

/// Uygulama açılırken bir kez ayarlanır ([kimlikAyarla]).
Kimlik kimlik = Kimlik.posta;
void kimlikAyarla(Kimlik k) => kimlik = k;

/// Bogahost görsel kimliği (bogahost.com): indigo #5443D2, grafit #1D2233, yeşil #00CC69, lavanta zemin #EFEDFB.
class Marka {
  static const mor = Color(0xFF5443D2);
  static const morAcik = Color(0xFF7B6DF0);
  static const morKoyu = Color(0xFF3B2DA8);
  static const indigo = Color(0xFF4F46E5);
  static const mavi = Color(0xFF2563EB);
  static const gok = Color(0xFF38BDF8);
  static const grafit = Color(0xFF1D2233);
  static const grafitAcik = Color(0xFF2C3350);
  static const yesil = Color(0xFF00CC69);
  static const yesilKoyu = Color(0xFF00A656);
  static const lavanta0 = Color(0xFFEFEDFB);
  static const zumrut = Color(0xFF10B981);
  static const lavanta = Color(0xFFA78BFA);
  static const gul = Color(0xFFE11D48);
  static const kehribar = Color(0xFFF59E0B);

  /// Eski adlar (geriye uyum).
  static const lacivert0 = grafit;
  static const lacivert1 = grafitAcik;
  static const lacivert2 = morKoyu;

  /// Uygulamanın ana vurgu rengi.
  static Color get aksan => kimlik == Kimlik.posta ? const Color(0xFF384ECF) : yesil;

  /// Uygulamanın imza degradesi (simge, açılış, başlık şeritleri).
  static LinearGradient get grad => kimlik == Kimlik.posta
      ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [morAcik, mor, morKoyu], stops: [0, .55, 1])
      : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [grafitAcik, grafit, Color(0xFF121522)], stops: [0, .55, 1]);

  /// Giriş ekranı üst şeridi.
  static LinearGradient get gece => grad;
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
    required this.vurgu,
    required this.vurguYumusak,
    required this.koyu,
  });

  /// [birincil]: düğmeler ve bağlantılar. [vurgu]: seçili gezinme, okunmamış işaretleri, canlı göstergeler.
  final Color zemin, kart, kenar, ic, metin, soluk, silik, birincil, birincilYumusak, vurgu, vurguYumusak;
  final bool koyu;

  // Posta: web postasının (apps/web globals.css) belirteçleri — nötr griler, birincil oklch(0.49 0.2 270).
  // zemin = bg-muted/30 (sol ray, kenar çubuğu), kart = background, ic = muted, kenar = border,
  // soluk = foreground/80 civarı, silik = muted-foreground, *Yumusak = primary/10.
  static const _postaAcik = Renkler(
    zemin: Color(0xFFFCFCFC),
    kart: Colors.white,
    kenar: Color(0xFFE5E5E5),
    ic: Color(0xFFF5F5F5),
    metin: Color(0xFF0A0A0A),
    soluk: Color(0xFF3B3B3B),
    silik: Color(0xFF737373),
    birincil: Color(0xFF384ECF),
    birincilYumusak: Color(0xFFEBEDFA),
    vurgu: Color(0xFF384ECF),
    vurguYumusak: Color(0xFFEBEDFA),
    koyu: false,
  );
  static const _yonetimAcik = Renkler(
    zemin: Color(0xFFF4F6F8),
    kart: Colors.white,
    kenar: Color(0xFFE2E6EC),
    ic: Color(0xFFEEF1F4),
    metin: Color(0xFF111827),
    soluk: Color(0xFF475166),
    silik: Color(0xFF687287),
    birincil: Marka.grafit,
    birincilYumusak: Color(0xFFE6E9F0),
    vurgu: Marka.yesilKoyu,
    vurguYumusak: Color(0xFFDDF7EA),
    koyu: false,
  );
  // Web .dark belirteçleri.
  static const _postaKoyu = Renkler(
    zemin: Color(0xFF111214),
    kart: Color(0xFF0A0B0D),
    kenar: Color(0xFF242527),
    ic: Color(0xFF262626),
    metin: Color(0xFFFAFAFA),
    soluk: Color(0xFFD4D4D4),
    silik: Color(0xFFA1A1A1),
    birincil: Color(0xFF7896FF),
    birincilYumusak: Color(0x1F7896FF),
    vurgu: Color(0xFF7896FF),
    vurguYumusak: Color(0x1F7896FF),
    koyu: true,
  );
  static const _yonetimKoyu = Renkler(
    zemin: Color(0xFF0D1016),
    kart: Color(0xFF161A24),
    kenar: Color(0xFF262C3A),
    ic: Color(0xFF1D2230),
    metin: Color(0xFFF1F4F8),
    soluk: Color(0xFFB3BAC8),
    silik: Color(0xFF8A92A3),
    birincil: Color(0xFF3DDC91),
    birincilYumusak: Color(0x3300CC69),
    vurgu: Color(0xFF3DDC91),
    vurguYumusak: Color(0x3300CC69),
    koyu: true,
  );

  static Renkler get acik => kimlik == Kimlik.posta ? _postaAcik : _yonetimAcik;
  static Renkler get karanlik => kimlik == Kimlik.posta ? _postaKoyu : _yonetimKoyu;

  List<BoxShadow> get golge => koyu
      ? const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8), spreadRadius: -14)]
      : const [BoxShadow(color: Color(0x1A111427), blurRadius: 24, offset: Offset(0, 8), spreadRadius: -12)];

  /// Hafif kart gölgesi (listeler, tablolar).
  List<BoxShadow> get hafifGolge => koyu ? const [] : const [BoxShadow(color: Color(0x0F111427), blurRadius: 10, offset: Offset(0, 2), spreadRadius: -2)];
}

extension RenkX on BuildContext {
  Renkler get r => Theme.of(this).brightness == Brightness.dark ? Renkler.karanlik : Renkler.acik;
  bool get genis => MediaQuery.sizeOf(this).width >= 900;
}

/// Kullanıcının tema seçimi (sistem / açık / koyu).
/// Varsayılan açık tema; kullanıcı Ayarlar'dan sistem/koyu seçebilir.
final temaKipi = ValueNotifier<ThemeMode>(ThemeMode.light);

/// Büyük rakam/başlık yazı stili (Plus Jakarta).
/// Ağırlık en çok w600'dür (sakin, okunaklı hiyerarşi); büyük gösterim boyutları küçültülür (32 → 24, en çok 28).
TextStyle gosterim(double boyut, {FontWeight agirlik = FontWeight.w600, Color? renk, double? satir}) =>
    _gosterim(boyut > 24 ? (boyut * .75).clamp(22, 28).roundToDouble() : boyut, agirlik.value > 600 ? FontWeight.w600 : agirlik, renk, satir);

TextStyle _gosterim(double boyut, FontWeight agirlik, Color? renk, double? satir) => TextStyle(
  fontFamily: _gosterimFont,
  fontSize: boyut,
  fontWeight: agirlik,
  fontVariations: [FontVariation('wght', agirlik.value.toDouble())],
  letterSpacing: -0.015 * boyut,
  height: satir,
  color: renk,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// Masaüstü platformlarda sıkı yoğunluk ve bir tık küçük gövde yazısı (fare hassas; ekranda daha çok satır).
bool get _masaustuPlatform => const {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}.contains(defaultTargetPlatform);

ThemeData temaKur(Brightness parlaklik) {
  final r = parlaklik == Brightness.dark ? Renkler.karanlik : Renkler.acik;
  final masaustu = _masaustuPlatform;
  // Posta: web gibi her yerde 14 px (text-sm); yönetim masaüstünde 13.5.
  final govde = masaustu && kimlik != Kimlik.posta ? 13.5 : 14.0;
  final temel = ThemeData(
    useMaterial3: true,
    visualDensity: masaustu ? VisualDensity.compact : VisualDensity.standard,
    brightness: parlaklik,
    fontFamily: _font,
    scaffoldBackgroundColor: r.zemin,
    colorScheme: ColorScheme.fromSeed(seedColor: Marka.aksan, brightness: parlaklik).copyWith(
      primary: r.birincil,
      onPrimary: r.koyu && kimlik == Kimlik.yonetim ? const Color(0xFF06140C) : Colors.white,
      secondary: r.vurgu,
      surface: r.kart,
    ),
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
  return temel.copyWith(
    // Yazı ölçeği: gövde 14 (masaüstü 13.5), başlıklar en çok 22/24, ağırlık en çok 600.
    textTheme: temel.textTheme
        .copyWith(
          displayLarge: temel.textTheme.displayLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.w600),
          displayMedium: temel.textTheme.displayMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w600),
          displaySmall: temel.textTheme.displaySmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
          headlineLarge: temel.textTheme.headlineLarge?.copyWith(fontSize: masaustu ? 24 : 22, fontWeight: FontWeight.w600),
          headlineMedium: temel.textTheme.headlineMedium?.copyWith(fontSize: masaustu ? 22 : 20, fontWeight: FontWeight.w600),
          headlineSmall: temel.textTheme.headlineSmall?.copyWith(fontSize: 19, fontWeight: FontWeight.w600),
          titleLarge: temel.textTheme.titleLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
          titleMedium: temel.textTheme.titleMedium?.copyWith(fontSize: govde + 1, fontWeight: FontWeight.w500),
          titleSmall: temel.textTheme.titleSmall?.copyWith(fontSize: govde - .5, fontWeight: FontWeight.w500),
          bodyLarge: temel.textTheme.bodyLarge?.copyWith(fontSize: govde, fontWeight: FontWeight.w400),
          bodyMedium: temel.textTheme.bodyMedium?.copyWith(fontSize: govde - .5, fontWeight: FontWeight.w400),
          bodySmall: temel.textTheme.bodySmall?.copyWith(fontSize: 12),
          labelLarge: temel.textTheme.labelLarge?.copyWith(fontSize: govde - .5, fontWeight: FontWeight.w500),
          labelMedium: temel.textTheme.labelMedium?.copyWith(fontSize: 12),
          labelSmall: temel.textTheme.labelSmall?.copyWith(fontSize: 11),
        )
        .apply(bodyColor: r.metin, displayColor: r.metin),
    appBarTheme: AppBarTheme(
      backgroundColor: r.zemin,
      surfaceTintColor: Colors.transparent,
      foregroundColor: r.metin,
      elevation: 0,
      scrolledUnderElevation: .5,
      centerTitle: false,
      titleTextStyle: gosterim(17, renk: r.metin, agirlik: FontWeight.w600),
      toolbarHeight: masaustu ? 52 : 56,
      systemOverlayStyle: r.koyu ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: r.kart,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: r.kenar),
      ),
    ),
    dividerTheme: DividerThemeData(color: r.kenar.withValues(alpha: .6), space: 1, thickness: .6),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: r.ic,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: masaustu ? 11 : 13),
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
        minimumSize: Size(0, masaustu ? 40 : 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(fontFamily: _font, fontWeight: FontWeight.w500, fontSize: govde),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, masaustu ? 40 : 44),
        side: BorderSide(color: r.kenar),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: r.ic,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(color: r.metin, fontFamily: _font, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: r.soluk,
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: govde, color: r.metin, fontWeight: FontWeight.w400),
    ),
    iconTheme: IconThemeData(size: 20, color: r.soluk),
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
      indicatorColor: r.vurguYumusak,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? r.vurgu : r.soluk)),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: _font,
          fontSize: 11.5,
          color: s.contains(WidgetState.selected) ? r.metin : r.soluk,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: r.kart,
      indicatorColor: r.vurguYumusak,
      selectedIconTheme: IconThemeData(color: r.vurgu),
      unselectedIconTheme: IconThemeData(color: r.soluk),
      selectedLabelTextStyle: TextStyle(fontFamily: _font, fontSize: 12, color: r.metin, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(fontFamily: _font, fontSize: 12, color: r.soluk, fontWeight: FontWeight.w500),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: r.kart, surfaceTintColor: Colors.transparent),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: r.birincil,
      foregroundColor: r.koyu && kimlik == Kimlik.yonetim ? const Color(0xFF06140C) : Colors.white,
      shape: const StadiumBorder(),
    ),
  );
}
