// Takvim (internal/api/calendar.go), toplantı davetleri (itip.go) ve görevler (webmail_tasks.go).
// Sunucu bilinmeyen alanları reddeder; yalnızca listelenen alanlar gönderilir.

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
String _utc(DateTime d) => d.toUtc().toIso8601String();

/// Hata kodu özellik kapalı mı (403 feature_disabled)?
bool ozellikKapali(Object e) => e is ApiHata && (e.kod == 'feature_disabled' || e.durum == 404);

class Takvim {
  Takvim({required this.id, this.ad = '', this.renk = '', this.varsayilan = false});
  final String id;
  final String ad;
  final String renk;
  final bool varsayilan;
  factory Takvim.json(Object? v) {
    final m = _m(v);
    return Takvim(id: _s(m['id']), ad: _s(m['name']), renk: _s(m['color']), varsayilan: _b(m['is_default']));
  }
}

class Katilimci {
  const Katilimci({this.ad = '', required this.eposta, this.yanit = ''});
  final String ad;
  final String eposta;

  /// Davetlerde: NEEDS-ACTION | ACCEPTED | TENTATIVE | DECLINED
  final String yanit;
  factory Katilimci.json(Object? v) {
    final m = _m(v);
    return Katilimci(ad: _s(m['name']), eposta: _s(m['email']), yanit: _s(m['partstat']));
  }
  Map<String, dynamic> get json => {'name': ad, 'email': eposta};
  String get gorunen => ad.trim().isNotEmpty ? ad.trim() : eposta;
}

const tekrarAdlari = {'': 'Tekrarlanmaz', 'DAILY': 'Her gün', 'WEEKLY': 'Her hafta', 'MONTHLY': 'Her ay', 'YEARLY': 'Her yıl'};
const hatirlatmaAdlari = <int?, String>{
  null: 'Hatırlatma yok',
  0: 'Başlangıçta',
  5: '5 dakika önce',
  10: '10 dakika önce',
  15: '15 dakika önce',
  30: '30 dakika önce',
  60: '1 saat önce',
  120: '2 saat önce',
  1440: '1 gün önce',
  10080: '1 hafta önce',
};

/// calEvent
class Etkinlik {
  Etkinlik({
    this.id = '',
    this.takvimId = '',
    this.baslik = '',
    this.yer = '',
    this.aciklama = '',
    required this.baslangic,
    required this.bitis,
    this.tumGun = false,
    this.tekrar = '',
    this.hatirlatma,
    this.katilimcilar = const [],
    this.renk = '',
    this.tekrarBaslangici,
    this.davetli = false,
  });
  final String id;
  final String takvimId;
  final String baslik;
  final String yer;
  final String aciklama;
  final DateTime baslangic;
  final DateTime bitis;
  final bool tumGun;
  final String tekrar;
  final int? hatirlatma;
  final List<Katilimci> katilimcilar;
  final String renk;

  /// Tekrarlanan etkinliğin bu örneği (sunucu genişletmesi).
  final DateTime? tekrarBaslangici;

  /// Gelen bir davetten oluştu (itip dolu).
  final bool davetli;

  factory Etkinlik.json(Object? v) {
    final m = _m(v);
    final h = m['reminder_minutes'];
    final bas = _t(m['starts_at']) ?? DateTime.now();
    return Etkinlik(
      id: _s(m['id']),
      takvimId: _s(m['calendar_id']),
      baslik: _s(m['title']),
      yer: _s(m['location']),
      aciklama: _s(m['description']),
      baslangic: bas,
      bitis: _t(m['ends_at']) ?? bas,
      tumGun: _b(m['all_day']),
      tekrar: _s(m['rrule']),
      hatirlatma: h == null ? null : _i(h),
      katilimcilar: _l(m['attendees']).map(Katilimci.json).toList(),
      renk: _s(m['color']),
      tekrarBaslangici: _t(m['occurrence_start']),
      davetli: m['itip'] != null,
    );
  }

  /// POST/PATCH gövdesi (calEvent alanları + send_invites).
  Map<String, dynamic> govde({bool davetGonder = false}) => {
    if (takvimId.isNotEmpty) 'calendar_id': takvimId,
    'title': baslik.trim(),
    'location': yer.trim(),
    'description': aciklama,
    'starts_at': _utc(baslangic),
    'ends_at': _utc(bitis),
    'all_day': tumGun,
    'rrule': tekrar,
    'reminder_minutes': hatirlatma,
    'attendees': [for (final k in katilimcilar) k.json],
    if (davetGonder) 'send_invites': true,
  };

