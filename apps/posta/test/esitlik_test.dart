// Web ↔ uygulama eşitliği (esitlik.md "Uygulamaya eklenecek"): SPF/DKIM/DMARC çipleri ve DMARC uyarısı, ek
// önizleme türleri (SVG/HTML asla), Giden Kutusu sunucu kuyruğu (Tekrar dene / Düzenle / Sil), taslak otomatik
// kaydı, yazdırma belgesi, liste genişliği, takvim Gün görünümü ve renkleri, rehber vCard/CSV içe-dışa aktarma,
// süzgeç "Sonraki süzgeçleri çalıştırma", sohbet durumu bitiş süresi. Ağ yok (sahte sunucu).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:posta/ekranlar/giden_kutusu.dart';
import 'package:posta/ekranlar/hesap/posta_yonetimi.dart';
import 'package:posta/ekranlar/hesap/suzgecler.dart';
import 'package:posta/ekranlar/okuyucu_parcalari.dart';
import 'package:posta/ekranlar/sol_ray.dart';
import 'package:posta/ekranlar/takvim/takvim_ekrani.dart';
import 'package:posta/ekranlar/yazma.dart';
import 'package:posta/ortak/ek_onizleme.dart';
import 'package:posta/ortak/simgeler.dart';
import 'package:posta/ortak/yazdir.dart';
import 'package:posta/veri/baglanti.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/esitleyici.dart';
import 'package:posta/veri/hesap_servisi.dart';
import 'package:posta/veri/kuyruk.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/onbellek.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:posta/veri/rehber_aktar.dart';
import 'package:posta/veri/sohbet_servisi.dart';
import 'package:posta/veri/yazma_hazirla.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

Map<String, dynamic> _ileti({Map<String, dynamic>? auth, String html = '', String metin = 'Merhaba'}) => {
  'message': {'id': 'a', 'subject': 'Fatura <Kasım>', 'from': 'Ali <ali@a.com>', 'seen': true, 'folder_id': 'f1'},
  'view': {
    'subject': 'Fatura <Kasım>',
    'from': [
      {'name': 'Ali & Ortak', 'email': 'ali@a.com'},
    ],
    'to': [
      {'name': '', 'email': 'ben@b.com'},
    ],
    'cc': [],
    'reply_to': [],
    'date': '2026-11-19T10:00:00Z',
    'text': metin,
    'html': html,
    'attachments': [
      {'index': 1, 'filename': 'fatura.pdf', 'content_type': 'application/pdf', 'size': 2048, 'disposition': 'attachment'},
    ],
  },
  'auth': ?auth,
};

/// Gerçek disk G/Ç'si ve sahte zamanlı ağ istekleri tamamlanana kadar.
Future<void> _bekle(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Widget _uyg(Widget w) => MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: w);

