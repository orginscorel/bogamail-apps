// Önce yerel / çevrimdışı çalışma: önbellekten ağsız soğuk açılış (<100 ms), hata ekranı yok, "Çevrimdışı — son
// eşitleme" göstergesi; çevrimdışı değişikliklerin iyimser uygulanması, kalıcı kuyruğu ve bağlantı gelince sırayla
// gönderilmesi (404 düşer); Giden Kutusu (düzenle / sil / otomatik gönderim / hata + Tekrar dene); çıkışta yerel
// verinin silinmesi. Ağ yok (sahte sunucu; "çevrimdışı" bağlantı hatası olarak benzetilir).

import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/giden_kutusu.dart';
import 'package:posta/ekranlar/kabuk.dart';
import 'package:posta/ekranlar/okuyucu.dart';
import 'package:posta/ekranlar/yazma.dart';
import 'package:posta/ortak/esitleme.dart';
import 'package:posta/ortak/iskelet.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/baglanti.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/esitleyici.dart';
import 'package:posta/veri/kuyruk.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/onbellek.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:posta/veri/posta_servisi.dart';
import 'package:posta/veri/yazma_hazirla.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

const _klasorler = {
  'items': [
    {'id': 'f1', 'name': 'INBOX', 'role': 'inbox', 'unseen': 2, 'total': 3},
    {'id': 'f2', 'name': 'Sent', 'role': 'sent', 'unseen': 0, 'total': 0},
  ],
};

Map<String, dynamic> _liste() => {
  'items': [
    for (final (id, konu, okundu) in [('a', 'Teklif hazır', false), ('b', 'Toplantı notları', true), ('c', 'Fatura', false)])
      {'id': id, 'folder_id': 'f1', 'subject': konu, 'from': 'Ali <ali@a.com>', 'date': '2026-11-20T09:00:00Z', 'seen': okundu},
  ],
  'total': 3,
  'page': 1,
  'page_size': 50,
};

Map<String, dynamic> _ileti(String id) => {
  'message': {'id': id, 'subject': 'Teklif hazır', 'from': 'Ali <ali@a.com>', 'seen': false, 'folder_id': 'f1'},
  'view': {
    'subject': 'Teklif hazır',
    'from': [
      {'name': 'Ali', 'email': 'ali@a.com'},
    ],
    'to': [],
    'cc': [],
    'reply_to': [],
    'date': '2026-11-19T10:00:00Z',
    'text': 'Fiyat ekte, çevrimdışı da okunur.',
    'html': '',
    'attachments': [],
  },
};