  /// Gün [g] ile çakışıyor mu (yerel saat)?
  bool gununde(DateTime g) {
    final gb = DateTime(g.year, g.month, g.day);
    final gs = gb.add(const Duration(days: 1));
    final son = tumGun && !bitis.isAfter(baslangic) ? baslangic.add(const Duration(days: 1)) : bitis;
    return baslangic.isBefore(gs) && (son.isAfter(gb) || (son == gb && baslangic == gb));
  }
}

class EtkinlikSonucu {
  EtkinlikSonucu(this.etkinlik, {this.davetGonderildi = false, this.davetHatasi = ''});
  final Etkinlik etkinlik;
  final bool davetGonderildi;
  final String davetHatasi;
}

/// Bir iletideki toplantı daveti (GET /messages/{id}/invite).
class Davet {
  Davet({
    this.yontem = '',
    this.baslik = '',
    this.yer = '',
    this.aciklama = '',
    this.duzenleyen = '',
    this.duzenleyenAd = '',
    this.baslangic,
    this.bitis,
    this.tumGun = false,
    this.tekrarli = false,
    this.katilimcilar = const [],
    this.etkinlikId = '',
    this.yanitim = '',
    this.eskimis = false,
    this.duzenleyenBenim = false,
    this.yanitVeren = '',
    this.yanitDurumu = '',
    this.yanitUygulandi = false,
    this.yanitNotu = '',
  });
  final String yontem; // REQUEST | CANCEL | REPLY
  final String baslik;
  final String yer;
  final String aciklama;
  final String duzenleyen;
  final String duzenleyenAd;
  final DateTime? baslangic;
  final DateTime? bitis;
  final bool tumGun;
  final bool tekrarli;
  final List<Katilimci> katilimcilar;
  final String etkinlikId;
  final String yanitim;
  final bool eskimis;
  final bool duzenleyenBenim;
  final String yanitVeren;
  final String yanitDurumu;
  final bool yanitUygulandi;
  final String yanitNotu;

  factory Davet.json(Object? v) {
    final m = _m(_m(v)['invite']);
    return Davet(
      yontem: _s(m['method']).toUpperCase(),
      baslik: _s(m['title']),
      yer: _s(m['location']),
      aciklama: _s(m['description']),
      duzenleyen: _s(m['organizer']),
      duzenleyenAd: _s(m['organizer_name']),
      baslangic: _t(m['starts_at']),
      bitis: _t(m['ends_at']),
      tumGun: _b(m['all_day']),
      tekrarli: _b(m['recurring']),
      katilimcilar: _l(m['attendees']).map(Katilimci.json).toList(),
      etkinlikId: _s(m['event_id']),
      yanitim: _s(m['my_partstat']),
      eskimis: _b(m['outdated']),
      duzenleyenBenim: _b(m['is_organizer']),
      yanitVeren: _s(m['reply_from']),
      yanitDurumu: _s(m['reply_status']),
      yanitUygulandi: _b(m['reply_applied']),
      yanitNotu: _s(m['reply_note']),
    );
  }
}

const katilimAdlari = {'ACCEPTED': 'Katılıyor', 'TENTATIVE': 'Belki', 'DECLINED': 'Katılmıyor', 'NEEDS-ACTION': 'Yanıt bekleniyor', 'DELEGATED': 'Devretti'};

class TakvimApi {
  TakvimApi._();
  static BogaApi get _api => Uyg.api;
  static const _k = '/api/v1/mail';

  static Future<List<Takvim>> takvimler({void Function(List<Takvim>)? yerel}) =>
      yerelOnce('takvim:liste', () => _api.get('$_k/calendars'), (v) => _ogeler(v).map(Takvim.json).toList(), yerel: yerel);
  static Future<void> takvimOlustur(String ad, String renk) => _api.post('$_k/calendars', {'name': ad.trim(), 'color': renk});
  static Future<void> takvimSil(String id) => _api.delete('$_k/calendars/$id');

