// Posta yönetimi ve güvenlik uç noktaları (/api/v1/mail/*). Alan adları internal/api/*.go ile birebir;
// sunucu bilinmeyen alanları reddettiğinden yalnızca listelenen alanlar gönderilir.

import 'dart:convert';
import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';

import '../oturum.dart';
import 'onbellek.dart';

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
bool _b(Object? v) => v == true;
DateTime? _t(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _l(Object? v) => v is List ? v : const [];
List<dynamic> _ogeler(Object? v) => _l(_m(v)['items']);

/// GET /scheduled → items[]
class Planli {
  Planli({
    required this.id,
    this.zaman,
    this.durum = '',
    this.hata = '',
    this.kime = const [],
    this.konu = '',
    this.tur = '',
    this.ozet = '',
    this.kesildi = false,
  });

  /// Gönderim denemesi yarıda kesildi (sunucu yeniden başladı): kısmen gitmiş olabilir.
  final bool kesildi;
  final String id;
  final DateTime? zaman;
  final String durum; // pending sending sent failed cancelled
  final String hata;
  final List<String> kime;
  final String konu;
  final String tur; // scheduled | undo
  final String ozet;

  factory Planli.json(Object? v) {
    final m = _m(v);
    return Planli(
      id: _s(m['id']),
      zaman: _t(m['send_at']),
      durum: _s(m['status']),
      hata: _s(m['error']),
      kime: _l(m['to']).map(_s).toList(),
      konu: _s(m['subject']),
      tur: _s(m['kind']),
      ozet: _s(m['summary']),
      kesildi: m['interrupted'] == true,
    );
  }

  bool get bekliyor => durum == 'pending';

  /// Giden Kutusu'nda görünür: henüz gitmedi ya da gönderilemedi (web serverOutgoing).
  bool get giden => durum == 'pending' || durum == 'sending' || durum == 'failed';

  Map<String, dynamic> get json => {
    'id': id,
    'send_at': zaman?.toUtc().toIso8601String(),
    'status': durum,
    'error': hata,
    'to': kime,
    'subject': konu,
    'kind': tur,
    'summary': ozet,
    'interrupted': kesildi,
  };
}

/// GET /contacts → sayfalı kişi listesi
class Kisi {
  Kisi({
    this.id = '',
    this.ad = '',
    this.eposta = '',
    this.telefon = '',
    this.sirket = '',
    this.not = '',
    this.favori = false,
    this.otomatik = false,
    this.kullanim = 0,
  });
  final String id;
  final String ad;
  final String eposta;
  final String telefon;
  final String sirket;
  final String not;
  final bool favori;
  final bool otomatik;
  final int kullanim;

  factory Kisi.json(Object? v) {
    final m = _m(v);
    return Kisi(
      id: _s(m['id']),
      ad: _s(m['name']),
      eposta: _s(m['email']),
      telefon: _s(m['phone']),
      sirket: _s(m['company']),
      not: _s(m['note']),
      favori: _b(m['favorite']),
      otomatik: _b(m['auto']),
      kullanim: _i(m['use_count']),
    );
  }

  /// POST/PATCH gövdesi (handleContactSave).
  Map<String, dynamic> govde() => {'name': ad, 'email': eposta, 'phone': telefon, 'company': sirket, 'note': not, 'favorite': favori};

  Kisi kopya({bool? favori}) =>
      Kisi(id: id, ad: ad, eposta: eposta, telefon: telefon, sirket: sirket, not: not, favori: favori ?? this.favori, otomatik: otomatik, kullanim: kullanim);
}

class SuzgecKosulu {
  SuzgecKosulu({this.alan = 'from', this.islec = 'contains', this.deger = ''});
  String alan; // from to cc recipient subject body size
  String islec; // contains not_contains equals starts ends gt lt
  String deger;
  factory SuzgecKosulu.json(Object? v) {
    final m = _m(v);
    return SuzgecKosulu(alan: _s(m['field']), islec: _s(m['op']), deger: _s(m['value']));
  }
  Map<String, dynamic> json() => {'field': alan, 'op': islec, 'value': deger};
}

class SuzgecEylemi {
  SuzgecEylemi({this.tur = 'move', this.deger = ''});
  String tur; // move label mark_read flag important trash junk
  String deger; // klasör / etiket kimliği
  factory SuzgecEylemi.json(Object? v) {
    final m = _m(v);
    return SuzgecEylemi(tur: _s(m['type']), deger: _s(m['value']));
  }
  bool get degerli => tur == 'move' || tur == 'label';
  Map<String, dynamic> json() => {'type': tur, if (degerli && deger.isNotEmpty) 'value': deger};
}

/// GET /filters → items[] (mailrules.Filter)
class Suzgec {
  Suzgec({
    this.id = '',
    this.ad = '',
    this.acik = true,
    this.sira = 0,
    this.hepsi = true,
    List<SuzgecKosulu>? kosullar,
    List<SuzgecEylemi>? eylemler,
    this.dur = false,
  }) : kosullar = kosullar ?? [],
       eylemler = eylemler ?? [];
  String id;
  String ad;
  bool acik;
  int sira;
  bool hepsi;
  List<SuzgecKosulu> kosullar;
  List<SuzgecEylemi> eylemler;
  bool dur;

  factory Suzgec.json(Object? v) {
    final m = _m(v);
    return Suzgec(
      id: _s(m['id']),
      ad: _s(m['name']),
      acik: _b(m['enabled']),
      sira: _i(m['position']),
      hepsi: _b(m['match_all']),
      kosullar: _l(m['conditions']).map(SuzgecKosulu.json).toList(),
      eylemler: _l(m['actions']).map(SuzgecEylemi.json).toList(),
      dur: _b(m['stop']),
    );
  }

  Map<String, dynamic> json() => {
    'id': id,
    'name': ad,
    'enabled': acik,
    'position': sira,
    'match_all': hepsi,
    'conditions': kosullar.map((k) => k.json()).toList(),
    'actions': eylemler.map((e) => e.json()).toList(),
    'stop': dur,
  };
}

/// GET /sender-lists → items[]
class GondericiKaydi {
  GondericiKaydi({required this.id, required this.tur, required this.deger, this.tarih});
  final String id;
  final String tur; // allow | block
  final String deger;
  final DateTime? tarih;
  factory GondericiKaydi.json(Object? v) {
    final m = _m(v);
    return GondericiKaydi(id: _s(m['id']), tur: _s(m['kind']), deger: _s(m['value']), tarih: _t(m['created_at']));
  }
}

/// GET/PUT /forwarding
class Yonlendirme {
  Yonlendirme({this.adres = '', this.kopyaKalsin = true, this.belirleyen = '', this.izinli = false, this.disIzinli = false});
  final String adres;
  final bool kopyaKalsin;
  final String belirleyen;
  final bool izinli;
  final bool disIzinli;
  factory Yonlendirme.json(Object? v) {
    final m = _m(v);
    return Yonlendirme(
      adres: _s(m['forward_to']),
      kopyaKalsin: m['keep_copy'] == null ? true : _b(m['keep_copy']),
      belirleyen: _s(m['set_by']),
      izinli: _b(m['allowed']),
      disIzinli: _b(m['external_allowed']),
    );
  }
}

/// GET /mfa
class IkiAdimDurumu {
  IkiAdimDurumu({this.acik = false, this.bekliyor = false, this.zorunlu = false, this.acilis, this.kurtarmaKalan = 0, this.kullanilabilir = true});
  final bool acik;
  final bool bekliyor;
  final bool zorunlu;
  final DateTime? acilis;
  final int kurtarmaKalan;
  final bool kullanilabilir;
  factory IkiAdimDurumu.json(Object? v) {
    final m = _m(v);
    return IkiAdimDurumu(
      acik: _b(m['enabled']),
      bekliyor: _b(m['pending']),
      zorunlu: _b(m['required']),
      acilis: _t(m['enabled_at']),
      kurtarmaKalan: _i(m['recovery_remaining']),
      kullanilabilir: m['available'] == null ? true : _b(m['available']),
    );
  }
}

/// GET /app-passwords → items[]
class UygulamaSifresi {
  UygulamaSifresi({required this.id, this.ad = '', this.olusturma, this.sonKullanim, this.sonIp = '', this.sonProtokol = ''});
  final String id;
  final String ad;
  final DateTime? olusturma;
  final DateTime? sonKullanim;
  final String sonIp;
  final String sonProtokol;
  factory UygulamaSifresi.json(Object? v) {
    final m = _m(v);
    return UygulamaSifresi(
      id: _s(m['id']),
      ad: _s(m['name']),
      olusturma: _t(m['created_at']),
      sonKullanim: _t(m['last_used_at']),
      sonIp: _s(m['last_used_ip']),
      sonProtokol: _s(m['last_used_proto']),
    );
  }
}

/// GET /security/admin-access
class YoneticiErisimi {
  YoneticiErisimi(this.olaylar, this.etkin);
  final List<({DateTime? zaman, String eylem, String yonetici, String neden, String ip})> olaylar;
  final List<({String yonetici, DateTime? baslangic, DateTime? bitis})> etkin;
  factory YoneticiErisimi.json(Object? v) {
    final m = _m(v);
    return YoneticiErisimi(
      _l(m['events']).map((e) {
        final x = _m(e);
        return (zaman: _t(x['at']), eylem: _s(x['action']), yonetici: _s(x['admin']), neden: _s(x['reason']), ip: _s(x['ip']));
      }).toList(),
      _l(m['active_sessions']).map((e) {
        final x = _m(e);
        return (yonetici: _s(x['admin']), baslangic: _t(x['created_at']), bitis: _t(x['expires_at']));
      }).toList(),
    );
  }
}

/// GET /devices → items[]
class Cihaz {
  Cihaz({
    required this.id,
    this.ad = '',
    this.model = '',
    this.tur = '',
    this.isletim = '',
    this.durum = '',
    this.sonEsitleme,
    this.silmeIstendi,
    this.silmeTuru = '',
  });
  final String id;
  final String ad;
  final String model;
  final String tur;
  final String isletim;
  final String durum; // allowed blocked quarantined …
  final DateTime? sonEsitleme;
  final DateTime? silmeIstendi;
  final String silmeTuru;
  factory Cihaz.json(Object? v) {
    final m = _m(v);
    return Cihaz(
      id: _s(m['id']),
      ad: _s(m['friendly_name']),
      model: _s(m['model']),
      tur: _s(m['device_type']),
      isletim: _s(m['os']),
      durum: _s(m['status']),
      sonEsitleme: _t(m['last_sync_at']) ?? _t(m['last_seen_at']),
      silmeIstendi: _t(m['wipe_requested_at']),
      silmeTuru: _s(m['wipe_type']),
    );
  }
  String get gorunen => [ad, model, tur].firstWhere((s) => s.trim().isNotEmpty, orElse: () => 'Cihaz');
}

/// GET /quarantine → items[]
class KarantinaKaydi {
  KarantinaKaydi({required this.id, this.gonderen = '', this.konu = '', this.neden = '', this.tarih, this.bitis, this.durum = ''});
  final String id;
  final String gonderen;
  final String konu;
  final String neden;
  final DateTime? tarih;
  final DateTime? bitis;
  final String durum;
  factory KarantinaKaydi.json(Object? v) {
    final m = _m(v);
    final from = _s(m['from_header']);
    return KarantinaKaydi(
      id: _s(m['id']),
      gonderen: from.isNotEmpty ? from : _s(m['mail_from']),
      konu: _s(m['subject']),
      neden: _s(m['reason']),
      tarih: _t(m['created_at']),
      bitis: _t(m['expires_at']),
      durum: _s(m['status']),
    );
  }
}

/// GET /activity → items[] (MailEvent)
class GonderimOlayi {
  GonderimOlayi({
    this.id = '',
    this.zaman,
    this.yon = '',
    this.gonderen = '',
    this.alici = '',
    this.durumEtiketi = '',
    this.ton = '',
    this.ozet = '',
    this.cozum = '',
    this.neden = '',
  });
  final String id;
  final DateTime? zaman;
  final String yon;
  final String gonderen;
  final String alici;
  final String durumEtiketi;
  final String ton; // explain.tone
  final String ozet;
  final String cozum;
  final String neden;
  factory GonderimOlayi.json(Object? v) {
    final m = _m(v);
    final e = _m(m['explain']);
    return GonderimOlayi(
      id: _s(m['id']),
      zaman: _t(m['at']),
      yon: _s(m['direction']),
      gonderen: _s(m['mail_from']),
      alici: _s(m['rcpt']),
      durumEtiketi: _s(e['label']).isNotEmpty ? _s(e['label']) : _s(m['event']),
      ton: _s(e['tone']),
      ozet: _s(e['summary']),
      cozum: _s(e['fix']),
      neden: _s(m['reason']),
    );
  }
}

/// GET /backups
class Yedek {
  Yedek({required this.calisma, this.tarih, this.ileti = 0, this.boyut = 0});
  final String calisma;
  final DateTime? tarih;
  final int ileti;
  final int boyut;
  factory Yedek.json(Object? v) {
    final m = _m(v);
    return Yedek(calisma: _s(m['run']), tarih: _t(m['started_at']), ileti: _i(m['messages']), boyut: _i(m['bytes']));
  }
}

/// GET /autoreply-rules → items[] / organization[]
class OtomatikKural {
  OtomatikKural({
    this.id = '',
    this.ad = '',
    this.acik = true,
    this.sira = 0,
    this.zamanlama = 'always',
    List<int>? gunler,
    this.baslangicSaati = '',
    this.bitisSaati = '',
    this.tarihBas = '',
    this.tarihBit = '',
    this.gonderen = 'any',
    this.konu = '',
    this.govdeHtml = '',
    this.araGun = 4,
    this.kurumsal = false,
    Map<String, dynamic>? hamKosullar,
  }) : gunler = gunler ?? [],
       hamKosullar = hamKosullar ?? {};
  String id;
  String ad;
  bool acik;
  int sira;
  String zamanlama; // always inside outside
  List<int> gunler;
  String baslangicSaati;
  String bitisSaati;
  String tarihBas;
  String tarihBit;
  String gonderen; // any internal external
  String konu;
  String govdeHtml;
  int araGun;
  bool kurumsal;

  /// Uygulamada düzenlenmeyen koşullar (senders, subject_keywords) korunur.
  Map<String, dynamic> hamKosullar;

  factory OtomatikKural.json(Object? v) {
    final m = _m(v);
    final k = _m(m['conditions']);
    return OtomatikKural(
      id: _s(m['id']),
      ad: _s(m['name']),
      acik: _b(m['enabled']),
      sira: _i(m['position']),
      zamanlama: _s(k['schedule']).isEmpty ? 'always' : _s(k['schedule']),
      gunler: _l(k['weekdays']).map(_i).toList(),
      baslangicSaati: _s(k['start_time']),
      bitisSaati: _s(k['end_time']),
      tarihBas: _s(k['date_from']),
      tarihBit: _s(k['date_to']),
      gonderen: _s(k['sender']).isEmpty ? 'any' : _s(k['sender']),
      konu: _s(m['subject']),
      govdeHtml: _s(m['body_html']),
      araGun: _i(m['once_per_days']) > 0 ? _i(m['once_per_days']) : 4,
      kurumsal: _b(m['org_wide']),
      hamKosullar: k,
    );
  }

  /// POST/PATCH gövdesi (yalnızca kullanıcının yazabildiği alanlar).
  Map<String, dynamic> json() => {
    'name': ad,
    'enabled': acik,
    'position': sira,
    'conditions': {
      ...hamKosullar,
      'schedule': zamanlama,
      'weekdays': gunler,
      'start_time': baslangicSaati,
      'end_time': bitisSaati,
      'date_from': tarihBas,
      'date_to': tarihBit,
      'sender': gonderen,
    },
    'subject': konu,
    'body_html': govdeHtml,
    'once_per_days': araGun,
  };
}

/// GET /profile
class ImzaProfili {
  ImzaProfili({this.unvan = '', this.departman = '', this.telefon = '', this.cep = '', this.web = '', Map<String, String>? sosyal, this.duzenlenebilir = true})
    : sosyal = sosyal ?? {};
  final String unvan;
  final String departman;
  final String telefon;
  final String cep;
  final String web;
  final Map<String, String> sosyal;
  final bool duzenlenebilir;
  factory ImzaProfili.json(Object? v) {
    final m = _m(v);
    final p = _m(m['profile']);
    return ImzaProfili(
      unvan: _s(p['title']),
      departman: _s(p['department']),
      telefon: _s(p['phone']),
      cep: _s(p['mobile']),
      web: _s(p['web']),
      sosyal: _m(p['social']).map((k, v) => MapEntry(k, _s(v))),
      duzenlenebilir: m['editable'] == null ? true : _b(m['editable']),
    );
  }
}

/// GET /saved-searches → items[]
class KayitliArama {
  KayitliArama(this.id, this.ad, this.sorgu);
  final String id;
  final String ad;
  final String sorgu;
  factory KayitliArama.json(Object? v) {
    final m = _m(v);
    return KayitliArama(_s(m['id']), _s(m['name']), _s(m['query']));
  }
}

class Hesap {
  Hesap._();
  static BogaApi get _api => Uyg.api;
  static const _k = '/api/v1/mail';

  // ---- planlanan gönderimler ----
  static Future<List<Planli>> planlananlar() async => _ogeler(await _api.get('$_k/scheduled')).map(Planli.json).toList();
  static Future<void> planIptal(String id) => _api.delete('$_k/scheduled/$id');

  /// Gönderilemeyen iletiyi yeniden gönderime alır (yalnız failed; değilse 409).
  static Future<void> planTekrar(String id) => _api.post('$_k/scheduled/$id/retry');

  /// Bekleyen / gönderilemeyen iletiyi taslağa çevirir: {draft_id, kind, send_at, compose}.
  static Future<Map<String, dynamic>> planGeriAl(String id) async {
    final v = await _api.post('$_k/scheduled/$id/restore');
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  static Future<void> planErtele(String id, DateTime z) => _api.patch('$_k/scheduled/$id', {'send_at': z.toUtc().toIso8601String()});

  // ---- kişiler ----
  static Future<({List<Kisi> ogeler, int toplam})> kisiler({
    String q = '',
    String? tur,
    int sayfa = 1,
    void Function(({List<Kisi> ogeler, int toplam}))? yerel,
  }) => yerelOnce(
    q.trim().isEmpty && sayfa == 1 ? 'kisiler:${tur ?? ''}' : null,
    () => _api.get('$_k/contacts', q: {'page': sayfa, 'page_size': 100, 'sort': 'name', 'order': 'asc', if (q.trim().isNotEmpty) 'q': q.trim(), 'kind': ?tur}),
    (v) => (ogeler: _ogeler(v).map(Kisi.json).toList(), toplam: _i(_m(v)['total'])),
    yerel: yerel,
  );

  /// Rehberin tamamı (dışa aktarma; 500'lük sayfalar).
  static Future<List<Kisi>> tumKisiler() async {
    final l = <Kisi>[];
    for (var s = 1; s < 100; s++) {
      final v = _m(await _api.get('$_k/contacts', q: {'page': s, 'page_size': 500}));
      final o = _ogeler(v).map(Kisi.json).toList();
      l.addAll(o);
      if (o.length < 500 || l.length >= _i(v['total'])) break;
    }
    return l;
  }

  static Future<void> kisiKaydet(Kisi k) => k.id.isEmpty ? _api.post('$_k/contacts', k.govde()) : _api.patch('$_k/contacts/${k.id}', k.govde());
  static Future<void> kisiSil(String id) => _api.delete('$_k/contacts/$id');

  // ---- süzgeçler ----
  static Future<List<Suzgec>> suzgecler() async => _ogeler(await _api.get('$_k/filters')).map(Suzgec.json).toList();
  static Future<void> suzgecKaydet(Suzgec s) => s.id.isEmpty ? _api.post('$_k/filters', s.json()) : _api.patch('$_k/filters/${s.id}', s.json());
  static Future<void> suzgecSil(String id) => _api.delete('$_k/filters/$id');
  static Future<({int eslesen, int taranan})> suzgecCalistir(String id) async {
    final v = _m(await _api.post('$_k/filters/$id/run'));
    return (eslesen: _i(v['matched']), taranan: _i(v['scanned']));
  }

  // ---- güvenilir / engelli gönderenler ----
  static Future<List<GondericiKaydi>> gondericiListeleri() async => _ogeler(await _api.get('$_k/sender-lists')).map(GondericiKaydi.json).toList();

  /// [tur]: allow | block. [deger]: adres veya @alanadi.
  static Future<void> gondericiEkle(String tur, String deger) => _api.post('$_k/sender-lists', {'kind': tur, 'value': deger.trim()});
  static Future<void> gondericiSil(String id) => _api.delete('$_k/sender-lists/$id');

  // ---- yönlendirme ----
  static Future<Yonlendirme> yonlendirme() async => Yonlendirme.json(await _api.get('$_k/forwarding'));
  static Future<Yonlendirme> yonlendirmeKaydet(String adres, bool kopya) async =>
      Yonlendirme.json(await _api.put('$_k/forwarding', {'forward_to': adres.trim(), 'keep_copy': kopya}));

  // ---- şifre ve iki adımlı doğrulama ----
  static Future<void> sifreDegistir(String eski, String yeni) => _api.post('$_k/auth/password', {'current': eski, 'new': yeni});
  static Future<IkiAdimDurumu> ikiAdim() async => IkiAdimDurumu.json(await _api.get('$_k/mfa'));
  static Future<({String gizli, String uri})> ikiAdimKur() async {
    final v = _m(await _api.post('$_k/mfa/setup'));
    return (gizli: _s(v['secret']), uri: _s(v['otpauth_uri']));
  }

  static Future<List<String>> ikiAdimAc(String kod) async => _l(_m(await _api.post('$_k/mfa/enable', {'code': kod.trim()}))['recovery_codes']).map(_s).toList();
  static Future<void> ikiAdimKapat(String kod) => _api.post('$_k/mfa/disable', {'code': kod.trim()});
  static Future<List<String>> kurtarmaKodlari(String kod) async =>
      _l(_m(await _api.post('$_k/mfa/recovery-codes', {'code': kod.trim()}))['recovery_codes']).map(_s).toList();

  // ---- uygulama şifreleri ----
  static Future<({List<UygulamaSifresi> ogeler, bool ikiAdim})> uygulamaSifreleri() async {
    final v = await _api.get('$_k/app-passwords');
    return (ogeler: _ogeler(v).map(UygulamaSifresi.json).toList(), ikiAdim: _b(_m(v)['mfa_enabled']));
  }

  static Future<String> uygulamaSifresiOlustur(String ad) async => _s(_m(await _api.post('$_k/app-passwords', {'name': ad.trim()}))['password']);
  static Future<void> uygulamaSifresiSil(String id) => _api.delete('$_k/app-passwords/$id');

  // ---- yönetici erişimi, cihazlar, karantina, gönderim durumu ----
  static Future<YoneticiErisimi> yoneticiErisimi() async => YoneticiErisimi.json(await _api.get('$_k/security/admin-access'));

  static Future<({List<Cihaz> ogeler, bool acik})> cihazlar() async {
    final v = await _api.get('$_k/devices');
    return (ogeler: _ogeler(v).map(Cihaz.json).toList(), acik: _m(v)['enabled'] == null ? true : _b(_m(v)['enabled']));
  }

  static Future<void> cihazDurumu(String id, bool izinli) => _api.patch('$_k/devices/$id', {'status': izinli ? 'allowed' : 'blocked'});
  static Future<void> cihazSil(String id) => _api.delete('$_k/devices/$id');

  /// [tur]: full | account. Sunucu "SİL" onay metnini ister.
  static Future<void> cihazTemizle(String id, String tur) => _api.post('$_k/devices/$id/wipe', {'type': tur, 'confirm': 'SİL'});
  static Future<void> cihazTemizlemeIptal(String id) => _api.post('$_k/devices/$id/wipe/cancel');

  static Future<List<KarantinaKaydi>> karantina() async => _ogeler(await _api.get('$_k/quarantine')).map(KarantinaKaydi.json).toList();

  /// [yon]: in | out.
  static Future<List<GonderimOlayi>> gonderimDurumu(String yon, {String q = ''}) async =>
      _ogeler(await _api.get('$_k/activity', q: {'direction': yon, if (q.trim().isNotEmpty) 'q': q.trim()})).map(GonderimOlayi.json).toList();

  // ---- yedekler ----
  static Future<({List<Yedek> ogeler, int saklama})> yedekler() async {
    final v = await _api.get('$_k/backups');
    return (ogeler: _ogeler(v).map(Yedek.json).toList(), saklama: _i(_m(v)['retention_days']));
  }

  /// [kip]: original | restore_folder.
  static Future<({int geriYuklenen, int toplam, String klasor})> yedekGeriYukle(String calisma, String kip) async {
    final v = _m(await _api.post('$_k/backups/$calisma/restore', {'mode': kip}));
    return (geriYuklenen: _i(v['restored']), toplam: _i(v['total']), klasor: _s(v['folder']));
  }

  // ---- otomatik yanıt kuralları ----
  static Future<({List<OtomatikKural> benim, List<OtomatikKural> kurum})> otomatikKurallar() async {
    final v = _m(await _api.get('$_k/autoreply-rules'));
    return (benim: _l(v['items']).map(OtomatikKural.json).toList(), kurum: _l(v['organization']).map(OtomatikKural.json).toList());
  }

  static Future<void> otomatikKuralKaydet(OtomatikKural k) =>
      k.id.isEmpty ? _api.post('$_k/autoreply-rules', k.json()) : _api.patch('$_k/autoreply-rules/${k.id}', k.json());
  static Future<void> otomatikKuralSil(String id) => _api.delete('$_k/autoreply-rules/$id');

  // ---- imza profili ve profil resmi ----
  static Future<ImzaProfili> profil() async => ImzaProfili.json(await _api.get('$_k/profile'));
  static Future<void> profilKaydet(Map<String, dynamic> p) => _api.put('$_k/profile', p);

  static Future<({bool var_, String kutuId, int surum})> avatarBilgisi() async {
    final v = _m(await _api.get('$_k/avatar'));
    return (var_: _b(v['has_avatar']), kutuId: _s(v['mailbox_id']), surum: _i(v['version']));
  }

  static Future<Uint8List> avatarGetir(String kutuId) => _api.indir('$_k/avatars/$kutuId');
  static Future<void> avatarYukle(Uint8List bayt) => _api.put('$_k/avatar', {'data': base64Encode(bayt)});
  static Future<void> avatarSil() => _api.delete('$_k/avatar');

  // ---- etiketler ----
  static Future<void> etiketGuncelle(String id, {String? ad, String? renk}) => _api.patch('$_k/labels/$id', {'name': ?ad, 'color': ?renk});
  static Future<void> etiketSil(String id) => _api.delete('$_k/labels/$id');

  // ---- kayıtlı aramalar ----
  static Future<List<KayitliArama>> kayitliAramalar() async => _ogeler(await _api.get('$_k/saved-searches')).map(KayitliArama.json).toList();
  static Future<void> aramaKaydet(String ad, String sorgu) => _api.post('$_k/saved-searches', {'name': ad.trim(), 'query': sorgu.trim()});
  static Future<void> kayitliAramaSil(String id) => _api.delete('$_k/saved-searches/$id');

  // ---- okuyucudan ----
  static Future<String> oltaBildir(String iletiId) async => _s(_m(await _api.post('$_k/messages/$iletiId/report-phishing'))['message']);
  static Future<void> takipKur(String iletiId, int gun) => _api.put('$_k/messages/$iletiId/followup', {'days': gun});
  static Future<void> takipKaldir(String iletiId) => _api.delete('$_k/messages/$iletiId/followup');

  /// {kind, due_at, status} veya null.
  static Future<({String tur, DateTime? zaman, String durum})?> takip(String iletiId) async {
    final f = _m(await _api.get('$_k/messages/$iletiId/followup'))['followup'];
    if (f is! Map) return null;
    final m = _m(f);
    return (tur: _s(m['kind']), zaman: _t(m['due_at']), durum: _s(m['status']));
  }
}