void main() {
  late Directory kok;
  final s = YolSunucusu();
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Onyukleme.etkin = false;
    SharedPreferences.setMockInitialValues({});
    s.kur();
    Uyg.api.ulasilabilirlik = Baglanti.ben.bildir;
  });
  setUp(() {
    kok = Directory.systemTemp.createTempSync('cevrimdisi_');
    Onbellek.kok = () async => kok;
    Onbellek.ben.testSifirla();
    IslemKuyrugu.ben.sifirla();
    GidenKutusu.ben.sifirla();
    Baglanti.ben.testSifirla();
    PostaDurum.ben.sifirla();
    s
      ..cevrimdisi = false
      ..istekler.clear()
      ..yollar.clear();
  });
  tearDown(() {
    Onbellek.ben.testSifirla();
    kok.deleteSync(recursive: true);
  });

  /// Çevrimiçiyken bir kez eşitlenmiş hesap: klasörler, Gelen listesi, bir ileti diskte.
  Future<void> esitlenmisHesap() async {
    s.yollar
      ..['GET /api/v1/mail/folders'] = (200, _klasorler)
      ..['GET /api/v1/mail/labels'] = (200, {'items': []})
      ..['GET /api/v1/mail/folders/f1/messages'] = (200, _liste())
      ..['GET /api/v1/mail/messages/a'] = (200, _ileti('a'));
    await Esitleyici.ben.hesapAc('m1');
    await Posta.klasorler();
    await Posta.etiketler();
    await Posta.liste(klasorId: 'f1');
    await Posta.iletiHam('a');
    await Baglanti.ben.esitlendi(DateTime(2026, 11, 21, 14, 32));
    await Future<void>.delayed(const Duration(milliseconds: 700)); // dizin indeksi yazılır
  }

  /// Uygulama kapanıp açıldı: bellek boş, yalnız disk.
  Future<void> yenidenAc() async {
    Onbellek.ben.testSifirla();
    IslemKuyrugu.ben.sifirla();
    GidenKutusu.ben.sifirla();
    Baglanti.ben.testSifirla();
    PostaDurum.ben.sifirla();
  }

  testWidgets('soğuk açılış ağsız: Gelen ve ileti önbellekten <100 ms, döner simge / hata yok, "Çevrimdışı — son eşitleme 14:32"', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(esitlenmisHesap);
    await t.runAsync(yenidenAc);
    s.cevrimdisi = true;
    Uyg.kutu.value = {'mailbox_id': 'm1', 'address': 'ben@ornek.com', 'display_name': 'Ben'};

    // Soğuk açılışın veri yolu (disk → bellek: hesap, klasörler, Gelen listesi, ileti) gerçek zamanla ölçülür.
    late int sure;
    await t.runAsync(() async {
      final sw = Stopwatch()..start();
      await Esitleyici.ben.hesapAc('m1');
      await PostaDurum.ben.yukle();
      final l = await Posta.listeOnbellek(Posta.listeAnahtari(klasorId: 'f1')!);
      final d = await Posta.iletiOnbellek('a');
      sure = sw.elapsedMilliseconds;
      expect(l!.ogeler, hasLength(3));
      expect(d!.gorunum.metin, contains('çevrimdışı'));
    });
    // ignore: avoid_print
    print('[posta-süre] soğuk açılış (önbellek, ağ yok): $sure ms');
    expect(sure, lessThan(100), reason: 'Gelen + ileti önbellekten 100 ms altında');
    expect(PostaDurum.ben.hata, isNull, reason: 'çevrimdışında hata yok, önbellekten açıldı');
    expect(Baglanti.ben.cevrimdisi.value, isTrue);

    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), navigatorKey: kokGezgin, scaffoldMessengerKey: kokMesaj, home: const Kabuk()));
    await t.pump();
    // İlk karelerde liste dolu: iskelet / döner simge yok.
    expect(find.text('Teklif hazır'), findsOneWidget);
    expect(find.byType(ListeIskeleti), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 50));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(find.text('Teklif hazır'), findsOneWidget);
    expect(find.textContaining('Sunucuya ulaşılamıyor'), findsNothing);
    // Geniş ekranda sol raydaki eşitleme noktası kırmızı; ipucunda "Çevrimdışı — son eşitleme 14:32".
    expect(find.byKey(const ValueKey('ray-esitleme-cevrimdisi')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('Çevrimdışı — son eşitleme 14:32')), findsOneWidget);
    // Önbellekteki ileti de ağsız açılır.
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        home: const Scaffold(body: Okuyucu(id: 'a')),
      ),
    );
    expect(find.text('Fiyat ekte, çevrimdışı da okunur.'), findsOneWidget, reason: 'ilk karede');
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Fiyat ekte, çevrimdışı da okunur.'), findsOneWidget);
    expect(find.textContaining('ulaşılamıyor'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 70));
  });

  test('cevrimdisiMetni', () {
    final simdi = DateTime(2026, 11, 21, 15);
    expect(cevrimdisiMetni(DateTime(2026, 11, 21, 14, 32), simdi), 'Çevrimdışı — son eşitleme 14:32');
    expect(cevrimdisiMetni(DateTime(2026, 11, 19, 9, 5), simdi), 'Çevrimdışı — son eşitleme 19 Kas 09:05');
    expect(cevrimdisiMetni(null, simdi), 'Çevrimdışı — henüz eşitlenmedi');
  });

  test('çevrimdışı değişiklikler: iyimser + önbelleğe işlenir, kalıcı kuyruk, bağlantı gelince sırayla; 404 sessizce düşer', () async {
    await esitlenmisHesap();
    s.cevrimdisi = true;
    // Hiçbiri hata atmaz (arayüz iyimser kalır).
    await Posta.guncelle('a', {'seen': true});
    await Posta.toplu(['b'], 'archive');
    await Posta.sil('c');
    expect(IslemKuyrugu.ben.ogeler.value.map((i) => i.aciklama), ['Okundu işaretle (1 ileti)', 'Arşivle (1 ileti)', 'Sil (1 ileti)']);
    expect(bekleyenMetni(), '3 değişiklik eşitlenmeyi bekliyor');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Önbellekteki liste: a okundu, b ve c listeden çıktı (yeniden açılışta da).
    final l = (await Posta.listeOnbellek('liste:k:f1'))!;
    expect(l.ogeler.map((m) => (m.id, m.okundu)), [('a', true)]);
    expect((await Posta.iletiOnbellek('a'))!.ozet.okundu, isTrue);

    // Uygulama kapanıp açıldı: kuyruk diskte.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await yenidenAc();
    await Esitleyici.ben.hesapAc('m1');
    expect(IslemKuyrugu.ben.ogeler.value, hasLength(3));

    // Bağlantı geldi: aynı sırayla gönderilir; c başka yerde silinmiş (404) → düşer.
    s.istekler.clear();
    s
      ..cevrimdisi = false
      ..yollar['PATCH /api/v1/mail/messages/a'] = (200, {'ok': true})
      ..yollar['POST /api/v1/mail/messages/bulk'] = (200, {'updated': 1});
    Esitleyici.ben.baslat(); // testte yalnız "bağlantı geldi" dinleyicisi
    Baglanti.ben.bildir(false);
    Baglanti.ben.bildir(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await IslemKuyrugu.ben.oynat();
    expect(s.istekler.map((i) => '$i'), ['PATCH /api/v1/mail/messages/a', 'POST /api/v1/mail/messages/bulk', 'DELETE /api/v1/mail/messages/c']);
    expect(s.istekler.first.json, {'seen': true});
    expect(s.istekler[1].json, {
      'ids': ['b'],
      'action': 'archive',
    });
    expect(IslemKuyrugu.ben.bos, isTrue);
  });

  test('kuyruk: sunucu hatası (5xx) ya da bağlantı yoksa durur, sıra korunur; kuyruk doluyken yeni değişiklik de sıraya girer', () async {
    await Esitleyici.ben.hesapAc('m1');
    s.cevrimdisi = true;
    await Posta.guncelle('a', {'flagged': true});
    s.cevrimdisi = false;
    s.yollar['PATCH /api/v1/mail/messages/a'] = (503, null);
    // Önünde bekleyen varken yeni değişiklik doğrudan gitmez (sıra bozulmaz).
    s.yollar['PATCH /api/v1/mail/messages/b'] = (200, {'ok': true});
    await Posta.guncelle('b', {'seen': true});
    await IslemKuyrugu.ben.oynat();
    expect(IslemKuyrugu.ben.ogeler.value.map((i) => i.yol), ['/api/v1/mail/messages/a', '/api/v1/mail/messages/b']);
    expect(s.bul('PATCH', '/api/v1/mail/messages/b'), isEmpty);
    s.istekler.clear();
    s.yollar['PATCH /api/v1/mail/messages/a'] = (200, {'ok': true});
    await IslemKuyrugu.ben.oynat();
    expect(IslemKuyrugu.ben.bos, isTrue);
    expect(s.istekler.map((i) => i.yol.split('/').last), ['a', 'b']);
  });

  Map<String, dynamic> istek(String konu) => {
    'to': ['Ali <ali@ornek.com>'],
    'cc': [],
    'bcc': [],
    'subject': konu,
    'text': 'Merhaba',
    'html': '',
    'attachments': [
      {'filename': 'teklif.pdf', 'content_type': 'application/pdf', 'data': 'JVBERi0xLjQK'},
    ],
  };

  test('Giden Kutusu: ekleriyle kalıcı, çevrimdışı bekler, bağlantı gelince sırayla gönderilir (sonra listeden çıkar)', () async {
    await Esitleyici.ben.hesapAc('m1');
    s.cevrimdisi = true;
    await GidenKutusu.ben.ekle(istek('Birinci'));
    await GidenKutusu.ben.ekle(istek('İkinci'));
    await GidenKutusu.ben.gonder();
    expect(GidenKutusu.ben.ogeler.value.map((o) => (o.konu, o.durum, o.ekSayisi)), [('Birinci', GidenDurum.bekliyor, 1), ('İkinci', GidenDurum.bekliyor, 1)]);
    expect(bekleyenMetni(), '2 ileti gönderilmeyi bekliyor');
    // Kapanıp açıldı: ekleriyle birlikte diskte.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await yenidenAc();
    await Esitleyici.ben.hesapAc('m1');
    expect(GidenKutusu.ben.ogeler.value, hasLength(2));
    var gonderildi = 0;
    GidenKutusu.gonderildi = () => gonderildi++;
    addTearDown(() => GidenKutusu.gonderildi = null);
    s
      ..istekler.clear()
      ..cevrimdisi = false
      ..yollar['POST /api/v1/mail/send'] = (200, {'queued': true});
    Esitleyici.ben.baslat();
    Baglanti.ben.bildir(false);
    Baglanti.ben.bildir(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await GidenKutusu.ben.gonder();
    final g = s.bul('POST', '/api/v1/mail/send').toList();
    expect(g.map((i) => i.json['subject']), ['Birinci', 'İkinci']);
    expect((g.first.json['attachments'] as List).single, containsPair('data', 'JVBERi0xLjQK'));
    expect(GidenKutusu.ben.ogeler.value, isEmpty);
    expect(gonderildi, 2);
    expect(Onbellek.ben.anahtarlar('kalici:giden:'), isEmpty, reason: 'gönderilen içerik yerelden silinir');
  });

  test('Giden Kutusu: her ileti kalıcı Idempotency-Key ile gider; bağlantı kopup yeniden denenince aynı anahtar', () async {
    await Esitleyici.ben.hesapAc('m1');
    await GidenKutusu.ben.ekle(istek('Tek sefer'));
    s
      ..istekler.clear()
      ..cevrimdisi = true;
    await GidenKutusu.ben.gonder();
    expect(GidenKutusu.ben.ogeler.value.single.durum, GidenDurum.bekliyor);
    s
      ..cevrimdisi = false
      ..yollar['POST /api/v1/mail/send'] = (200, {'queued': true});
    await GidenKutusu.ben.gonder();
    final g = s.bul('POST', '/api/v1/mail/send').toList();
    final anahtarlar = g.map((i) => '${i.basliklar['Idempotency-Key'] ?? i.basliklar['idempotency-key']}').toSet();
    expect(anahtarlar, hasLength(1));
    expect(anahtarlar.single, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(g.last.json.containsKey('_idem'), isFalse, reason: 'anahtar gövdeye girmez');
    expect(GidenKutusu.ben.ogeler.value, isEmpty);
  });

  test('Giden Kutusu: sonucu belirsiz önceki deneme (409 send_unknown) tekrar gönderilmez, açıklamalı Hata olur', () async {
    await Esitleyici.ben.hesapAc('m1');
    s.yollar['POST /api/v1/mail/send'] = (
      409,
      {
        'error': {'code': 'send_unknown', 'message': 'outcome unknown'},
      },
    );
    await GidenKutusu.ben.ekle(istek('Belirsiz'));
    await GidenKutusu.ben.gonder();
    final o = GidenKutusu.ben.ogeler.value.single;
    expect(o.durum, GidenDurum.hata);
    expect(o.hata, contains('Gönderilenler'));
  });

  test('Giden Kutusu: sunucu reddederse "Hata: neden", Tekrar dene ile yeniden gönderilir', () async {
    await Esitleyici.ben.hesapAc('m1');
    s.yollar['POST /api/v1/mail/send'] = (
      422,
      {
        'error': {'code': 'validation', 'message': 'Alıcı adresi geçersiz'},
      },
    );
    await GidenKutusu.ben.ekle(istek('Hatalı'));
    await GidenKutusu.ben.gonder();
    final o = GidenKutusu.ben.ogeler.value.single;
    expect(o.durum, GidenDurum.hata);
    expect(o.hata, contains('geçersiz'));
    s.yollar['POST /api/v1/mail/send'] = (200, {'queued': true});
    await GidenKutusu.ben.tekrarDene(o.id);
    expect(GidenKutusu.ben.ogeler.value, isEmpty);
  });

  test('Giden Kutusu: düzenlenirken gönderilmez; düzenlenen öğenin yerine geçer; silinen gitmez', () async {
    await Esitleyici.ben.hesapAc('m1');
    s.cevrimdisi = true;
    final id = await GidenKutusu.ben.ekle({
      ...istek('Taslak hâli'),
      'cc': ['Can <can@ornek.com>'],
      'reply_to_id': 'r1',
    });
    final sil = await GidenKutusu.ben.ekle(istek('Vazgeçilen'));
    final c = (await GidenKutusu.ben.icerik(id))!;
    final b = gidenHazirla(id, c.$1, c.$2);
    expect(b.konu, 'Taslak hâli');
    expect(b.kime.single.eposta, 'ali@ornek.com');
    expect(b.bilgi.single.eposta, 'can@ornek.com');
    expect(b.yanitlananId, 'r1');
    expect(b.yerelEkler.single, ('teklif.pdf', 'JVBERi0xLjQK'));
    expect(b.gidenId, id);

    GidenKutusu.ben.duzenlemeBasla(id);
    await GidenKutusu.ben.sil(sil);
    s
      ..cevrimdisi = false
      ..yollar['POST /api/v1/mail/send'] = (200, {'queued': true});
    await GidenKutusu.ben.gonder();
    expect(s.bul('POST', '/api/v1/mail/send'), isEmpty, reason: 'düzenlenen gönderilmez, silinen hiç gitmez');
    // Düzenleme bitti (yeniden kuyruğa): eskisinin yerine geçer, sonra gider.
    s.cevrimdisi = true;
    final yeni = await GidenKutusu.ben.ekle({...c.$1, 'subject': 'Düzeltilmiş'}, eskiId: id);
    expect(GidenKutusu.ben.ogeler.value.map((o) => o.konu), ['Düzeltilmiş']);
    expect(await GidenKutusu.ben.icerik(id), isNull);
    s.cevrimdisi = false;
    await GidenKutusu.ben.gonder();
    expect(s.bul('POST', '/api/v1/mail/send').single.json['subject'], 'Düzeltilmiş');
    expect(GidenKutusu.ben.ogeler.value.where((o) => o.id == yeni), isEmpty);
  });

  testWidgets('Giden Kutusu ekranı: durumlar (Bekliyor / Hata + Tekrar dene), sil', (t) async {
    await t.runAsync(() async {
      await Esitleyici.ben.hesapAc('m1');
      s.yollar['POST /api/v1/mail/send'] = (
        422,
        {
          'error': {'code': 'validation', 'message': 'Alıcı adresi geçersiz'},
        },
      );
      await GidenKutusu.ben.ekle(istek('Reddedilen'));
      await GidenKutusu.ben.gonder();
      s.cevrimdisi = true;
      await GidenKutusu.ben.ekle(istek('Bekleyen'));
    });
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const GidenKutusuEkrani()));
    await t.pump();
    expect(find.text('Reddedilen'), findsOneWidget);
    expect(find.text('Bekliyor'), findsOneWidget);
    expect(find.textContaining('Hata: Alıcı adresi geçersiz'), findsOneWidget);
    // Tekrar dene: çevrimdışıyken yeniden bekliyor olur.
    await t.tap(find.text('Tekrar dene'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(find.text('Bekliyor'), findsNWidgets(2));
    // Sil.
    final o = GidenKutusu.ben.ogeler.value.last;
    await t.tap(find.byKey(ValueKey('giden-menu-${o.id}')));
    await t.pumpAndSettle();
    await t.tap(find.text('Sil').last);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Sil'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(find.text('Bekleyen'), findsNothing);
    expect(GidenKutusu.ben.ogeler.value, hasLength(1));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('çevrimdışıyken Gönder: ileti (ekiyle) Giden Kutusu\'na alınır, pencere kapanır, sunucuya istek yok', (t) async {
    await t.runAsync(() => Esitleyici.ben.hesapAc('m1'));
    Baglanti.ben.cevrimdisi.value = true;
    PostaDurum.ben.ayarlar = PostaAyarlari.json({
      'settings': {'display_name': 'Ayşe', 'compose_html': false},
    });
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        navigatorKey: kokGezgin,
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () =>
                yazmaAc(c, YazmaBaslangic(kime: const [Adres('Ali', 'ali@ornek.com')], konu: 'Yolda yazıldı', yerelEkler: const [('not.txt', 'bWVyaGFiYQ==')])),
            child: const Text('aç'),
          ),
        ),
      ),
    );
    await t.tap(find.text('aç'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Bağlantı gelince gitsin');
    await t.tap(find.text('Gönder'));
    for (var i = 0; i < 12; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(YazmaEkrani), findsNothing, reason: 'pencere kapandı');
    expect(s.bul('POST', '/api/v1/mail/send'), isEmpty);
    final o = GidenKutusu.ben.ogeler.value.single;
    expect(o.konu, 'Yolda yazıldı');
    expect(o.ekSayisi, 1);
    expect(find.textContaining('Giden Kutusu'), findsWidgets);
    final c = (await t.runAsync(() => GidenKutusu.ben.icerik(o.id)))!;
    expect((c.$1['attachments'] as List).single, containsPair('data', 'bWVyaGFiYQ=='));
    await t.pump(const Duration(seconds: 5));
  });

  test('çıkış: hesabın önbelleği, bekleyen değişiklikleri ve Giden Kutusu silinir', () async {
    await esitlenmisHesap();
    s.cevrimdisi = true;
    await Posta.guncelle('a', {'seen': true});
    await GidenKutusu.ben.ekle(istek('Gitmedi'));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(Directory(kok.path).listSync(), isNotEmpty);
    await Esitleyici.ben.hesabiSil('m1');
    expect(IslemKuyrugu.ben.bos, isTrue);
    expect(GidenKutusu.ben.ogeler.value, isEmpty);
    expect(Directory(kok.path).listSync(), isEmpty, reason: 'hesap dizini silindi');
    await Esitleyici.ben.hesapAc('m1');
    expect(await Posta.listeOnbellek('liste:k:f1'), isNull);
    expect(IslemKuyrugu.ben.bos, isTrue);
    expect(GidenKutusu.ben.ogeler.value, isEmpty);
    expect(Baglanti.ben.sonEsitleme.value, isNull);
  });
}
