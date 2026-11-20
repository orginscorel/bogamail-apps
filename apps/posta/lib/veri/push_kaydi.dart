// APNs cihaz kaydı (iPhone, iPad, Mac): her açılışta, öne gelişte (seyreltilmiş), giriş / hesap ekleme / geçiş /
// "kaydet" sonrasında ve cihaz anahtarı değişince POST /api/v1/mail/app/push yapılır. Sunucu kaydı bu cihazın
// bm_mail_device çerezine bağlar ve aynı anahtarı cihazdaki tüm açık hesaplara dağıtır; bu yüzden kayıttan önce
// /auth/accounts çağrılır (eski oturumlarda çerez yoksa sunucu burada oluşturur). Anahtar günlüğe yazılmaz.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';

import '../oturum.dart';
import 'bildirim_izni.dart';

class PushKaydi {
  PushKaydi._();

  /// Aynı hesap + aynı anahtar için öne gelişlerde en sık bu aralıkla yeniden kaydedilir.
  static const yenilemeAraligi = Duration(hours: 6);

  static String? _son;
  static DateTime? _zaman;
  static Future<bool>? _suren;

  /// Son kaydın sonucu (tanılama): null = başarılı ya da denenmedi.
  static String? sonHata;

  // Testler için değiştirilebilir.
  @visibleForTesting
  static bool Function() destekli = () => Push.destekli;
  @visibleForTesting
  static Future<String?> Function() anahtar = Push.anahtar;
  @visibleForTesting
  static Future<bool> Function() gonder = () => Push.kaydet(Uyg.api, yol: Uyg.pushYolu, konu: Uyg.pushKonu);
  @visibleForTesting
  static DateTime Function() simdi = DateTime.now;

  /// Cihazı bu hesap için kaydeder. [zorla]: seyreltme atlanır (giriş, hesap ekleme, "kaydet").
  /// Aynı anda gelen çağrılar tek isteğe indirgenir.
  static Future<bool> kaydet({bool zorla = false}) {
    if (!destekli()) return Future.value(false);
    return _suren ??= _kaydet(zorla).whenComplete(() => _suren = null);
  }

  static Future<bool> _kaydet(bool zorla) async {
    final t = await anahtar();
    if (t == null || t.isEmpty) {
      sonHata = 'Bildirim izni yok ya da cihaz anahtarı alınamadı';
      BildirimIzni.bildir(izinVar: false);
      return false;
    }
    BildirimIzni.bildir(izinVar: true);
    final adres = Uyg.adres.toLowerCase();
    if (adres.isEmpty) return false;
    final anahtarHesap = '$adres|$t';
    final z = _zaman;
    if (!zorla && _son == anahtarHesap && z != null && simdi().difference(z) < yenilemeAraligi) return true;
    // bm_mail_device çerezi: yoksa sunucu bu çağrıda oluşturur (çoklu hesap dağıtımı için gerekli).
    try {
      await Uyg.api.get('/api/v1/mail/auth/accounts');
    } catch (_) {}
    final ok = await gonder();
    if (ok) {
      _son = anahtarHesap;
      _zaman = simdi();
      sonHata = null;
    } else {
      sonHata = 'Sunucuya kayıt yapılamadı';
    }
    if (kDebugMode) debugPrint('[push] kayıt ${ok ? 'tamam' : 'başarısız'}');
    return ok;
  }

  /// Çıkışta / hesap kaldırılınca: bir sonraki kayıt seyreltilmeden yapılır.
  static void sifirla() {
    _son = null;
    _zaman = null;
  }
}
