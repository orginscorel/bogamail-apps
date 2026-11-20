import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import 'ekranlar/kabuk.dart';
import 'veri/arkaplan.dart';

/// Yönetim uygulamasının tekil durumu.
class Uyg {
  Uyg._();
  /// API istemcisi. Testlerde sahte bir [BogaApi] ile değiştirilebilir.
  static BogaApi api = BogaApi(uygulama: 'yonetim', csrfCerezi: 'bm_csrf');
  static const pushYolu = '/api/v1/app/push';
  static const pushKonu = 'com.bogahost.yonetim';

  /// Oturumdaki panel kullanıcısı (GET /api/v1/auth/me → user). Panel bağlamı: [baglam].
  static final ben = ValueNotifier<Map<String, dynamic>?>(null);

  /// GET /auth/me → context (panel başlığı, özellikler).
  static Map<String, dynamic> baglam = {};

  /// super_admin | reseller_admin | org_admin
  static String get rol => '${ben.value?['role'] ?? ''}';
  static bool get platformYoneticisi => rol == 'super_admin';

  /// Platform ya da bayi yöneticisi (müşterileri yönetir).
  static bool get ortak => rol == 'super_admin' || rol == 'reseller_admin';
  static bool get musteri => rol == 'org_admin';

  /// Panel yetkisi (permissions null = rolün tüm yetkileri; sunucudaki Principal.can ile aynı kural).
  static bool yetki(String izin) {
    final p = ben.value?['permissions'];
    if (p is! List) return true;
    return p.contains(izin);
  }

  /// Müşteri paketinin özelliği açık mı (GET /auth/me → context.organization.features). Müşteri değilse true.
  static bool ozellik(String ad) {
    final o = baglam['organization'];
    if (!musteri || o is! Map) return true;
    final f = o['features'];
    return f is Map && f[ad] == true;
  }

  /// Müşteri / bayi görünümü (yönetici başka bir panele girmiş): GET /auth/me → user.impersonation.
  static Map<String, dynamic>? get taklit {
    final t = ben.value?['impersonation'];
    return t is Map ? Map<String, dynamic>.from(t) : null;
  }

  /// Müşteri paneline / webmail'e girebilir mi (web: canImpersonate): süper yönetici ya da bayi, görünüm içinde değil.
  static bool get girebilir => taklit == null && (rol == 'super_admin' || rol == 'reseller_admin');

  /// Müşterinin paket türü (hosting | gateway | hybrid); müşteri değilse boş.
  static String get paketTuru {
    final o = baglam['organization'];
    return o is Map ? '${o['plan_kind'] ?? ''}' : '';
  }

  /// Panel başlığı: kimin paneli (platform, bayi ya da müşteri adı).
  static String get panelAdi {
    final o = baglam['organization'], r = baglam['reseller'];
    if (o is Map && '${o['name'] ?? ''}'.isNotEmpty) return '${o['name']}';
    if (r is Map && '${r['name'] ?? ''}'.isNotEmpty) return '${r['name']}';
    return platformYoneticisi ? 'Platform yönetimi' : 'Yönetim paneli';
  }

  /// Panel alt başlığı (paket ya da bayi bilgisi).
  static String get panelAlt {
    final o = baglam['organization'], r = baglam['reseller'];
    if (o is Map && '${o['plan_name'] ?? ''}'.isNotEmpty) return '${o['plan_name']} paketi';
    if (r is Map) return 'Bayi paneli · ${r['customers'] ?? 0} müşteri';
    return platformYoneticisi ? 'Tüm platform' : '';
  }

  /// Push bildiriminden açılan alarm olayı (Alarmlar ekranı vurgular ve tüketir).
  static final vurguluAlarm = ValueNotifier<int?>(null);

  static String get adres => '${ben.value?['email'] ?? ''}';
  static String get ad => '${ben.value?['display_name'] ?? ''}';

  /// Sunucudan kullanıcıyı yükler. Oturum yoksa false.
  static Future<bool> yukle() async {
    if (!await api.oturumVar()) return false;
    try {
      final v = await api.get('/api/v1/auth/me');
      ben.value = Map<String, dynamic>.from(v['user'] as Map);
      baglam = v['context'] is Map ? Map<String, dynamic>.from(v['context'] as Map) : {};
      return true;
    } on ApiHata catch (e) {
      if (e.durum == 401 || e.durum == 403) return false;
      rethrow;
    }
  }

  static Widget girisEkrani() => GirisEkrani(
    api: api,
    baslik: 'BogaMail Yönetim',
    aciklama: 'Yönetim paneli hesabınızla giriş yapın',
    girisYolu: '/api/v1/auth/login',
    isaret: AcilisIsaret.yonetim,
    girisYapildi: (c) async {
      final nav = Navigator.of(c);
      await yukle();
      nav.pushAndRemoveUntil(HizliRota(builder: (_) => const Kabuk()), (_) => false);
    },
  );

  /// Çıkış: push kaydını siler, sunucu oturumunu kapatır, çerezleri temizler.
  static Future<void> cikis() async {
    await Push.sil(api, yol: pushYolu);
    await Arkaplan.oturumKapandi();
    try {
      await api.post('/api/v1/auth/logout');
    } catch (_) {}
    await api.cerezleriTemizle();
    ben.value = null;
    await Push.rozet(0);
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => girisEkrani()), (_) => false);
  }

  /// Sunucu 401 döndürdü: oturum sona ermiş.
  static void oturumDustu() {
    if (ben.value == null) return;
    ben.value = null;
    api.cerezleriTemizle();
    Arkaplan.oturumKapandi();
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => girisEkrani()), (_) => false);
    bildir('Oturum kapandı', mesaj: 'Yeniden giriş yapın.', tur: MesajTur.uyari);
  }
}
