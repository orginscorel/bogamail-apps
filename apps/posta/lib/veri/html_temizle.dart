// Güvenilmeyen e-posta HTML'ini gösterime hazırlar (web lib/mail-html.ts ile aynı kurallar). Görüntüleyicide
// JavaScript kapalıdır ve CSP tüm ağ yüklemelerini engeller; burada da uzak kaynaklar ayıklanır (derinlemesine savunma).

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as ayristir;

import 'yardimci.dart';

const _atilanEtiketler = [
  'script',
  'noscript',
  'iframe',
  'frame',
  'frameset',
  'object',
  'embed',
  'applet',
  'link',
  'meta',
  'base',
  'form',
  'template',
  'portal',
  'audio',
  'video',
  'source',
  'track',
  'svg',
  'math',
];
const _urlNitelikleri = ['src', 'srcset', 'background', 'poster', 'data', 'action', 'formaction', 'lowsrc', 'dynsrc', 'xlink:href'];

bool _yerel(String u) => RegExp(r'^\s*(data:image/|cid:)', caseSensitive: false).hasMatch(u);
final _uzakGorsel = RegExp(r'^\s*(https?:)?//', caseSensitive: false);

/// İleti başına en fazla bu kadar uzak görsel yüklenir.
const uzakGorselSiniri = 80;

class TemizHtml {
  const TemizHtml(this.html, this.engellenen);
  final String html;

  /// Engellenen uzak kaynak sayısı (> 0 ise "Görselleri göster" çubuğu gösterilir).
  final int engellenen;
}

/// İletideki uzak görsel adresleri (img src, background), belge sırasıyla, tekrarsız.
List<String> uzakGorseller(String ham) {
  final belge = ayristir.parse(ham);
  final out = <String>{};
  for (final el in belge.querySelectorAll('img[src], [background]')) {
    final v = (el.localName == 'img' ? el.attributes['src'] : el.attributes['background'])?.trim() ?? '';
    if (_uzakGorsel.hasMatch(v) && out.length < uzakGorselSiniri) out.add(v);
  }
  return out.toList();
}

/// HTML'i temizler. [baglantilar]: özgün bağlantı → imzalı tıklama adresi. [uzak]: uzak görsel → data: adresi
/// (sunucu vekili üzerinden alınmış). [cid]: içerik kimliği (küçük harf) → data: adresi.
/// [uzakKalsin]: http(s) görsel adresleri korunur (yalnızca giden imza için; alıcının istemcisi karar verir).
TemizHtml htmlTemizle(
  String ham, {
  Map<String, String>? baglantilar,
  Map<String, String>? uzak,
  Map<String, String>? cid,
  String? kok,
  bool uzakKalsin = false,
}) {
  final belge = ayristir.parse(ham);
  var engellenen = 0;
  for (final e in belge.querySelectorAll(_atilanEtiketler.join(','))) {
    e.remove();
  }
  for (final el in belge.querySelectorAll('*')) {
    for (final anahtar in el.attributes.keys.toList()) {
      final ad = '$anahtar'.toLowerCase();
      final deger = el.attributes[anahtar] ?? '';
      if (ad.startsWith('on')) {
        el.attributes.remove(anahtar);
      } else if (_urlNitelikleri.contains(ad)) {
        final v = deger.trim();
        final vekil = (ad == 'src' || ad == 'background') ? (uzak == null ? null : uzak[v]) : null;
        if (vekil != null) {
          el.attributes[anahtar] = vekil;
        } else if (ad == 'srcset') {
          el.attributes.remove(anahtar);
        } else if (v.toLowerCase().startsWith('cid:')) {
          final c = cid?[v.substring(4).trim().replaceAll(RegExp(r'^<|>$'), '').toLowerCase()];
          if (c != null) {
            el.attributes[anahtar] = c;
          } else {
            el.attributes.remove(anahtar);
          }
        } else if (uzakKalsin && (ad == 'src' || ad == 'background') && RegExp(r'^https?://', caseSensitive: false).hasMatch(v)) {
          // korunur
        } else if (!_yerel(v)) {
          el.attributes.remove(anahtar);
          engellenen++;
        }
      } else if (ad == 'href') {
        final v = deger.trim();
        if (!RegExp(r'^(https?:|mailto:|#)', caseSensitive: false).hasMatch(v)) {
          el.attributes.remove(anahtar);
        } else {
          final korunan = baglantilar?[v];
          if (korunan != null && korunan.isNotEmpty) {
            el.attributes[anahtar] = korunan.startsWith('/') && kok != null ? '$kok$korunan' : korunan;
          }
        }
      } else if (ad == 'style' && RegExp(r'url\s*\(|expression\s*\(|@import', caseSensitive: false).hasMatch(deger)) {
        el.attributes.remove(anahtar);
        engellenen++;
      }
    }
  }
  for (final st in belge.querySelectorAll('style')) {
    final css = st.text;
    if (RegExp(r'url\s*\(|@import|expression\s*\(', caseSensitive: false).hasMatch(css)) {
      st.text = css
          .replaceAll(RegExp(r'@import[^;]*;?', caseSensitive: false), '')
          .replaceAll(RegExp(r'url\s*\([^)]*\)', caseSensitive: false), 'none')
          .replaceAll(RegExp(r'expression\s*\(', caseSensitive: false), 'x(');
      engellenen++;
    }
  }
  final bas = belge.head?.querySelectorAll('style').map((s) => s.outerHtml).join() ?? '';
  return TemizHtml(bas + (belge.body?.innerHtml ?? ''), engellenen);
}