void main() {
  final s = YolSunucusu();
  late Directory kok;
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Onyukleme.etkin = false;
    SharedPreferences.setMockInitialValues({});
    s.kur();
  });
  setUp(() {
    kok = Directory.systemTemp.createTempSync('esitlik_');
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

  group('1. SPF / DKIM / DMARC', () {
    test('auth alanı çözülür; DMARC başarısız + tehdit yok → amber uyarı', () {
      final d = IletiDetay.json(
        _ileti(
          auth: {
            'spf': {'result': 'pass', 'domain': 'a.com'},
            'dkim': {'result': 'softfail', 'domain': 'a.com'},
            'dmarc': {'result': 'fail', 'domain': 'a.com'},
          },
        ),
      );
      expect(d.dogrulama.map((x) => x.metin), ['SPF geçti', 'DKIM softfail', 'DMARC başarısız']);
      expect(d.dmarcBasarisiz, isTrue);
      final u = sezgiselUyarilar(d);
      expect(u.where((b) => b.baslik == 'Gönderen doğrulanamadı'), hasLength(1));
      expect(u.firstWhere((b) => b.baslik == 'Gönderen doğrulanamadı').tur, BantTuru.uyari);
      expect(u.first.metin, contains('DMARC başarısız'));
      // auth yoksa çip ve uyarı yok.
      final yok = IletiDetay.json(_ileti());
      expect(yok.dogrulama, isEmpty);
      expect(sezgiselUyarilar(yok).where((b) => b.baslik == 'Gönderen doğrulanamadı'), isEmpty);
    });

    testWidgets('çipler: geçti yeşil, başarısız kırmızı, softfail amber', (t) async {
      await t.pumpWidget(
        _uyg(
          const Scaffold(
            body: DogrulamaCipleri(sonuclar: [Dogrulama('SPF', 'pass', 'a.com'), Dogrulama('DKIM', 'softfail', 'a.com'), Dogrulama('DMARC', 'fail', 'a.com')]),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('dogrulama-cipleri')), findsOneWidget);
      Color renk(String m) => t.widget<Text>(find.textContaining(m)).style!.color!;
      expect(renk('SPF geçti'), Marka.zumrut);
      expect(renk('DMARC başarısız'), Marka.gul);
      expect(renk('DKIM softfail'), Marka.kehribar);
    });
  });

  group('2. ek önizleme', () {
    test('görsel / PDF / düz metin uygulama içinde; SVG, HTML ve diğerleri asla', () {
      Ek ek(String ad, String tur) => Ek.json({'index': 1, 'filename': ad, 'content_type': tur, 'size': 10});
      expect(ekOnizlemeTuru(ek('a.png', 'image/png'), android: false), EkOnizlemeTuru.gorsel);
      expect(ekOnizlemeTuru(ek('a.pdf', 'application/pdf'), android: false), EkOnizlemeTuru.pdf);
      expect(ekOnizlemeTuru(ek('a.pdf', 'application/pdf'), android: true), isNull, reason: 'Android: sistem görüntüleyicisi');
      expect(ekOnizlemeTuru(ek('notlar.txt', 'text/plain; charset=utf-8'), android: false), EkOnizlemeTuru.metin);
      expect(ekOnizlemeTuru(ek('a.csv', 'application/octet-stream'), android: false), EkOnizlemeTuru.metin);
      expect(ekOnizlemeTuru(ek('logo.svg', 'image/svg+xml'), android: false), isNull);
      expect(ekOnizlemeTuru(ek('sayfa.html', 'text/html'), android: false), isNull);
      expect(ekOnizlemeTuru(ek('x.svg', 'text/plain'), android: false), isNull, reason: 'uzantı SVG ise tür yalan söylese de');
      expect(ekOnizlemeTuru(ek('rapor.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'), android: false), isNull);
    });

    testWidgets('düz metin önizlemesi: içerik seçilebilir metin; Paylaş / Kaydet / Başka uygulamada aç', (t) async {
      final ek = Ek.json({'index': 1, 'filename': 'notlar.txt', 'content_type': 'text/plain', 'size': 12});
      var kaydet = 0;
      await t.pumpWidget(
        _uyg(
          EkOnizleme(
            ek: ek,
            tur: EkOnizlemeTuru.metin,
            veri: Uint8List.fromList(utf8.encode('Şubat raporu\nikinci satır')),
            paylas: () {},
            kaydet: () => kaydet++,
            disaridaAc: () {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('metin-onizleme')), findsOneWidget);
      expect(find.text('Şubat raporu\nikinci satır'), findsOneWidget);
      await t.tap(find.byTooltip('Kaydet'));
      expect(kaydet, 1);
      expect(find.byTooltip('Başka uygulamada aç'), findsOneWidget);
    });
  });

  group('3. Giden Kutusu sunucu kuyruğu', () {
    Map<String, dynamic> planli(String id, String durum, String tur, {String hata = ''}) => {
      'id': id,
      'send_at': '2026-11-21T15:00:00Z',
      'status': durum,
      'error': hata,
      'kind': tur,
      'to': ['veli@c.com'],
      'subject': 'Konu $id',
      'summary': '',
    };

    testWidgets('pending / sending / failed rozetleri; Tekrar dene → retry; Sil → DELETE; kenar sayısı kırmızı', (t) async {
      final liste = [planli('p1', 'pending', 'scheduled'), planli('p2', 'sending', 'undo'), planli('p3', 'failed', 'scheduled', hata: 'Alıcı sunucu reddetti')];
      s.yollar
        ..['GET /api/v1/mail/scheduled'] = ((Istek _) => (200, {'items': liste}))
        ..['POST /api/v1/mail/scheduled/p3/retry'] = (Istek _) {
          liste[2] = planli('p3', 'pending', 'scheduled');
          return (204, null);
        }
        ..['DELETE /api/v1/mail/scheduled/p1'] = (Istek _) {
          liste.removeAt(0);
          return (204, null);
        };
      await t.runAsync(() => Esitleyici.ben.hesapAc('m1'));
      await t.pumpWidget(_uyg(const GidenKutusuEkrani()));
      await _bekle(t);
      expect(find.byKey(const ValueKey('giden-sunucu-p1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('giden-durum-p1')), matching: find.text('Bekliyor')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('giden-durum-p2')), matching: find.text('Gönderiliyor…')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('giden-durum-p3')), matching: find.text('Hata')), findsOneWidget);
      expect(find.text('Geri alma süresi doluyor'), findsOneWidget);
      expect(find.textContaining('Alıcı sunucu reddetti'), findsOneWidget);
      expect(GidenKutusu.ben.toplam, 3);
      expect(GidenKutusu.ben.hataVar, isTrue);

      await t.tap(find.byKey(const ValueKey('giden-tekrar-p3')));
      await _bekle(t);
      expect(s.bul('POST', '/api/v1/mail/scheduled/p3/retry'), hasLength(1));
      expect(GidenKutusu.ben.hataVar, isFalse);

      // "Gönderiliyor…" döner simgesi yüzünden pumpAndSettle bitmez: sabit adımlar.
      Future<void> animasyon() async {
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
      }

      await t.tap(find.byKey(const ValueKey('giden-menu-p1')));
      await animasyon();
      await t.tap(find.text('Sil').last);
      await animasyon();
      await t.tap(find.widgetWithText(FilledButton, 'Sil'));
      await _bekle(t);
      expect(s.bul('DELETE', '/api/v1/mail/scheduled/p1'), hasLength(1));
      expect(find.byKey(const ValueKey('giden-sunucu-p1')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('Düzenle: restore → yazma penceresi "Planla" aynı saatle', (t) async {
      final zaman = DateTime.now().add(const Duration(days: 2)).toUtc();
      s.yollar
        ..['GET /api/v1/mail/scheduled'] = (200, {'items': []})
        ..['GET /api/v1/mail/folders'] = (200, {'items': []})
        ..['GET /api/v1/mail/labels'] = (200, {'items': []})
        ..['POST /api/v1/mail/scheduled/p1/restore'] = (
          200,
          {'draft_id': 'd1', 'kind': 'scheduled', 'send_at': zaman.toIso8601String(), 'compose': <String, dynamic>{}},
        )
        ..['GET /api/v1/mail/messages/d1'] = (
          200,
          {
            ..._ileti(),
            'message': {'id': 'd1', 'subject': 'Planlı', 'from': 'Ben <ben@b.com>', 'seen': true, 'folder_id': 'f3'},
          },
        );
      t.view.physicalSize = const Size(900, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        _uyg(
          Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(onPressed: () => planliDuzenle(c, Planli.json(planli('p1', 'pending', 'scheduled'))), child: const Text('aç')),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('aç'));
      await _bekle(t);
      expect(s.bul('POST', '/api/v1/mail/scheduled/p1/restore'), hasLength(1));
      expect(find.byType(YazmaEkrani), findsOneWidget);
      final beklenen = 'Planla · ${DateFormat('d MMM HH:mm', 'tr_TR').format(zaman.toLocal())}';
      expect(find.textContaining(beklenen), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    });
  });

  testWidgets('4. taslak otomatik kaydı: son değişiklikten 5 sn sonra kaydedilir, "Taslak kaydedildi HH:MM"', (t) async {
    s.yollar
      ..['POST /api/v1/mail/drafts'] = (200, {'id': 'd9'})
      ..['GET /api/v1/mail/folders'] = (200, {'items': []})
      ..['GET /api/v1/mail/labels'] = (200, {'items': []});
    PostaDurum.ben.ayarlar = PostaAyarlari.json({
      'settings': {'display_name': 'Ayşe', 'compose_html': false},
    });
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _uyg(
        YazmaEkrani(
          baslangic: YazmaBaslangic(kime: const [Adres('Ali', 'ali@ornek.com')], konu: 'Selam'),
        ),
      ),
    );
    await t.pump();
    await t.enterText(find.byType(TextField).last, 'Merhaba Ali');
    await t.pump(const Duration(seconds: 4));
    expect(s.bul('POST', '/api/v1/mail/drafts'), isEmpty, reason: '5 sn dolmadan kaydedilmez');
    await t.enterText(find.byType(TextField).last, 'Merhaba Ali, nasılsın?');
    await t.pump(const Duration(seconds: 4));
    expect(s.bul('POST', '/api/v1/mail/drafts'), isEmpty, reason: 'her değişiklik süreyi baştan başlatır');
    await t.pump(const Duration(seconds: 1, milliseconds: 100));
    await _bekle(t);
    expect(s.bul('POST', '/api/v1/mail/drafts'), hasLength(1));
    expect(s.bul('POST', '/api/v1/mail/drafts').single.json['subject'], 'Selam');
    expect(t.widget<Text>(find.byKey(const ValueKey('taslak-durumu'))).data, matches(RegExp(r'^Taslak kaydedildi \d\d:\d\d$')));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
  });

  group('6. yazdır', () {
    test('belge: başlık bilgileri kaçışlı, betik ve olay öznitelikleri atılır, uzak görsel yok', () {
      final d = IletiDetay.json(_ileti(html: '<p onclick="x()">Tutar <b>100 TL</b></p><script>alert(1)</script><img src="https://izci.com/p.gif">'));
      final b = yazdirmaBelgesi(d);
      expect(b, contains('<h1>Fatura &lt;Kasım&gt;</h1>'));
      expect(b, contains('Ali &amp; Ortak'));
      expect(b, contains('ben@b.com'));
      expect(b, contains('fatura.pdf'));
      expect(b, contains('<b>100 TL</b>'));
      expect(b, isNot(contains('<script')));
      expect(b, isNot(contains('onclick')));
      expect(b, isNot(contains('izci.com')));
      expect(b, contains("default-src 'none'"));
      // Düz metin ileti kaçışlanır.
      final dz = yazdirmaBelgesi(IletiDetay.json(_ileti(metin: 'a < b && c')));
      expect(dz, contains('<pre>a &lt; b &amp;&amp; c</pre>'));
    });

    testWidgets('Yazdır ekranı: önizleme ve Yazdır düğmesi', (t) async {
      await t.pumpWidget(_uyg(const YazdirmaEkrani(belge: '<p>x</p>', baslik: 'Fatura')));
      expect(find.byKey(const ValueKey('yazdirma-onizleme')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('yazdir'))).onPressed, isNotNull);
    });
  });

  test('7. liste varsayılanı %36 (340–600 px), okuma alanına en az 600 px (web mail-view.tsx)', () {
    double b(double alan) => bolmeBoyu(alan: alan, oran: listeVarsayilanOrani, enAz: 340, enCok: 600, kalan: 600);
    expect(b(1200), closeTo(432, .01));
    expect(b(900), 340, reason: 'okumaya 600 kalmasa da en az 340');
    expect(b(1000), 360);
    expect(b(2400), 600);
  });

  group('8. takvim', () {
    test('renk adları (sunucu etiket renkleri) ve eski #rrggbb', () {
      expect(takvimRengi('green', Colors.black), etiketRengi('green'));
      expect(takvimRengi('teal', Colors.black), etiketRengi('teal'));
      expect(takvimRengi('#ff0000', Colors.black), const Color(0xffff0000));
      expect(takvimRengi('', Colors.black), Colors.black);
    });

    testWidgets('Gün görünümü: saatli etkinlik çizelgede, takvim renginde; tüm gün üstte', (t) async {
      final g = DateTime.now();
      String utc(int saat) => DateTime(g.year, g.month, g.day, saat).toUtc().toIso8601String();
      s.yollar
        ..['GET /api/v1/mail/calendars'] = (
          200,
          {
            'items': [
              {'id': 'k1', 'name': 'İş', 'color': 'purple', 'is_default': true},
            ],
          },
        )
        ..['GET /api/v1/mail/calendar/events'] = (
          200,
          {
            'items': [
              {'id': 'e1', 'calendar_id': 'k1', 'title': 'Planlama', 'starts_at': utc(10), 'ends_at': utc(11), 'color': 'purple', 'attendees': []},
              {'id': 'e2', 'calendar_id': 'k1', 'title': 'Bayram', 'starts_at': utc(0), 'ends_at': utc(0), 'all_day': true, 'color': 'purple', 'attendees': []},
            ],
          },
        );
      t.view.physicalSize = const Size(800, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_uyg(const TakvimEkrani()));
      await _bekle(t);
      await t.tap(find.byTooltip('Görünüm'));
      await t.pumpAndSettle();
      await t.tap(find.text('Gün').last);
      await _bekle(t);
      expect(find.byKey(const ValueKey('takvim-gun')), findsOneWidget);
      expect(find.byKey(const ValueKey('gun-etkinlik-e1')), findsOneWidget);
      expect(find.byKey(const ValueKey('gun-etkinlik-e2')), findsNothing, reason: 'tüm gün etkinliği çizelgede değil, üstte');
      expect(find.text('Bayram'), findsOneWidget);
      final m = t.widget<Material>(find.descendant(of: find.byKey(const ValueKey('gun-etkinlik-e1')), matching: find.byType(Material)).first);
      expect(m.color, etiketRengi('purple').withValues(alpha: .16));
      expect(find.text(DateFormat('d MMMM y, EEEE', 'tr_TR').format(g)), findsOneWidget);
      // Sonraki gün.
      await t.tap(find.byTooltip('Sonraki'));
      await _bekle(t);
      expect(find.text(DateFormat('d MMMM y, EEEE', 'tr_TR').format(DateTime(g.year, g.month, g.day + 1))), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });

  group('9. rehber içe / dışa aktarma', () {
    test('vCard yazılır ve geri okunur (kaçışlar dahil)', () {
      final v = vcardYaz([Kisi(ad: 'Ayşe Nur Yılmaz', eposta: 'ayse@a.com', telefon: '+90 555', sirket: 'Boğa; A.Ş.', not: 'satır 1\nsatır 2')]);
      expect(v, contains('FN:Ayşe Nur Yılmaz'));
      expect(v, contains('N:Yılmaz;Ayşe Nur;;;'));
      expect(v, contains(r'ORG:Boğa\; A.Ş.'));
      expect(v, contains(r'NOTE:satır 1\nsatır 2'));
      final k = vcardOku(v).single;
      expect([k.ad, k.eposta, k.telefon, k.sirket, k.not], ['Ayşe Nur Yılmaz', 'ayse@a.com', '+90 555', 'Boğa; A.Ş.', 'satır 1\nsatır 2']);
    });

    test('vCard: katlama, quoted-printable, FN yoksa N', () {
      const v =
          'BEGIN:VCARD\r\nVERSION:2.1\r\nN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=C3=96zt=C3=BCrk;Mehmet;;;\r\n'
          'EMAIL;TYPE=INTERNET:mehmet@\r\n ornek.com\r\nTEL:tel:+90 212\r\nEND:VCARD\r\n';
      final k = vcardOku(v).single;
      expect(k.ad, 'Mehmet Öztürk');
      expect(k.eposta, 'mehmet@ornek.com');
      expect(k.telefon, '+90 212');
    });

    test('CSV: Türkçe başlıklar, ; ayırıcı, tırnaklı alan; başlıksız dosya; geçersiz ve yinelenen atlanır', () {
      final o = rehberDosyasiOku(
        'rehber.csv',
        '﻿Ad;Soyad;E-posta;Telefon;Şirket\nAli;Kaya;ALI@a.com;0555;"Kaya; Ortak"\nVeli;;gecersiz;;\nAli;K;ali@a.com;;\n',
      );
      expect(o.vcard, isFalse);
      expect(o.kisiler, hasLength(1));
      expect(o.kisiler.single.ad, 'Ali Kaya');
      expect(o.kisiler.single.eposta, 'ali@a.com');
      expect(o.kisiler.single.sirket, 'Kaya; Ortak');
      expect(o.atlanan, 2);
      final b = csvOku('Zeynep,zeynep@z.com,0533,Z Ltd\nCan,can@c.com,,\n');
      expect(b.map((k) => '${k.ad}|${k.eposta}|${k.telefon}|${k.sirket}'), ['Zeynep|zeynep@z.com|0533|Z Ltd', 'Can|can@c.com||']);
    });

    testWidgets('Kişiler: İçe aktar (ön izleme → sırayla POST) ve Dışa aktar (.vcf)', (t) async {
      s.yollar
        ..['GET /api/v1/mail/contacts'] = (
          200,
          {
            'items': [
              {'id': 'k1', 'name': 'Ali', 'email': 'ali@a.com'},
            ],
            'total': 1,
          },
        )
        ..['POST /api/v1/mail/contacts'] = (201, {'id': 'yeni'});
      KisilerEkrani.dosyaSec = () async =>
          ('rehber.vcf', Uint8List.fromList(utf8.encode(vcardYaz([Kisi(ad: 'Can', eposta: 'can@c.com'), Kisi(ad: 'Ece', eposta: 'ece@e.com')]))));
      String? kaydedilen;
      String? icerik;
      KisilerEkrani.dosyaKaydet = (ad, b) async {
        kaydedilen = ad;
        icerik = utf8.decode(b);
        return true;
      };
      await t.pumpWidget(_uyg(const KisilerEkrani()));
      await _bekle(t);
      await t.tap(find.byKey(const ValueKey('kisiler-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('İçe aktar (vCard/CSV)'));
      await _bekle(t);
      expect(find.text('rehber.vcf: 2 kişi bulundu.'), findsOneWidget);
      await t.tap(find.text('2 kişiyi içe aktar'));
      await _bekle(t);
      final post = s.bul('POST', '/api/v1/mail/contacts').toList();
      expect(post.map((i) => i.json['email']), ['can@c.com', 'ece@e.com']);
      await t.pumpAndSettle(const Duration(seconds: 5));

      await t.tap(find.byKey(const ValueKey('kisiler-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('Dışa aktar (vCard)'));
      await _bekle(t);
      expect(kaydedilen, matches(RegExp(r'^rehber-\d{4}-\d\d-\d\d\.vcf$')));
      expect(icerik, contains('EMAIL;TYPE=INTERNET:ali@a.com'));
      await t.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  test('10. süzgeç: "stop" alanı gidip gelir, özette görünür', () {
    final sz = Suzgec.json({
      'id': 's1',
      'name': 'Faturalar',
      'stop': true,
      'match_all': true,
      'enabled': true,
      'conditions': [
        {'field': 'subject', 'op': 'contains', 'value': 'fatura'},
      ],
      'actions': [
        {'type': 'mark_read'},
      ],
    });
    expect(sz.dur, isTrue);
    expect(sz.json()['stop'], isTrue);
    expect(suzgecOzeti(sz), endsWith('sonraki süzgeçler çalışmaz'));
  });

  group('11. sohbet durumu bitişi', () {
    test('süre seçenekleri (web UNTIL_OPTIONS) ve metin', () {
      final n = DateTime(2026, 11, 21, 14, 0);
      expect(durumBitisi('none', n), isNull);
      expect(durumBitisi('30m', n), DateTime(2026, 11, 21, 14, 30));
      expect(durumBitisi('4h', n), DateTime(2026, 11, 21, 18, 0));
      expect(durumBitisi('today', n), DateTime(2026, 11, 21, 23, 59));
      expect(durumBitisMetni(DateTime(2026, 11, 21, 15, 30), n), 'bitiş 15:30');
      expect(durumBitisMetni(DateTime(2026, 11, 22, 9, 0), n), 'bitiş yarın 09:00');
      final k = SohbetKisi.json({
        'mailbox_id': 'x',
        'status': 'meeting',
        'status_text': 'Bütçe',
        'status_until': DateTime.now().add(const Duration(minutes: 30)).toUtc().toIso8601String(),
      });
      expect(k.durumYazisi, startsWith('Toplantıda · Bütçe · bitiş '));
    });

    test('kaydetme status_until gönderir (Süresiz: null)', () async {
      s.yollar['PUT /api/v1/mail/chat/me'] = (200, {'status': 'busy'});
      final b = DateTime.utc(2026, 11, 21, 16);
      await Sohbet.benKaydet(durum: 'busy', durumMetni: '', durumBitis: b, bitisGonder: true);
      expect(s.istekler.last.json['status_until'], '2026-11-21T16:00:00.000Z');
      await Sohbet.benKaydet(durum: 'out', durumMetni: '', bitisGonder: true);
      expect(s.istekler.last.json.containsKey('status_until'), isTrue);
      expect(s.istekler.last.json['status_until'], isNull);
    });
  });
}
