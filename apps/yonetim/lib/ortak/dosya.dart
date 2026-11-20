import 'dart:async';
import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:open_filex/open_filex.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../oturum.dart';
import 'simgeler.dart';

// Dosya işlemleri: indirme (oturum çerezleriyle), mobilde paylaşım sayfası, masaüstünde İndirilenler/kaydetme
// penceresi ve ardından açma; dosya seçme; güvenli HTML önizleme; QR çizimi.

/// Flutter testinde mi (eklenti kanalları yoktur).
bool get _testte => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

bool get _mobil => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Seçilen dosya: ad ve içerik.
typedef SecilenDosya = ({String ad, Uint8List bayt});

/// Dosya seçici (testlerde değiştirilebilir).
Future<List<SecilenDosya>> Function({required String baslik, required List<String> uzantilar, bool coklu}) dosyaSecici = _dosyaSec;

Future<List<SecilenDosya>> _dosyaSec({required String baslik, required List<String> uzantilar, bool coklu = false}) async {
  final List<PlatformFile> l;
  if (coklu) {
    l = await FilePicker.pickFiles(dialogTitle: baslik, type: FileType.custom, allowedExtensions: uzantilar);
  } else {
    final f = await FilePicker.pickFile(dialogTitle: baslik, type: FileType.custom, allowedExtensions: uzantilar);
    l = [?f];
  }
  return [for (final f in l) (ad: f.name, bayt: await f.readAsBytes())];
}

/// Dosya seçtirir; hata olursa bildirir ve boş liste döner.
Future<List<SecilenDosya>> dosyaSec({required String baslik, required List<String> uzantilar, bool coklu = false}) async {
  try {
    return await dosyaSecici(baslik: baslik, uzantilar: uzantilar, coklu: coklu);
  } catch (_) {
    bildir('Dosya seçilemedi', mesaj: 'Dosya seçici açılamadı veya dosya okunamadı.', tur: MesajTur.hata);
    return const [];
  }
}

/// Hazır dosyanın kullanıcıya teslimi (testlerde değiştirilebilir).
Future<void> Function(File dosya, String ad, String? tur) dosyaTeslimci = _teslimEt;

/// Dosya indirmelerinin kaydedileceği klasör (masaüstü: İndirilenler; mobil: geçici klasör, ardından paylaşım).
Directory indirmeKlasoru() {
  if (_mobil || _testte) return Directory.systemTemp;
  final env = Platform.environment;
  final aday = switch (defaultTargetPlatform) {
    TargetPlatform.windows => env['USERPROFILE'] == null ? null : '${env['USERPROFILE']}\\Downloads',
    TargetPlatform.macOS || TargetPlatform.linux => env['HOME'] == null ? null : '${env['HOME']}/Downloads',
    _ => null,
  };
  if (aday != null && Directory(aday).existsSync()) return Directory(aday);
  return Directory.systemTemp;
}

/// Dosya adını güvenli hale getirir (yol ayırıcıları ve denetim karakterleri atılır).
String guvenliAd(String ad) {
  final t = ad.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return t.isEmpty ? 'dosya' : t;
}

String _benzersizYol(Directory d, String ad) {
  final s = Platform.pathSeparator;
  var yol = '${d.path}$s$ad';
  if (!File(yol).existsSync()) return yol;
  final nokta = ad.lastIndexOf('.');
  final kok = nokta > 0 ? ad.substring(0, nokta) : ad;
  final uz = nokta > 0 ? ad.substring(nokta) : '';
  for (var i = 1; i < 1000; i++) {
    yol = '${d.path}$s$kok ($i)$uz';
    if (!File(yol).existsSync()) return yol;
  }
  return '${d.path}$s$kok-${DateTime.now().millisecondsSinceEpoch}$uz';
}

Future<void> _teslimEt(File f, String ad, String? tur) async {
  final gezgin = kokGezgin.currentState;
  if (gezgin == null) return;
  if (_mobil) {
    // Mobil: paylaşım sayfası (Dosyalar'a kaydet, Drive, e-posta…) ya da doğrudan aç.
    await showDialog<void>(
      context: gezgin.context,
      builder: (c) => AlertDialog(
        icon: Icon(Simgeler.taskAlt, color: c.r.vurgu, size: 30),
        title: Text('Dosya hazır', style: gosterim(19, agirlik: FontWeight.w600)),
        content: Text('$ad (${boyutYaz(f.lengthSync())})\nKaydetmek veya göndermek için Paylaş\'ı kullanın.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat')),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              await dosyayiAc(f.path, tur: tur);
            },
            child: const Text('Aç'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(c);
              try {
                await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: tur, name: ad)], fileNameOverrides: [ad]));
              } catch (_) {
                bildir('Paylaşılamadı', tur: MesajTur.hata);
              }
            },
            icon: const Icon(Simgeler.iosShare, size: 18),
            label: const Text('Paylaş'),
          ),
        ],
      ),
    );
    return;
  }
  // Masaüstü: İndirilenler'e kaydedildi; aç veya klasörü göster.
  await showDialog<void>(
    context: gezgin.context,
    builder: (c) => AlertDialog(
      icon: Icon(Simgeler.downloadDone, color: c.r.vurgu, size: 30),
      title: Text('İndirildi', style: gosterim(19, agirlik: FontWeight.w600)),
      content: SelectableText('${f.path}\n${boyutYaz(f.lengthSync())}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat')),
        TextButton(
          onPressed: () {
            Navigator.pop(c);
            unawaited(launchUrl(Uri.directory(f.parent.path)));
          },
          child: const Text('Klasörü göster'),
        ),
        FilledButton.icon(
          onPressed: () async {
            Navigator.pop(c);
            await dosyayiAc(f.path, tur: tur);
          },
          icon: const Icon(Simgeler.openInNew, size: 18),
          label: const Text('Aç'),
        ),
      ],
    ),
  );
}

