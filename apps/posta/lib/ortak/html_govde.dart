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

/// İzolatta çalışan hazırlık (büyük bültenler arayüzü dondurmasın).
({String belge, int engellenen}) _hazirla(
  ({String html, Map<String, String> baglantilar, Map<String, String> uzak, Map<String, String> cid, String kok, bool katla, bool sikisik}) a,
) {
  final t = htmlTemizle(a.html, baglantilar: a.baglantilar, uzak: a.uzak, cid: a.cid, kok: a.kok);
  return (belge: gorunumBelgesi(a.katla ? alintilariKatla(t.html) : t.html, sikisik: a.sikisik), engellenen: t.engellenen);
}

/// Widget testlerinde web görünümü eklentisi yoktur: içerik düz metin olarak çizilir.
bool get _testOrtami => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Güvenilmeyen ileti HTML'ini JavaScript'siz, ağ erişimsiz bir görüntüleyicide gösterir. Uzak görseller varsayılan
/// olarak engellenir; "Görselleri göster" ile sunucu vekili üzerinden (data: olarak) yüklenir. Bağlantılar dış
/// tarayıcıda açılır, mailto: bağlantıları uygulamada yeni ileti açar.
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

  /// Konuşma görünümü: yükseklik içerikten ölçülür, web görünümü kendi içinde kaymaz (iç içe kaydırma yok);
  /// dış liste kayar. Ölçülemeyen platformlarda sınırlı yükseklikte kendi içinde kayar.
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
  Map<String, String> _cid = const {};
  Map<String, String> _uzak = const {};
  double? _yukseklik;
  bool _olculemedi = false;

  @override
  void initState() {
    super.initState();
    _gorseller = widget.otomatikGorsel;
    unawaited(_baslat());
  }

  /// Aynı görüntüleyici başka bir iletiye geçti (geniş ekranda okuma bölmesi): web görünümü korunur, yalnız belge
  /// değişir (her açılışta yeni web görünümü kurma maliyeti yok).
  @override
  void didUpdateWidget(HtmlGovde eski) {
    super.didUpdateWidget(eski);
    if (eski.iletiId == widget.iletiId && eski.html == widget.html) return;
    _cid = const {};
    _uzak = const {};
    _engellenen = 0;
    _gorseller = widget.otomatikGorsel;
    _gorselYukleniyor = false;
    _olculemedi = false;
    unawaited(_baslat());
  }

  Future<void> _baslat() async {
    var eksik = true;
    if (_gorseller) {
      // Önbellekteki (önyüklenmiş) görseller ilk belgeye girer: ağ yok, ikinci çizim yok.
      final s = Stopwatch()..start();
      final (bulunan, tumu) = await _onbellektekiGorseller();
      _uzak = bulunan;
      eksik = !tumu;
      zamanLogu('görseller (önbellek)', s);
    }
    await _yenidenOlustur();
    unawaited(_cidYukle());
    if (_gorseller && eksik) unawaited(_uzakYukle());
  }

  /// Uzak görsellerden yerel önbellekte olanlar (bellek, sonra disk). İkinci değer: hepsi bulundu mu.
  Future<(Map<String, String>, bool)> _onbellektekiGorseller() async {
    final html = widget.html;
    final adresler = html.length > 60000 ? await compute(uzakGorseller, html) : uzakGorseller(html);
    if (adresler.isEmpty) return (const <String, String>{}, true);
    final out = <String, String>{};
    final diskte = <String>[];
    for (final u in adresler) {
      final v = Onbellek.ben.hemen('gorsel:$u');
      if (v is String) {
        out[u] = v;
      } else {
        diskte.add(u);
      }
    }
    await Future.wait(
      diskte.map((u) async {
        final v = await Onbellek.ben.oku('gorsel:$u');
        if (v is String) out[u] = v;
      }),
    );
    return (out, out.length == adresler.length);
  }

  Future<void> _yenidenOlustur() async {
    final id = widget.iletiId;
    final r = await compute(_hazirla, (
      html: widget.html,
      baglantilar: widget.baglantilar,
      uzak: _gorseller ? _uzak : const <String, String>{},
      cid: _cid,
      kok: Uyg.api.sunucu,
      katla: widget.alintiyiKatla,
      sikisik: widget.otomatikYukseklik,
    ));
    if (!mounted || id != widget.iletiId) return;
    setState(() {
      _belge = r.belge;
      if (!_gorseller || _uzak.isEmpty) _engellenen = r.engellenen;
    });
    if (_k != null && _yuklenen != r.belge) {
      _yuklenen = r.belge;
      await _k!.loadData(data: r.belge, mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank'));
    }
  }

  Future<void> _cidYukle() async {
    final kimlik = widget.iletiId;
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
    if (!mounted || out.isEmpty || kimlik != widget.iletiId) return;
    _cid = out;
    await _yenidenOlustur();
  }

  Future<void> _uzakYukle() async {
    final kimlik = widget.iletiId;
    final adresler = await compute(uzakGorseller, widget.html);
    if (adresler.isEmpty || !mounted) return;
    setState(() => _gorselYukleniyor = true);
    final kuyruk = [...adresler];
    final bulunan = <String, String>{};
    Future<void> isci() async {
      while (kuyruk.isNotEmpty && mounted && kimlik == widget.iletiId) {
        final u = kuyruk.removeAt(0);
        final d = await Posta.uzakGorselVeri(u);
        if (d != null) bulunan[u] = d;
      }
    }

    await Future.wait(List.generate(adresler.length < 6 ? adresler.length : 6, (_) => isci()));
    if (!mounted || kimlik != widget.iletiId) return;
    if (bulunan.length == _uzak.length && bulunan.keys.every(_uzak.containsKey)) {
      setState(() => _gorselYukleniyor = false);
      return;
    }
    _uzak = bulunan;
    setState(() => _gorselYukleniyor = false);
    await _yenidenOlustur();
  }

  void _gorselleriGoster() {
    setState(() => _gorseller = true);
    unawaited(_uzakYukle());
  }

  /// İçerik yüksekliğini ölçer (yükleme bitince ve görseller yerleşince birkaç kez).
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
    final belge = _belge;
    final oto = widget.otomatikYukseklik;
    // Ölçülemezse (ör. JavaScript'siz masaüstü) sınırlı yükseklik; içerik kendi içinde kayar.
    final sinir = (MediaQuery.sizeOf(context).height * .7).clamp(240.0, 640.0);
    final yukseklik = _olculemedi ? sinir : (_yukseklik ?? 120);
    Widget kutu(Widget c) => oto ? SizedBox(height: yukseklik, child: c) : Expanded(child: c);
    if (_testOrtami) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, oto ? 2 : 14, 16, oto ? 8 : 14),
        child: Text(htmlMetne(widget.html).trim(), style: TextStyle(fontSize: 14, height: 1.5, color: r.metin)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: oto ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (_engellenen > 0 && !_gorseller)
          Material(
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
          ),
        if (_gorselYukleniyor) const LinearProgressIndicator(minHeight: 2),
        kutu(
          Container(
            // İleti HTML'i beyaz zemin varsayar; ek çerçeve/dolgu yok, bölmenin tam genişliği (yan dolgu 16 px ve
            // çok geniş bölmede 760 px ortalı sütun belgenin kendi stilinde).
            color: Colors.white,
            child: belge == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : Semantics(
                    label: 'İleti içeriği',
                    child: InAppWebView(
                      initialData: InAppWebViewInitialData(data: belge, mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank')),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: false,
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
                      },
                      onLoadStop: oto ? (c, _) => _olc(c) : null,
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
        ),
      ],
    );
  }
}
