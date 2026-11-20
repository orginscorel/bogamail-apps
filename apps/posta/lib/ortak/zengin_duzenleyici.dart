// Biçimli ileti düzenleyici. Webmail ile birebir aynı HTML'i üretmek için web'in yaptığını yapar: contenteditable bir
// alanda document.execCommand (styleWithCSS) ve gövde olarak innerHTML / innerText. Bu yüzden ayrı bir editör paketi
// (ör. flutter_quill: kendi Delta modeli, HTML'e dönüşümü web'in çıktısından farklı) yerine uygulamada zaten olan
// flutter_inappwebview kullanılır (iOS, macOS, Android, Windows). Araç çubuğu Flutter'dadır; komutlar web
// görünümüne gönderilir. Düzenleyici sayfası yerel bir belgedir: ağ erişimi kapalı, gezinme engelli.
// Web görünümü olmayan ortamlarda (testler, Linux) aynı arayüzü sağlayan bellek içi bir motor kullanılır.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as ayristir;

import '../veri/html_temizle.dart';
import '../veri/yardimci.dart';

/// Web'deki renkler ve yazı boyutları (compose.tsx TEXT_COLORS, HIGHLIGHT_COLORS, FONT_SIZES).
const yaziRenkleri = <(String, String)>[
  ('Siyah', '#111827'),
  ('Gri', '#6b7280'),
  ('Kırmızı', '#dc2626'),
  ('Turuncu', '#ea580c'),
  ('Sarı', '#ca8a04'),
  ('Yeşil', '#16a34a'),
  ('Mavi', '#2563eb'),
  ('Mor', '#7c3aed'),
  ('Pembe', '#db2777'),
];
const vurguRenkleri = <(String, String)>[
  ('Sarı', '#fef08a'),
  ('Yeşil', '#bbf7d0'),
  ('Mavi', '#bfdbfe'),
  ('Pembe', '#fbcfe8'),
  ('Turuncu', '#fed7aa'),
  ('Mor', '#e9d5ff'),
];
const yaziBoyutlari = <(String, String)>[('Küçük', '2'), ('Normal', '3'), ('Büyük', '5')];

/// Düz metni web'in textToHtml'i gibi HTML'e çevirir.
String metniHtmlYap(String s) => metindenHtml(s);

/// Düzenleyiciye girecek dış HTML'i (şablon, imza, alıntı, taslak) güvenli hale getirir.
String guvenliHtml(String html) => htmlTemizle(html, uzakKalsin: true).html;

/// Düzenleyici motoru: web görünümü ya da bellek içi.
abstract class DuzenleyiciMotoru {
  Future<void> komut(String ad, [String? deger]);
  Future<void> htmlEkle(String html);
  Future<void> baglantiEkle(String url, String metin);
  Future<({String html, String metin})> icerik();

  /// İmza bloğunu ([data-signature]) kaldırır; yoksa alıntıdan önce ekler (web toggleSignature ile birebir aynı).
  Future<void> imzaDegistir(String imzaHtml);
  Future<void> odakla();
}

/// Düzenleyicinin durumu: etkin biçimler (araç çubuğu vurgusu), boş mu, imza var mı. Değişince bildirir.
class ZenginDenetleyici extends ChangeNotifier {
  ZenginDenetleyici({required this.ilkHtml});

  final String ilkHtml;

  DuzenleyiciMotoru? _motor;
  Set<String> etkin = const {};
  bool bos = true;
  bool imzaVar = false;

  /// Kullanıcı içeriği değiştirdi (taslak kirli).
  VoidCallback? degisti;

  @visibleForTesting
  DuzenleyiciMotoru? get motor => _motor;

  void _bagla(DuzenleyiciMotoru m) => _motor = m;

