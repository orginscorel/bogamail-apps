import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../oturum.dart';
import '../veri/html_temizle.dart';
import '../veri/modeller.dart';
import '../veri/onbellek.dart';
import '../veri/posta_servisi.dart';

final _cidTurleri = RegExp(r'^image/(png|jpeg|gif|webp)$', caseSensitive: false);
const _cidSiniri = 5 * 1024 * 1024;

HeadlessInAppWebView? _isitici;

/// Telefonlarda web görünümü motorunu uygulama açılışında ısıtır (ilk ileti açılışındaki motor başlatma gecikmesi
/// ortadan kalkar). Ağ ve JavaScript kapalı, boş bir belge; uygulama boyunca yaşar.
Future<void> webGorunumunuIsit() async {
  if (kIsWeb || _isitici != null || !(Platform.isAndroid || Platform.isIOS)) return;
  try {
    _isitici = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(data: '<!doctype html><html><body></body></html>', baseUrl: WebUri('about:blank')),
      initialSettings: InAppWebViewSettings(javaScriptEnabled: false, blockNetworkLoads: true, cacheEnabled: false, isInspectable: false),
    );
    await _isitici!.run();
  } catch (_) {
    _isitici = null;
  }
}

typedef _Girdi = ({
  String html,
  Map<String, String> baglantilar,
  Map<String, String> uzak,
  Map<String, String> cid,
  String kok,
  bool katla,
  bool sikisik,
  bool isaretle,
});

/// Hazırlık (büyük bültenlerde izolatta; arayüz donmasın).
({String belge, int engellenen, double dogal}) _hazirla(_Girdi a) {
  final t = htmlTemizle(a.html, baglantilar: a.baglantilar, uzak: a.uzak, cid: a.cid, kok: a.kok, isaretle: a.isaretle);
  return (belge: gorunumBelgesi(a.katla ? alintilariKatla(t.html) : t.html, sikisik: a.sikisik), engellenen: t.engellenen, dogal: dogalGenislik(t.html));
}

/// Bu boyutun altındaki HTML ana iş parçacığında, aynı karede hazırlanır (ileti değişince bekleme yok).
const _esZamanliSinir = 60000;

/// Hazırlanmış (görselleri yerleşmiş) son belgeler: aynı iletiye dönünce anında ve aynısı gösterilir.
class _HazirBelge {
  _HazirBelge(this.belge, this.engellenen, this.dogal, this.tam);
  final String belge;
  final int engellenen;
  final double dogal;

  /// Tüm görseller (uzak + gömülü) yerleşti mi.
  final bool tam;
}

class HazirBelgeler {
  HazirBelgeler._();
  static final _l = <String, _HazirBelge>{};
  static int _boyut = 0;

  /// Toplam üst sınır (karakter; data: görseller dahil).
  static int sinir = 80 * 1024 * 1024;

  static _HazirBelge? _al(String k) {
    final v = _l.remove(k);
    if (v != null) _l[k] = v;
    return v;
  }

  static void _koy(String k, _HazirBelge v) {
    final eski = _l.remove(k);
    if (eski != null) _boyut -= eski.belge.length;
    _l[k] = v;
    _boyut += v.belge.length;
    while (_boyut > sinir && _l.length > 1) {
      final ilk = _l.keys.first;
      _boyut -= _l.remove(ilk)!.belge.length;
    }
  }

  @visibleForTesting
  static int get sayi => _l.length;

  static void temizle() {
    _l.clear();
    _boyut = 0;
  }
}

/// Widget testlerinde web görünümü eklentisi yoktur: içerik düz metin olarak çizilir.
bool get _testOrtami => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Masaüstü (macOS / Windows / Linux) düzeni: okuma bölmesini dolduran, kendi içinde kayan tek web görünümü.
/// Testlerde [masaustuZorla] ile seçilir.
bool? masaustuZorla;
bool get masaustuDuzeni => masaustuZorla ?? (!kIsWeb && !_testOrtami && (Platform.isMacOS || Platform.isWindows || Platform.isLinux));

