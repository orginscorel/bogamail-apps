import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ekranlar/hesaplar.dart';
import 'ekranlar/kabuk.dart';
import 'veri/bildirim.dart';
import 'veri/birlesik.dart';
import 'veri/canli.dart';
import 'veri/durum.dart';
import 'veri/onbellek.dart';
import 'veri/sohbet_servisi.dart';

/// Bu cihazda kayıtlı posta hesabı (GET /api/v1/mail/auth/accounts).
class KayitliHesap {
  const KayitliHesap({required this.id, this.adres = '', this.ad = '', this.avatarUrl, this.etkin = false, this.cikisYapti = false, this.okunmamis = 0});
  final String id;
  final String adres;
  final String ad;
  final String? avatarUrl;
  final bool etkin;
  final bool cikisYapti;
  final int okunmamis;

  factory KayitliHesap.json(Object? v) {
    final m = v is Map ? v : const {};
    final a = m['avatar_url'];
    final u = m['unread'];
    return KayitliHesap(
      id: '${m['id'] ?? ''}',
      adres: '${m['address'] ?? ''}',
      ad: '${m['display_name'] ?? ''}',
      avatarUrl: a is String && a.isNotEmpty ? a : null,
      etkin: m['active'] == true,
      cikisYapti: m['signed_out'] == true,
      okunmamis: u is num ? u.toInt() : 0,
    );
  }

  String get gorunen => ad.trim().isNotEmpty ? ad.trim() : adres;
}

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
      unawaited(Onbellek.ben.hesapAc('${kutu.value?['mailbox_id'] ?? ''}'));
      return true;
    } on ApiHata catch (e) {
      if (e.durum == 401 || e.durum == 403) return false;
      rethrow;
    }
  }

  static const _k = '/api/v1/mail/auth';

  /// Başka hesaba ait bir bildirime dokunuldu: hesap değişince yeni kabuk bunu açar.
  static Map<String, dynamic>? bekleyenBildirim;

  /// Birleşik görünümden yanıt/iletme: hesap değişince yeni kabuk bu iletiyle yazma penceresini açar
  /// (ileti kimliği, tür: yanit | tumu | ilet).
  static (String, String)? bekleyenYazma;

  /// Oturum yokken: kayıtlı hesaplar (varsa) ya da giriş formu.
  static Widget girisEkrani({String? bilgi}) => GirisKapisi(bilgi: bilgi);

  /// Giriş formu. [ekle]: oturum açıkken başka hesap ekleme (geri düğmeli).
  /// [sonra]: başarılı girişten sonra kabuk yerine bu çağrılır (ör. önce mevcut hesabı kaydetme adımı).
  static Widget girisFormu({bool ekle = false, String? adres, Widget? ust, VoidCallback? geri, String? aciklama, Future<void> Function()? sonra}) =>
      GirisEkrani(
        api: api,
        baslik: 'BogaMail',
        aciklama: aciklama ?? (ekle ? 'Bu cihaza başka bir posta hesabı ekleyin' : 'Kurumsal e-posta hesabınızla giriş yapın'),
        girisYolu: '$_k/login',
        isaret: AcilisIsaret.posta,
        kaydetSecenegi: true,
        ilkAdres: adres,
        ust: ust,
        geri: geri,
        girisYapildi: (_) => (sonra ?? kabugaGec)(),
      );

  /// Kayıtlı hesaplar (oturum olmadan da çalışır; bm_mail_device çerezi).
  static Future<List<KayitliHesap>> hesaplar() async {
    final v = await api.get('$_k/accounts');
    final l = v is Map && v['items'] is List ? v['items'] as List : const [];
    return l.map(KayitliHesap.json).where((h) => h.id.isNotEmpty).toList();
  }

  /// Hesaba özgü bellek içi durumu temizler (klasörler, listeler, canlı akış, sohbet).
  static void _durumuTemizle() {
    Canli.ben.durdur();
    SohbetDurum.ben.sifirla();
    PostaDurum.ben.sifirla();
    BirlesikDurum.ben.sifirla();
  }

  /// Kutuyu yükler ve yeni bir kabuk açar (tüm hesap durumu sıfırlanır: klasörler, listeler, canlı akış, sohbet, push kaydı).
  static Future<void> kabugaGec() async {
    await yukle();
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => const Kabuk()), (_) => false);
  }

  /// Şifresiz hesap değiştirme. [adres] verilirse (bildirimden) kimlik listeden bulunur.
  static Future<bool> hesabaGec({String? id, String? adres}) async {
    try {
      var hedef = id;
      if (hedef == null && adres != null) {
        final l = await hesaplar();
        hedef = l.where((h) => h.adres.toLowerCase() == adres.toLowerCase()).firstOrNull?.id;
      }
      if (hedef == null || hedef.isEmpty) return false;
      await api.post('$_k/switch', {'mailbox_id': hedef});
      _durumuTemizle();
      await kabugaGec();
      return true;
    } catch (e) {
      bekleyenBildirim = null;
      bildir('Hesaba geçilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
      return false;
    }
  }

  /// Hesabı bu cihazdan kaldırır (etkin hesap değilse).
  static Future<void> hesabiKaldir(String id) async {
    await api.delete('$_k/accounts/$id');
    await Onbellek.ben.hesabiSil(id);
  }

  /// Çıkış. [unut]: hesabı bu cihazdan da kaldır. Sunucu sıradaki kayıtlı hesabı döndürürse ona geçilir.
  static Future<void> cikis({bool unut = false}) async {
    String? sonraki;
    try {
      final p = await SharedPreferences.getInstance();
      final jeton = p.getString('${api.uygulama}.push');
      final v = await api.post('$_k/logout', {'forget': unut, 'push_token': ?jeton});
      if (v is Map && v['next'] is String && (v['next'] as String).isNotEmpty) sonraki = v['next'] as String;
    } catch (_) {}
    final eski = '${kutu.value?['mailbox_id'] ?? ''}';
    kutu.value = null;
    _durumuTemizle();
    // Unutulan hesabın önbelleği silinir; yalnız çıkışta (kayıtlı kalır) korunur.
    if (unut) await Onbellek.ben.hesabiSil(eski);
    await Bildirim.temizle();
    await Push.rozet(0);
    if (sonraki != null && await hesabaGec(id: sonraki)) return;
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => girisEkrani()), (_) => false);
  }

  /// Sunucu 401 döndürdü: oturum yok. Boş giriş yerine kayıtlı hesaplar gösterilir. Cihaz çerezi silinmez.
  static void oturumDustu() {
    if (kutu.value == null) return;
    kutu.value = null;
    _durumuTemizle();
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => girisEkrani(bilgi: 'Oturum kapandı. Hesabınızı seçin.')), (_) => false);
  }
}
