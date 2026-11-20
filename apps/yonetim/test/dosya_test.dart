import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:yonetim/ekranlar/bolumler.dart';
import 'package:yonetim/ekranlar/dmarc.dart';
import 'package:yonetim/ekranlar/hesap_avatar.dart';
import 'package:yonetim/ekranlar/marka.dart';
import 'package:yonetim/oturum.dart';
import 'package:yonetim/ortak/dosya.dart';

import 'sahte_api.dart';

/// 1×1 PNG.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  late List<(String, String)> secimler;
  setUp(() {
    secimler = [];
    kullaniciAyarla();
  });
  tearDown(() {
    dosyaSecici = ({required String baslik, required List<String> uzantilar, bool coklu = false}) async => const [];
  });

  void secilecek(List<SecilenDosya> l) {
    dosyaSecici = ({required String baslik, required List<String> uzantilar, bool coklu = false}) async {
      secimler.add((baslik, uzantilar.join(',')));
      return l;
    };
  }

  group('güvenli HTML', () {
    test('betikler, olay öznitelikleri, çerçeveler ve yönlendirmeler atılır; CSP uzak içeriği engeller', () {
      final b = guvenliHtmlBelgesi(
        '<p onclick="x()">Merhaba</p><script>alert(1)</script><iframe src="https://kotu.test"></iframe>'
        '<meta http-equiv="refresh" content="0;url=https://kotu.test"><a href="javascript:alert(1)">a</a><img src="https://iz.test/p.gif">',
      );
      expect(b, contains('Merhaba'));
      expect(b, isNot(contains('<script')));
      expect(b, isNot(contains('onclick')));
      expect(b, isNot(contains('<iframe')));
      expect(b, isNot(contains('http-equiv="refresh"')));
      expect(b, isNot(contains('javascript:')));
      expect(b, contains("default-src 'none'"));
      expect(b, contains('img-src data:'));
    });

    testWidgets('web görünümü olmayan ortamda düz metin gösterilir', (t) async {
      await t.pumpWidget(testUygulamasi(const Scaffold(body: HtmlOnizleme(html: '<h1>Başlık</h1><p>Gövde &amp; metin</p>'))));
      expect(find.textContaining('Başlık'), findsOneWidget);
      expect(find.textContaining('Gövde & metin'), findsOneWidget);
    });
  });

  testWidgets('QR kodu çizilir', (t) async {
    await t.pumpWidget(testUygulamasi(const Scaffold(body: Center(child: QrKodu('otpauth://totp/BogaMail:a@b.test?secret=JBSWY3DPEHPK3PXP')))));
    expect(find.bySemanticsLabel('QR kodu'), findsOneWidget);
    expect(find.descendant(of: find.byType(QrKodu), matching: find.byType(CustomPaint)), findsOneWidget);
  });

  test('baytlariKaydet dosyayı yazar ve teslim eder', () async {
    File? teslim;
    String? ad;
    final eski = dosyaTeslimci;
    dosyaTeslimci = (f, a, _) async {
      teslim = f;
      ad = a;
    };
    addTearDown(() => dosyaTeslimci = eski);
    final ok = await baytlariKaydet('bölge/kaydı.zone', utf8.encode('example. IN A 192.0.2.1'));
    expect(ok, isTrue);
    expect(ad, 'bölge_kaydı.zone');
    expect(await teslim!.readAsString(), 'example. IN A 192.0.2.1');
    await teslim!.delete();
  });

  testWidgets('DMARC: dosya seçilir ve base64 olarak yüklenir', (t) async {
    final api = SahteApi({
      'POST /api/v1/dmarc/upload': (Object? g, Object? _) => {
        'stored': 2,
        'files': [
          {'name': 'a.xml', 'reports': []},
          {'name': 'b.zip', 'reports': []},
        ],
      },
    });
    Uyg.api = api;
    secilecek([
      (ad: 'a.xml', bayt: Uint8List.fromList(utf8.encode('<feedback/>'))),
      (ad: 'b.zip', bayt: Uint8List.fromList([80, 75, 3, 4])),
    ]);
    await t.pumpWidget(testUygulamasi(Builder(
      builder: (c) => Scaffold(
        body: Center(child: TextButton(onPressed: () => showDialog<bool>(context: c, builder: (_) => const DmarcYuklemeDialog()), child: const Text('aç'))),
      ),
    )));
    await t.tap(find.text('aç'));
    await t.pumpAndSettle();
    await t.tap(find.text('Dosya seç'));
    await t.pumpAndSettle();
    expect(secimler.single.$2, 'xml,gz,zip');
    expect(find.text('a.xml'), findsOneWidget);
    expect(find.text('b.zip'), findsOneWidget);
    await t.tap(find.text('2 dosyayı yükle'));
    await t.pumpAndSettle();
    final govde = api.istekler.lastWhere((i) => i.$2 == '/api/v1/dmarc/upload').$3! as Map;
    final dosyalar = (govde['files'] as List).cast<Map>();
    expect(dosyalar.map((f) => f['name']), ['a.xml', 'b.zip']);
    expect(base64Decode(dosyalar[1]['data'] as String), [80, 75, 3, 4]);
  });

  testWidgets('Profil resmi: seçilen resim PUT /auth/avatar ile yüklenir', (t) async {
    final api = SahteApi({'PUT /api/v1/auth/avatar': {'has_avatar': true, 'version': '2'}});
    Uyg.api = api;
    secilecek([(ad: 'ben.png', bayt: _png)]);
    await t.pumpWidget(testUygulamasi(const Scaffold(body: Center(child: ProfilResmi()))));
    await t.pumpAndSettle();
    await t.tap(find.byType(ProfilResmi));
    await t.pumpAndSettle();
    await t.tap(find.text('Resim yükle'));
    await t.pumpAndSettle();
    final govde = api.istekler.firstWhere((i) => i.$1 == 'PUT').$3! as Map;
    expect(base64Decode(govde['data'] as String), _png);
    expect(api.istendi('INDIR', '/api/v1/users/u1/avatar'), isTrue);
  });

  testWidgets('Profil resmi müşteri görünümündeyken değiştirilemez', (t) async {
    Uyg.api = SahteApi();
    kullaniciAyarla(taklit: {'kind': 'organization', 'organization_name': 'Örnek'});
    await t.pumpWidget(testUygulamasi(const Scaffold(body: Center(child: ProfilResmi()))));
    await t.pumpAndSettle();
    expect(find.byType(PopupMenuButton<int>), findsNothing);
  });

  testWidgets('Marka: logo yüklenir (PUT …/branding/logo?variant=dark)', (t) async {
    ekranBoyutu(t, const Size(1400, 2200));
    final api = SahteApi({
      'GET /api/v1/organizations/o1/branding': {
        'organization_id': 'o1',
        'enabled': true,
        'product_name': 'Örnek Posta',
        'primary_color': '#0f766e',
        'has_logo': false,
        'has_logo_dark': false,
        'version': '1',
      },
      'GET /api/v1/organizations/o1/login-host': {
        'login_host': {'hostname': '', 'expected_cname': 'posta.ornek.test', 'expected_ips': <String>[]},
        'branding_enabled': true,
      },
      'PUT /api/v1/organizations/o1/branding/logo?variant=dark': {'ok': true},
    });
    Uyg.api = api;
    kullaniciAyarla(rol: 'org_admin');
    Uyg.ben.value = {...Uyg.ben.value!, 'organization_id': 'o1'};
    secilecek([(ad: 'logo.png', bayt: _png)]);
    await t.pumpWidget(testUygulamasi(const MarkaEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Yükle'), findsNWidgets(2));
    await t.tap(find.text('Yükle').last);
    await t.pumpAndSettle();
    final i = api.istekler.firstWhere((i) => i.$1 == 'PUT' && i.$2.contains('/branding/logo'));
    expect(i.$2, '/api/v1/organizations/o1/branding/logo?variant=dark');
    expect(base64Decode((i.$3! as Map)['data'] as String), _png);
  });

  testWidgets('bolumeGit: müşteri kimliğiyle ayrıntı açılır', (t) async {
    ekranBoyutu(t, const Size(1400, 1000));
    final api = SahteApi();
    Uyg.api = api;
    await t.pumpWidget(testUygulamasi(const Scaffold(body: SizedBox())));
    bolumeGit(Bolum.musteriler, musteriId: 'o42');
    await t.pump();
    await t.pumpAndSettle();
    expect(api.istendi('GET', '/api/v1/organizations/o42'), isTrue);
    expect(find.text('Müşteri açılamadı'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