/// Güvenilmeyen ileti HTML'ini ağ erişimsiz bir görüntüleyicide gösterir. Uzak görseller varsayılan olarak
/// engellenir; "Görselleri göster" ile sunucu vekili üzerinden (data: olarak) yüklenir. Bağlantılar dış tarayıcıda
/// açılır, mailto: bağlantıları uygulamada yeni ileti açar.
///
/// İki kip: [otomatikYukseklik] (telefon konuşması: yükseklik yerel ölçülür, dış liste kayar) ve tam boy (varsayılan:
/// bölmeyi doldurur, kendi içinde kayar; masaüstü okuyucu). Tam boy kipte web görünümü ileti değişince korunur:
/// yeni belge hemen yüklenir (bellekteki görseller içinde), geç gelen görseller masaüstünde belge yeniden
/// yüklenmeden yerine konur (kaydırma konumu korunur, beyaz sayfa yok).
class HtmlGovde extends StatefulWidget {
  const HtmlGovde({
    super.key,
    required this.iletiId,
    required this.html,
    required this.ekler,
    this.baglantilar = const {},
    this.otomatikGorsel = false,
    this.kaydirma,
    this.epostaBaglantisi,
    this.ekIndir,
    this.otomatikYukseklik = false,
    this.alintiyiKatla = true,
  });

  final String iletiId;
  final String html;
  final List<Ek> ekler;
  final Map<String, String> baglantilar;
  final bool otomatikGorsel;
  final ValueChanged<double>? kaydirma;
  final ValueChanged<Uri>? epostaBaglantisi;

  /// Gömülü (cid:) görsel indirme; verilmezse oturumdaki hesabın eki.
  final Future<Uint8List> Function(int sira)? ekIndir;

  /// Telefon konuşma görünümü: yükseklik içerikten ölçülür (iOS/Android yerel), web görünümü kendi içinde kaymaz.
  final bool otomatikYukseklik;

  /// Alıntılanan geçmişi belge içinde "•••" ile katla (konuşma görünümü bunu kendisi yapar).
  final bool alintiyiKatla;

  @override
  State<HtmlGovde> createState() => _HtmlGovdeState();
}

class _HtmlGovdeState extends State<HtmlGovde> {
  InAppWebViewController? _k;
  String? _belge;
  String? _yuklenen;
  int _engellenen = 0;
  bool _gorseller = false;
  bool _gorselYukleniyor = false;
  bool _hazirlaniyor = false;
  Map<String, String> _cid = const {};
  Map<String, String> _uzak = const {};
  double? _yukseklik;
  bool _olculemedi = false;

  /// Her ileti değişiminde artar; eski işlerin sonucu atılır.
  int _nesil = 0;

  /// Yüklenen belge bitti mi (masaüstü yamaları yükleme bitince uygulanır).
  bool _yuklemeBitti = false;
  final _bekleyenUzak = <String, String>{};

  /// Hazırlanan belgenin içine zaten konmuş görseller (yükleme bitince yeniden yamalanmaz).
  Set<String> _belgedekiUzak = const {};
  Set<String> _belgedekiCid = const {};
  final _bekleyenCid = <String, String>{};

  /// İletinin sabit genişliği ve görüntüleyiciye sığdırma oranı (yatay kaydırma yok; web reader.tsx fit()).
  double _dogal = 0;
  double _oran = 1;
  double _en = 0;

  /// Masaüstü tam boy kipte görseller JavaScript ile (belge yeniden yüklenmeden) yerine konur. JavaScript yalnız
  /// uygulamanın çağrısı içindir: ileti betikleri temizleyicide silinir ve belgenin CSP'si (script-src 'none') sayfa
  /// betiği çalıştırmaz; evaluateJavascript CSP'ye tabi değildir. Telefonda JavaScript kapalıdır.
  bool get _yama => masaustuDuzeni && !widget.otomatikYukseklik;

  String? get _gosterilen => _belge == null ? null : sigdirilmisBelge(_belge!, _oran);

  String get _anahtar => '${widget.iletiId}|${widget.html.hashCode}|${widget.html.length}|$_gorseller|${widget.alintiyiKatla}|${widget.otomatikYukseklik}';

  _Girdi _girdi({Map<String, String>? uzak, Map<String, String>? cid, bool? isaretle}) => (
    html: widget.html,
    baglantilar: widget.baglantilar,
    uzak: _gorseller ? (uzak ?? _uzak) : const <String, String>{},
    cid: cid ?? _cid,
    kok: Uyg.api.sunucu,
    katla: widget.alintiyiKatla,
    sikisik: widget.otomatikYukseklik,
    isaretle: isaretle ?? _yama,
  );

