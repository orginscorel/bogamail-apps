// Yanıt / tümünü yanıtla / ilet / taslak için yazma penceresinin başlangıç durumu ve gönderilecek gövde.
// Web'deki reader.tsx (reply, forward, editDraft) ve compose.tsx (buildInitialBody, imza) ile aynı davranış.

import 'package:intl/intl.dart';

import 'html_temizle.dart';
import 'modeller.dart';
import 'yardimci.dart';

/// Başka bir iletiden eklenecek ek (include_parts).
class DahilEk {
  const DahilEk({required this.iletiId, required this.sira, required this.ad, required this.tur, required this.boyut});
  final String iletiId;
  final int sira;
  final String ad;
  final String tur;
  final int boyut;

  Map<String, dynamic> get json => {'message_id': iletiId, 'index': sira};
}

enum YazmaTuru { yeni, yanit, tumuneYanit, ilet, taslak }

class YazmaBaslangic {
  YazmaBaslangic({
    this.tur = YazmaTuru.yeni,
    this.kime = const [],
    this.bilgi = const [],
    this.gizli = const [],
    this.konu = '',
    this.metin = '',
    this.alintiHtml,
    this.alintiMetin,
    this.inReplyTo,
    this.references,
    this.yanitlananId,
    this.iletilenId,
    this.taslakId,
    this.dahilEkler = const [],
    this.imzaEkle = true,
    this.htmlTaslak = false,
    this.htmlGovde,
    this.oncelik,
    this.okunduBilgisi = false,
    this.takipGun = 0,
    this.gidenId,
    this.yerelEkler = const [],
  });

  /// Giden Kutusu'ndaki bir iletinin düzenlenmesi: gönderilince / yeniden kuyruğa alınınca bu öğenin yerine geçer.
  final String? gidenId;

  /// Giden Kutusu'nda saklanan yerel ekler (ad, base64 içerik).
  final List<(String, String)> yerelEkler;

  final YazmaTuru tur;
  final List<Adres> kime;
  final List<Adres> bilgi;
  final List<Adres> gizli;
  final String konu;

  /// Düzenlenebilir gövde metni.
  final String metin;

  /// Yanıt/iletmede özgün iletinin alıntısı (gövdenin altına eklenir, düzenlenmez).
  final String? alintiHtml;
  final String? alintiMetin;
  final String? inReplyTo;
  final String? references;
  final String? yanitlananId;
  final String? iletilenId;
  final String? taslakId;
  final List<DahilEk> dahilEkler;
  final bool imzaEkle;

  /// Taslak HTML biçimliydi: düz metin düzenleyicide biçimlendirme kaybolur (kullanıcıya bildirilir).
  final bool htmlTaslak;

  /// Biçimli taslağın HTML gövdesi (düzenleyici bununla açılır).
  final String? htmlGovde;

  /// Geri alınan gönderimden korunan seçenekler.
  final String? oncelik;
  final bool okunduBilgisi;
  final int takipGun;

  String get baslik => switch (tur) {
    YazmaTuru.yeni => 'Yeni ileti',
    YazmaTuru.yanit => 'Yanıtla',
    YazmaTuru.tumuneYanit => 'Tümünü yanıtla',
    YazmaTuru.ilet => 'İlet',
    YazmaTuru.taslak => 'Taslak',
  };
}

String _adresler(List<Adres> l) => l.map(adresYaz).join(', ');

List<DahilEk> _ekler(IletiDetay d, String iletiId) =>
    d.gorunum.dosyaEkleri.map((a) => DahilEk(iletiId: iletiId, sira: a.sira, ad: a.ad, tur: a.tur, boyut: a.boyut)).toList();

String _ozgunMetin(IletiGorunum v) => v.metin.trim().isNotEmpty ? v.metin : htmlMetne(v.html);

/// Yanıt / tümünü yanıtla.
YazmaBaslangic yanitHazirla(IletiDetay d, {required String ben, required bool tumu}) {
  final v = d.gorunum;
  final a = yanitAlicilari(kimden: v.kimden, yanitAdresi: v.yanitAdresi, kime: v.kime, bilgi: v.bilgi, ben: ben, tumu: tumu);
  final kimden = _adresler(v.kimden).isNotEmpty ? _adresler(v.kimden) : d.ozet.kimden;
  final giris = alintiGirisi(v.tarih ?? d.ozet.tarih, kimden);
  final mid = v.mesajKimligi.trim();
  return YazmaBaslangic(
    tur: tumu ? YazmaTuru.tumuneYanit : YazmaTuru.yanit,
    kime: a.kime,
    bilgi: a.bilgi,
    konu: onekli('Re', v.konu),
    alintiHtml: alintiHtml(giris, html: v.html, metin: v.metin),
    alintiMetin: '$giris\n${alintila(_ozgunMetin(v))}',
    inReplyTo: mid.isEmpty ? null : mid,
    references: mid.isEmpty ? null : mid,
    yanitlananId: d.ozet.id,
  );
}

/// İletme başlığı ("---------- İletilen ileti ----------").
String iletmeBasligi(IletiDetay d) {
  final v = d.gorunum;
  final t = v.tarih ?? d.ozet.tarih;
  final satirlar = [
    '---------- İletilen ileti ----------',
    'Kimden: ${_adresler(v.kimden).isNotEmpty ? _adresler(v.kimden) : d.ozet.kimden}',
    if (t != null) 'Tarih: ${DateFormat('d MMMM y HH:mm', 'tr_TR').format(t)}',
    'Konu: ${v.konu}',
    'Kime: ${_adresler(v.kime)}',
    if (v.bilgi.isNotEmpty) 'Bilgi: ${_adresler(v.bilgi)}',
  ];
  return satirlar.join('\n');
}

