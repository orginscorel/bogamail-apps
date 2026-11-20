// Saf yardımcılar (arayüzden bağımsız, birim testli): adres ayrıştırma, tarih grupları, alıntılama, konu önekleri.

import 'package:intl/intl.dart';

import 'modeller.dart';

const _klasorAdlari = {
  'inbox': 'Gelen Kutusu',
  'sent': 'Gönderilenler',
  'drafts': 'Taslaklar',
  'trash': 'Çöp Kutusu',
  'junk': 'Gereksiz (Spam)',
  'archive': 'Arşiv',
  'snoozed': 'Ertelenenler',
  'templates': 'Şablonlar',
};

/// Sistem klasörlerinin Türkçe adı (web'deki folderName ile aynı).
String klasorAdi(String? rol, String ad) => rol == null ? ad : (_klasorAdlari[rol] ?? ad);

/// Sistem klasörlerinin kenar çubuğundaki sabit sırası.
const sistemSirasi = ['inbox', 'snoozed', 'drafts', 'sent', 'archive', 'templates', 'junk', 'trash'];

final _adresRe = RegExp(r'^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$');

/// `"Ad Soyad <a@b.c>"` → Adres.
Adres adresCoz(String s) {
  final m = _adresRe.firstMatch(s);
  if (m != null) return Adres(m.group(1)!.trim(), m.group(2)!.trim());
  return Adres('', s.trim().replaceAll(RegExp(r'^<|>$'), ''));
}

/// Başlıktaki adres listesini ayırır (tırnak içindeki virgüller korunur).
List<Adres> adresListesiCoz(String s) {
  final out = <Adres>[];
  final b = StringBuffer();
  var tirnak = false;
  var acili = false;
  for (final c in s.split('')) {
    if (c == '"') tirnak = !tirnak;
    if (c == '<') acili = true;
    if (c == '>') acili = false;
    if ((c == ',' || c == ';') && !tirnak && !acili) {
      if (b.toString().trim().isNotEmpty) out.add(adresCoz(b.toString()));
      b.clear();
    } else {
      b.write(c);
    }
  }
  if (b.toString().trim().isNotEmpty) out.add(adresCoz(b.toString()));
  return out;
}

/// Adres → `Ad <e-posta>` (adda özel karakter varsa tırnaklı).
String adresYaz(Adres a) {
  if (a.ad.isEmpty) return a.eposta;
  return RegExp(r'[",;<>@]').hasMatch(a.ad) ? '"${a.ad.replaceAll('"', '')}" <${a.eposta}>' : '${a.ad} <${a.eposta}>';
}

/// Liste satırında gösterilecek ad.
String gorunenAd(String baslik) {
  final ilk = adresListesiCoz(baslik);
  if (ilk.isEmpty) return '(gönderen yok)';
  final a = ilk.first;
  return a.ad.isNotEmpty ? a.ad : (a.eposta.isNotEmpty ? a.eposta : '(gönderen yok)');
}

final _epostaRe = RegExp(r"^[^\s@<>(),;:\x22\[\]]+@[^\s@<>(),;:\x22\[\]]+\.[^\s@<>(),;:\x22\[\]]+$");

/// Basit e-posta adresi doğrulaması (sunucu son sözü söyler).
bool gecerliEposta(String s) => _epostaRe.hasMatch(s.trim());

/// Yazılan metinden alıcı çıkarır: `Ad <a@b>` veya çıplak adres. Geçersizse null.
Adres? aliciCoz(String s) {
  final t = s.trim().replaceAll(RegExp(r'[,;]+$'), '').trim();
  if (t.isEmpty) return null;
  final a = adresCoz(t);
  return gecerliEposta(a.eposta) ? a : null;
}

/// Liste için tarih grubu: Bugün / Dün / Bu hafta / Geçen hafta / Bu ay / "Ekim 2026".
String tarihGrubu(DateTime d, [DateTime? simdi]) {
  final n = simdi ?? DateTime.now();
  final gun = DateTime(n.year, n.month, n.day);
  final g = DateTime(d.year, d.month, d.day);
  final fark = (gun.difference(g).inHours / 24).round();
  if (fark <= 0) return 'Bugün';
  if (fark == 1) return 'Dün';
  // Pazartesi başlangıçlı hafta (weekday: 1 = Pzt … 7 = Paz).
  if (fark < 7 && d.weekday <= n.weekday) return 'Bu hafta';
  if (fark < 14) return 'Geçen hafta';
  if (d.year == n.year && d.month == n.month) return 'Bu ay';
  final ay = DateFormat('MMMM y', 'tr_TR').format(d);
  return ay[0].toUpperCase() + ay.substring(1);
}

/// "Re: …" / "Fwd: …" öneki (Türkçe ve yaygın eşdeğerleri tekrarlanmaz).
String onekli(String onek, String konu) {
  final alt = onek == 'Re' ? 'Ynt|Cvp|Yanıt' : 'Fw|İlt|İlet';
  final re = RegExp('^\\s*($onek|$alt):', caseSensitive: false);
  final k = konu.trim();
  return re.hasMatch(k) ? k : '$onek: $k';
}