  /// Genişlik değişince oran yeniden hesaplanır; değiştiyse belge yeniden yüklenir.
  void _genislikDegisti(double en) {
    if ((en - _en).abs() < 1) return;
    _en = en;
    final o = sigdirmaOrani(_dogal, en);
    if ((o - _oran).abs() < .01) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _oran = o);
      // Masaüstünde yerleşmiş görseller belgede değil: yeniden yüklemeden önce belge görsellerle kurulur.
      if (_yama && (_uzak.isNotEmpty || _cid.isNotEmpty)) {
        _esZamanliKur(isaretle: true);
      }
      unawaited(_yukle());
    });
  }

  Future<void> _yukle() async {
    final g = _gosterilen;
    if (_k == null || g == null) return;
    if (_yuklenen == g) {
      // Belge aynı: yeniden yükleme ve onLoadStop olmaz; telefonda yükseklik yine ölçülür.
      if (widget.otomatikYukseklik && _yukseklik == null) unawaited(_olc(_k!));
      return;
    }
    _yuklenen = g;
    _yuklemeBitti = false;
    await _k!.loadData(data: g, mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank'));
  }

  @override
  void initState() {
    super.initState();
    _gorseller = widget.otomatikGorsel;
    _baslat();
  }

  /// Aynı görüntüleyici başka bir iletiye geçti (okuma bölmesi): web görünümü korunur, yalnız belge değişir.
  @override
  void didUpdateWidget(HtmlGovde eski) {
    super.didUpdateWidget(eski);
    if (eski.iletiId == widget.iletiId && eski.html == widget.html && eski.otomatikGorsel == widget.otomatikGorsel) return;
    _cid = const {};
    _uzak = const {};
    _engellenen = 0;
    _gorseller = widget.otomatikGorsel;
    _gorselYukleniyor = false;
    _olculemedi = false;
    _bekleyenUzak.clear();
    _bekleyenCid.clear();
    _baslat();
  }

  /// Başlangıç: hazır belge (LRU) varsa aynı karede; yoksa bellekteki görsellerle (küçük iletide eşzamanlı)
  /// hazırlanır; eksik görseller (disk, gömülü, uzak) sonra yerleşir.
  void _baslat() {
    final n = ++_nesil;
    final h = HazirBelgeler._al(_anahtar);
    if (h != null) {
      _belge = h.belge;
      _dogal = h.dogal;
      _engellenen = h.engellenen;
      if (_en > 0) _oran = sigdirmaOrani(_dogal, _en);
      _hazirlaniyor = false;
      _belgedekiUzak = const {};
      _belgedekiCid = const {};
      if (mounted) setState(() {});
      unawaited(_yukle());
      // Yalnız tamamlanmış belgeler saklanır: görsel / ek indirme yok.
      return;
    }
    List<String> adresler = const [];
    if (_gorseller && widget.html.length <= _esZamanliSinir) {
      adresler = uzakGorseller(widget.html);
      _uzak = {
        for (final u in adresler)
          if (Onbellek.ben.hemen('gorsel:$u') case final String v) u: v,
      };
    }
    if (widget.html.length <= _esZamanliSinir) {
      _esZamanliKur();
      if (mounted) setState(() {});
      unawaited(_yukle());
    } else {
      // Büyük bülten: izolatta hazırlanır; önceki içerik görünür kalır, üstte ince gösterge.
      _hazirlaniyor = true;
      if (mounted) setState(() {});
      unawaited(_izolattaKur(n));
    }
    unawaited(_sonraYukle(n));
  }

  void _esZamanliKur({bool? isaretle}) {
    _belgedekiUzak = _uzak.keys.toSet();
    _belgedekiCid = _cid.keys.toSet();
    final r = _hazirla(_girdi(isaretle: isaretle));
    _belge = r.belge;
    _dogal = r.dogal;
    if (_en > 0) _oran = sigdirmaOrani(_dogal, _en);
    if (!_gorseller || _uzak.isEmpty) _engellenen = r.engellenen;
    _hazirlaniyor = false;
  }

  Future<void> _izolattaKur(int n) async {
    final u = _uzak.keys.toSet(), c = _cid.keys.toSet();
    final r = await compute(_hazirla, _girdi());
    if (!mounted || n != _nesil) return;
    _belgedekiUzak = u;
    _belgedekiCid = c;
    setState(() {
      _belge = r.belge;
      _dogal = r.dogal;
      if (_en > 0) _oran = sigdirmaOrani(_dogal, _en);
      if (!_gorseller || _uzak.isEmpty) _engellenen = r.engellenen;
      _hazirlaniyor = false;
    });
    await _yukle();
  }

  /// Diskteki görseller, gömülü (cid) görseller, uzak görseller.
  Future<void> _sonraYukle(int n) async {
    if (_gorseller) {
      final html = widget.html;
      final adresler = html.length > _esZamanliSinir ? await compute(uzakGorseller, html) : uzakGorseller(html);
      if (!mounted || n != _nesil) return;
      final eksik = adresler.where((u) => !_uzak.containsKey(u)).toList();
      final diskte = <String, String>{};
      await Future.wait(
        eksik.map((u) async {
          final v = Onbellek.ben.hemen('gorsel:$u') ?? await Onbellek.ben.oku('gorsel:$u').catchError((_) => null);
          if (v is String) diskte[u] = v;
        }),
      );
      if (!mounted || n != _nesil) return;
      if (diskte.isNotEmpty) await _uzakEkle(n, diskte);
      unawaited(_cidYukle(n));
      if (adresler.any((u) => !_uzak.containsKey(u))) await _uzakYukle(n, adresler);
    } else {
      await _cidYukle(n);
    }
    _tamamsaSakla(n);
  }

  /// Tüm görseller yerleştiyse son belge (görseller içinde, işaretsiz) LRU'ya konur.
  void _tamamsaSakla(int n) {
    if (!mounted || n != _nesil) return;
    final k = _anahtar;
    final girdi = _girdi(isaretle: false);
    unawaited(
      compute(_hazirla, girdi).then((r) {
        HazirBelgeler._koy(k, _HazirBelge(r.belge, r.engellenen, r.dogal, true));
      }),
    );
  }

  Future<void> _uzakEkle(int n, Map<String, String> yeni) async {
    _uzak = {..._uzak, ...yeni};
    if (_yama) {
      _bekleyenUzak.addAll(yeni);
      await _yamala();
    } else {
      await _yenidenKur(n);
    }
  }

  /// Telefon: belge yeni görsellerle yeniden kurulup yüklenir.
  Future<void> _yenidenKur(int n) async {
    final u = _uzak.keys.toSet(), c = _cid.keys.toSet();
    final r = await compute(_hazirla, _girdi());
    if (!mounted || n != _nesil) return;
    _belgedekiUzak = u;
    _belgedekiCid = c;
    setState(() {
      _belge = r.belge;
      _dogal = r.dogal;
      if (_en > 0) _oran = sigdirmaOrani(_dogal, _en);
      if (!_gorseller || _uzak.isEmpty) _engellenen = r.engellenen;
    });
    await _yukle();
  }

  static const _yamaBetigi = """(function(u,c){var n=0;
document.querySelectorAll('[data-bm-g]').forEach(function(e){var d=u[e.getAttribute('data-bm-g')];if(d){if(e.tagName==='IMG'){e.src=d;}else{e.setAttribute('background',d);}e.removeAttribute('data-bm-g');n++;}});
document.querySelectorAll('[data-bm-c]').forEach(function(e){var d=c[e.getAttribute('data-bm-c')];if(d){if(e.tagName==='IMG'){e.src=d;}else{e.setAttribute('background',d);}e.removeAttribute('data-bm-c');n++;}});
return n;})""";

  /// Masaüstü: bekleyen görseller belge yeniden yüklenmeden yerine konur (kaydırma konumu korunur).
  Future<void> _yamala() async {
    final c = _k;
    if (c == null || !_yuklemeBitti || (_bekleyenUzak.isEmpty && _bekleyenCid.isEmpty)) return;
    final u = Map.of(_bekleyenUzak), ci = Map.of(_bekleyenCid);
    _bekleyenUzak.clear();
    _bekleyenCid.clear();
    try {
      await c.evaluateJavascript(source: '$_yamaBetigi(${jsonEncode(u)},${jsonEncode(ci)})');
    } catch (_) {}
  }

  Future<void> _cidYukle(int n) async {
    final h = widget.html.toLowerCase();
    final istenen = widget.ekler
        .where((a) => a.icerikId.isNotEmpty && _cidTurleri.hasMatch(a.tur) && a.boyut <= _cidSiniri && h.contains('cid:${a.icerikId.toLowerCase()}'))
        .toList();
    if (istenen.isEmpty) return;
    final out = <String, String>{};
    await Future.wait(
      istenen.map((a) async {
        try {
          final b = await (widget.ekIndir ?? (int s) => Posta.ekIndir(widget.iletiId, s))(a.sira);
          out[a.icerikId.toLowerCase()] = 'data:${a.tur.toLowerCase()};base64,${base64Encode(b)}';
        } catch (_) {}
      }),
    );
    if (!mounted || out.isEmpty || n != _nesil) return;
    _cid = {..._cid, ...out};
    if (_yama) {
      _bekleyenCid.addAll(out);
      await _yamala();
    } else {
      await _yenidenKur(n);
    }
  }

  Future<void> _uzakYukle(int n, List<String> adresler) async {
    if (adresler.isEmpty || !mounted) return;
    setState(() => _gorselYukleniyor = true);
    final kuyruk = adresler.where((u) => !_uzak.containsKey(u)).toList();
    final gelen = <String, String>{};
    // Görseller geldikçe gösterilir: masaüstünde hemen (yama), telefonda en fazla ~350 ms'de bir yeniden çizim.
    var sonCizim = DateTime.fromMillisecondsSinceEpoch(0);
    var cizimBekliyor = false;
    Future<void> ara() async {
      if (cizimBekliyor) return;
      cizimBekliyor = true;
      final gecen = DateTime.now().difference(sonCizim).inMilliseconds;
      final bekle = _yama ? 60 : 350;
      if (gecen < bekle) await Future<void>.delayed(Duration(milliseconds: bekle - gecen));
      cizimBekliyor = false;
      if (!mounted || n != _nesil || gelen.isEmpty) return;
      sonCizim = DateTime.now();
      final parti = Map.of(gelen);
      gelen.clear();
      await _uzakEkle(n, parti);
    }

    Future<void> isci() async {
      while (kuyruk.isNotEmpty && mounted && n == _nesil) {
        final u = kuyruk.removeAt(0);
        final d = await Posta.uzakGorselVeri(u);
        if (d != null) {
          gelen[u] = d;
          unawaited(ara());
        }
      }
    }

    await Future.wait(List.generate(kuyruk.length < 8 ? kuyruk.length : 8, (_) => isci()));
    if (!mounted || n != _nesil) return;
    if (gelen.isNotEmpty) await _uzakEkle(n, Map.of(gelen));
    setState(() => _gorselYukleniyor = false);
  }

  void _gorselleriGoster() {
    setState(() => _gorseller = true);
    final n = _nesil;
    unawaited(() async {
      final adresler = await compute(uzakGorseller, widget.html);
      await _uzakYukle(n, adresler);
      _tamamsaSakla(n);
    }());
  }

  /// İçerik yüksekliğini ölçer (telefon; yükleme bitince ve görseller yerleşince birkaç kez).
  Future<void> _olc(InAppWebViewController c) async {
    if (!widget.otomatikYukseklik) return;
    for (final bekle in const [0, 250, 900]) {
      if (bekle > 0) await Future<void>.delayed(Duration(milliseconds: bekle));
      if (!mounted || _k != c) return;
      int? h;
      try {
        h = await c.getContentHeight();
      } catch (_) {}
      if (!mounted) return;
      if (h == null || h <= 0) {
        if (_yukseklik == null) setState(() => _olculemedi = true);
        continue;
      }
      final y = h.toDouble() + 8;
      if (_yukseklik == null || (y - _yukseklik!).abs() > 2) {
        setState(() {
          _yukseklik = y;
          _olculemedi = false;
        });
      }
    }
  }

  Future<NavigationActionPolicy?> _gezinme(InAppWebViewController c, NavigationAction a) async {
    final u = a.request.url;
    if (u == null) return NavigationActionPolicy.ALLOW;
    final sema = u.scheme.toLowerCase();
    if (sema == 'about' || sema == 'data') return NavigationActionPolicy.ALLOW;
    if (sema == 'mailto') {
      widget.epostaBaglantisi?.call(Uri.parse(u.toString()));
      return NavigationActionPolicy.CANCEL;
    }
    if (sema == 'http' || sema == 'https') {
      unawaited(launchUrl(Uri.parse(u.toString()), mode: LaunchMode.externalApplication));
    }
    return NavigationActionPolicy.CANCEL;
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final belge = _gosterilen;
    final oto = widget.otomatikYukseklik;
    final bant = _engellenen > 0 && !_gorseller
        ? Material(
            key: const ValueKey('gorsel-bandi'),
            color: r.birincilYumusak,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: [
                  Icon(Simge.kalkan, size: 18, color: r.birincil),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Güvenliğiniz için uzak görseller gösterilmedi.', style: TextStyle(fontSize: 12.5, color: r.soluk)),
                  ),
                  TextButton(onPressed: _gorselleriGoster, child: const Text('Görselleri göster')),
                ],
              ),
            ),
          )
        : null;
    if (_testOrtami) {
      final metin = Padding(
        padding: EdgeInsets.fromLTRB(16, oto ? 2 : 14, 16, oto ? 8 : 14),
        child: Text(htmlMetne(widget.html).trim(), style: TextStyle(fontSize: 14, height: 1.5, color: r.metin)),
      );
      if (oto) return metin;
      return Column(
        key: const ValueKey('html-tam-boy'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?bant,
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: SingleChildScrollView(child: metin),
            ),
          ),
        ],
      );
    }
    // Ölçülemezse sınırlı yükseklik; içerik kendi içinde kayar.
    final sinir = (MediaQuery.sizeOf(context).height - 160).clamp(360.0, 4000.0);
    final yukseklik = _olculemedi ? sinir : (_yukseklik ?? 120);
    Widget kutu(Widget c) => oto ? SizedBox(height: yukseklik, child: c) : Expanded(child: c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: oto ? MainAxisSize.min : MainAxisSize.max,
      children: [
        ?bant,
        kutu(
          LayoutBuilder(
            builder: (context, k) {
              _genislikDegisti(k.maxWidth);
              return Container(
                // İleti HTML'i beyaz zemin varsayar; bölmenin tam genişliği (yan dolgu 16 px belgede).
                color: Colors.white,
                child: belge == null
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator.adaptive(strokeWidth: 2)))
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: Semantics(
                              label: 'İleti içeriği',
                              child: InAppWebView(
                                initialData: InAppWebViewInitialData(data: belge, mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank')),
                                initialSettings: InAppWebViewSettings(
                                  javaScriptEnabled: _yama,
                                  javaScriptCanOpenWindowsAutomatically: false,
                                  useShouldOverrideUrlLoading: true,
                                  blockNetworkLoads: true,
                                  blockNetworkImage: true,
                                  allowFileAccess: false,
                                  allowContentAccess: false,
                                  allowFileAccessFromFileURLs: false,
                                  allowUniversalAccessFromFileURLs: false,
                                  supportZoom: true,
                                  builtInZoomControls: true,
                                  displayZoomControls: false,
                                  allowsLinkPreview: false,
                                  isFraudulentWebsiteWarningEnabled: false,
                                  mediaPlaybackRequiresUserGesture: true,
                                  isInspectable: false,
                                  transparentBackground: false,
                                  cacheEnabled: false,
                                  thirdPartyCookiesEnabled: false,
                                  disableVerticalScroll: oto && !_olculemedi,
                                  verticalScrollBarEnabled: !oto || _olculemedi,
                                ),
                                onWebViewCreated: (c) {
                                  _k = c;
                                  _yuklenen = belge;
                                  _yuklemeBitti = false;
                                },
                                onLoadStop: (c, _) {
                                  _yuklemeBitti = true;
                                  if (oto) unawaited(_olc(c));
                                  if (_yama) {
                                    // Yükleme sırasında gelen görseller (belge işaretli; yerleşenler belgenin içinde).
                                    _bekleyenUzak.addAll({
                                      for (final e in _uzak.entries)
                                        if (!_belgedekiUzak.contains(e.key)) e.key: e.value,
                                    });
                                    _bekleyenCid.addAll({
                                      for (final e in _cid.entries)
                                        if (!_belgedekiCid.contains(e.key)) e.key: e.value,
                                    });
                                    unawaited(_yamala());
                                  }
                                },
                                onContentSizeChanged: oto
                                    ? (c, _, yeni) {
                                        if (yeni.height > 0 && mounted && (_yukseklik == null || (yeni.height + 8 - _yukseklik!).abs() > 2)) {
                                          setState(() => _yukseklik = yeni.height + 8);
                                        }
                                      }
                                    : null,
                                shouldOverrideUrlLoading: _gezinme,
                                onCreateWindow: (c, a) async {
                                  final u = a.request.url;
                                  if (u != null && (u.scheme == 'http' || u.scheme == 'https')) {
                                    unawaited(launchUrl(Uri.parse(u.toString()), mode: LaunchMode.externalApplication));
                                  }
                                  return false;
                                },
                                onScrollChanged: widget.kaydirma == null ? null : (c, x, y) => widget.kaydirma!(y.toDouble()),
                              ),
                            ),
                          ),
                          // Görsel yükleniyor / büyük belge hazırlanıyor: içeriği itmeyen ince çizgi (üstte).
                          if (_gorselYukleniyor || _hazirlaniyor) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}
