// /api/v1/mail/* uç noktalarının ince sarmalayıcısı. JSON biçimleri internal/api/webmail*.go ile birebir.

import 'dart:convert';
import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:dio/dio.dart';

import '../oturum.dart';
import 'modeller.dart';

/// Gönderim/taslak hatası: DLP raporu veya alan bilgisiyle.
class GonderimHatasi implements Exception {
  GonderimHatasi(this.mesaj, {this.kod = '', this.alan, this.dlp});
  final String mesaj;
  final String kod;
  final String? alan;
  final DlpRapor? dlp;
  @override
  String toString() => mesaj;
}

const _gonderimHataMetni = {
  'outbound_disabled': 'Bu sunucuda dış alan adlarına gönderim şu an kapalı. Yalnızca platformdaki posta kutularına gönderebilirsiniz.',
  'unknown_recipient': 'Alıcı posta kutusu bulunamadı. Adresi kontrol edin.',
  'send_limit': 'Saatlik gönderim sınırınıza ulaştınız. Bir süre sonra tekrar deneyin.',
  'daily_limit': 'Paketinizin günlük gönderim sınırına ulaşıldı. Yarın tekrar deneyebilirsiniz.',
  'external_send_disabled': 'Paketiniz veya posta kutusu ayarınız dış alan adlarına gönderime izin vermiyor.',
  'too_many_recipients': 'Bu iletide paketinizin izin verdiğinden fazla alıcı var. Alıcıları birkaç iletiye bölün.',
  'message_too_large': 'İleti, paketinizin izin verdiği boyutu aşıyor. Ekleri küçültün veya azaltın.',
  'temporarily_unavailable': 'İleti şu an kuyruğa alınamadı. Lütfen biraz sonra tekrar deneyin.',
  'quota_exceeded': 'Posta kutunuz dolu; taslak kaydedilemedi. Yer açmak için eski iletileri silin.',
  'outbound_refused': 'İleti gönderilmedi: spam/güvenlik denetiminden geçemedi.',
  'outbound_virus': 'İleti gönderilmedi: ekte virüs veya zararlı yazılım bulundu.',
  'send_blocked': 'Bu posta kutusundan gönderim güvenlik nedeniyle durduruldu. Yöneticinize başvurun.',
  'unavailable': 'Gönderim bu sunucuda şu an kullanılamıyor.',
};

const _adresKodlari = {'outbound_disabled', 'unknown_recipient', 'external_send_disabled'};

String _dogrulamaCevir(String m) {
  final kurallar = <RegExp, String Function(RegExpMatch)>{
    RegExp(r'^Invalid address: (.*)$'): (x) => 'Geçersiz adres: ${x.group(1)}',
    RegExp(r'^At least one recipient is required'): (_) => 'En az bir alıcı ekleyin.',
    RegExp(r'^At most (\d+) recipients'): (x) => 'Bir iletiye en fazla ${x.group(1)} alıcı ekleyebilirsiniz.',
    RegExp(r'^Message too long'): (_) => 'İleti metni çok uzun.',
    RegExp(r'^Invalid attachment encoding'): (_) => 'Bir ek okunamadı; eki kaldırıp yeniden ekleyin.',
    RegExp(r'^Too many attachments'): (_) => 'Çok fazla ek var (en fazla 50).',
    RegExp(r'^Invalid JSON body'): (_) => 'İleti gönderilemeyecek kadar büyük veya bozuk. Ekleri azaltıp tekrar deneyin.',
  };
  for (final e in kurallar.entries) {
    final x = e.key.firstMatch(m);
    if (x != null) return e.value(x);
  }
  return m;
}

class Posta {
  Posta._();
  static BogaApi get _api => Uyg.api;

  // ---- klasörler ve etiketler ----

  static Future<List<Klasor>> klasorler() async {
    final v = await _api.get('/api/v1/mail/folders');
    return ((v is Map ? v['items'] : null) as List? ?? const []).map(Klasor.json).toList();
  }

  static Future<List<Etiket>> etiketler() async {
    final v = await _api.get('/api/v1/mail/labels');
    return ((v is Map ? v['items'] : null) as List? ?? const []).map(Etiket.json).toList();
  }