const _alintiSecicileri = [
  '.gmail_quote_container',
  'div.gmail_quote',
  'blockquote.gmail_quote',
  '.yahoo_quoted',
  '#mail-editor-reference-message-container',
  'div[data-quote]',
  'blockquote[type=cite]',
  '.moz-cite-prefix',
  '#divRplyFwdMsg',
  '#appendonsend',
  'div.OutlookMessageHeader',
];

String _gorunurMetin(dom.Node n) => (n.text ?? '').replaceAll(RegExp('[\\s ​]+'), '');

/// Alıntılanmış geçmişi "•••" düğmeli `<details>` içine katlar (betik gerektirmez).
String alintilariKatla(String html) {
  final belge = ayristir.parse(html);
  final govde = belge.body;
  if (govde == null) return html;
  final ilk = govde.querySelector(_alintiSecicileri.join(','));
  if (ilk == null || ilk.parent == null) return html;
  dom.Element bas = ilk;
  final outlook =
      ilk.classes.contains('moz-cite-prefix') || ilk.id == 'divRplyFwdMsg' || ilk.id == 'appendonsend' || ilk.classes.contains('OutlookMessageHeader');
  if (outlook) {
    final once = ilk.previousElementSibling;
    if (once != null && once.localName == 'hr') bas = once;
  }
  final ebeveyn = bas.parent!;
  final dugumler = <dom.Node>[];
  final i = ebeveyn.nodes.indexOf(bas);
  dugumler.addAll(ebeveyn.nodes.sublist(i));
  final ayrinti = dom.Element.tag('details')..classes.add('bm-quote');
  final ozet = dom.Element.tag('summary')
    ..attributes['title'] = 'Önceki iletileri göster/gizle'
    ..text = '•••';
  ayrinti.append(ozet);
  ebeveyn.insertBefore(ayrinti, bas);
  for (final n in dugumler) {
    n.remove();
    ayrinti.append(n);
  }
  final kopya = govde.clone(true);
  kopya.querySelector('details.bm-quote')?.remove();
  if (_gorunurMetin(kopya).isEmpty) return html;
  return govde.innerHtml;
}

const alintiCss =
    'details.bm-quote{margin:12px 0 0}details.bm-quote>summary{display:inline-block;list-style:none;cursor:pointer;user-select:none;'
    'padding:0 8px;border-radius:6px;background:#eceef1;color:#57606a;font:bold 12px/18px system-ui;letter-spacing:1px}'
    'details.bm-quote>summary::-webkit-details-marker{display:none}details.bm-quote[open]>summary{margin-bottom:8px}';

/// Görüntüleyiciye verilecek tam belge: CSP yalnızca satır içi stil ve data: görsellere izin verir.
String gorunumBelgesi(String govde) =>
    '<!doctype html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">'
    '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; img-src data:; font-src data:">'
    '<style>html,body{margin:0;font:15px/1.6 -apple-system,system-ui,"Segoe UI",Roboto,sans-serif;color:#1f2328;background:#fff;'
    'word-wrap:break-word;overflow-wrap:anywhere;color-scheme:light}body{padding:14px 16px 28px;display:flow-root}'
    'img{max-width:100%;height:auto}table{max-width:100%}pre{white-space:pre-wrap}a{color:#4f46e5}'
    'blockquote{margin:0 0 0 .8ex;border-left:2px solid #d0d7de;padding-left:1ex;color:#57606a}$alintiCss</style>'
    '</head><body>$govde</body></html>';

const _blokEtiketler = {'p', 'div', 'br', 'li', 'tr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre', 'table', 'ul', 'ol', 'hr', 'section', 'article'};

/// HTML → okunur düz metin (taslakları ve imzayı düz metin düzenleyiciye aktarmak için).
String htmlMetne(String html) {
  final belge = ayristir.parse(html);
  for (final s in belge.querySelectorAll('style,script,head,title')) {
    s.remove();
  }
  final b = StringBuffer();
  void gez(dom.Node n) {
    if (n is dom.Text) {
      b.write(n.text.replaceAll(RegExp(r'[ \t\r\n]+'), ' '));
      return;
    }
    if (n is dom.Element) {
      final ad = n.localName ?? '';
      if (ad == 'br') {
        b.write('\n');
        return;
      }
      if (ad == 'li') b.write('\n• ');
      for (final c in n.nodes) {
        gez(c);
      }
      if (ad == 'a') {
        final href = n.attributes['href'] ?? '';
        if (href.startsWith('http') && href != n.text.trim()) b.write(' <$href>');
      }
      // Liste öğesi kendi satırını açar; sonuna ayrıca satır eklenmez (maddeler arasında boş satır olmasın).
      if (_blokEtiketler.contains(ad) && ad != 'li') b.write('\n');
      return;
    }
    for (final c in n.nodes) {
      gez(c);
    }
  }

  final govde = belge.body;
  if (govde != null) gez(govde);
  return b
      .toString()
      .replaceAll(' ', ' ')
      .split('\n')
      .map((l) => l.trimRight().replaceAll(RegExp(r'^ +'), ''))
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Yanıt/iletme alıntısının HTML bloğu (web'deki quoteHtml ile aynı biçim).
String alintiHtml(String giris, {required String html, required String metin}) {
  final govde = html.trim().isNotEmpty ? htmlTemizle(html).html : metindenHtml(metin);
  return '<div data-quote><p style="color:#666">${htmlKacis(giris)}</p>'
      '<blockquote style="margin:0 0 0 .8ex;border-left:2px solid #c7c7d1;padding-left:1ex">$govde</blockquote></div>';
}

/// İletme başlığı + özgün gövde.
String iletmeHtml(String baslik, {required String html, required String metin}) {
  final govde = html.trim().isNotEmpty ? htmlTemizle(html).html : metindenHtml(metin);
  return '<div data-quote><p>${metindenHtml(baslik)}</p>$govde</div>';
}
