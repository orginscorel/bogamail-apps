// Yönetici erişimi (sunucu: internal/api/impersonate.go).
//
// Webmail: POST /mailboxes/{id}/webmail-session → {url: "/mail/impersonate#<tek kullanımlık jeton>", expires_in: 60}.
// Jeton 60 saniye geçerlidir ve bir kez kullanılır; adres hemen dış tarayıcıda açılmalıdır. Açılan webmail oturumu
// 30 dakikadır, şifre değiştirilemez, gönderilen her ileti "mail.impersonated_send" olarak denetime yazılır ve kutu
// sahibi erişimi Ayarlar → Güvenlik'te görür.
//
// Panel: POST /organizations/{id}/impersonate {reason ≥ 5 karakter} (ya da /resellers/{id}/impersonate, yalnızca
// süper yönetici, gerekçe isteğe bağlı) yanıtında bm_session/bm_csrf çerezleri değişir (Path=/) ve asıl oturum
// bm_session_orig çerezinde (Path=/api/v1/auth/impersonation) saklanır. Uygulamanın çerez deposu (Dio
// CookieManager) bunları kendiliğinden işler; POST /auth/impersonation/end asıl oturumu geri yükler
// ({restored: true}) ya da çerezleri siler. Görünüm 30 dakika sonra (ya da asıl oturum bitince) düşer;
// görünüm içinde kullanıcı/paket/bayi/IP/kuyruk/ayar değişiklikleri sunucuda 403 impersonation_forbidden döner.

import 'package:boga_ortak/boga_ortak.dart';

import 'json.dart';

/// Webmail erişiminde sunucuya yazılan varsayılan gerekçe (web paneliyle aynı).
const webmailGerekcesi = 'Yönetici panelinden doğrudan giriş';

/// Görünüm içinde yapılamayan işlem hatası mı (sunucu: impersonationBlocked).
bool taklitEngeli(Object e) => e is ApiHata && e.kod == 'impersonation_forbidden';

class Taklit {
  Taklit._();

  /// Webmail için tek kullanımlık giriş adresini alır: `sunucu + url`.
  static Future<Uri> webmailAdresi(BogaApi api, String kutuId, {String gerekce = webmailGerekcesi}) async {
    final v = harita(await api.post('/api/v1/mailboxes/$kutuId/webmail-session', {'reason': gerekce}));
    final yol = metin(v['url']);
    if (!yol.startsWith('/')) throw ApiHata(null, 'Sunucu geçerli bir webmail adresi döndürmedi.');
    return Uri.parse('${api.sunucu.replaceAll(RegExp(r'/+$'), '')}$yol');
  }

  /// Müşteri paneline girer (gerekçe en az 5 karakter). Dönen: müşteri adı.
  static Future<String> musteriyeGir(BogaApi api, String orgId, String gerekce) async {
    final g = gerekce.trim();
    if (g.length < 5) throw ApiHata(400, 'Gerekçe en az 5 karakter olmalı.', alan: 'reason');
    final v = harita(await api.post('/api/v1/organizations/$orgId/impersonate', {'reason': g}));
    return metin(harita(v['organization'])['name']);
  }

  /// Bayi paneline girer (yalnızca süper yönetici). Dönen: bayi adı.
  static Future<String> bayiyeGir(BogaApi api, String bayiId) async {
    final v = harita(await api.post('/api/v1/resellers/$bayiId/impersonate'));
    return metin(harita(v['reseller'])['name']);
  }

  /// Görünümden çıkar. true: asıl yönetici oturumu geri yüklendi; false: oturum kapandı (yeniden giriş gerekir).
  static Future<bool> cik(BogaApi api) async {
    final v = harita(await api.post('/api/v1/auth/impersonation/end'));
    return mantik(v['restored']);
  }
}

/// /auth/me → user.impersonation özetinden banda yazılacak ad.
String taklitAdi(Map<String, dynamic> t) =>
    metin(t['kind']) == 'reseller' ? metin(t['reseller_name'], 'bayi') : metin(t['organization_name'], 'müşteri');