  static Future<void> klasorOlustur(String ad) => _api.post('/api/v1/mail/folders', {'name': ad});
  static Future<void> klasorAdlandir(String id, String ad) => _api.patch('/api/v1/mail/folders/$id', {'name': ad});
  static Future<void> klasorSil(String id) => _api.delete('/api/v1/mail/folders/$id');
  static Future<int> klasorBosalt(String id) async => _sayi(await _api.post('/api/v1/mail/folders/$id/empty'), 'deleted');
  static Future<int> klasorOkundu(String id) async => _sayi(await _api.post('/api/v1/mail/folders/$id/read'), 'updated');
  static Future<int> hepsiOkundu() async => _sayi(await _api.post('/api/v1/mail/read-all'), 'updated');
  static Future<void> etiketOlustur(String ad, String renk) => _api.post('/api/v1/mail/labels', {'name': ad, 'color': renk});

  static int _sayi(Object? v, String k) => v is Map && v[k] is num ? (v[k] as num).toInt() : 0;

  // ---- liste ----

  /// [klasorId] verilirse klasör listesi; yoksa görünüm (view=all|starred|important|unread|attachments|followup) veya etiket.
  /// [filtre]: unread | flagged | attachments | important. [alan]: from | to | subject (aramayı bu alanla sınırlar).
  /// [baslangic]/[bitis]: YYYY-AA-GG (since/before).
  static Future<Sayfa> liste({
    String? klasorId,
    String gorunum = 'all',
    String? etiketId,
    int sayfa = 1,
    int boyut = 50,
    String? filtre,
    String? arama,
    String? alan,
    String? baslangic,
    String? bitis,
  }) async {
    final q = <String, dynamic>{'page': sayfa, 'page_size': boyut, 'sort': 'date', 'order': 'desc'};
    if (filtre != null) q['filter'] = filtre;
    if (arama != null && arama.trim().isNotEmpty) {
      q['q'] = arama.trim();
      if (alan != null) q['in'] = alan;
    }
    if (baslangic != null) q['since'] = baslangic;
    if (bitis != null) q['before'] = bitis;
    final dynamic v;
    if (klasorId != null) {
      v = await _api.get('/api/v1/mail/folders/$klasorId/messages', q: q);
    } else {
      q['view'] = gorunum;
      if (etiketId != null) q['label'] = etiketId;
      v = await _api.get('/api/v1/mail/messages', q: q);
    }
    return Sayfa.json(v);
  }

  static Future<List<AramaIsleci>> aramaIslecleri() async {
    final v = await _api.get('/api/v1/mail/search/operators');
    return ((v is Map ? v['items'] : null) as List? ?? const []).map(AramaIsleci.json).toList();
  }

  // ---- ileti ----

  static Future<IletiDetay> ileti(String id) async => IletiDetay.json(await _api.get('/api/v1/mail/messages/$id'));

  static Future<void> guncelle(String id, Map<String, dynamic> govde) => _api.patch('/api/v1/mail/messages/$id', govde);

  /// Çöpe taşır; Çöp Kutusu'ndaysa kalıcı siler.
  static Future<void> sil(String id) => _api.delete('/api/v1/mail/messages/$id');

  /// action: read unread flag unflag important unimportant move label unlabel delete spam notspam archive
  static Future<int> toplu(List<String> idler, String eylem, {String? klasorId, String? etiketId}) async {
    var n = 0;
    for (var i = 0; i < idler.length; i += 500) {
      final parca = idler.sublist(i, i + 500 > idler.length ? idler.length : i + 500);
      final govde = <String, dynamic>{'ids': parca, 'action': eylem};
      if (klasorId != null) govde['folder_id'] = klasorId;
      if (etiketId != null) govde['label_id'] = etiketId;
      n += _sayi(await _api.post('/api/v1/mail/messages/bulk', govde), 'updated');
    }
    return n;
  }

  static Future<Uint8List> ekIndir(String iletiId, int sira, {void Function(int, int)? ilerleme}) =>
      _api.indir('/api/v1/mail/messages/$iletiId/parts/$sira', ilerleme: ilerleme);