String htmlKacis(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Düz metin → güvenli HTML (satır sonları <br>).
String metindenHtml(String s) => htmlKacis(s).replaceAll(RegExp(r'\r?\n'), '<br>');

/// Düz metni "> " ile alıntılar.
String alintila(String metin) {
  final satirlar = metin.replaceAll('\r\n', '\n').split('\n');
  while (satirlar.isNotEmpty && satirlar.last.trim().isEmpty) {
    satirlar.removeLast();
  }
  return satirlar.map((l) => l.isEmpty ? '>' : (l.startsWith('>') ? '>$l' : '> $l')).join('\n');
}

/// Yanıtta alıntının giriş satırı.
String alintiGirisi(DateTime? tarih, String kimden) {
  final t = tarih == null ? '' : '${DateFormat('d MMMM y HH:mm', 'tr_TR').format(tarih)} tarihinde ';
  return '$t$kimden yazdı:';
}

/// Yanıt-tümü alıcıları: kendisi ve asıl alıcılar çıkarılır, tekrarlar atılır.
({List<Adres> kime, List<Adres> bilgi}) yanitAlicilari({
  required List<Adres> kimden,
  required List<Adres> yanitAdresi,
  required List<Adres> kime,
  required List<Adres> bilgi,
  required String ben,
  required bool tumu,
}) {
  final hedef = yanitAdresi.isNotEmpty ? yanitAdresi : kimden;
  final benK = ben.toLowerCase();
  // Kendi gönderdiği iletiye yanıt: asıl alıcılara gider.
  final kendisi = hedef.length == 1 && hedef.first.eposta.toLowerCase() == benK;
  final kimeOut = <Adres>[];
  final gorulen = <String>{};
  void ekle(List<Adres> l, List<Adres> hedefListe) {
    for (final a in l) {
      final k = a.eposta.toLowerCase();
      if (k.isEmpty || k == benK || gorulen.contains(k)) continue;
      gorulen.add(k);
      hedefListe.add(a);
    }
  }

  if (kendisi) {
    ekle(kime, kimeOut);
  } else {
    ekle(hedef, kimeOut);
  }
  final bilgiOut = <Adres>[];
  if (tumu) {
    if (!kendisi) ekle(kime, bilgiOut);
    ekle(bilgi, bilgiOut);
  }
  return (kime: kimeOut, bilgi: bilgiOut);
}

/// Düz metin gövdesinde sondaki alıntılanmış geçmişi ayırır (web splitQuotedText ile aynı kurallar).
({String ana, String alinti}) alintiAyir(String metin) {
  final satirlar = metin.split(RegExp(r'\r?\n'));
  final giris = RegExp(
    r'^(On .{4,200} wrote:|.{4,200} (yazdı|şunu yazdı|tarihinde şunu yazdı):|-{2,}\s*(Original Message|Orijinal İleti|Özgün ileti|İletilen ileti|Forwarded message)\s*-{2,})\s*$',
    caseSensitive: false,
  );
  var kes = -1;
  for (var i = 0; i < satirlar.length; i++) {
    final l = satirlar[i].trim();
    if (giris.hasMatch(l)) {
      kes = i;
      break;
    }
    final sonraki = i + 1 < satirlar.length ? satirlar[i + 1].trim() : '';
    if (RegExp(r'^(On|Am|Le)\s.+').hasMatch(l) && RegExp(r'^(wrote|yazdı|schrieb|a écrit)\s*:\s*$', caseSensitive: false).hasMatch(sonraki)) {
      kes = i;
      break;
    }
  }
  if (kes < 0) {
    var i = satirlar.length - 1;
    while (i >= 0 && satirlar[i].trim().isEmpty) {
      i--;
    }
    var j = i;
    while (j >= 0 && (satirlar[j].startsWith('>') || satirlar[j].trim().isEmpty)) {
      j--;
    }
    if (j < i && satirlar.sublist(j + 1, i + 1).any((l) => l.startsWith('>'))) kes = j + 1;
  }
  if (kes <= 0) return (ana: metin, alinti: '');
  final ana = satirlar.sublist(0, kes).join('\n').replaceAll(RegExp(r'\s+$'), '');
  if (ana.trim().isEmpty) return (ana: metin, alinti: '');
  return (ana: ana, alinti: satirlar.sublist(kes).join('\n'));
}

/// Kota: 1 PiB ve üstü sınırsız sayılır.
bool sinirsizKota(int bayt) => bayt <= 0 || bayt >= 1125899906842624;

/// Dosya adından içerik türü (sunucu da doğrular; bilinmeyenler octet-stream).
String icerikTuru(String ad) {
  final u = ad.toLowerCase();
  final nokta = u.lastIndexOf('.');
  final uz = nokta < 0 ? '' : u.substring(nokta + 1);
  const t = {
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'svg': 'image/svg+xml',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'htm': 'text/html',
    'html': 'text/html',
    'ics': 'text/calendar',
    'zip': 'application/zip',
    'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'mp3': 'audio/mpeg',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'eml': 'message/rfc822',
    'json': 'application/json',
    'xml': 'application/xml',
  };
  return t[uz] ?? 'application/octet-stream';
}

/// Dosya adını yerel dosya sistemine güvenli hâle getirir.
String guvenliDosyaAdi(String ad) {
  var s = ad.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  if (s.isEmpty || s == '.' || s == '..') s = 'ek';
  return s.length > 120 ? s.substring(s.length - 120) : s;
}