/// Dosyayı uygun uygulamayla açar.
Future<void> dosyayiAc(String yol, {String? tur}) async {
  try {
    final r = await OpenFilex.open(yol, type: tur);
    if (r.type == ResultType.noAppToOpen) {
      bildir('Dosya açılamadı', mesaj: 'Bu dosya türünü açacak bir uygulama bulunamadı.', tur: MesajTur.uyari);
    } else if (r.type != ResultType.done) {
      if (!_mobil && await launchUrl(Uri.file(yol))) return;
      bildir('Dosya açılamadı', mesaj: r.message, tur: MesajTur.uyari);
    }
  } catch (_) {
    bildir('Dosya açılamadı', tur: MesajTur.hata);
  }
}

/// Oturum çerezleriyle bir dosyayı indirir (ilerleme penceresiyle), sonra kullanıcıya teslim eder: mobilde
/// paylaş/aç, masaüstünde İndirilenler klasörüne kaydedip aç. Büyük dosyalar belleğe alınmadan diske yazılır.
Future<bool> dosyaIndir(String yol, String ad, {String baslik = 'İndiriliyor', Map<String, dynamic>? q, String? tur}) async {
  final gezgin = kokGezgin.currentState;
  if (gezgin == null) return false;
  final hedef = _benzersizYol(indirmeKlasoru(), guvenliAd(ad));
  final ilerleme = ValueNotifier<(int, int)>((0, -1));
  unawaited(showDialog<void>(
    context: gezgin.context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text(baslik, style: gosterim(19, agirlik: FontWeight.w600)),
      content: ValueListenableBuilder<(int, int)>(
        valueListenable: ilerleme,
        builder: (_, n, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: n.$2 > 0 ? n.$1 / n.$2 : null),
            const SizedBox(height: 12),
            Text(n.$2 > 0 ? '${boyutYaz(n.$1)} / ${boyutYaz(n.$2)}' : '${boyutYaz(n.$1)} indirildi', style: TextStyle(color: c.r.soluk)),
          ],
        ),
      ),
    ),
  ));
  String? hata;
  try {
    final c = await Uyg.api.dio.download(yol, hedef, queryParameters: q, onReceiveProgress: (a, t) => ilerleme.value = (a, t));
    final d = c.statusCode ?? 0;
    if (d >= 400) {
      hata = switch (d) {
        403 => 'Bu işlem için yetkiniz yok.',
        404 => 'Dosya bulunamadı.',
        410 => 'Dosyanın süresi dolmuş.',
        _ => 'İndirme başarısız (HTTP $d).',
      };
    }
  } catch (_) {
    hata = 'Dosya indirilemedi. Bağlantınızı ve depolama alanını kontrol edin.';
  }
  gezgin.pop();
  if (hata != null) {
    try {
      File(hedef).deleteSync();
    } catch (_) {}
    bildir('İndirilemedi', mesaj: hata, tur: MesajTur.hata);
    return false;
  }
  await dosyaTeslimci(File(hedef), guvenliAd(ad), tur);
  return true;
}

/// Bellekteki içeriği dosya olarak teslim eder (CSV, EML, BIND dışa aktarımı…).
Future<bool> baytlariKaydet(String ad, List<int> bayt, {String? tur}) async {
  try {
    final f = File(_benzersizYol(indirmeKlasoru(), guvenliAd(ad)));
    await f.writeAsBytes(bayt, flush: true);
    await dosyaTeslimci(f, guvenliAd(ad), tur);
    return true;
  } catch (_) {
    bildir('Dosya kaydedilemedi', tur: MesajTur.hata);
    return false;
  }
}

