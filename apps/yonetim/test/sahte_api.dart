import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yonetim/oturum.dart';

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
