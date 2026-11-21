// İletiyi yazdırma (web: Yazdır). Başlık bilgileri (konu, kimden, kime, bilgi, tarih, ekler) ve temizlenmiş gövde
// tek bir yazdırma belgesine konur; önizleme penceresinde "Yazdır" sistem yazdırma iletişimini açar
// (Android / iOS / macOS / Windows web görünümü). JavaScript ve ağ kapalı; uzak görseller yüklenmez.
// Web görünümü yazdıramazsa belge sistem tarayıcısında açılır (oradan yazdırılır).

import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as ayristir show parse;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../veri/html_temizle.dart';
import '../veri/modeller.dart';
import '../veri/yardimci.dart';

String _kacir(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Yazdırılacak tam HTML belgesi.
String yazdirmaBelgesi(IletiDetay d) {
  final v = d.gorunum;
  final tarih = v.tarih ?? d.ozet.tarih;
  final satirlar = <(String, String)>[
    ('Kimden', v.kimden.isNotEmpty ? v.kimden.map(adresYaz).join(', ') : d.ozet.kimden),
    ('Kime', v.kime.map(adresYaz).join(', ')),
    if (v.bilgi.isNotEmpty) ('Bilgi', v.bilgi.map(adresYaz).join(', ')),
    if (tarih != null) ('Tarih', DateFormat('d MMMM y EEEE HH:mm', 'tr_TR').format(tarih.toLocal())),
    if (v.dosyaEkleri.isNotEmpty) ('Ekler', v.dosyaEkleri.map((e) => '${e.ad} (${boyutYaz(e.boyut)})').join(', ')),
  ];
  final String govde;
  if (v.html.trim().isNotEmpty) {
    // Temizlenmiş gövde (betik, form, iframe, olay öznitelikleri atılır; uzak görseller engellenir).
    final t = htmlTemizle(v.html).html;
    final b = ayristir.parse(t).body;
    govde = b?.innerHtml ?? t;
  } else {
    govde = '<pre>${_kacir(v.metin)}</pre>';
  }
  final konu = v.konu.trim().isEmpty ? '(konu yok)' : v.konu;
  return '''<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: cid:; style-src 'unsafe-inline'; font-src data:">
<title>${_kacir(konu)}</title>
<style>
body{font-family:-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:#111;margin:24px;font-size:14px;line-height:1.5}
.bas{border-bottom:1px solid #bbb;padding-bottom:10px;margin-bottom:16px}
.bas h1{font-size:19px;margin:0 0 8px}
.bas table{border-collapse:collapse}
.bas td{padding:1px 10px 1px 0;vertical-align:top;font-size:12.5px}
.bas td.e{color:#666;white-space:nowrap}
pre{white-space:pre-wrap;word-wrap:break-word;font-family:inherit;margin:0}
img{max-width:100%;height:auto}
@media print{body{margin:0}}
</style></head><body>
<div class="bas"><h1>${_kacir(konu)}</h1><table>
${satirlar.map((x) => '<tr><td class="e">${x.$1}</td><td>${_kacir(x.$2)}</td></tr>').join('\n')}
</table></div>
<div class="govde">$govde</div>
</body></html>''';
}

/// Yazdırma önizlemesi ve "Yazdır".
Future<void> iletiYazdir(BuildContext context, IletiDetay d) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => YazdirmaEkrani(belge: yazdirmaBelgesi(d), baslik: d.gorunum.konu),
  ),
);

class YazdirmaEkrani extends StatefulWidget {
  const YazdirmaEkrani({super.key, required this.belge, required this.baslik});
  final String belge;
  final String baslik;

  @override
  State<YazdirmaEkrani> createState() => _YazdirmaEkraniState();
}

class _YazdirmaEkraniState extends State<YazdirmaEkrani> {
  InAppWebViewController? _c;
  bool _hazir = false;

  static bool get _testOrtami => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  Future<void> _yazdir() async {
    try {
      final c = _c;
      if (c == null) throw StateError('web görünümü yok');
      await c.printCurrentPage();
    } catch (_) {
      await _tarayicidaAc();
    }
  }

  /// Web görünümü yazdıramıyorsa: belge geçici dosyaya yazılıp sistem tarayıcısında açılır.
  Future<void> _tarayicidaAc() async {
    try {
      final d = await getTemporaryDirectory();
      final f = File('${d.path}/yazdir/ileti.html');
      await f.parent.create(recursive: true);
      await f.writeAsString(widget.belge, flush: true);
      if (!await launchUrl(Uri.file(f.path))) throw StateError('açılamadı');
      bildir('Belge tarayıcıda açıldı', mesaj: 'Tarayıcının Yazdır komutuyla yazdırabilirsiniz.');
    } catch (_) {
      bildir('Yazdırılamadı', mesaj: 'Bu cihazda yazdırma desteklenmiyor.', tur: MesajTur.hata);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.baslik.trim().isEmpty ? 'Yazdır' : widget.baslik, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              key: const ValueKey('yazdir'),
              onPressed: _testOrtami || _hazir ? _yazdir : null,
              icon: const Icon(Simge.yazdir, size: 18),
              label: const Text('Yazdır'),
            ),
          ),
        ],
      ),
      body: _testOrtami
          ? const Center(key: ValueKey('yazdirma-onizleme'), child: Text('Yazdırma önizlemesi'))
          : InAppWebView(
              key: const ValueKey('yazdirma-onizleme'),
              initialData: InAppWebViewInitialData(data: widget.belge, baseUrl: WebUri('about:blank')),
              initialSettings: InAppWebViewSettings(javaScriptEnabled: false, blockNetworkLoads: true, cacheEnabled: false, isInspectable: false),
              onWebViewCreated: (c) => _c = c,
              onLoadStop: (_, _) {
                if (mounted) setState(() => _hazir = true);
              },
            ),
    );
  }
}