/// Bir API yolunu belleğe indirip dosya olarak teslim eder (küçük dosyalar için).
Future<bool> apiDosyasiKaydet(String yol, String ad, {Map<String, dynamic>? q, String? tur}) async {
  try {
    final b = await Uyg.api.indir(yol, q: q);
    return await baytlariKaydet(ad, b, tur: tur);
  } catch (e) {
    bildir('İndirilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    return false;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Güvenli HTML önizleme

/// Bu platformda gömülü web görünümü var mı (Android, iOS, macOS, Windows; testlerde yok).
bool get htmlGorunumuVar =>
    !kIsWeb && !_testte && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

const _csp = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; "
    "media-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'";

/// Güvenilmeyen HTML'i yalıtılmış bir belgeye sarar: betikler, yönlendirmeler ve gömülü çerçeveler atılır, CSP ile
/// tüm uzak içerik (görsel, stil, yazı tipi, bağlantı) engellenir.
String guvenliHtmlBelgesi(String html) {
  var g = html
      .replaceAll(RegExp(r'<script\b[\s\S]*?</script\s*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<(script|iframe|frame|frameset|object|embed|applet|base|link)\b[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</(iframe|frame|frameset|object|applet)\s*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<meta\b[^>]*http-equiv[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'\son[a-z]+\s*=\s*("[^"]*"|' "'[^']*'" r'|[^\s>]+)', caseSensitive: false), '');
  g = g.replaceAll(RegExp(r'javascript:', caseSensitive: false), 'blocked:');
  return '<!doctype html><html><head><meta charset="utf-8">'
      '<meta http-equiv="Content-Security-Policy" content="$_csp">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<style>html,body{margin:0;padding:8px;background:#fff;color:#111;font-family:-apple-system,Segoe UI,Roboto,sans-serif;word-wrap:break-word}img{max-width:100%;height:auto}</style>'
      '</head><body>$g</body></html>';
}

/// HTML içeriğini düz metne çevirir (web görünümü olmayan platformlar için).
String htmlDuzMetin(String html) => html
    .replaceAll(RegExp(r'<(script|style|head)\b[\s\S]*?</\1\s*>', caseSensitive: false), '')
    .replaceAll(RegExp(r'<br\s*/?>|</(p|div|tr|li|h[1-6])>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n')
    .trim();

/// Güvenilmeyen HTML'in önizlemesi: JavaScript kapalı, ağ erişimi ve uzak içerik engelli, dosya erişimi yok.
/// Bağlantılar yalnızca kullanıcı dokunursa dış tarayıcıda açılır. Web görünümü olmayan yerde düz metin gösterir.
class HtmlOnizleme extends StatelessWidget {
  const HtmlOnizleme({super.key, required this.html, this.yukseklik = 520});
  final String html;
  final double yukseklik;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final Widget icerik;
    if (!htmlGorunumuVar) {
      icerik = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(htmlDuzMetin(html), style: const TextStyle(color: Color(0xFF111111), height: 1.45)),
      );
    } else {
      icerik = InAppWebView(
        initialData: InAppWebViewInitialData(data: guvenliHtmlBelgesi(html), mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank')),
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
          allowsLinkPreview: false,
          isFraudulentWebsiteWarningEnabled: false,
          mediaPlaybackRequiresUserGesture: true,
          isInspectable: false,
          cacheEnabled: false,
          thirdPartyCookiesEnabled: false,
          incognito: true,
          transparentBackground: false,
        ),
        shouldOverrideUrlLoading: (c, a) async {
          final u = a.request.url;
          if (u == null || u.scheme == 'about' || u.scheme == 'data') return NavigationActionPolicy.ALLOW;
          if (a.isForMainFrame && a.navigationType == NavigationType.LINK_ACTIVATED && (u.scheme == 'http' || u.scheme == 'https')) {
            unawaited(launchUrl(Uri.parse(u.toString()), mode: LaunchMode.externalApplication));
          }
          return NavigationActionPolicy.CANCEL;
        },
        onCreateWindow: (c, a) async => false,
      );
    }
    return Container(
      height: yukseklik,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: r.kenar)),
      child: Semantics(label: 'HTML önizleme', child: icerik),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// QR kodu

/// Metni QR kodu olarak çizer (orta düzey hata düzeltme, beyaz zemin ve sessiz bölge ile).
class QrKodu extends StatelessWidget {
  const QrKodu(this.veri, {super.key, this.boyut = 200});
  final String veri;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    QrImage? img;
    try {
      img = QrImage(QrCode.fromData(data: veri, errorCorrectLevel: QrErrorCorrectLevel.M));
    } catch (_) {}
    if (img == null) return const SizedBox.shrink();
    return Semantics(
      image: true,
      label: 'QR kodu',
      child: Container(
        width: boyut,
        height: boyut,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: CustomPaint(painter: _QrBoyayici(img)),
      ),
    );
  }
}

class _QrBoyayici extends CustomPainter {
  _QrBoyayici(this.img);
  final QrImage img;

  @override
  void paint(Canvas canvas, Size size) {
    final n = img.moduleCount;
    final h = size.shortestSide / n;
    final p = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (img.isDark(y, x)) canvas.drawRect(Rect.fromLTWH(x * h, y * h, h + 0.3, h + 0.3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_QrBoyayici o) => o.img != img;
}