YazmaBaslangic iletHazirla(IletiDetay d) {
  final v = d.gorunum;
  final baslik = iletmeBasligi(d);
  return YazmaBaslangic(
    tur: YazmaTuru.ilet,
    konu: onekli('Fwd', v.konu),
    alintiHtml: iletmeHtml(baslik, html: v.html, metin: v.metin),
    alintiMetin: '$baslik\n\n${_ozgunMetin(v)}',
    iletilenId: d.ozet.id,
    dahilEkler: _ekler(d, d.ozet.id),
  );
}

/// Taslaklar klasöründeki iletiyi düzenlemeye açar (imza ve alıntı zaten taslağın içinde).
YazmaBaslangic taslakHazirla(IletiDetay d, {String? taslakId, Map<String, dynamic>? geriAlinan}) {
  final v = d.gorunum;
  final c = geriAlinan ?? const <String, dynamic>{};
  String? s(String k) => '${c[k] ?? ''}'.isEmpty ? null : '${c[k]}';
  final oncelik = s('priority');
  return YazmaBaslangic(
    tur: YazmaTuru.taslak,
    kime: v.kime,
    bilgi: v.bilgi,
    konu: v.konu,
    metin: v.metin.trim().isNotEmpty ? v.metin.trimRight() : htmlMetne(v.html),
    taslakId: taslakId ?? d.ozet.id,
    dahilEkler: _ekler(d, d.ozet.id),
    imzaEkle: false,
    htmlTaslak: v.html.trim().isNotEmpty,
    htmlGovde: v.html.trim().isNotEmpty ? v.html : null,
    inReplyTo: s('in_reply_to'),
    references: s('references'),
    yanitlananId: s('reply_to_id'),
    iletilenId: s('forward_of_id'),
    oncelik: oncelik == 'high' || oncelik == 'low' ? oncelik : null,
    okunduBilgisi: c['read_receipt'] == true,
    takipGun: c['followup_days'] is num ? (c['followup_days'] as num).toInt() : 0,
  );
}

/// Gönderilecek düz metin + HTML gövde.
({String metin, String html}) govdeOlustur({required String metin, String? imzaHtml, String? alintiHtml, String? alintiMetin}) {
  final imza = (imzaHtml ?? '').trim();
  final imzaMetin = imza.isEmpty ? '' : htmlMetne(imza);
  final m = StringBuffer(metin.trimRight());
  final h = StringBuffer('<div>${metin.trimRight().isEmpty ? '<br>' : metindenHtml(metin.trimRight())}</div>');
  if (imza.isNotEmpty) {
    m.write('\n\n-- \n$imzaMetin');
    h.write('<div><br></div><div data-signature="">${htmlTemizle(imza, uzakKalsin: true).html}</div>');
  }
  if (alintiHtml != null && alintiHtml.isNotEmpty) {
    if (alintiMetin != null && alintiMetin.isNotEmpty) m.write('\n\n$alintiMetin');
    h.write('<div><br></div>$alintiHtml');
  }
  return (metin: m.toString(), html: h.toString());
}

/// Giden Kutusu'ndaki gönderim isteğinden yazma penceresi (düzenleme). [ek]: dahil edilen eklerin adları/boyutları.
YazmaBaslangic gidenHazirla(String gidenId, Map<String, dynamic> istek, Map<String, dynamic> ek) {
  List<Adres> adresler(String alan) => ((istek[alan] as List?) ?? const []).map((e) => adresCoz('$e')).where((a) => a.eposta.isNotEmpty).toList();
  final dahil = <DahilEk>[];
  final adlar = (ek['dahil'] as List?) ?? const [];
  for (final (i, p) in ((istek['include_parts'] as List?) ?? const []).indexed) {
    if (p is! Map) continue;
    final m = i < adlar.length && adlar[i] is Map ? adlar[i] as Map : const {};
    dahil.add(
      DahilEk(
        iletiId: '${p['message_id'] ?? ''}',
        sira: (p['index'] as num?)?.toInt() ?? 0,
        ad: '${m['ad'] ?? 'Ek ${i + 1}'}',
        tur: '${m['tur'] ?? ''}',
        boyut: (m['boyut'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  final html = '${istek['html'] ?? ''}';
  String? s(String k) => istek[k] is String && (istek[k] as String).isNotEmpty ? istek[k] as String : null;
  return YazmaBaslangic(
    tur: YazmaTuru.taslak,
    kime: adresler('to'),
    bilgi: adresler('cc'),
    gizli: adresler('bcc'),
    konu: '${istek['subject'] ?? ''}',
    metin: '${istek['text'] ?? ''}',
    htmlTaslak: html.trim().isNotEmpty,
    htmlGovde: html.trim().isNotEmpty ? html : null,
    inReplyTo: s('in_reply_to'),
    references: s('references'),
    yanitlananId: s('reply_to_id'),
    iletilenId: s('forward_of_id'),
    taslakId: s('draft_id'),
    dahilEkler: dahil,
    imzaEkle: false,
    oncelik: s('priority'),
    okunduBilgisi: istek['read_receipt'] == true,
    takipGun: (istek['followup_days'] as num?)?.toInt() ?? 0,
    gidenId: gidenId,
    yerelEkler: [
      for (final a in (istek['attachments'] as List?) ?? const [])
        if (a is Map) ('${a['filename'] ?? 'ek'}', '${a['data'] ?? ''}'),
    ],
  );
}
