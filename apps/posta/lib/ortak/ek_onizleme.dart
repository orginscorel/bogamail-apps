// Ek önizleme (web: blob → iframe): görsel, PDF ve düz metin uygulama içinde açılır; SVG / HTML ve diğer türler
// asla önizlenmez (dış uygulamaya gider). PDF: iOS/macOS'ta WKWebView, Windows'ta WebView2 yerleşik PDF
// görüntüleyicisi (JavaScript kapalı, ağ kapalı, yalnız yerel dosya); Android web görünümü PDF çizemediği için
// sistem PDF görüntüleyicisi açılır. Üst çubukta Paylaş / Kaydet / Başka uygulamada aç.

import 'dart:convert';
import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../veri/modeller.dart';

enum EkOnizlemeTuru { gorsel, pdf, metin }

/// Ekin uygulama içi önizleme türü (yoksa null: dış uygulama). [android]: platform (testlerde verilir).
EkOnizlemeTuru? ekOnizlemeTuru(Ek e, {bool? android}) {
  final t = e.tur.toLowerCase().split(';').first.trim();
  final ad = e.ad.toLowerCase();
  // Etkin içerik asla önizlenmez.
  if (t.contains('svg') || t.contains('html') || t.contains('xml') || ad.endsWith('.svg') || ad.endsWith('.html') || ad.endsWith('.htm')) return null;
  const gorseller = {'image/png', 'image/jpeg', 'image/jpg', 'image/gif', 'image/webp', 'image/bmp'};
  if (gorseller.contains(t)) return EkOnizlemeTuru.gorsel;
  if (t == 'application/pdf' || ad.endsWith('.pdf')) {
    final a = android ?? (!kIsWeb && Platform.isAndroid);
    return a ? null : EkOnizlemeTuru.pdf;
  }
  if (t == 'text/plain' || t == 'text/csv' || RegExp(r'\.(txt|log|csv|md|ini|conf|json|ya?ml)$').hasMatch(ad)) return EkOnizlemeTuru.metin;
  return null;
}

/// Düz metin önizlemesi en çok bu kadar bayt gösterir.
const azamiMetinOnizleme = 1024 * 1024;

class EkOnizleme extends StatelessWidget {
  const EkOnizleme({super.key, required this.ek, required this.tur, required this.veri, this.dosya, this.paylas, this.kaydet, this.disaridaAc});
  final Ek ek;
  final EkOnizlemeTuru tur;
  final Uint8List veri;

  /// PDF için yerel dosya (web görünümü dosyadan okur).
  final File? dosya;
  final VoidCallback? paylas;
  final VoidCallback? kaydet;
  final VoidCallback? disaridaAc;

  static bool get _testOrtami => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Scaffold(
      key: const ValueKey('ek-onizleme'),
      backgroundColor: tur == EkOnizlemeTuru.gorsel ? Colors.black : r.kart,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ek.ad, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              boyutYaz(ek.boyut > 0 ? ek.boyut : veri.length),
              style: TextStyle(fontSize: 12, color: r.silik, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          if (paylas != null) IconButton(tooltip: 'Paylaş', icon: const Icon(Simge.paylas), onPressed: paylas),
          if (kaydet != null) IconButton(tooltip: 'Kaydet', icon: const Icon(Simge.indir), onPressed: kaydet),
          if (disaridaAc != null) IconButton(tooltip: 'Başka uygulamada aç', icon: const Icon(Simge.disaAc), onPressed: disaridaAc),
          const SizedBox(width: 4),
        ],
      ),
      body: switch (tur) {
        EkOnizlemeTuru.gorsel => InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.memory(
              veri,
              errorBuilder: (_, _, _) => const Text('Görsel açılamadı.', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
        EkOnizlemeTuru.metin => _MetinOnizleme(veri: veri, esIkili: ek.ad.toLowerCase().endsWith('.csv') || ek.ad.toLowerCase().endsWith('.log')),
        EkOnizlemeTuru.pdf =>
          _testOrtami || dosya == null
              ? Center(key: const ValueKey('pdf-onizleme'), child: Text('PDF · ${boyutYaz(veri.length)}'))
              : InAppWebView(
                  key: const ValueKey('pdf-onizleme'),
                  initialUrlRequest: URLRequest(url: WebUri(Uri.file(dosya!.path).toString())),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: false,
                    blockNetworkLoads: true,
                    allowFileAccess: true,
                    allowingReadAccessTo: WebUri(Uri.directory(dosya!.parent.path).toString()),
                    isInspectable: false,
                    transparentBackground: false,
                  ),
                ),
      },
    );
  }
}

class _MetinOnizleme extends StatelessWidget {
  const _MetinOnizleme({required this.veri, required this.esIkili});
  final Uint8List veri;
  final bool esIkili;

  @override
  Widget build(BuildContext context) {
    final kesik = veri.length > azamiMetinOnizleme;
    final metin = utf8.decode(kesik ? veri.sublist(0, azamiMetinOnizleme) : veri, allowMalformed: true);
    return Scrollbar(
      child: SingleChildScrollView(
        key: const ValueKey('metin-onizleme'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(metin, style: TextStyle(fontSize: 13.5, height: 1.45, fontFeatures: esIkili ? const [FontFeature.tabularFigures()] : null)),
            if (kesik)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('İlk 1 MB gösteriliyor. Tamamı için kaydedin ya da başka uygulamada açın.', style: TextStyle(color: context.r.silik, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
