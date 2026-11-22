import 'dart:async';
import 'dart:convert';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ekranlar/hesaplar.dart';
import 'ekranlar/kabuk.dart';
import 'veri/arkaplan.dart';
import 'veri/baglanti.dart';
import 'veri/bildirim.dart';
import 'veri/birlesik.dart';
import 'veri/canli.dart';
import 'veri/durum.dart';
import 'veri/esitleyici.dart';
import 'veri/onbellek.dart';
import 'veri/posta_servisi.dart';
import 'veri/push_kaydi.dart';
import 'veri/sohbet_servisi.dart';
import 'veri/gorev_hatirlatma.dart';

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
  static String get kutuId => '${kutu.value?['mailbox_id'] ?? ''}';

  /// Bir bildirimin hesabı (kutu kimliği, yoksa adres) oturumdaki hesap mı. İkisi de boşsa evet (eski yük).
  static bool buHesapMi({String kutu = '', String adres = ''}) {
    if (kutu.isNotEmpty) return kutu == kutuId;
    if (adres.isNotEmpty) return adresEsit(adres, Uyg.adres);
    return true;
  }

  /// Adres karşılaştırması: büyük/küçük harf ve boşluk duyarsız.
  static bool adresEsit(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();
  static String get ad => '${kutu.value?['display_name'] ?? ''}';

  static const _kutuAnahtari = 'posta.kutu';

  /// Kutuyu yükler. Oturum yoksa false. Soğuk açılışta (önceki oturumun kutusu kayıtlıysa) ağ beklenmez: kabuk
  /// yerel verilerle hemen açılır, kutu sunucudan arkada doğrulanır (çevrimdışıyken de açılır). [ag]: girişten
  /// hemen sonra olduğu gibi sunucudan alınması gerekir.
  static Future<bool> yukle({bool ag = false}) async {
    if (!await api.oturumVar()) return false;
    api.ulasilabilirlik ??= Baglanti.ben.bildir;
    if (!ag && kutu.value == null) {
      final o = await _kayitliKutu();
      final id = '${o?['mailbox_id'] ?? ''}';
      if (o != null && id.isNotEmpty) {
        kutu.value = o;
        await Esitleyici.ben.hesapAc(id);
        unawaited(_kutuTazele(arka: true));
        return true;
      }
    }
    return _kutuTazele(arka: false);
  }

  static Future<Map<String, dynamic>?> _kayitliKutu() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_kutuAnahtari);
      if (s == null) return null;
      final v = jsonDecode(s);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _kutuKaydet(Map<String, dynamic>? m) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (m == null) {
        await p.remove(_kutuAnahtari);
      } else {
        await p.setString(_kutuAnahtari, jsonEncode(m));
      }
    } catch (_) {}
  }

  /// GET auth/me. [arka]: kabuk zaten yerel verilerle açık; bağlantı yoksa sessiz kalınır, oturum düştüyse giriş
  /// ekranına dönülür.
  static Future<bool> _kutuTazele({required bool arka}) async {
    final nesil = _gecisNesli;
    try {
      final v = await api.get('/api/v1/mail/auth/me');
      // Bu arada hesap değiştirildiyse (ör. soğuk açılışta başka hesabın bildirimine dokunuldu) eski yanıt yok sayılır.
      if (arka && nesil != _gecisNesli) return true;
      final m = Map<String, dynamic>.from(v['mailbox'] as Map);
      final eski = '${kutu.value?['mailbox_id'] ?? ''}';
      final yeni = '${m['mailbox_id'] ?? ''}';
      kutu.value = m;
      await _kutuKaydet(m);
      if (arka && eski.isNotEmpty && eski != yeni) {
        // Oturum başka bir kutuya ait (başka yerde hesap değişti): yeni kabuk o hesabın verileriyle açılır.
        await Esitleyici.ben.hesapAc(yeni);
        kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => const Kabuk()), (_) => false);
      } else if (!arka || eski != yeni) {
        unawaited(Esitleyici.ben.hesapAc(yeni));
      }
      return true;
    } on ApiHata catch (e) {
      if (e.durum == 401 || e.durum == 403) {
        if (arka) oturumDustu();
        return false;
      }
      if (arka) return true;
      rethrow;
    }
  }

  static const _k = '/api/v1/mail/auth';

  /// Her hesap geçişinde artar: geçişten önce başlamış bir kutu doğrulaması (auth/me) sonucu yeni kabuğu bozmasın.
  static int _gecisNesli = 0;

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
    Esitleyici.ben.durdur();
    SohbetDurum.ben.sifirla();
    PostaDurum.ben.sifirla();
    BirlesikDurum.ben.sifirla();
  }

  /// Kutuyu yükler ve yeni bir kabuk açar (tüm hesap durumu sıfırlanır: klasörler, listeler, canlı akış, sohbet, push kaydı).
  static Future<void> kabugaGec() async {
    await yukle(ag: true);
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => const Kabuk()), (_) => false);
  }

  /// Şifresiz hesap değiştirme. [adres] verilirse (bildirimden) kimlik listeden bulunur. [hesap] biliniyorsa
  /// (hesap menüsünden) geçiş beklemesizdir: kabuk hedef hesabın önbelleğiyle hemen açılır, açık klasör rolü /
  /// görünüm korunur, sunucu doğrulaması, canlı akış ve push kaydı arka planda yapılır.
  static Future<bool> hesabaGec({String? id, String? adres, KayitliHesap? hesap}) async {
    _gecisNesli++;
    try {
      var hedef = hesap?.id ?? id;
      var h = hesap;
      if (h == null) {
        // Hesap bilgisi (ad, adres) önbellekle hemen açılış için gerekir. Önce kutu kimliği, yoksa adres.
        final l = await hesaplar().catchError((_) => <KayitliHesap>[]);
        h =
            (hedef != null && hedef.isNotEmpty ? l.where((x) => x.id == hedef).firstOrNull : null) ??
            (adres != null && adres.isNotEmpty ? l.where((x) => adresEsit(x.adres, adres)).firstOrNull : null);
        if (h != null) hedef = h.id;
      }
      if (hedef == null || hedef.isEmpty) {
        bekleyenBildirim = null;
        bildir('Hesap bu cihazda bulunamadı', mesaj: adres == null ? null : '$adres hesabıyla yeniden giriş yapın.', tur: MesajTur.uyari);
        return false;
      }
      // Açık yer korunur: klasör rolü (Gelen → Gelen), görünüm ya da birleşik.
      final d = PostaDurum.ben;
      final k = d.konum;
      final rol = k?.tur == KonumTur.klasor ? d.klasor(k!.id)?.rol : null;
      final korunan = k != null && (k.tur == KonumTur.gorunum || k.tur == KonumTur.birlesik) ? k : null;
      await api.post('$_k/switch', {'mailbox_id': hedef});
      _durumuTemizle();
      d
        ..gecisRolu = rol
        ..gecisKonumu = korunan;
      if (h != null) {
        kutu.value = {'mailbox_id': h.id, 'address': h.adres, 'display_name': h.ad, 'avatar_url': ?h.avatarUrl};
        unawaited(_kutuKaydet(kutu.value));
        await Esitleyici.ben.hesapAc(h.id);
        // Hedef hesabın klasörleri ve açılacak liste diskten belleğe alınır: yeni kabuk ilk karede dolu çizilir.
        await _onbellegiIsit(rol, korunan).timeout(const Duration(milliseconds: 400), onTimeout: () {});
        kokGezgin.currentState?.pushAndRemoveUntil(_GecisRotasi(builder: (_) => const Kabuk()), (_) => false);
        // Yeni kabuk (ve iskelesi) çizildikten sonra gösterilir.
        final ileti = '${h.adres} hesabına geçildi';
        final avatar = Avatar(h.ad.isEmpty ? h.adres : h.ad, boyut: 28, tohum: h.adres);
        // Sağ üstte (telefonda üst ortada) hesabın avatarıyla tost kartı.
        WidgetsBinding.instance.addPostFrameCallback((_) => bildir(ileti, onde: avatar));
        // Sunucudaki kutu bilgisi (ad, avatar, izinler) arka planda tazelenir.
        unawaited(yukle().catchError((_) => false));
      } else {
        await kabugaGec();
      }
      return true;
    } catch (e) {
      bekleyenBildirim = null;
      bildir('Hesaba geçilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
      return false;
    }
  }

  static Future<void> _onbellegiIsit(String? rol, Konum? korunan) async {
    try {
      final o = await Posta.klasorlerOnbellek();
      if (o == null) return;
      final f = o.$1.where((x) => x.rol == (rol ?? 'inbox')).firstOrNull ?? o.$1.where((x) => x.rol == 'inbox').firstOrNull;
      final k = korunan ?? (f != null ? Konum.klasor(f.id) : null);
      final a = switch (k?.tur) {
        KonumTur.klasor => Posta.listeAnahtari(klasorId: k!.id),
        KonumTur.gorunum => Posta.listeAnahtari(gorunum: k!.id),
        _ => null,
      };
      if (a != null) await Onbellek.ben.oku(a);
    } catch (_) {}
  }

  /// Hesabı bu cihazdan kaldırır (etkin hesap değilse).
  static Future<void> hesabiKaldir(String id) async {
    await api.delete('$_k/accounts/$id');
    await Esitleyici.ben.hesabiSil(id);
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
    await _kutuKaydet(null);
    _durumuTemizle();
    // Çıkışta hesabın tüm yerel verisi (önbellek, bekleyen değişiklikler, Giden Kutusu) bu cihazdan silinir.
    await Esitleyici.ben.hesabiSil(eski);
    await Bildirim.temizle();
    await GorevHatirlatma.hesapKapandi(eski);
    await Push.rozet(0);
    PushKaydi.sifirla();
    if (sonraki != null && await hesabaGec(id: sonraki)) return;
    // Hesap kalmadı: arka plan hizmeti (Android) durur.
    await Arkaplan.oturumKapandi();
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => girisEkrani()), (_) => false);
  }

  /// Sunucu 401 döndürdü: oturum yok. Boş giriş yerine kayıtlı hesaplar gösterilir. Cihaz çerezi silinmez.
  static void oturumDustu() {
    if (kutu.value == null) return;
    kutu.value = null;
    unawaited(_kutuKaydet(null));
    _durumuTemizle();
    kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => girisEkrani(bilgi: 'Oturum kapandı. Hesabınızı seçin.')), (_) => false);
  }
}

/// Hesap geçişi: kabuk yerinde kalıyormuş gibi kısa bir çapraz geçiş (açılış ekranı / bekleme yok).
class _GecisRotasi<T> extends PageRouteBuilder<T> {
  _GecisRotasi({required WidgetBuilder builder})
    : super(
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (c, _, _) => builder(c),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: child,
        ),
      );
}