  void _durum({Set<String>? etkin, bool? bos, bool? imzaVar, bool kullanici = false}) {
    var d = false;
    if (etkin != null && !setEquals(etkin, this.etkin)) {
      this.etkin = etkin;
      d = true;
    }
    if (bos != null && bos != this.bos) {
      this.bos = bos;
      d = true;
    }
    if (imzaVar != null && imzaVar != this.imzaVar) {
      this.imzaVar = imzaVar;
      d = true;
    }
    void bildirim() {
      if (kullanici) degisti?.call();
      if (d) notifyListeners();
    }

    // Düzenleyici kurulurken (build sırasında) dinleyiciler bir sonraki kareye ertelenir.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_atildi) bildirim();
      });
    } else {
      bildirim();
    }
  }

  bool _atildi = false;

  @override
  void dispose() {
    _atildi = true;
    super.dispose();
  }

  Future<void> komut(String ad, [String? deger]) async => _motor?.komut(ad, deger);
  Future<void> htmlEkle(String html) async => _motor?.htmlEkle(guvenliHtml(html));
  Future<void> baglantiEkle(String url, String metin) async => _motor?.baglantiEkle(url, metin);
  Future<void> imzaDegistir(String imzaHtml) async => _motor?.imzaDegistir(guvenliHtml(imzaHtml));
  Future<void> odakla() async => _motor?.odakla();

  /// Gönderilecek gövde: innerHTML ve innerText (nbsp → boşluk), web ile aynı.
  Future<({String html, String metin})> icerik() async => _motor?.icerik() ?? (html: ilkHtml, metin: htmlMetne(ilkHtml));
}

/// Bu platformda web görünümlü düzenleyici var mı.
bool get webDuzenleyiciDestekli => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows) && !_testOrtami;

bool get _testOrtami => Platform.environment.containsKey('FLUTTER_TEST');

/// Araç çubuğu + düzenleme alanı.
class ZenginDuzenleyici extends StatefulWidget {
  const ZenginDuzenleyici({super.key, required this.denetleyici, this.ipucu = 'İletinizi yazın', this.enAz = 260});
  final ZenginDenetleyici denetleyici;
  final String ipucu;
  final double enAz;

  @override
  State<ZenginDuzenleyici> createState() => _ZenginDuzenleyiciState();
}

class _ZenginDuzenleyiciState extends State<ZenginDuzenleyici> {
  ZenginDenetleyici get d => widget.denetleyici;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: d,
          builder: (_, _) => BicimCubugu(denetleyici: d),
        ),
        if (webDuzenleyiciDestekli)
          _WebDuzenleyici(denetleyici: d, ipucu: widget.ipucu, enAz: widget.enAz)
        else
          _BellekDuzenleyici(denetleyici: d, ipucu: widget.ipucu, enAz: widget.enAz),
      ],
    );
  }
}

/// Web'deki biçimlendirme çubuğu (aynı sıra, aynı Türkçe adlar).
class BicimCubugu extends StatelessWidget {
  const BicimCubugu({super.key, required this.denetleyici});
  final ZenginDenetleyici denetleyici;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = denetleyici;
    Widget dugme(String ad, IconData ikon, VoidCallback f, {String? durum}) {
      final acik = durum != null && d.etkin.contains(durum);
      return IconButton(
        key: ValueKey('bicim-$ad'),
        tooltip: ad,
        visualDensity: VisualDensity.compact,
        isSelected: acik,
        style: IconButton.styleFrom(backgroundColor: acik ? r.vurguYumusak : null),
        icon: Icon(ikon, size: 20, color: acik ? r.vurgu : r.soluk),
        onPressed: f,
      );
    }

