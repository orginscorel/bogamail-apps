// Kurum içi sohbet: /api/v1/mail/chat/* (internal/api/chat.go, chat_community.go). Alan adları birebir.
// Canlı olaylar posta akışından gelir (chat_message, chat_update, chat_room, chat_read, chat_mention, presence).

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../oturum.dart';
import 'canli.dart';
import 'modeller.dart';

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
bool _b(Object? v) => v == true;
DateTime? _t(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _l(Object? v) => v is List ? v : const [];

/// chatPerson
class SohbetKisi {
  SohbetKisi({
    required this.id,
    this.adres = '',
    this.ad = '',
    this.sonGorulme,
    this.cevrimici = '',
    this.durum = '',
    this.durumMetni = '',
    this.unvan = '',
    this.departman = '',
  });
  final String id;
  final String adres;
  final String ad;
  DateTime? sonGorulme;

  /// online | away | offline | "" (gizli)
  String cevrimici;
  final String durum; // "" available busy meeting out
  final String durumMetni;
  final String unvan;
  final String departman;

  factory SohbetKisi.json(Object? v) {
    final m = _m(v);
    return SohbetKisi(
      id: _s(m['mailbox_id']),
      adres: _s(m['address']),
      ad: _s(m['display_name']),
      sonGorulme: _t(m['last_seen']),
      cevrimici: _s(m['presence']),
      durum: _s(m['status']),
      durumMetni: _s(m['status_text']),
      unvan: _s(m['title']),
      departman: _s(m['department']),
    );
  }

  String get gorunen => ad.trim().isNotEmpty ? ad.trim() : adres;
  String get altBilgi => [unvan, departman].where((s) => s.trim().isNotEmpty).join(' · ');
}

/// Sohbet eki (iletiye bağlı ya da yeni yüklenmiş).
class SohbetEki {
  const SohbetEki({required this.id, this.ad = '', this.boyut = 0, this.tur = '', this.url = '', this.kucukUrl});
  final String id;
  final String ad;
  final int boyut;
  final String tur;
  final String url;

  /// Yalnızca resimlerde.
  final String? kucukUrl;
  bool get resim => tur.startsWith('image/');

  factory SohbetEki.json(Object? v) {
    final m = _m(v);
    final id = _s(m['id']);
    final k = m['thumb_url'];
    return SohbetEki(
      id: id,
      ad: _s(m['name']),
      boyut: _i(m['size']),
      tur: _s(m['content_type']),
      url: _s(m['url']).isEmpty ? '/api/v1/mail/chat/attachments/$id' : _s(m['url']),
      kucukUrl: k is String && k.isNotEmpty ? k : null,
    );
  }
}

/// Tepki (emoji) özeti.
class Tepki {
  const Tepki({required this.emoji, this.sayi = 0, this.benim = false, this.adlar = const []});
  final String emoji;
  final int sayi;
  final bool benim;
  final List<String> adlar;
  factory Tepki.json(Object? v) {
    final m = _m(v);
    return Tepki(emoji: _s(m['emoji']), sayi: _i(m['count']), benim: _b(m['mine']), adlar: _l(m['names']).map(_s).toList());
  }
}

const sikTepkiler = ['👍', '❤️', '😂', '🎉', '😮', '😢', '🙏', '✅'];
const tumTepkiler = [
  '👍', '👎', '❤️', '😂', '😊', '😍', '🎉', '👏', '🙌', '🔥', '💯', '✅', '❌', '👀', '🤔', '😮', '😢', '😡', '🙏', '💪', //
  '🚀', '⭐', '☕', '🍰', '🤝', '👌', '😅', '🥳', '😴', '🤯', '📌', '📎', '⏰', '💡', '⚠️', '❓',
];

/// chatMessage
class SohbetMesaji {
  SohbetMesaji({
    required this.id,
    this.odaId = '',
    this.gonderenId,
    this.gonderenAd = '',
    this.metin = '',
    this.tarih,
    this.duzenlendi,
    this.silindi = false,
    this.benim = false,
    this.ekler = const [],
    this.tepkiler = const [],
  });
  final List<SohbetEki> ekler;
  List<Tepki> tepkiler;
  final int id;
  final String odaId;
  final String? gonderenId;
  final String gonderenAd;
  final String metin;
  final DateTime? tarih;
  final DateTime? duzenlendi;
  final bool silindi;
  final bool benim;

  factory SohbetMesaji.json(Object? v) {
    final m = _m(v);
    final g = m['sender_id'];
    return SohbetMesaji(
      id: _i(m['id']),
      odaId: _s(m['room_id']),
      gonderenId: g is String && g.isNotEmpty ? g : null,
      gonderenAd: _s(m['sender_name']),
      metin: _s(m['body']),
      tarih: _t(m['created_at']),
      duzenlendi: _t(m['edited_at']),
      silindi: _b(m['deleted']),
      benim: _b(m['mine']),
      ekler: _l(m['attachments']).map(SohbetEki.json).toList(),
      tepkiler: _l(m['reactions']).map(Tepki.json).where((t) => t.emoji.isNotEmpty && t.sayi > 0).toList(),
    );
  }
}

/// chatRoom
class SohbetOdasi {
  SohbetOdasi({
    required this.id,
    this.tur = 'direct',
    this.ad = '',
    this.aciklama = '',
    this.varsayilan = false,
    this.yonetebilir = false,
    this.olusturan,
    this.uyeSayisi = 0,
    this.uyeler = const [],
    this.okunmamis = 0,
    this.sonMesaj,
    this.sonTarih,
  });
  final String id;
  final String tur; // direct | group | channel
  final String ad;
  final String aciklama;
  final bool varsayilan;
  final bool yonetebilir;
  final String? olusturan;
  final int uyeSayisi;
  final List<SohbetKisi> uyeler;
  int okunmamis;
  final SohbetMesaji? sonMesaj;
  final DateTime? sonTarih;

  factory SohbetOdasi.json(Object? v) {
    final m = _m(v);
    final o = m['created_by'];
    return SohbetOdasi(
      id: _s(m['id']),
      tur: _s(m['kind']).isEmpty ? 'direct' : _s(m['kind']),
      ad: _s(m['name']),
      aciklama: _s(m['description']),
      varsayilan: _b(m['is_default']),
      yonetebilir: _b(m['can_manage']),
      olusturan: o is String ? o : null,
      uyeSayisi: _i(m['member_count']),
      uyeler: _l(m['members']).map(SohbetKisi.json).toList(),
      okunmamis: _i(m['unread']),
      sonMesaj: m['last_message'] is Map ? SohbetMesaji.json(m['last_message']) : null,
      sonTarih: _t(m['last_message_at']),
    );
  }

  bool get birebir => tur == 'direct';
  bool get kanal => tur == 'channel';

  /// Birebir sohbette karşı taraf (üyelerden kendisi dışındaki).
  SohbetKisi? karsi(String benId) {
    for (final u in uyeler) {
      if (u.id != benId) return u;
    }
    return uyeler.isEmpty ? null : uyeler.first;
  }

  String baslik(String benId) {
    if (birebir) return karsi(benId)?.gorunen ?? 'Sohbet';
    if (ad.trim().isNotEmpty) return kanal ? '# ${ad.trim()}' : ad.trim();
    return uyeler.where((u) => u.id != benId).map((u) => u.gorunen).take(3).join(', ');
  }
}

/// chatChannel
class Kanal {
  Kanal({
    required this.id,
    this.ad = '',
    this.aciklama = '',
    this.varsayilan = false,
    this.arsivli = false,
    this.katildi = false,
    this.uyeSayisi = 0,
    this.olusturanAd = '',
    this.yonetebilir = false,
    this.sonTarih,
  });
  final String id;
  final String ad;
  final String aciklama;
  final bool varsayilan;
  final bool arsivli;
  final bool katildi;
  final int uyeSayisi;
  final String olusturanAd;
  final bool yonetebilir;
  final DateTime? sonTarih;

  factory Kanal.json(Object? v) {
    final m = _m(v);
    return Kanal(
      id: _s(m['id']),
      ad: _s(m['name']),
      aciklama: _s(m['description']),
      varsayilan: _b(m['is_default']),
      arsivli: _b(m['archived']),
      katildi: _b(m['joined']),
      uyeSayisi: _i(m['member_count']),
      olusturanAd: _s(m['creator_name']),
      yonetebilir: _b(m['can_manage']),
      sonTarih: _t(m['last_message_at']),
    );
  }
}

/// GET/PUT /chat/me
class SohbetProfili {
  SohbetProfili({this.cevrimiciGoster = true, this.durum = '', this.durumMetni = '', this.durumBitis, this.cevrimici = '', this.yonetici = false});
  final bool cevrimiciGoster;
  final String durum;
  final String durumMetni;
  final DateTime? durumBitis;
  final String cevrimici;
  final bool yonetici;

  factory SohbetProfili.json(Object? v) {
    final m = _m(v);
    return SohbetProfili(
      cevrimiciGoster: m['show_presence'] == null ? true : _b(m['show_presence']),
      durum: _s(m['status']),
      durumMetni: _s(m['status_text']),
      durumBitis: _t(m['status_until']),
      cevrimici: _s(m['presence']),
      yonetici: _b(m['is_org_admin']),
    );
  }
}

const sohbetDurumAdlari = {'': 'Durum yok', 'available': 'Müsait', 'busy': 'Meşgul', 'meeting': 'Toplantıda', 'out': 'Dışarıda'};

/// Sohbet uç noktaları.
class Sohbet {
  Sohbet._();
  static BogaApi get _api => Uyg.api;
  static const _k = '/api/v1/mail/chat';

  static List<dynamic> _ogeler(Object? v) => _l(_m(v)['items']);

  static Future<List<SohbetOdasi>> odalar() async => _ogeler(await _api.get('$_k/rooms')).map(SohbetOdasi.json).toList();

  /// Bir kişi ve ad yoksa birebir sohbet (varsa mevcut oda döner); aksi hâlde grup.
  static Future<String> odaOlustur(List<String> uyeler, {String ad = ''}) async =>
      _s(_m(await _api.post('$_k/rooms', {'members': uyeler, 'name': ad.trim()}))['id']);

  /// En yeni 100 ileti (eskiden yeniye). [once]: bu kimlikten eskiler; [sonra]: bu kimlikten yeniler.
  static Future<List<SohbetMesaji>> mesajlar(String oda, {int? once, int? sonra}) async {
    final v = await _api.get('$_k/rooms/$oda/messages', q: {'before': ?once, 'after': ?sonra});
    return _ogeler(v).map(SohbetMesaji.json).toList();
  }

  /// [ekler]: önceden yüklenmiş ek kimlikleri (en çok 10); ek varsa metin boş olabilir.
  static Future<SohbetMesaji> gonder(String oda, String metin, {List<String> ekler = const []}) async =>
      SohbetMesaji.json(await _api.post('$_k/rooms/$oda/messages', {'body': metin.trim(), if (ekler.isNotEmpty) 'attachments': ekler}));

  static const azamiEk = 25 * 1024 * 1024;

  /// Çok parçalı yükleme (alan "file"). Virüs bulunursa ApiHata kodu "attachment_virus".
  static Future<SohbetEki> ekYukle(String oda, String ad, Uint8List veri, {void Function(int, int)? ilerleme, CancelToken? iptal}) async {
    final Response<dynamic> c;
    try {
      c = await _api.dio.post<dynamic>(
        '$_k/rooms/$oda/attachments',
        data: FormData.fromMap({'file': MultipartFile.fromBytes(veri, filename: ad)}),
        onSendProgress: ilerleme,
        cancelToken: iptal,
        options: Options(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 2)),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw ApiHata(null, 'Yükleme iptal edildi.', kod: 'iptal');
      throw ApiHata(null, 'Sunucuya ulaşılamıyor. İnternet bağlantınızı kontrol edin.');
    }
    final d = c.statusCode ?? 0;
    if (d >= 200 && d < 300) return SohbetEki.json(c.data);
    if (d == 401) Uyg.oturumDustu();
    final v = c.data;
    final e = v is Map && v['error'] is Map ? Map<String, dynamic>.from(v['error'] as Map) : const <String, dynamic>{};
    final kod = '${e['code'] ?? ''}';
    final mesaj = switch (kod) {
      'attachment_virus' => 'Dosyada virüs bulundu; yüklenmedi.',
      _ when d == 413 => 'Dosya çok büyük (en fazla 25 MB).',
      _ => '${e['message'] ?? 'Dosya yüklenemedi (HTTP $d).'}',
    };
    throw ApiHata(d, mesaj, kod: kod);
  }

  /// Tepkiyi aç/kapat; güncel tepkiler döner.
  static Future<List<Tepki>> tepki(String oda, int mesaj, String emoji) async {
    final v = _m(await _api.post('$_k/rooms/$oda/messages/$mesaj/reactions', {'emoji': emoji}));
    return _l(v['reactions']).map(Tepki.json).where((t) => t.emoji.isNotEmpty && t.sayi > 0).toList();
  }

  /// Ek veya küçük resim baytları (oturum çereziyle).
  static Future<Uint8List> ekIndir(String url, {void Function(int, int)? ilerleme}) {
    final u = Uri.parse(url);
    return _api.indir(u.path, q: u.queryParameters.isEmpty ? null : u.queryParameters, ilerleme: ilerleme);
  }

  static Future<void> okundu(String oda) => _api.post('$_k/rooms/$oda/read');
  static Future<void> mesajSil(String oda, int id) => _api.delete('$_k/rooms/$oda/messages/$id');

  static Future<({List<SohbetKisi> kisiler, bool cevrimiciGorunur})> kisiler({String q = ''}) async {
    final v = _m(await _api.get('$_k/people', q: {if (q.trim().isNotEmpty) 'q': q.trim()}));
    return (kisiler: _l(v['items']).map(SohbetKisi.json).toList(), cevrimiciGorunur: v['presence_visible'] == null ? true : _b(v['presence_visible']));
  }

  static Future<SohbetProfili> ben() async => SohbetProfili.json(await _api.get('$_k/me'));

  /// Yalnızca verilen alanlar değişir.
  static Future<SohbetProfili> benKaydet({bool? cevrimiciGoster, String? durum, String? durumMetni, DateTime? durumBitis, bool bitisGonder = false}) async {
    final g = <String, dynamic>{
      'show_presence': ?cevrimiciGoster,
      'status': ?durum,
      'status_text': ?durumMetni,
      if (bitisGonder) 'status_until': durumBitis?.toUtc().toIso8601String(),
    };
    return SohbetProfili.json(await _api.put('$_k/me', g));
  }

  /// [etkin]: active | idle.
  static Future<void> varlik(bool etkin) => _api.post('$_k/presence', {'state': etkin ? 'active' : 'idle'});

  static Future<({List<Kanal> kanallar, bool hepsiniYonetir})> kanallar() async {
    final v = _m(await _api.get('$_k/channels'));
    return (kanallar: _l(v['items']).map(Kanal.json).toList(), hepsiniYonetir: _b(v['can_manage_all']));
  }

  static Future<String> kanalOlustur(String ad, String aciklama) async =>
      _s(_m(await _api.post('$_k/channels', {'name': ad.trim(), 'description': aciklama.trim()}))['id']);
  static Future<void> kanalGuncelle(String id, {String? ad, String? aciklama, bool? arsiv}) =>
      _api.patch('$_k/channels/$id', {'name': ?ad?.trim(), 'description': ?aciklama?.trim(), 'archived': ?arsiv});
  static Future<void> kanalaKatil(String id) => _api.post('$_k/channels/$id/join');
  static Future<void> kanaldanAyril(String id) => _api.post('$_k/channels/$id/leave');
}

/// Sohbet durumu: oda listesi, toplam okunmamış (alt çubuk rozeti), varlık (çevrimiçi) bildirimi, canlı olaylar.
class SohbetDurum extends ChangeNotifier {
  SohbetDurum._();
  static final ben = SohbetDurum._();

  List<SohbetOdasi> odalar = [];
  bool yuklendi = false;
  String? hata;

  /// Sunucu sohbeti kapalı bildirdi (403 feature_disabled) veya paket özelliği kapalı.
  bool kapali = false;

  /// Okunmamış toplamı; alt çubuk ve kenar menüsü rozeti.
  final okunmamis = ValueNotifier<int>(0);

  /// Şu an ekranda açık oda (okunmamış sayılmaz, bildirim gösterilmez).
  String? acikOda;

  /// Canlı olaylar (oda ekranları kendi odalarını dinler).
  final _olaylar = StreamController<CanliOlay>.broadcast();
  Stream<CanliOlay> get olaylar => _olaylar.stream;

  StreamSubscription<CanliOlay>? _abone;
  Timer? _gecikme;
  Timer? _nabiz;
  Timer? _yoklama;
  bool _etkin = false;

  static String get benId => '${Uyg.kutu.value?['mailbox_id'] ?? ''}';

  /// Kabuk açılınca çağrılır.
  void baslat() {
    _abone ??= Canli.ben.olaylar.listen(_canli);
    _yoklama ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (!Canli.ben.bagli.value && !kapali && _etkin) yenile();
    });
    etkin(true);
    yenile();
  }

  void durdur() {
    _abone?.cancel();
    _abone = null;
    _yoklama?.cancel();
    _yoklama = null;
    _nabiz?.cancel();
    _nabiz = null;
    _gecikme?.cancel();
    _etkin = false;
  }

  /// Uygulama öne geldi / arka plana geçti: varlık bildirimi.
  void etkin(bool v) {
    _etkin = v;
    _nabiz?.cancel();
    _nabiz = null;
    if (kapali) return;
    unawaited(Sohbet.varlik(v).catchError((_) {}));
    if (v) {
      _nabiz = Timer.periodic(const Duration(seconds: 90), (_) => unawaited(Sohbet.varlik(true).catchError((_) {})));
    }
  }

  Future<void> yenile() async {
    try {
      final l = await Sohbet.odalar();
      odalar = l;
      if (acikOda != null) {
        for (final o in odalar.where((o) => o.id == acikOda)) {
          o.okunmamis = 0;
        }
      }
      hata = null;
      kapali = false;
      yuklendi = true;
    } on ApiHata catch (e) {
      if (e.kod == 'feature_disabled' || e.durum == 403 || e.durum == 404) {
        kapali = true;
        _nabiz?.cancel();
      }
      hata = e.mesaj;
      yuklendi = true;
    } catch (_) {
      hata = 'Sohbetler yüklenemedi.';
      yuklendi = true;
    }
    okunmamis.value = odalar.fold(0, (t, o) => t + o.okunmamis);
    notifyListeners();
  }

  void _gecikmeliYenile() {
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(milliseconds: 400), yenile);
  }

  void _canli(CanliOlay o) {
    switch (o.tur) {
      case 'chat_message' || 'chat_update' || 'chat_room' || 'chat_read' || 'chat_mention' || 'chat_reaction':
        _olaylar.add(o);
        _gecikmeliYenile();
      case 'presence':
        _varlikIsle(o.veri);
        _olaylar.add(o);
      case 'chat_profile':
        _olaylar.add(o);
        _gecikmeliYenile();
      case 'changed' when o.veri.isEmpty:
        // yeniden bağlanma: kaçırılanlar için tazele
        _gecikmeliYenile();
    }
  }

  void _varlikIsle(Map<String, dynamic> v) {
    final id = _s(v['mailbox_id']);
    if (id.isEmpty) return;
    var degisti = false;
    for (final oda in odalar) {
      for (final u in oda.uyeler.where((u) => u.id == id)) {
        u.cevrimici = _s(v['presence']);
        if (v['last_seen'] != null) u.sonGorulme = _t(v['last_seen']);
        degisti = true;
      }
    }
    if (degisti) notifyListeners();
  }

  /// Oda açıldı/okundu: yerelde sıfırla ve sunucuya bildir.
  Future<void> okunduIsaretle(String oda) async {
    for (final o in odalar.where((o) => o.id == oda)) {
      o.okunmamis = 0;
    }
    okunmamis.value = odalar.fold(0, (t, o) => t + o.okunmamis);
    notifyListeners();
    try {
      await Sohbet.okundu(oda);
    } catch (_) {}
  }

  /// Hesap değişince / testlerde: tüm sohbet durumunu temizler.
  void sifirla() {
    durdur();
    odalar = [];
    yuklendi = false;
    hata = null;
    kapali = false;
    acikOda = null;
    okunmamis.value = 0;
  }
}

/// Çevrimiçi göstergesi rengi ve metni.
({String metin, bool cevrimici, bool uzakta}) varlikMetni(SohbetKisi k) {
  if (k.cevrimici == 'online') return (metin: 'Çevrimiçi', cevrimici: true, uzakta: false);
  if (k.cevrimici == 'away') return (metin: 'Uzakta', cevrimici: false, uzakta: true);
  if (k.cevrimici == 'offline' && k.sonGorulme != null) return (metin: 'Son görülme ${goreliZaman(k.sonGorulme)}', cevrimici: false, uzakta: false);
  return (metin: k.cevrimici == 'offline' ? 'Çevrimdışı' : '', cevrimici: false, uzakta: false);
}
