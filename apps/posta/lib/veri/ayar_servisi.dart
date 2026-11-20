// Ayarlar ekranlarının ek uç noktaları (webmail settings-view ile aynı): ham ayarlar + bağlantı bilgisi, kayıtlı
// cihazlar, IMAP taşıma, Apple kurulum profili.

import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';

import '../oturum.dart';

Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _l(Object? v) => v is List ? v : const [];
String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
bool _b(Object? v) => v == true;
DateTime? _t(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

/// GET /mail/settings içindeki sunucu tarafı tercihler (PostaAyarlari'nda olmayanlar) ve bağlantı bilgisi.
class SunucuAyarlari {
  SunucuAyarlari({
    required this.gorunenAd,
    required this.yazmaHtml,
    required this.bildirimMasaustu,
    required this.bildirimSes,
    required this.esitlemeSaniye,
    required this.tema,
    required this.sayfaBoyutu,
    required this.geriAlmaSaniye,
    required this.tatilAcik,
    required this.tatilKonu,
    required this.tatilMetin,
    this.tatilBaslangic,
    this.tatilBitis,
    required this.ozellikler,
    required this.baglanti,
  });

  final String gorunenAd;
  final bool yazmaHtml;
  final bool bildirimMasaustu;
  final bool bildirimSes;
  final int esitlemeSaniye;
  final String tema; // system | light | dark
  final int sayfaBoyutu;
  final int geriAlmaSaniye;
  final bool tatilAcik;
  final String tatilKonu;
  final String tatilMetin;
  final String? tatilBaslangic;
  final String? tatilBitis;
  final Map<String, bool> ozellikler;
  final BaglantiBilgisi baglanti;

  bool ozellik(String ad) => ozellikler[ad] ?? false;

  factory SunucuAyarlari.json(Object? v) {
    final m = _m(v);
    final s = _m(m['settings']);
    String? tarih(Object? x) => x is String && x.isNotEmpty ? x : null;
    return SunucuAyarlari(
      gorunenAd: _s(s['display_name']),
      yazmaHtml: s['compose_html'] == null ? true : _b(s['compose_html']),
      bildirimMasaustu: s['notify_desktop'] == null ? true : _b(s['notify_desktop']),
      bildirimSes: s['notify_sound'] == null ? true : _b(s['notify_sound']),
      esitlemeSaniye: _i(s['sync_seconds']) > 0 ? _i(s['sync_seconds']) : 60,
      tema: const {'light', 'dark', 'system'}.contains(s['theme']) ? s['theme'] as String : 'system',
      sayfaBoyutu: _i(s['page_size']) > 0 ? _i(s['page_size']) : 50,
      geriAlmaSaniye: _i(s['undo_send_seconds']),
      tatilAcik: _b(s['vacation_enabled']),
      tatilKonu: _s(s['vacation_subject']),
      tatilMetin: _s(s['vacation_body']),
      tatilBaslangic: tarih(s['vacation_start']),
      tatilBitis: tarih(s['vacation_end']),
      ozellikler: _m(m['features']).map((k, v) => MapEntry(k, v == true)),
      baglanti: BaglantiBilgisi.json(m['connection']),
    );
  }
}

/// settings.connection: istemci programları için sunucu/port bilgisi (internal/api/imap_status.go mailConnection).
class BaglantiBilgisi {
  BaglantiBilgisi({
    this.sunucu = '',
    this.imapAcik = false,
    this.imapPort = 993,
    this.imapGuvenlik = 'SSL/TLS',
    this.pop3Acik = false,
    this.pop3Port = 995,
    this.pop3Guvenlik = 'SSL/TLS',
    this.smtpAcik = false,
    this.smtpPort = 587,
    this.smtpGuvenlik = 'STARTTLS',
    this.not = '',
    this.kendindenImzali = false,
    this.kisitli = false,
    this.davYolu = '',
  });

  final String sunucu;
  final bool imapAcik;
  final int imapPort;
  final String imapGuvenlik;
  final bool pop3Acik;
  final int pop3Port;
  final String pop3Guvenlik;
  final bool smtpAcik;
  final int smtpPort;
  final String smtpGuvenlik;
  final String not;
  final bool kendindenImzali;
  final bool kisitli;
  final String davYolu;

  factory BaglantiBilgisi.json(Object? v) {
    final m = _m(v);
    int port(String k, int vars) => _i(m[k]) > 0 ? _i(m[k]) : vars;
    String guv(String k, String vars) => _s(m[k]).isEmpty ? vars : _s(m[k]);
    return BaglantiBilgisi(
      sunucu: _s(m['host']),
      imapAcik: _b(m['imap_enabled']),
      imapPort: port('imap_port', 993),
      imapGuvenlik: guv('imap_security', 'SSL/TLS'),
      pop3Acik: _b(m['pop3_enabled']),
      pop3Port: port('pop3_port', 995),
      pop3Guvenlik: guv('pop3_security', 'SSL/TLS'),
      smtpAcik: _b(m['smtp_enabled']),
      smtpPort: port('smtp_port', 587),
      smtpGuvenlik: guv('smtp_security', 'STARTTLS'),
      not: _s(m['host_note']),
      kendindenImzali: _b(m['self_signed']),
      kisitli: _b(m['restricted']),
      davYolu: _s(m['dav_path']),
    );
  }
}

/// GET /mail/security/saved-devices → items[]: bu kutunun "kayıtlı postalarınız" listesinde durduğu tarayıcı/uygulamalar.
class KayitliCihaz {
  KayitliCihaz({required this.id, this.buCihaz = false, this.cikisYapildi = false, this.eklendi, this.sonKullanim, this.tarayici = '', this.ip = ''});
  final String id;
  final bool buCihaz;
  final bool cikisYapildi;
  final DateTime? eklendi;
  final DateTime? sonKullanim;
  final String tarayici;
  final String ip;

  factory KayitliCihaz.json(Object? v) {
    final m = _m(v);
    return KayitliCihaz(
      id: _s(m['id']),
      buCihaz: _b(m['current']),
      cikisYapildi: _b(m['signed_out']),
      eklendi: _t(m['added_at']),
      sonKullanim: _t(m['last_used_at']),
      tarayici: _s(m['user_agent']),
      ip: _s(m['ip']),
    );
  }

  /// "Chrome · Windows" gibi kısa ad (web saved-devices.tsx deviceName ile aynı).
  String get ad {
    final ua = tarayici;
    if (ua.isEmpty) return 'Bilinmeyen cihaz';
    if (RegExp('BogaMail|Dart/', caseSensitive: false).hasMatch(ua)) return 'BogaMail uygulaması';
    final t = ua.contains('Edg/')
        ? 'Edge'
        : ua.contains('OPR/')
        ? 'Opera'
        : ua.contains('Firefox/')
        ? 'Firefox'
        : ua.contains('Chrome/')
        ? 'Chrome'
        : ua.contains('Safari/')
        ? 'Safari'
        : 'Tarayıcı';
    final os = RegExp('iPhone|iPad').hasMatch(ua)
        ? 'iOS'
        : ua.contains('Android')
        ? 'Android'
        : ua.contains('Mac OS X')
        ? 'macOS'
        : ua.contains('Windows')
        ? 'Windows'
        : ua.contains('Linux')
        ? 'Linux'
        : '';
    return os.isEmpty ? t : '$t · $os';
  }
}

/// IMAP taşıma işinin klasör satırı.
class TasimaKlasoru {
  TasimaKlasoru({this.kaynak = '', this.hedef = '', this.durum = 'pending', this.toplam = 0, this.yapilan = 0, this.atlanan = 0, this.hatali = 0});
  final String kaynak;
  final String hedef;
  final String durum; // pending running done failed skipped
  final int toplam;
  final int yapilan;
  final int atlanan;
  final int hatali;

  factory TasimaKlasoru.json(Object? v) {
    final m = _m(v);
    return TasimaKlasoru(
      kaynak: _s(m['source_name']),
      hedef: _s(m['target_name']),
      durum: _s(m['status']),
      toplam: _i(m['messages_total']),
      yapilan: _i(m['messages_done']),
      atlanan: _i(m['messages_skipped']),
      hatali: _i(m['messages_failed']),
    );
  }
}

/// IMAP taşıma işi (lib/migration.ts MigrationJob).
class TasimaIsi {
  TasimaIsi({
    required this.id,
    this.sunucu = '',
    this.port = 993,
    this.guvenlik = 'tls',
    this.kullanici = '',
    this.durum = 'queued',
    this.iptalIstendi = false,
    this.toplam = 0,
    this.yapilan = 0,
    this.atlanan = 0,
    this.hatali = 0,
    this.cokBuyuk = 0,
    this.bayt = 0,
    this.sonHata = '',
    this.olusturuldu,
    this.bitti,
    this.klasorler = const [],
  });

  final String id;
  final String sunucu;
  final int port;
  final String guvenlik;
  final String kullanici;
  final String durum; // queued running paused completed failed cancelled
  final bool iptalIstendi;
  final int toplam;
  final int yapilan;
  final int atlanan;
  final int hatali;
  final int cokBuyuk;
  final int bayt;
  final String sonHata;
  final DateTime? olusturuldu;
  final DateTime? bitti;
  final List<TasimaKlasoru> klasorler;

  bool get etkin => durum == 'queued' || durum == 'running' || durum == 'paused';

  /// İşlenen / toplam (0–100); toplam henüz bilinmiyorsa 0.
  int get yuzde => toplam <= 0 ? 0 : (((yapilan + atlanan + hatali) / toplam) * 100).round().clamp(0, 100);

  factory TasimaIsi.json(Object? v) {
    final m = _m(v);
    return TasimaIsi(
      id: _s(m['id']),
      sunucu: _s(m['source_host']),
      port: _i(m['source_port']),
      guvenlik: _s(m['source_security']),
      kullanici: _s(m['source_username']),
      durum: _s(m['status']),
      iptalIstendi: _b(m['cancel_requested']),
      toplam: _i(m['messages_total']),
      yapilan: _i(m['messages_done']),
      atlanan: _i(m['messages_skipped']),
      hatali: _i(m['messages_failed']),
      cokBuyuk: _i(m['messages_too_large']),
      bayt: _i(m['bytes_done']),
      sonHata: _s(m['last_error']),
      olusturuldu: _t(m['created_at']),
      bitti: _t(m['finished_at']),
      klasorler: _l(m['folders']).map(TasimaKlasoru.json).toList(),
    );
  }
}

/// Sağlayıcı şablonu (internal/migration/presets.go).
class TasimaSablonu {
  TasimaSablonu({
    required this.anahtar,
    required this.ad,
    this.sunucu = '',
    this.port = 993,
    this.guvenlik = 'tls',
    this.yetki = 'password',
    this.oauthDurumu = '',
    this.sifreBasarisiz = false,
    this.kullaniciIpucu = '',
    this.adimlar = const [],
    this.notlar = const [],
  });
  final String anahtar;
  final String ad;
  final String sunucu; // "{domain}" kullanıcı adının alan adıyla değişir
  final int port;
  final String guvenlik;
  final String yetki; // password | app_password | oauth
  final String oauthDurumu;
  final bool sifreBasarisiz;
  final String kullaniciIpucu;
  final List<String> adimlar;
  final List<String> notlar;

  factory TasimaSablonu.json(Object? v) {
    final m = _m(v);
    return TasimaSablonu(
      anahtar: _s(m['key']),
      ad: _s(m['name']),
      sunucu: _s(m['host']),
      port: _i(m['port']) == 143 ? 143 : 993,
      guvenlik: _s(m['security']) == 'starttls' ? 'starttls' : 'tls',
      yetki: _s(m['auth']),
      oauthDurumu: _s(m['oauth_status']),
      sifreBasarisiz: _b(m['password_likely_fails']),
      kullaniciIpucu: _s(m['username_hint']),
      adimlar: _l(m['steps']).map(_s).toList(),
      notlar: _l(m['notes']).map(_s).toList(),
    );
  }

  /// "{domain}" yerine kullanıcı adının alan adı.
  String sunucuIcin(String kullanici) {
    if (!sunucu.contains('{domain}')) return sunucu;
    final at = kullanici.lastIndexOf('@');
    final alan = at >= 0 ? kullanici.substring(at + 1).trim().toLowerCase() : '';
    return sunucu.replaceAll('{domain}', alan);
  }
}

class Ayar {
  Ayar._();
  static BogaApi get _api => Uyg.api;
  static const _k = '/api/v1/mail';

  static Future<SunucuAyarlari> sunucu() async => SunucuAyarlari.json(await _api.get('$_k/settings'));

  /// Kısmi PATCH: gönderilmeyen alanlar değişmez.
  static Future<void> kaydet(Map<String, dynamic> degisen) => _api.patch('$_k/settings', degisen);

  static Future<List<KayitliCihaz>> kayitliCihazlar() async => _l(_m(await _api.get('$_k/security/saved-devices'))['items']).map(KayitliCihaz.json).toList();
  static Future<void> kayitliCihazSil(String id) => _api.delete('$_k/security/saved-devices/$id');

  static Future<({bool acik, TasimaIsi? is_})> tasima() async {
    final m = _m(await _api.get('$_k/migration'));
    return (acik: _b(m['enabled']), is_: m['job'] is Map ? TasimaIsi.json(m['job']) : null);
  }

  static Future<List<TasimaSablonu>> tasimaSablonlari() async => _l(_m(await _api.get('$_k/migration/presets'))['items']).map(TasimaSablonu.json).toList();

  static Future<TasimaIsi> tasimaBaslat({
    required String sunucu,
    required int port,
    required String guvenlik,
    required String kullanici,
    required String sifre,
  }) async => TasimaIsi.json(
    await _api.post('$_k/migration', {'host': sunucu.trim(), 'port': port, 'security': guvenlik, 'username': kullanici.trim(), 'password': sifre}),
  );
  static Future<TasimaIsi> tasimaIptal() async => TasimaIsi.json(await _api.post('$_k/migration/cancel'));
  static Future<TasimaIsi> tasimaDevam() async => TasimaIsi.json(await _api.post('$_k/migration/resume'));

  /// Apple (iPhone/iPad/Mac) kurulum profili; şifre dosyada yoktur, kurulumda sorulur.
  static Future<Uint8List> appleProfili() => _api.indir('$_k/setup/apple.mobileconfig');
}