  /// Uzak görseli sunucu vekili üzerinden alır (gönderen okuyucunun IP'sini görmez). Yalnızca raster görseller.
  static Future<String?> uzakGorselVeri(String url) async {
    try {
      final c = await _api.dio.get<List<int>>(
        '/api/v1/mail/remote-image',
        queryParameters: {'u': url},
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 20)),
      );
      final tur = (c.headers.value('content-type') ?? '').split(';').first.trim().toLowerCase();
      if ((c.statusCode ?? 0) != 200 || !tur.startsWith('image/') || tur.contains('svg') || c.data == null) return null;
      return 'data:$tur;base64,${base64Encode(c.data!)}';
    } catch (_) {
      return null;
    }
  }

  // ---- gönderim ----

  static Future<GonderimSonucu> gonder(Map<String, dynamic> istek, {void Function(int, int)? ilerleme}) async =>
      GonderimSonucu.json(await _yaz('/api/v1/mail/send', istek, ilerleme: ilerleme));

  /// Taslağı kaydeder; yeni taslak kimliğini döndürür (eski taslak sunucuda değiştirilir).
  static Future<String> taslakKaydet(Map<String, dynamic> istek) async {
    final v = await _yaz('/api/v1/mail/drafts', istek);
    return v is Map ? '${v['id'] ?? ''}' : '';
  }

  /// Geri alma süresinde bekleyen gönderimi iptal eder ve taslağa çevirir: taslak kimliği + yazma bilgileri.
  static Future<Map<String, dynamic>> gonderimiGeriAl(String planId) async {
    final v = await _api.post('/api/v1/mail/scheduled/$planId/restore');
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  /// DLP ayrıntıları BogaApi'nin hata nesnesinde taşınmadığından gönderim ham Dio isteğiyle yapılır.
  static Future<dynamic> _yaz(String yol, Map<String, dynamic> govde, {void Function(int, int)? ilerleme}) async {
    final Response<dynamic> c;
    try {
      c = await _api.dio.post<dynamic>(
        yol,
        data: govde,
        onSendProgress: ilerleme,
        options: Options(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 2)),
      );
    } on DioException catch (e) {
      final zaman = e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.sendTimeout || e.type == DioExceptionType.receiveTimeout;
      throw GonderimHatasi(
        zaman ? 'Sunucu zamanında yanıt vermedi. Bağlantınızı kontrol edip tekrar deneyin.' : 'Sunucuya ulaşılamıyor. İnternet bağlantınızı kontrol edin.',
      );
    }
    final d = c.statusCode ?? 0;
    if (d >= 200 && d < 300) return c.data;
    if (d == 401) {
      Uyg.oturumDustu();
      throw GonderimHatasi('Oturumunuz sona erdi. Yeniden giriş yapın.');
    }
    final v = c.data;
    if (v is Map && v['error'] is Map) {
      final e = Map<String, dynamic>.from(v['error'] as Map);
      final kod = '${e['code'] ?? ''}';
      final ham = '${e['message'] ?? ''}';
      if (kod == 'dlp_warning' || kod == 'dlp_blocked') {
        throw GonderimHatasi(ham, kod: kod, dlp: DlpRapor.json(e));
      }
      var metin = _gonderimHataMetni[kod];
      if (metin != null && _adresKodlari.contains(kod)) {
        final i = ham.lastIndexOf(': ');
        if (i >= 0) metin = '$metin (${ham.substring(i + 2)})';
      }
      throw GonderimHatasi(metin ?? _dogrulamaCevir(ham.isEmpty ? 'İleti gönderilemedi (HTTP $d).' : ham), kod: kod, alan: e['field'] as String?);
    }
    if (d == 413) throw GonderimHatasi('İleti gönderilemeyecek kadar büyük. Ekleri azaltıp tekrar deneyin.');
    throw GonderimHatasi(d >= 500 ? 'Sunucuda bir hata oluştu. Tekrar deneyin.' : 'İleti gönderilemedi (HTTP $d).');
  }

  // ---- kişiler ----

  static Future<List<Oneri>> oneriler(String q) async {
    final v = await _api.get('/api/v1/mail/contacts/suggest', q: {'q': q});
    return ((v is Map ? v['items'] : null) as List? ?? const []).map(Oneri.json).toList();
  }

  // ---- ayarlar ----

  static Future<PostaAyarlari> ayarlar() async => PostaAyarlari.json(await _api.get('/api/v1/mail/settings'));

  static Future<void> ayarKaydet(Map<String, dynamic> degisen) => _api.patch('/api/v1/mail/settings', degisen);

  static Future<Map<String, dynamic>> pushBilgi() async {
    final v = await _api.get(Uyg.pushYolu);
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  static Future<void> pushTest() => _api.post('${Uyg.pushYolu}/test');

  /// Kutu bilgisini (kota) tazeler.
  static Future<void> kutuYenile() async {
    try {
      final v = await _api.get('/api/v1/mail/auth/me');
      if (v is Map && v['mailbox'] is Map) Uyg.kutu.value = Map<String, dynamic>.from(v['mailbox'] as Map);
    } catch (_) {}
  }
}