  static Future<List<Etkinlik>> etkinlikler(DateTime bas, DateTime son, {void Function(List<Etkinlik>)? yerel}) => yerelOnce(
    'takvim:etk:${_utc(bas)}:${_utc(son)}',
    () => _api.get('$_k/calendar/events', q: {'from': _utc(bas), 'to': _utc(son)}),
    (v) => _ogeler(v).map(Etkinlik.json).toList(),
    yerel: yerel,
  );

  static Future<EtkinlikSonucu> kaydet(Etkinlik e, {bool davetGonder = false}) async {
    final v = _m(
      e.id.isEmpty
          ? await _api.post('$_k/calendar/events', e.govde(davetGonder: davetGonder))
          : await _api.patch('$_k/calendar/events/${e.id}', e.govde(davetGonder: davetGonder)),
    );
    return EtkinlikSonucu(Etkinlik.json(v), davetGonderildi: _b(v['invites_sent']), davetHatasi: _s(v['invite_error']));
  }

  /// [bildir]: düzenleyen, davetlilere iptal gönderir.
  static Future<void> sil(String id, {bool bildir = false}) => _api.delete('$_k/calendar/events/$id', q: {if (bildir) 'notify': '1'});

  static Future<Davet> davet(String iletiId) async => Davet.json(await _api.get('$_k/messages/$iletiId/invite'));

  /// [yanit]: ACCEPTED | TENTATIVE | DECLINED. [yanitsiz]: yalnızca takvime işle, düzenleyene yanıt gönderme.
  static Future<({String etkinlikId, bool yanitlandi, String hata})> davetYanitla(String iletiId, String yanit, {bool yanitsiz = false}) async {
    final v = _m(await _api.post('$_k/messages/$iletiId/invite/respond', {'partstat': yanit, 'no_reply': yanitsiz}));
    return (etkinlikId: _s(v['event_id']), yanitlandi: _b(v['replied']), hata: _s(v['reply_error']));
  }

  static Future<String> iptaliUygula(String iletiId) async {
    final v = _m(await _api.post('$_k/messages/$iletiId/invite/cancel'));
    return _s(v['note']);
  }
}

// ——— Görevler ———

class GorevKisi {
  const GorevKisi({required this.id, this.adres = '', this.ad = ''});
  final String id;
  final String adres;
  final String ad;
  factory GorevKisi.json(Object? v) {
    final m = _m(v);
    return GorevKisi(id: _s(m['id']), adres: _s(m['address']), ad: _s(m['name']));
  }
  String get gorunen => ad.trim().isNotEmpty ? ad.trim() : adres;
}

const gorevDurumAdlari = {'todo': 'Yapılacak', 'doing': 'Sürüyor', 'done': 'Tamamlandı'};
const gorevOncelikAdlari = {'low': 'Düşük', 'normal': 'Normal', 'high': 'Yüksek'};

class Gorev {
  Gorev({
    required this.id,
    this.baslik = '',
    this.notlar = '',
    this.bitis,
    this.oncelik = 'normal',
    this.durum = 'todo',
    this.olusturan,
    this.atanan,
    this.iletiId,
    this.iletiKonu = '',
    this.iletiKimden = '',
    this.yorumSayisi = 0,
    this.olusturma,
    this.guncelleme,
    this.tamamlanma,
    this.duzenleyebilir = false,
  });
  final String id;
  final String baslik;
  final String notlar;
  final DateTime? bitis;
  final String oncelik;
  final String durum;
  final GorevKisi? olusturan;
  final GorevKisi? atanan;
  final String? iletiId;
  final String iletiKonu;
  final String iletiKimden;
  final int yorumSayisi;
  final DateTime? olusturma;
  final DateTime? guncelleme;
  final DateTime? tamamlanma;

  /// Oluşturan her alanı; atanan yalnızca durumu değiştirebilir.
  final bool duzenleyebilir;