    Widget ayrac() => Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 4), color: r.kenar);

    Widget renkSecici(String ad, IconData ikon, List<(String, String)> renkler, void Function(String) sec, {VoidCallback? temizle}) => PopupMenuButton<String>(
      key: ValueKey('bicim-$ad'),
      tooltip: ad,
      icon: Icon(ikon, size: 20, color: r.soluk),
      onSelected: (v) => v == '' ? temizle?.call() : sec(v),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (adi, deger) in renkler)
                Tooltip(
                  message: adi,
                  child: InkWell(
                    key: ValueKey('renk-$deger'),
                    customBorder: const CircleBorder(),
                    onTap: () {
                      Navigator.pop(context, deger);
                    },
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | int.parse(deger.substring(1), radix: 16)),
                        shape: BoxShape.circle,
                        border: Border.all(color: r.kenar),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (temizle != null) const PopupMenuItem<String>(value: '', child: Text('Vurguyu kaldır')),
      ],
    );

    return Material(
      color: r.kart,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: r.kenar)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            key: const ValueKey('bicimlendirme'),
            children: [
              dugme('Geri al (Ctrl+Z)', Simge.geriAl, () => d.komut('undo')),
              dugme('Yinele (Ctrl+Y)', Simge.yinele, () => d.komut('redo')),
              ayrac(),
              PopupMenuButton<String>(
                key: const ValueKey('bicim-Yazı boyutu'),
                tooltip: 'Yazı boyutu',
                icon: Icon(Simge.yaziBoyutu, size: 20, color: r.soluk),
                onSelected: (v) => d.komut('fontSize', v),
                itemBuilder: (_) => [
                  for (final (ad, v) in yaziBoyutlari)
                    PopupMenuItem(
                      value: v,
                      child: Text(ad, style: TextStyle(fontSize: v == '2' ? 12 : (v == '5' ? 19 : 15))),
                    ),
                ],
              ),
              dugme('Kalın (Ctrl+B)', Simge.kalin, () => d.komut('bold'), durum: 'bold'),
              dugme('İtalik (Ctrl+I)', Simge.italik, () => d.komut('italic'), durum: 'italic'),
              dugme('Altı çizili (Ctrl+U)', Simge.altiCizili, () => d.komut('underline'), durum: 'underline'),
              dugme('Üstü çizili', Simge.ustuCizili, () => d.komut('strikeThrough'), durum: 'strikeThrough'),
              renkSecici('Yazı rengi', Simge.yaziRengi, yaziRenkleri, (c) => d.komut('foreColor', c)),
              renkSecici(
                'Vurgu rengi',
                Simge.vurguRengi,
                vurguRenkleri,
                (c) => d.komut('hiliteColor', c),
                temizle: () => d.komut('hiliteColor', 'transparent'),
              ),
              ayrac(),
              dugme('Madde işaretli liste', Simge.maddeListe, () => d.komut('insertUnorderedList'), durum: 'insertUnorderedList'),
              dugme('Numaralı liste', Simge.numaraliListe, () => d.komut('insertOrderedList'), durum: 'insertOrderedList'),
              dugme('Girintiyi azalt', Simge.girintiAzalt, () => d.komut('outdent')),
              dugme('Girintiyi artır', Simge.girintiArtir, () => d.komut('indent')),
              ayrac(),
              dugme('Sola hizala', Simge.solaHizala, () => d.komut('justifyLeft'), durum: 'justifyLeft'),
              dugme('Ortala', Simge.ortala, () => d.komut('justifyCenter'), durum: 'justifyCenter'),
              dugme('Sağa hizala', Simge.sagaHizala, () => d.komut('justifyRight'), durum: 'justifyRight'),
              ayrac(),
              dugme('Alıntı', Simge.alinti, () => d.komut('formatBlock', d.etkin.contains('blockquote') ? 'div' : 'blockquote'), durum: 'blockquote'),
              dugme('Bağlantı ekle', Simge.baglanti, () => _baglanti(context)),
              dugme('Yatay çizgi', Simge.yatayCizgi, () => d.komut('insertHorizontalRule')),
              dugme('Biçimlendirmeyi temizle', Simge.bicimTemizle, () async {
                await d.komut('removeFormat');
                await d.komut('unlink');
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _baglanti(BuildContext context) async {
    final url = TextEditingController(text: 'https://');
    final metin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bağlantı ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('baglanti-adres'),
              controller: url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Adres'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('baglanti-metin'),
              controller: metin,
              decoration: const InputDecoration(labelText: 'Görünen metin (isteğe bağlı)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ekle')),
        ],
      ),
    );
    // Denetleyiciler iletişim kutusu kapanış animasyonu sürerken atılmaz; çöp toplayıcıya bırakılır.
    var u = url.text.trim();
    final m = metin.text.trim();
    if (ok != true || u.isEmpty || u == 'https://') return;
    // Yalnız güvenli şemalar (web ile aynı: http(s), mailto, tel).
    if (!RegExp(r'^(https?:|mailto:|tel:)', caseSensitive: false).hasMatch(u)) u = u.contains('@') && !u.contains('/') ? 'mailto:$u' : 'https://$u';
    await denetleyici.baglantiEkle(u, m);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Web görünümü motoru

