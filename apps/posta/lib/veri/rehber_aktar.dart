// Rehber içe / dışa aktarma (web contacts-view.tsx ile aynı biçimler, yalnız istemci tarafı):
// dışa aktarma vCard 3.0; içe aktarma vCard (.vcf, quoted-printable ve satır katlama dahil) veya CSV (Outlook,
// Gmail, telefon rehberi; ayırıcı , ; sekme kendiliğinden; Türkçe / İngilizce sütun başlıkları).

import 'dart:convert';

import 'hesap_servisi.dart';

/// En çok bu kadar kişi içe aktarılır (web IMPORT_MAX).
const iceAktarmaSiniri = 1000;

final _epostaKalibi = RegExp(r'^[^\s@<>()",;]+@[^\s@<>()",;]+\.[^\s@<>()",;]+$');

String _vKacir(String s) => s.replaceAll(r'\', r'\\').replaceAll(RegExp(r'\r?\n'), r'\n').replaceAll(',', r'\,').replaceAll(';', r'\;');

String _vCoz(String s) => s.replaceAllMapped(RegExp(r'\\([nN,;\\])'), (m) => m[1] == 'n' || m[1] == 'N' ? '\n' : m[1]!);

/// Kişileri vCard 3.0 metnine çevirir.
String vcardYaz(List<Kisi> l) {
  final o = <String>[];
  for (final k in l) {
    final ad = k.ad.trim();
    final p = ad.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    final soyad = p.length > 1 ? p.last : '';
    final ilk = p.length > 1 ? p.sublist(0, p.length - 1).join(' ') : (p.firstOrNull ?? '');
    o
      ..add('BEGIN:VCARD')
      ..add('VERSION:3.0')
      ..add('FN:${_vKacir(ad.isEmpty ? k.eposta : ad)}')
      ..add('N:${_vKacir(soyad)};${_vKacir(ilk)};;;')
      ..add('EMAIL;TYPE=INTERNET:${k.eposta}');
    if (k.telefon.isNotEmpty) o.add('TEL;TYPE=CELL:${_vKacir(k.telefon)}');
    if (k.sirket.isNotEmpty) o.add('ORG:${_vKacir(k.sirket)}');
    if (k.not.isNotEmpty) o.add('NOTE:${_vKacir(k.not)}');
    o.add('END:VCARD');
  }
  return '${o.join('\r\n')}\r\n';
}

String _qpCoz(String s) {
  final b = <int>[];
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '=' && i + 3 <= s.length && RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(s.substring(i + 1, i + 3))) {
      b.add(int.parse(s.substring(i + 1, i + 3), radix: 16));
      i += 2;
    } else {
      b.addAll(utf8.encode(s[i]));
    }
  }
  return utf8.decode(b, allowMalformed: true);
}

/// Noktalı virgülle ayrılmış (kaçışlı olmayan) vCard alanları.
List<String> _bol(String s) => s.split(RegExp(r'(?<!\\);'));

/// vCard metnindeki kişiler.
List<Kisi> vcardOku(String metin) {
  final acik = metin.replaceAll(RegExp(r'\r\n?'), '\n').replaceAll('=\n', '').replaceAll(RegExp(r'\n[ \t]'), '');
  final out = <Kisi>[];
  Map<String, String>? k;
  var nAlani = '';
  for (final ham in acik.split('\n')) {
    final satir = ham.trimRight();
    final i = satir.indexOf(':');
    if (i < 0) continue;
    final parcalar = satir.substring(0, i).split(';');
    final ad = parcalar.first.split('.').last.toUpperCase();
    var deger = satir.substring(i + 1);
    if (parcalar.skip(1).any((p) => p.toUpperCase().contains('QUOTED-PRINTABLE'))) deger = _qpCoz(deger);
    if (ad == 'BEGIN' && deger.trim().toUpperCase() == 'VCARD') {
      k = {};
      nAlani = '';
      continue;
    }
    if (k == null) continue;
    switch (ad) {
      case 'END':
        if ((k['ad'] ?? '').isEmpty && nAlani.isNotEmpty) {
          final n = _bol(nAlani).map(_vCoz).toList();
          k['ad'] = [n.length > 1 ? n[1] : '', n[0]].where((x) => x.isNotEmpty).join(' ').trim();
        }
        out.add(Kisi(ad: k['ad'] ?? '', eposta: k['eposta'] ?? '', telefon: k['tel'] ?? '', sirket: k['sirket'] ?? '', not: k['not'] ?? ''));
        k = null;
      case 'FN':
        k['ad'] = _vCoz(deger).trim();
      case 'N':
        nAlani = deger;
      case 'EMAIL':
        k['eposta'] ??= deger.trim().replaceFirst(RegExp('^mailto:', caseSensitive: false), '');
      case 'TEL':
        k['tel'] ??= _vCoz(deger).replaceFirst(RegExp('^tel:', caseSensitive: false), '').trim();
      case 'ORG':
        k['sirket'] = _vCoz(_bol(deger).first).trim();
      case 'NOTE':
        k['not'] = _vCoz(deger).trim();
    }
  }
  return out;
}

