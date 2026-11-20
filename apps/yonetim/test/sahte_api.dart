import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yonetim/oturum.dart';
import 'package:yonetim/veri/arkaplan.dart';
import 'package:yonetim/veri/bildirim.dart';

/// Ağa çıkmayan sahte API: yanıtlar "YÖNTEM /yol" anahtarıyla verilir (sorgu parametresi yok sayılır).
/// Yanıt bir fonksiyonsa (gövde, sorgu) ile çağrılır; ApiHata ise fırlatılır. Bilinmeyen yol → 404.
class SahteApi extends BogaApi {
  SahteApi([Map<String, Object?>? yanitlar]) : yanitlar = yanitlar ?? {}, super(uygulama: 'yonetim', csrfCerezi: 'bm_csrf') {
    sunucu = 'https://ornek.test';
  }

  final Map<String, Object?> yanitlar;

  /// Yapılan istekler: (yöntem, yol, gövde, sorgu).
  final istekler = <(String, String, Object?, Map<String, dynamic>?)>[];

  Future<dynamic> _yanit(String y, String yol, Object? govde, Map<String, dynamic>? q) async {
    istekler.add((y, yol, govde, q));
    final anahtar = '$y $yol';
    if (!yanitlar.containsKey(anahtar)) throw ApiHata(404, 'Kayıt bulunamadı.', kod: 'not_found');
    var v = yanitlar[anahtar];
    if (v is Function) v = Function.apply(v, [govde, q]);
    if (v is ApiHata) throw v;
    return v;
  }

  @override
  Future<bool> oturumVar() async => true;
  @override
  Future<dynamic> get(String yol, {Map<String, dynamic>? q}) => _yanit('GET', yol, null, q);
  @override
  Future<dynamic> post(String yol, [Object? govde]) => _yanit('POST', yol, govde, null);
  @override
  Future<dynamic> put(String yol, [Object? govde]) => _yanit('PUT', yol, govde, null);
  @override
  Future<dynamic> patch(String yol, [Object? govde]) => _yanit('PATCH', yol, govde, null);
  @override
  Future<dynamic> delete(String yol, {Object? govde, Map<String, dynamic>? q}) => _yanit('DELETE', yol, govde, q);

  /// Ham indirme: yanıt "INDIR /yol" anahtarıyla bayt listesi olarak verilir; yoksa 404.
  @override
  Future<Uint8List> indir(String yol, {Map<String, dynamic>? q, void Function(int, int)? ilerleme}) async {
    istekler.add(('INDIR', yol, null, q));
    final v = yanitlar['INDIR $yol'];
    if (v is List<int>) return Uint8List.fromList(v);
    throw ApiHata(404, 'Dosya bulunamadı.');
  }

  bool istendi(String yontem, String yol) => istekler.any((i) => i.$1 == yontem && i.$2 == yol);
}

/// Oturumdaki kullanıcıyı ayarlar (rol: super_admin | reseller_admin | org_admin).
void kullaniciAyarla({String rol = 'super_admin', List<String>? izinler, Map<String, dynamic>? baglam, Map<String, dynamic>? taklit}) {
  Uyg.ben.value = {
    'id': 'u1',
    'email': 'yonetici@ornek.test',
    'display_name': 'Deneme Yönetici',
    'role': rol,
    'permissions': izinler,
    'impersonation': ?taklit,
  };
  Uyg.baglam = baglam ?? {};
  Bildirim.platform = SahteBildirimPlatformu();
  Arkaplan.platform = SahteArkaplanPlatformu();
  Bildirim.durum.value = null;
  Bildirim.pilMuaf.value = true;
}

/// Sahte bildirim platformu: izin durumu ve çağrılar test tarafından ayarlanır / okunur.
class SahteBildirimPlatformu extends BildirimPlatformu {
  SahteBildirimPlatformu({this.izin = IzinDurumu.gerekmiyor, this.muaf = true, this.yerelMi = false, this.verilecek = IzinDurumu.verildi});
  IzinDurumu izin;
  bool muaf;
  bool yerelMi;
  IzinDurumu verilecek;
  int izinIstendi = 0, ayarlarAcildi = 0, pilIstendi = 0;
  final gosterilen = <(int, String, String, String)>[];

  @override
  bool get yerel => yerelMi;
  @override
  Future<void> hazirla() async {}
  @override
  Future<String?> baslangic() async => null;
  @override
  Future<IzinDurumu> izinDurumu() async => izin;
  @override
  Future<bool> izinIste() async {
    izinIstendi++;
    izin = verilecek;
    return izin == IzinDurumu.verildi;
  }

  @override
  Future<void> ayarlariAc() async => ayarlarAcildi++;
  @override
  Future<bool> pilMuaf() async => muaf;
  @override
  Future<bool> pilMuafiyetiIste() async {
    pilIstendi++;
    muaf = true;
    return true;
  }

  @override
  Future<void> goster({required int id, required String baslik, required String metin, required String yuk}) async => gosterilen.add((id, baslik, metin, yuk));
}

/// Sahte arka plan platformu (Android hizmeti, girişte başlat, tepsi).
class SahteArkaplanPlatformu extends ArkaplanPlatformu {
  SahteArkaplanPlatformu({this.androidMi = false, this.windowsMi = false});
  bool androidMi, windowsMi;
  bool hizmet = false, girisAcik = false;
  int hizmetBaslatildi = 0, hizmetDurdu = 0;

  @override
  bool get android => androidMi;
  @override
  bool get windows => windowsMi;
  @override
  bool get macos => false;
  @override
  Future<bool> hizmetCalisiyor() async => hizmet;
  @override
  Future<void> hizmetiBaslat() async {
    hizmetBaslatildi++;
    hizmet = true;
  }

  @override
  Future<void> hizmetiDurdur() async {
    hizmetDurdu++;
    hizmet = false;
  }

  @override
  Future<bool> giristeBaslatAcik() async => girisAcik;
  @override
  Future<void> giristeBaslatAyarla(bool acik) async => girisAcik = acik;
  @override
  Future<void> tepsiyiKur({required bool gizliBasla}) async {}
  @override
  void pencereyiGoster() {}
  @override
  void tepsiMetni(String m) {}
}

/// Testlerde kullanılan uygulama sarmalayıcısı (Türkçe yerel ayar, tema, kök gezgin).
Widget testUygulamasi(Widget govde, {Brightness parlaklik = Brightness.light}) {
  kimlikAyarla(Kimlik.yonetim);
  return MaterialApp(
    navigatorKey: kokGezgin,
    scaffoldMessengerKey: kokMesaj,
    theme: temaKur(parlaklik),
    home: govde,
  );
}

/// Ekran boyutunu ayarlar (geniş tablo / telefon kart görünümü için); test sonunda sıfırlanır.
void ekranBoyutu(WidgetTester t, Size s) {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}