const _js = r'''
const e = document.getElementById('e');
let r = null;
const STATE = ["bold","italic","underline","strikeThrough","insertUnorderedList","insertOrderedList","justifyLeft","justifyCenter","justifyRight"];
const DROP = "script,style,iframe,frame,frameset,object,embed,form,input,button,select,textarea,link,meta,base,svg,math";
function send(n, v) { try { window.flutter_inappwebview.callHandler(n, v); } catch (_) {} }
function clean(h) {
  const d = new DOMParser().parseFromString(h, 'text/html');
  d.body.querySelectorAll(DROP).forEach(n => n.remove());
  d.body.querySelectorAll('*').forEach(el => {
    for (const a of Array.from(el.attributes)) {
      const n = a.name.toLowerCase(), v = a.value.trim().toLowerCase();
      if (n.startsWith('on') || n === 'srcdoc' || ((n === 'href' || n === 'src' || n === 'action' || n === 'xlink:href') && /^(javascript|vbscript|data:text)/.test(v)) || (n === 'style' && /(url\(|expression|@import)/.test(v))) el.removeAttribute(a.name);
    }
  });
  return d.body.innerHTML;
}
function save() { const s = getSelection(); if (s.rangeCount && e.contains(s.getRangeAt(0).commonAncestorContainer)) r = s.getRangeAt(0).cloneRange(); }
function restore() {
  e.focus();
  const s = getSelection();
  if (r && e.contains(r.commonAncestorContainer)) { s.removeAllRanges(); s.addRange(r); }
  else if (!s.rangeCount || !e.contains(s.getRangeAt(0).commonAncestorContainer)) { const x = document.createRange(); x.setStart(e, 0); x.collapse(true); s.removeAllRanges(); s.addRange(x); }
}
function empty() { const c = e.cloneNode(true); c.querySelectorAll('[data-signature]').forEach(n => n.remove()); return (c.textContent || '').trim() === '' && !c.querySelector('img'); }
function state() {
  const on = STATE.filter(c => { try { return document.queryCommandState(c); } catch (_) { return false; } });
  let b = ''; try { b = String(document.queryCommandValue('formatBlock') || '').toLowerCase(); } catch (_) {}
  if (b === 'blockquote') on.push('blockquote');
  send('durum', { etkin: on.join(' '), bos: empty(), imza: !!e.querySelector('[data-signature]') });
}
function changed(user) { send('degisti', { h: Math.ceil(e.getBoundingClientRect().height), kullanici: !!user }); state(); }
window.bm = {
  exec(c, v) { restore(); try { document.execCommand('styleWithCSS', false, 'true'); } catch (_) {} document.execCommand(c, false, v == null ? null : v); save(); changed(true); },
  insertHtml(h) { restore(); document.execCommand('insertHTML', false, clean(h)); save(); changed(true); },
  link(u, t) {
    restore();
    const s = getSelection();
    if (!s || s.isCollapsed) { const a = document.createElement('a'); a.href = u; a.textContent = t || u; document.execCommand('insertHTML', false, a.outerHTML); }
    else document.execCommand('createLink', false, u);
    save(); changed(true);
  },
  sig(h) {
    const x = e.querySelector('[data-signature]');
    if (x) { x.remove(); changed(true); return; }
    const b = document.createElement('div'); b.setAttribute('data-signature', ''); b.innerHTML = clean(h);
    const q = Array.from(e.children).find(c => c.localName === 'blockquote' || c.querySelector('blockquote'));
    e.insertBefore(b, q || null);
    changed(true);
  },
  get() { return JSON.stringify({ h: e.innerHTML, t: e.innerText.replace(/ /g, ' ') }); },
  focus() { restore(); },
};
e.addEventListener('input', () => { save(); changed(true); });
e.addEventListener('keyup', save); e.addEventListener('mouseup', save);
document.addEventListener('selectionchange', () => { save(); state(); });
e.addEventListener('paste', ev => {
  const cd = ev.clipboardData; if (!cd) return;
  const h = cd.getData('text/html');
  if (h) { ev.preventDefault(); document.execCommand('insertHTML', false, clean(h)); changed(true); return; }
  const t = cd.getData('text/plain');
  if (t) { ev.preventDefault(); document.execCommand('insertText', false, t); changed(true); }
});
e.addEventListener('drop', ev => { if (Array.from(ev.dataTransfer.types).includes('Files')) ev.preventDefault(); });
new ResizeObserver(() => changed(false)).observe(e);
e.innerHTML = clean(INIT);
changed(false);
''';