List<List<String>> _csvSatirlari(String metin) {
  final ilkSon = metin.indexOf('\n');
  final ilk = ilkSon >= 0 ? metin.substring(0, ilkSon) : metin;
  var ayirici = ',';
  for (final d in const [';', '\t']) {
    if (ilk.split(d).length > ilk.split(ayirici).length) ayirici = d;
  }
  final satirlar = <List<String>>[];
  var satir = <String>[];
  final alan = StringBuffer();
  var tirnak = false;
  void satirBitti() {
    satir.add(alan.toString());
    alan.clear();
    if (satir.any((c) => c.trim().isNotEmpty)) satirlar.add(satir);
    satir = <String>[];
  }

  for (var i = 0; i < metin.length; i++) {
    final c = metin[i];
    if (tirnak) {
      if (c == '"') {
        if (i + 1 < metin.length && metin[i + 1] == '"') {
          alan.write('"');
          i++;
        } else {
          tirnak = false;
        }
      } else {
        alan.write(c);
      }
      continue;
    }
    if (c == '"' && alan.isEmpty) {
      tirnak = true;
    } else if (c == ayirici) {
      satir.add(alan.toString());
      alan.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < metin.length && metin[i + 1] == '\n') i++;
      satirBitti();
    } else {
      alan.write(c);
    }
  }
  satirBitti();
  return satirlar;
}

const _basliklar = <String, List<String>>{
  'ad': ['name', 'ad soyad', 'adı soyadı', 'ad-soyad', 'isim', 'full name', 'display name', 'görünen ad', 'kişi'],
  'ilk': ['first name', 'given name', 'ad', 'adı'],
  'soyad': ['last name', 'family name', 'surname', 'soyad', 'soyadı'],
  'eposta': ['email', 'e-mail', 'e-posta', 'eposta', 'mail', 'email address', 'e-mail address', 'e-posta adresi', 'e-mail 1 - value', 'primary email'],
  'tel': ['phone', 'telefon', 'tel', 'mobile', 'mobile phone', 'cep', 'cep telefonu', 'gsm', 'phone 1 - value', 'primary phone'],
  'sirket': ['company', 'şirket', 'firma', 'kurum', 'organization', 'organisation', 'organization 1 - name'],
  'not': ['note', 'notes', 'not', 'notlar', 'açıklama'],
};

String _kucuk(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// CSV metnindeki kişiler (ilk satır sütun başlıkları; yoksa e-posta sütunu "@" ile bulunur).
List<Kisi> csvOku(String metin) {
  final s = _csvSatirlari(metin);
  if (s.isEmpty) return [];
  final bas = s.first.map((h) => _kucuk(h.trim())).toList();
  final sut = <String, int>{};
  for (final e in _basliklar.entries) {
    final i = bas.indexWhere(e.value.contains);
    if (i >= 0) sut[e.key] = i;
  }
  var govde = s.skip(1).toList();
  if (!sut.containsKey('eposta')) {
    govde = s;
    final ornek = s.first;
    final ei = ornek.indexWhere((c) => c.contains('@'));
    if (ei < 0) return [];
    sut
      ..clear()
      ..['eposta'] = ei;
    if (ei != 0) sut['ad'] = 0;
    if (ornek.length > ei + 1) sut['tel'] = ei + 1;
    if (ornek.length > ei + 2) sut['sirket'] = ei + 2;
  }
  String al(List<String> r, String a) {
    final i = sut[a];
    return i == null || i >= r.length ? '' : r[i].trim();
  }

  return [
    for (final r in govde)
      Kisi(
        ad: al(r, 'ad').isNotEmpty ? al(r, 'ad') : [al(r, 'ilk'), al(r, 'soyad')].where((x) => x.isNotEmpty).join(' '),
        eposta: al(r, 'eposta'),
        telefon: al(r, 'tel'),
        sirket: al(r, 'sirket'),
        not: al(r, 'not'),
      ),
  ];
}

/// İçe aktarma ön izlemesi: geçerli, yinelenmeyen kişiler (en çok [iceAktarmaSiniri]); atlanan ve kesilen sayısı.
({List<Kisi> kisiler, int atlanan, int kesilen, bool vcard}) rehberDosyasiOku(String dosyaAdi, String metin) {
  final m = metin.startsWith('\uFEFF') ? metin.substring(1) : metin;
  final vcard =
      RegExp(r'\.(vcf|vcard)$', caseSensitive: false).hasMatch(dosyaAdi) ||
      RegExp('BEGIN:VCARD', caseSensitive: false).hasMatch(m.length > 2000 ? m.substring(0, 2000) : m);
  final ham = vcard ? vcardOku(m) : csvOku(m);
  final gorulen = <String>{};
  final l = <Kisi>[];
  var atlanan = 0;
  String kes(String s, int n) => s.length > n ? s.substring(0, n) : s;
  for (final k in ham) {
    final e = k.eposta.trim().toLowerCase();
    if (!_epostaKalibi.hasMatch(e) || !gorulen.add(e)) {
      atlanan++;
      continue;
    }
    l.add(Kisi(ad: kes(k.ad, 200), eposta: e, telefon: kes(k.telefon, 40), sirket: kes(k.sirket, 200), not: kes(k.not, 2000)));
  }
  final kesilen = l.length > iceAktarmaSiniri ? l.length - iceAktarmaSiniri : 0;
  return (kisiler: l.take(iceAktarmaSiniri).toList(), atlanan: atlanan, kesilen: kesilen, vcard: vcard);
}