  factory Gorev.json(Object? v) {
    final m = _m(v);
    final ileti = m['message'] is Map ? _m(m['message']) : null;
    return Gorev(
      id: _s(m['id']),
      baslik: _s(m['title']),
      notlar: _s(m['notes']),
      bitis: _t(m['due_at']),
      oncelik: _s(m['priority']).isEmpty ? 'normal' : _s(m['priority']),
      durum: _s(m['status']).isEmpty ? 'todo' : _s(m['status']),
      olusturan: m['creator'] is Map ? GorevKisi.json(m['creator']) : null,
      atanan: m['assignee'] is Map ? GorevKisi.json(m['assignee']) : null,
      iletiId: ileti != null && ileti['id'] is String ? ileti['id'] as String : null,
      iletiKonu: ileti == null ? '' : _s(ileti['subject']),
      iletiKimden: ileti == null ? '' : _s(ileti['from']),
      yorumSayisi: _i(m['comments']),
      olusturma: _t(m['created_at']),
      guncelleme: _t(m['updated_at']),
      tamamlanma: _t(m['completed_at']),
      duzenleyebilir: _b(m['can_edit']),
    );
  }

  bool get bitti => durum == 'done';
  bool get gecikti => !bitti && bitis != null && bitis!.isBefore(DateTime.now());
}

class GorevYorumu {
  GorevYorumu({required this.id, this.yazar, this.metin = '', this.tarih});
  final int id;
  final GorevKisi? yazar;
  final String metin;
  final DateTime? tarih;
  factory GorevYorumu.json(Object? v) {
    final m = _m(v);
    return GorevYorumu(id: _i(m['id']), yazar: m['author'] is Map ? GorevKisi.json(m['author']) : null, metin: _s(m['body']), tarih: _t(m['created_at']));
  }
}

class GorevApi {
  GorevApi._();
  static BogaApi get _api => Uyg.api;
  static const _k = '/api/v1/mail/tasks';

  /// [kapsam]: '' (hepsi) | assigned | created; [durum]: open | done | all.
  static Future<List<Gorev>> liste({String kapsam = '', String durum = 'open', String q = '', void Function(List<Gorev>)? yerel}) => yerelOnce(
    q.trim().isEmpty ? 'gorev:$kapsam:$durum' : null,
    () => _api.get(_k, q: {if (kapsam.isNotEmpty) 'scope': kapsam, 'status': durum, if (q.trim().isNotEmpty) 'q': q.trim()}),
    (v) => _ogeler(v).map(Gorev.json).toList(),
    yerel: yerel,
  );

  static Future<List<GorevKisi>> kisiler() async => _ogeler(await _api.get('$_k/people')).map(GorevKisi.json).toList();

  static Future<({Gorev gorev, List<GorevYorumu> yorumlar})> getir(String id) async {
    final v = _m(await _api.get('$_k/$id'));
    return (gorev: Gorev.json(v['task']), yorumlar: _l(v['comments']).map(GorevYorumu.json).toList());
  }

  static Map<String, dynamic> _govde({
    required String baslik,
    required String notlar,
    DateTime? bitis,
    required String oncelik,
    required String durum,
    String? atananId,
  }) => {
    'title': baslik.trim(),
    'notes': notlar,
    'due_at': bitis == null ? null : _utc(bitis),
    'priority': oncelik,
    'status': durum,
    'assignee_id': (atananId == null || atananId.isEmpty) ? null : atananId,
  };

  static Future<Gorev> olustur({
    required String baslik,
    String notlar = '',
    DateTime? bitis,
    String oncelik = 'normal',
    String durum = 'todo',
    String? atananId,
    String? iletiId,
  }) async => Gorev.json(
    await _api.post(_k, {..._govde(baslik: baslik, notlar: notlar, bitis: bitis, oncelik: oncelik, durum: durum, atananId: atananId), 'message_id': ?iletiId}),
  );

  /// Oluşturan için tüm alanlar.
  static Future<void> guncelle(
    String id, {
    required String baslik,
    String notlar = '',
    DateTime? bitis,
    String oncelik = 'normal',
    String durum = 'todo',
    String? atananId,
  }) => _api.patch('$_k/$id', _govde(baslik: baslik, notlar: notlar, bitis: bitis, oncelik: oncelik, durum: durum, atananId: atananId));

  /// Atanan kişi yalnızca durumu değiştirebilir.
  static Future<void> durumDegistir(String id, String durum) => _api.patch('$_k/$id', {'status': durum});
  static Future<void> sil(String id) => _api.delete('$_k/$id');
  static Future<GorevYorumu> yorumla(String id, String metin) async => GorevYorumu.json(await _api.post('$_k/$id/comments', {'body': metin.trim()}));
}
