import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import 'ekranlar/kabuk.dart';

/// Posta uygulamasının tekil durumu.
class Uyg {
  Uyg._();
  static final api = BogaApi(uygulama: 'posta', csrfCerezi: 'bm_mail_csrf');
  static const pushYolu = '/api/v1/mail/app/push';
  static const pushKonu = 'com.bogahost.posta';

  /// Oturumdaki posta kutusu (GET /api/v1/mail/auth/me → mailbox).
  static final kutu = ValueNotifier<Map<String, dynamic>?>(null);

  static String get adres => '${kutu.value?['address'] ?? ''}';
  static String get ad => '${kutu.value?['display_name'] ?? ''}';

  /// Sunucudan kutuyu yükler. Oturum yoksa false.
  static Future<bool> yukle() async {
    if (!await api.oturumVar()) return false;
    try {
      final v = await api.get('/api/v1/mail/auth/me');
      kutu.value = Map<String, dynamic>.from(v['mailbox'] as Map);
      return true;
    } on ApiHata catch (e) {
      if (e.durum == 401 || e.durum == 403) return false;
      rethrow;
    }
  }

  static Widget girisEkrani() => GirisEkrani(
    api: api,
    baslik: 'BogaMail',
    aciklama: 'Kurumsal e-posta hesabınızla giriş yapın',
    girisYolu: '/api/v1/mail/auth/login',
    isaret: AcilisIsaret.posta,
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
      await api.post('/api/v1/mail/auth/logout');
    } catch (_) {}
    await api.cerezleriTemizle();
    kutu.value = null;
    await Push.rozet(0);
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => girisEkrani()), (_) => false);
  }

  /// Sunucu 401 döndürdü: oturum sona ermiş.
  static void oturumDustu() {
    if (kutu.value == null) return;
    kutu.value = null;
    api.cerezleriTemizle();
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => girisEkrani()), (_) => false);
    bildir('Oturum kapandı', mesaj: 'Yeniden giriş yapın.', tur: MesajTur.uyari);
  }
}
