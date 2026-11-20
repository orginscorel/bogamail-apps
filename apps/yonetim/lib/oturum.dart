import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import 'ekranlar/kabuk.dart';

/// Yönetim uygulamasının tekil durumu.
class Uyg {
  Uyg._();
  static final api = BogaApi(uygulama: 'yonetim', csrfCerezi: 'bm_csrf');
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
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => girisEkrani()), (_) => false);
    bildir('Oturum kapandı', mesaj: 'Yeniden giriş yapın.', tur: MesajTur.uyari);
  }
}
