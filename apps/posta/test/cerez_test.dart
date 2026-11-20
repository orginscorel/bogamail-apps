// bm_mail_device çerezi: BogaApi ile aynı kurulum (PersistCookieJar + CookieManager, ignoreExpires: false) üzerinden
// sunucunun gönderdiği biçimle (Secure, HttpOnly, Path=/api/v1/mail, Max-Age 10 yıl, SameSite=Lax) saklanır,
// /api/v1/mail/auth/accounts isteğine gönderilir, uygulama yeniden açılınca (diskten) korunur. Ağ yok.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gerçek sunucu sözleşmesini taklit eder: giriş cihaz çerezi yoksa yenisini verir; /auth/accounts çereze göre listeler.
class _Sunucu implements HttpClientAdapter {
  final kayitli = <String, List<String>>{}; // cihaz → adresler
  final gelenCerezler = <String, String?>{}; // yol → Cookie başlığı
  var sayac = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? govde, Future<void>? iptal) async {
    final cerez = o.headers['cookie'] as String?;
    gelenCerezler[o.uri.path] = cerez;
    final cihaz = RegExp(r'bm_mail_device=([^;]+)').firstMatch(cerez ?? '')?.group(1);
    final basliklar = <String, List<String>>{
      Headers.contentTypeHeader: ['application/json'],
    };
    Object? yanit;
    if (o.uri.path == '/api/v1/mail/auth/login') {
      final g = o.data is String ? jsonDecode(o.data as String) as Map : o.data as Map;
      var c = cihaz;
      final yeni = <String>[];
      if (c == null && g['save'] != false) {
        c = 'cihaz-jetonu-${'x' * 20}-${sayac++}';
        yeni.add('bm_mail_device=$c; Path=/api/v1/mail; Max-Age=315360000; HttpOnly; Secure; SameSite=Lax');
      }
      if (c != null) (kayitli[c] ??= []).add('${g['email']}');
      yeni
        ..add('bm_mail_session=s${sayac++}; Path=/api/v1/mail; Max-Age=2592000; HttpOnly; Secure; SameSite=Lax')
        ..add('bm_mail_csrf=c$sayac; Path=/api/v1/mail; Max-Age=2592000; Secure; SameSite=Lax');
      basliklar['set-cookie'] = yeni;
      yanit = {'ok': true};
    } else if (o.uri.path == '/api/v1/mail/auth/logout') {
      basliklar['set-cookie'] = [
        'bm_mail_session=; Path=/api/v1/mail; Max-Age=0; HttpOnly; Secure; SameSite=Lax',
        'bm_mail_csrf=; Path=/api/v1/mail; Max-Age=0; Secure; SameSite=Lax',
      ];
      yanit = {'next': null};
    } else {
      yanit = {
        'items': [
          for (final a in kayitli[cihaz] ?? const <String>[]) {'address': a},
        ],
      };
    }
    return ResponseBody.fromString(jsonEncode(yanit), 200, headers: basliklar);
  }

  @override
  void close({bool force = false}) {}
}

Dio _istemci(CookieJar jar, _Sunucu s) => Dio(BaseOptions(baseUrl: 'https://posta.ornek.test', validateStatus: (_) => true))
  ..httpClientAdapter = s
  ..interceptors.add(CookieManager(jar));

void main() {
  late Directory dizin;
  setUp(() => dizin = Directory.systemTemp.createTempSync('cerez_'));
  tearDown(() => dizin.deleteSync(recursive: true));

  PersistCookieJar jar() => PersistCookieJar(storage: FileStorage('${dizin.path}/cerezler_posta/'), ignoreExpires: false);

  test('cihaz çerezi saklanır, /auth/accounts isteğine gider, ikinci hesap aynı cihaza eklenir', () async {
    final s = _Sunucu();
    final d = _istemci(jar(), s);
    await d.post('/api/v1/mail/auth/login', data: {'email': 'a@ornek.com', 'password': 'x', 'save': true});
    var l = (await d.get('/api/v1/mail/auth/accounts')).data;
    expect(s.gelenCerezler['/api/v1/mail/auth/accounts'], contains('bm_mail_device='));
    expect((l['items'] as List).length, 1);

    // Hesap ekle: oturum açıkken ikinci giriş aynı cihaz çerezini taşır (yeni cihaz oluşmaz).
    await d.post('/api/v1/mail/auth/login', data: {'email': 'b@ornek.com', 'password': 'y', 'save': true});
    expect(s.gelenCerezler['/api/v1/mail/auth/login'], contains('bm_mail_device='));
    l = (await d.get('/api/v1/mail/auth/accounts')).data;
    expect([for (final h in l['items'] as List) h['address']], ['a@ornek.com', 'b@ornek.com']);

    // Çıkış oturum çerezlerini siler, cihaz çerezi kalır.
    await d.post('/api/v1/mail/auth/logout', data: {'forget': false});
    final kalan = await jar().loadForRequest(Uri.parse('https://posta.ornek.test/api/v1/mail/auth/accounts'));
    expect(kalan.map((c) => c.name), ['bm_mail_device']);

    // Uygulama yeniden açıldı: diskteki kavanozdan aynı liste.
    final d2 = _istemci(jar(), s);
    l = (await d2.get('/api/v1/mail/auth/accounts')).data;
    expect((l['items'] as List).length, 2);
  });

  test('Secure çerez yalnız https ile; yol /api/v1/mail dışına gitmez', () async {
    final j = jar();
    await j.saveFromResponse(Uri.parse('https://posta.ornek.test/api/v1/mail/auth/login'), [
      Cookie.fromSetCookieValue('bm_mail_device=abc${'x' * 20}; Path=/api/v1/mail; Max-Age=315360000; HttpOnly; Secure; SameSite=Lax'),
    ]);
    expect(await j.loadForRequest(Uri.parse('https://posta.ornek.test/api/v1/mail/auth/accounts')), hasLength(1));
    expect(await j.loadForRequest(Uri.parse('https://posta.ornek.test/api/v1/mail')), hasLength(1));
    expect(await j.loadForRequest(Uri.parse('https://posta.ornek.test/api/v1/admin')), isEmpty);
  });
}
