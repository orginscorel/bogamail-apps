import 'dart:async';
import 'dart:convert';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../oturum.dart';
import '../veri/html_temizle.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';

final _cidTurleri = RegExp(r'^image/(png|jpeg|gif|webp)$', caseSensitive: false);
const _cidSiniri = 5 * 1024 * 1024;

/// İzolatta çalışan hazırlık (büyük bültenler arayüzü dondurmasın).
({String belge, int engellenen}) _hazirla(({String html, Map<String, String> baglantilar, Map<String, String> uzak, Map<String, String> cid, String kok}) a) {
  final t = htmlTemizle(a.html, baglantilar: a.baglantilar, uzak: a.uzak, cid: a.cid, kok: a.kok);
  return (belge: gorunumBelgesi(alintilariKatla(t.html)), engellenen: t.engellenen);
}

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
  });

  final String iletiId;
  final String html;
  final List<Ek> ekler;
  final Map<String, String> baglantilar;
  final bool otomatikGorsel;
  final ValueChanged<double>? kaydirma;
  final ValueChanged<Uri>? epostaBaglantisi;

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

  @override
  void initState() {
    super.initState();
    _gorseller = widget.otomatikGorsel;
    unawaited(_baslat());
  }

  Future<void> _baslat() async {
    await _yenidenOlustur();
    unawaited(_cidYukle());
    if (_gorseller) unawaited(_uzakYukle());
  }

  Future<void> _yenidenOlustur() async {
    final r = await compute(_hazirla, (
      html: widget.html,
      baglantilar: widget.baglantilar,
      uzak: _gorseller ? _uzak : const <String, String>{},
      cid: _cid,
      kok: Uyg.api.sunucu,
    ));
    if (!mounted) return;
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
    final h = widget.html.toLowerCase();
    final istenen = widget.ekler
        .where((a) => a.icerikId.isNotEmpty && _cidTurleri.hasMatch(a.tur) && a.boyut <= _cidSiniri && h.contains('cid:${a.icerikId.toLowerCase()}'))
        .toList();
    if (istenen.isEmpty) return;
    final out = <String, String>{};
    await Future.wait(
      istenen.map((a) async {
        try {
          final b = await Posta.ekIndir(widget.iletiId, a.sira);
          out[a.icerikId.toLowerCase()] = 'data:${a.tur.toLowerCase()};base64,${base64Encode(b)}';
        } catch (_) {}
      }),
    );
    if (!mounted || out.isEmpty) return;
    _cid = out;
    await _yenidenOlustur();
  }

  Future<void> _uzakYukle() async {
    final adresler = await compute(uzakGorseller, widget.html);
    if (adresler.isEmpty || !mounted) return;
    setState(() => _gorselYukleniyor = true);
    final kuyruk = [...adresler];
    final bulunan = <String, String>{};
    Future<void> isci() async {
      while (kuyruk.isNotEmpty && mounted) {
        final u = kuyruk.removeAt(0);
        final d = await Posta.uzakGorselVeri(u);
        if (d != null) bulunan[u] = d;
      }
    }

    await Future.wait(List.generate(adresler.length < 6 ? adresler.length : 6, (_) => isci()));
    if (!mounted) return;
    _uzak = bulunan;
    setState(() => _gorselYukleniyor = false);
    await _yenidenOlustur();
  }

  void _gorselleriGoster() {
    setState(() => _gorseller = true);
    unawaited(_uzakYukle());
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_engellenen > 0 && !_gorseller)
          Material(
            color: r.birincilYumusak,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: r.birincil),
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
        Expanded(
          child: Container(
            // İleti HTML'i beyaz zemin varsayar: koyu temada beyaz bir kart içinde gösterilir.
            margin: r.koyu ? const EdgeInsets.fromLTRB(10, 6, 10, 10) : EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(r.koyu ? 14 : 0)),
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
                      ),
                      onWebViewCreated: (c) {
                        _k = c;
                        _yuklenen = belge;
                      },
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