String _belge(String ilk, Renkler r, String ipucu) {
  String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  final init = jsonEncode(ilk).replaceAll('</', r'<\/');
  return '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
<style>
html,body{margin:0;padding:0;background:${hex(r.kart)};color:${hex(r.metin)};font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
#e{min-height:200px;padding:10px 16px 16px;outline:none;overflow-wrap:break-word}
#e:empty:before{content:attr(data-ph);color:${hex(r.silik)}}
#e a{color:${hex(r.vurgu)};text-decoration:underline}
#e blockquote{margin:8px 0;border-left:4px solid ${hex(r.kenar)};padding-left:12px;color:${hex(r.soluk)}}
#e hr{margin:12px 0;border:0;border-top:1px solid ${hex(r.kenar)}}
#e img{max-width:100%}#e ol{list-style:decimal;padding-left:24px}#e ul{list-style:disc;padding-left:24px}#e table{max-width:100%}
#e [data-signature]{color:${hex(r.soluk)}}
</style></head><body><div id="e" contenteditable="true" role="textbox" aria-multiline="true" aria-label="İleti metni" spellcheck="true" data-ph="${htmlKacis(ipucu)}"></div>
<script>const INIT = $init;
$_js</script></body></html>''';
}

class _WebMotoru implements DuzenleyiciMotoru {
  _WebMotoru(this.k);
  final InAppWebViewController k;

  Future<void> _calistir(String js) async {
    try {
      await k.evaluateJavascript(source: js);
    } catch (_) {}
  }

  @override
  Future<void> komut(String ad, [String? deger]) => _calistir('bm.exec(${jsonEncode(ad)}, ${jsonEncode(deger)})');
  @override
  Future<void> htmlEkle(String html) => _calistir('bm.insertHtml(${jsonEncode(html)})');
  @override
  Future<void> baglantiEkle(String url, String metin) => _calistir('bm.link(${jsonEncode(url)}, ${jsonEncode(metin)})');
  @override
  Future<void> imzaDegistir(String imzaHtml) => _calistir('bm.sig(${jsonEncode(imzaHtml)})');
  @override
  Future<void> odakla() => _calistir('bm.focus()');
  @override
  Future<({String html, String metin})> icerik() async {
    final v = await k.evaluateJavascript(source: 'bm.get()');
    final m = v is String ? jsonDecode(v) : v;
    if (m is Map) return (html: '${m['h'] ?? ''}', metin: '${m['t'] ?? ''}');
    return (html: '', metin: '');
  }
}

class _WebDuzenleyici extends StatefulWidget {
  const _WebDuzenleyici({required this.denetleyici, required this.ipucu, required this.enAz});
  final ZenginDenetleyici denetleyici;
  final String ipucu;
  final double enAz;
  @override
  State<_WebDuzenleyici> createState() => _WebDuzenleyiciState();
}

class _WebDuzenleyiciState extends State<_WebDuzenleyici> {
  late double _yukseklik = widget.enAz;
  String? _belgeMetni;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final belge = _belgeMetni ??= _belge(widget.denetleyici.ilkHtml, r, widget.ipucu);
    return SizedBox(
      height: _yukseklik,
      child: InAppWebView(
        initialData: InAppWebViewInitialData(data: belge, mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank')),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: false,
          useShouldOverrideUrlLoading: true,
          blockNetworkLoads: true,
          allowFileAccess: false,
          allowContentAccess: false,
          allowFileAccessFromFileURLs: false,
          allowUniversalAccessFromFileURLs: false,
          supportZoom: false,
          disableVerticalScroll: true,
          disableHorizontalScroll: true,
          isInspectable: false,
          transparentBackground: true,
          cacheEnabled: false,
          thirdPartyCookiesEnabled: false,
          allowsLinkPreview: false,
        ),
        shouldOverrideUrlLoading: (c, a) async {
          final s = a.request.url?.scheme.toLowerCase() ?? '';
          return s == 'about' || s == 'data' ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL;
        },
        onCreateWindow: (c, a) async => false,
        onWebViewCreated: (c) {
          widget.denetleyici._bagla(_WebMotoru(c));
          c.addJavaScriptHandler(
            handlerName: 'degisti',
            callback: (a) {
              final m = a.isNotEmpty && a.first is Map ? a.first as Map : const {};
              final h = (m['h'] as num?)?.toDouble();
              if (h != null && mounted) {
                final y = h + 8 < widget.enAz ? widget.enAz : h + 8;
                if ((y - _yukseklik).abs() > 1) setState(() => _yukseklik = y);
              }
              if (m['kullanici'] == true) widget.denetleyici._durum(kullanici: true);
              return null;
            },
          );
          c.addJavaScriptHandler(
            handlerName: 'durum',
            callback: (a) {
              final m = a.isNotEmpty && a.first is Map ? a.first as Map : const {};
              widget.denetleyici._durum(
                etkin: '${m['etkin'] ?? ''}'.split(' ').where((x) => x.isNotEmpty).toSet(),
                bos: m['bos'] == true,
                imzaVar: m['imza'] == true,
              );
              return null;
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Bellek motoru (web görünümü olmayan ortamlar ve testler): aynı HTML yapısını package:html ile kurar. Kullanıcı
// metni ilk bloğa düz metin olarak yazılır; komutlar kaydedilir.

class BellekMotoru implements DuzenleyiciMotoru {
  BellekMotoru(String ilkHtml, this._d) {
    final b = ayristir.parseFragment(guvenliHtml(ilkHtml));
    _govde = dom.Element.tag('div')..nodes.addAll(b.nodes.toList());
    final ilk = _govde.children.isNotEmpty ? _govde.children.first : null;
    if (ilk != null && ilk.localName == 'div' && !ilk.attributes.containsKey('data-signature') && ilk.innerHtml == '<br>') {
      _yazi = ilk;
    } else if (ilk != null && ilk.localName == 'div' && !ilk.attributes.containsKey('data-signature') && ilk.querySelector('blockquote') == null) {
      _yazi = ilk;
      metin = htmlMetne(ilk.outerHtml);
    } else {
      _yazi = dom.Element.tag('div')..innerHtml = '<br>';
      _govde.nodes.insert(0, _yazi);
    }
    _guncelle(kullanici: false);
  }

  final ZenginDenetleyici _d;
  late final dom.Element _govde;
  late dom.Element _yazi;
  String metin = '';

  /// Testler için: uygulanan komutlar.
  final komutlar = <(String, String?)>[];

  void metinYaz(String s) {
    metin = s;
    _yazi.innerHtml = s.isEmpty ? '<br>' : metindenHtml(s);
    _guncelle(kullanici: true);
  }

  void _guncelle({required bool kullanici}) {
    final c = _govde.clone(true);
    for (final x in c.querySelectorAll('[data-signature]')) {
      x.remove();
    }
    _d._durum(bos: c.text.trim().isEmpty && c.querySelector('img') == null, imzaVar: _govde.querySelector('[data-signature]') != null, kullanici: kullanici);
  }

  @override
  Future<void> komut(String ad, [String? deger]) async {
    komutlar.add((ad, deger));
    _guncelle(kullanici: true);
  }

  @override
  Future<void> htmlEkle(String html) async {
    final f = ayristir.parseFragment(html);
    final i = _govde.nodes.indexOf(_yazi) + 1;
    _govde.nodes.insertAll(i, f.nodes.toList());
    _guncelle(kullanici: true);
  }

  @override
  Future<void> baglantiEkle(String url, String metin) async {
    final a = dom.Element.tag('a')
      ..attributes['href'] = url
      ..text = metin.isEmpty ? url : metin;
    _yazi.append(a);
    _guncelle(kullanici: true);
  }

  @override
  Future<void> imzaDegistir(String imzaHtml) async {
    final x = _govde.querySelector('[data-signature]');
    if (x != null) {
      x.remove();
    } else {
      final b = dom.Element.tag('div')
        ..attributes['data-signature'] = ''
        ..innerHtml = imzaHtml;
      final q = _govde.children.where((c) => c.localName == 'blockquote' || c.querySelector('blockquote') != null).firstOrNull;
      if (q == null) {
        _govde.append(b);
      } else {
        _govde.insertBefore(b, q);
      }
    }
    _guncelle(kullanici: true);
  }

  @override
  Future<void> odakla() async {}

  @override
  Future<({String html, String metin})> icerik() async => (html: _govde.innerHtml, metin: htmlMetne(_govde.innerHtml));
}

class _BellekDuzenleyici extends StatefulWidget {
  const _BellekDuzenleyici({required this.denetleyici, required this.ipucu, required this.enAz});
  final ZenginDenetleyici denetleyici;
  final String ipucu;
  final double enAz;
  @override
  State<_BellekDuzenleyici> createState() => _BellekDuzenleyiciState();
}

class _BellekDuzenleyiciState extends State<_BellekDuzenleyici> {
  late final BellekMotoru _m = BellekMotoru(widget.denetleyici.ilkHtml, widget.denetleyici);
  late final _metin = TextEditingController(text: _m.metin);

  @override
  void initState() {
    super.initState();
    widget.denetleyici._bagla(_m);
  }

  @override
  void dispose() {
    _metin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.enAz),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(
          key: const ValueKey('zengin-metin'),
          controller: _metin,
          minLines: 8,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          onChanged: _m.metinYaz,
          decoration: InputDecoration(
            hintText: widget.ipucu,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
