import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/taklit_islemleri.dart';
import 'package:yonetim/oturum.dart';
import 'package:yonetim/veri/taklit.dart';

import 'sahte_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  late SahteApi api;
  late List<Uri> acilan;
  late int yenilendi;

  setUp(() {
    api = SahteApi({
      'POST /api/v1/mailboxes/k1/webmail-session': {'url': '/mail/impersonate#tek-jeton', 'expires_in': 60},
      'POST /api/v1/organizations/o1/impersonate': {'csrf_token': 'x', 'organization': {'id': 'o1', 'name': 'Örnek AŞ'}},
      'POST /api/v1/resellers/b1/impersonate': {'reseller': {'id': 'b1', 'name': 'Bayi Ltd'}},
      'POST /api/v1/auth/impersonation/end': {'restored': true, 'kind': 'organization'},
    });
    Uyg.api = api;
    kullaniciAyarla();
    acilan = [];
    yenilendi = 0;
    adresAc = (u) async {
      acilan.add(u);
      return true;
    };
    kabuguYenile = () async => yenilendi++;
  });

  test('webmail adresi sunucu + url olarak kurulur ve gerekçe gönderilir', () async {
    final u = await Taklit.webmailAdresi(api, 'k1');
    expect(u.toString(), 'https://ornek.test/mail/impersonate#tek-jeton');
    expect(u.fragment, 'tek-jeton');
    expect((api.istekler.single.$3 as Map)['reason'], webmailGerekcesi);
  });

  test('müşteri görünümü gerekçesi en az 5 karakter', () async {
    expect(() => Taklit.musteriyeGir(api, 'o1', 'abc'), throwsA(isA<ApiHata>()));
    expect(api.istekler, isEmpty);
    expect(await Taklit.musteriyeGir(api, 'o1', 'Destek talebi #12'), 'Örnek AŞ');
    expect(await Taklit.cik(api), isTrue);
  });

  test('görünüm engeli tanınır', () {
    expect(taklitEngeli(ApiHata(403, 'x', kod: 'impersonation_forbidden')), isTrue);
    expect(taklitEngeli(ApiHata(403, 'x', kod: 'forbidden')), isFalse);
    expect(taklitAdi({'kind': 'reseller', 'reseller_name': 'B'}), 'B');
    expect(taklitAdi({'kind': 'organization', 'organization_name': 'O'}), 'O');
  });

  testWidgets('Posta kutusuna gir: onay açıklaması, tek kullanımlık adres dış tarayıcıda açılır', (t) async {
    await t.pumpWidget(testUygulamasi(Builder(
      builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => postaKutusunaGir(c, id: 'k1', adres: 'ali@ornek.com'), child: const Text('gir')))),
    )));
    await t.tap(find.text('gir'));
    await t.pumpAndSettle();
    expect(find.textContaining('30 dakika'), findsOneWidget);
    expect(find.textContaining('güvenlik kaydında'), findsOneWidget);
    expect(find.textContaining('şifresi değiştirilemez'), findsOneWidget);
    expect(acilan, isEmpty);
    await t.tap(find.text('Webmail\'i aç'));
    await t.pumpAndSettle();
    expect(api.istendi('POST', '/api/v1/mailboxes/k1/webmail-session'), isTrue);
    expect(acilan.single.toString(), 'https://ornek.test/mail/impersonate#tek-jeton');
  });

  testWidgets('Posta kutusuna gir: vazgeçilirse istek atılmaz', (t) async {
    await t.pumpWidget(testUygulamasi(Builder(
      builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => postaKutusunaGir(c, id: 'k1', adres: 'ali@ornek.com'), child: const Text('gir')))),
    )));
    await t.tap(find.text('gir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();
    expect(api.istekler, isEmpty);
  });

  testWidgets('Müşteri paneline gir: gerekçe ister, gönderir ve kabuğu yeniler', (t) async {
    await t.pumpWidget(testUygulamasi(Builder(
      builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => musteriPanelineGir(c, id: 'o1', ad: 'Örnek AŞ'), child: const Text('gir')))),
    )));
    await t.tap(find.text('gir'));
    await t.pumpAndSettle();
    final dugme = find.widgetWithText(FilledButton, 'Müşteri paneline gir');
    expect(t.widget<FilledButton>(dugme).onPressed, isNull);
    await t.enterText(find.byType(TextField), 'Destek talebi #1234');
    await t.pump();
    await t.tap(dugme);
    await t.pumpAndSettle();
    expect(api.istendi('POST', '/api/v1/organizations/o1/impersonate'), isTrue);
    expect((api.istekler.last.$3 as Map)['reason'], 'Destek talebi #1234');
    expect(yenilendi, 1);
  });

  testWidgets('Görünüm bandı adı gösterir, Çık asıl oturuma döner', (t) async {
    kullaniciAyarla(
      rol: 'org_admin',
      taklit: {'kind': 'organization', 'organization_name': 'Örnek AŞ', 'expires_at': DateTime.now().add(const Duration(minutes: 25)).toUtc().toIso8601String()},
    );
    await t.pumpWidget(testUygulamasi(const Scaffold(body: Column(children: [TaklitBandi()]))));
    expect(find.textContaining('Müşteri panelindesiniz'), findsOneWidget);
    expect(find.textContaining('Örnek AŞ'), findsOneWidget);
    await t.tap(find.text('Çık'));
    await t.pumpAndSettle();
    expect(api.istendi('POST', '/api/v1/auth/impersonation/end'), isTrue);
    expect(yenilendi, 1);
    Uyg.ben.value = null;
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Görünüm süresi dolmadan kendiliğinden çıkılır', (t) async {
    kullaniciAyarla(
      rol: 'org_admin',
      taklit: {'kind': 'organization', 'organization_name': 'Örnek AŞ', 'expires_at': DateTime.now().add(const Duration(seconds: 25)).toUtc().toIso8601String()},
    );
    await t.pumpWidget(testUygulamasi(const Scaffold(body: Column(children: [TaklitBandi()]))));
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(api.istendi('POST', '/api/v1/auth/impersonation/end'), isTrue);
    Uyg.ben.value = null;
    await t.pumpWidget(const SizedBox());
  });
}
