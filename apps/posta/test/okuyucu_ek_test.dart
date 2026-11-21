// Okuyucu: PDF ekleri gövdeden önce kart olarak (tek iletide ve konuşmanın her açık iletisinde), "N ek" çipi,
// web gibi spam denetimi satırı ve ayrıntılar (Boyut), erteleme bandı; konuşmada "▸ N önceki ileti" kararlılığı;
// hesap değişimi tostu. Ağ yok (sahte sunucu).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/okuyucu.dart';
import 'package:posta/ekranlar/okuyucu_parcalari.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'konusma_ornek.dart';
import 'sahte_sunucu.dart';

void main() {
  final s = YolSunucusu();
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Onyukleme.etkin = false;
    SharedPreferences.setMockInitialValues({});
    s.kur();
  });
  setUp(() {
    s.istekler.clear();
    s.yollar.clear();
    konusmaKur(s);
  });
  tearDown(PostaDurum.ben.sifirla);

  Map<String, dynamic> detay(String id) => ((s.yollar['GET /api/v1/mail/messages/$id']! as Yanit).$2! as Map).cast<String, dynamic>();

  Future<void> ac(WidgetTester t, String id, {Size boyut = const Size(1000, 900), bool sayfa = false}) async {
    t.view.physicalSize = boyut;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        home: sayfa ? Okuyucu(id: id, sayfa: true) : Scaffold(body: Okuyucu(id: id)),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> kapat(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  }

  /// k1 tek ileti olarak (konuşma yok): PDF + XLSX ekli; spam puanı ve kuralları, erteleme.
  void tekIleti({bool erteli = false}) {
    final d = detay('k1');
    s.yollar['GET /api/v1/mail/messages/k1/thread'] = (
      200,
      {
        'items': [d['message']],
      },
    );
    s.yollar['GET /api/v1/mail/messages/k1'] = (
      200,
      {
        ...d,
        'message': {...(d['message'] as Map), 'size': 523000, if (erteli) 'snoozed_until': '2026-12-01T09:00:00Z'},
        'spam': {
          'score': -0.7,
          'rules': ['DKIM_VALID', 'SPF_PASS'],
        },
      },
    );
  }

  testWidgets('tek ileti: PDF eki gövdeden önce kart, başlıkta "2 ek" çipi; dokununca menüde Aç / Paylaş / Kaydet', (t) async {
    tekIleti();
    await ac(t, 'k1');
    final ekler = find.byKey(const ValueKey('okuyucu-ekler'));
    expect(ekler, findsOneWidget);
    expect(find.descendant(of: ekler, matching: find.text('Teklif-2026-114.pdf')), findsOneWidget);
    expect(find.descendant(of: ekler, matching: find.text('Fiyat-tablosu.xlsx')), findsOneWidget);
    expect(find.text('2 ek'), findsOneWidget);
    expect(t.getTopLeft(ekler).dy, lessThan(t.getTopLeft(find.textContaining('Görüşmemizde')).dy), reason: 'ekler gövdeden önce');
    // Ek menüsü: aç (PDF önizleme / sistem görüntüleyicisi) / paylaş / kaydet.
    await t.tap(find.descendant(of: ekler, matching: find.byTooltip('Ek seçenekleri')).first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Aç'), findsOneWidget);
    expect(find.text('Paylaş'), findsOneWidget);
    await kapat(t);
  });

  testWidgets('web gibi "Spam denetimi: puan -0.7 (temiz)" (dokununca kurallar), ayrıntıda Boyut ve spam puanı', (t) async {
    tekIleti();
    await ac(t, 'k1');
    expect(find.text('Spam denetimi: puan -0.7 (temiz)'), findsOneWidget);
    expect(find.text('DKIM_VALID'), findsNothing);
    await t.tap(find.text('Spam denetimi: puan -0.7 (temiz)'));
    await t.pump();
    expect(find.text('DKIM_VALID'), findsOneWidget);
    expect(find.text('SPF_PASS'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('gonderen-karti')));
    await t.pump();
    expect(find.text('Boyut'), findsOneWidget);
    expect(find.text('Spam puanı'), findsOneWidget);
    await kapat(t);
  });

  test('IletiDetay.json: spam.score / spam.rules (puan yoksa null)', () {
    final a = IletiDetay.json({
      'message': {'id': 'x'},
      'view': {},
      'spam': {
        'score': 3.2,
        'rules': ['A'],
      },
    });
    expect(a.spamPuani, 3.2);
    expect(a.spamKurallari, ['A']);
    final b = IletiDetay.json({
      'message': {'id': 'x'},
      'view': {},
      'spam': {'score': null, 'rules': null},
    });
    expect(b.spamPuani, isNull);
    expect(b.spamKurallari, isEmpty);
  });

  testWidgets('ertelenmiş ileti: "… Gelen Kutusu\'na geri gelecek" bandı, Şimdi geri al snooze_until: null gönderir', (t) async {
    tekIleti(erteli: true);
    s.yollar['PATCH /api/v1/mail/messages/k1'] = (200, {'ok': true});
    await ac(t, 'k1');
    expect(find.byKey(const ValueKey('erteleme-bandi')), findsOneWidget);
    await t.tap(find.text('Şimdi geri al'));
    await t.pump(const Duration(milliseconds: 100));
    expect(s.bul('PATCH', '/api/v1/mail/messages/k1').map((i) => i.json), anyElement(equals({'snooze_until': null})));
    await kapat(t);
  });

  testWidgets('telefonda tek iletide alt yanıt çubuğu', (t) async {
    tekIleti();
    await ac(t, 'k1', boyut: const Size(390, 844), sayfa: true);
    expect(find.byType(YanitCubugu), findsOneWidget);
    await kapat(t);
  });

  testWidgets('konuşma: açık iletilerde PDF kartları; önceki iletiler açılır, açılıp kapanan ileti yerinde kalır, yenilemede durum korunur', (t) async {
    await ac(t, 'k8', boyut: const Size(1000, 1400));
    // k7 (açık, okunmamış) PDF ekli.
    final k7 = find.byKey(const ValueKey('konusma-ileti-k7'));
    expect(find.descendant(of: k7, matching: find.text('Sozlesme-taslagi.pdf')), findsOneWidget);
    await t.tap(find.text('6 önceki ileti'));
    await t.pump();
    for (final id in ['k1', 'k2', 'k3', 'k4', 'k5', 'k6']) {
      expect(find.byKey(ValueKey('konusma-kapali-$id')), findsOneWidget);
    }
    // k1'i aç: tam gövde + PDF kartı.
    await t.tap(find.byKey(const ValueKey('konusma-kapali-k1')));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final k1 = find.byKey(const ValueKey('konusma-ileti-k1'));
    expect(k1, findsOneWidget);
    expect(find.descendant(of: k1, matching: find.text('Teklif-2026-114.pdf')), findsOneWidget);
    // "Gizle" ile önceki iletiler kapanınca açtığımız k1 görünür kalır (gizli gruba kaçmaz).
    expect(find.text('5 önceki iletiyi gizle'), findsOneWidget, reason: 'açılan k1 artık gizli sayılmaz');
    await t.tap(find.text('5 önceki iletiyi gizle'));
    await t.pump();
    expect(k1, findsOneWidget);
    // k1'i kapat: sıkı satır olarak yerinde kalır, sayaç değişmez.
    await t.tapAt(t.getTopLeft(find.descendant(of: k1, matching: find.byKey(const ValueKey('ileti-basligi')))) + const Offset(70, 12));
    await t.pump();
    expect(find.byKey(const ValueKey('konusma-kapali-k1')), findsOneWidget);
    expect(find.text('5 önceki ileti'), findsOneWidget);
    // Konuşma yenilenince (aynı iletiler) açık/kapalı durum ve kaydırma sıfırlanmaz.
    final st = t.state<OkuyucuState>(find.byType(Okuyucu));
    final f = st.yenileKonusma();
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await f;
    expect(find.byKey(const ValueKey('konusma-kapali-k1')), findsOneWidget);
    expect(find.text('5 önceki ileti'), findsOneWidget);
    await kapat(t);
  });

  testWidgets('hesap değişimi tostu: geniş ekranda sağ üst kart (avatar), ~2.5 sn sonra kapanır; telefonda üst orta', (t) async {
    for (final (boyut, sag) in [(const Size(1200, 800), true), (const Size(390, 844), false)]) {
      t.view.physicalSize = boyut;
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        MaterialApp(
          theme: temaKur(Brightness.light),
          navigatorKey: kokGezgin,
          scaffoldMessengerKey: kokMesaj,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      bildir('info@ornek.com hesabına geçildi', onde: const Avatar('info', boyut: 28, tohum: 'info@ornek.com'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      final kart = find.byKey(const ValueKey('tost'));
      expect(kart, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing, reason: 'alt bant değil');
      final r = t.getRect(kart);
      expect(r.top, lessThan(40));
      if (sag) {
        expect(boyut.width - r.right, closeTo(16, 2));
      } else {
        expect((r.center.dx - boyut.width / 2).abs(), lessThan(2));
      }
      expect(find.descendant(of: kart, matching: find.byType(Avatar)), findsOneWidget);
      await t.pump(const Duration(milliseconds: 2600));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('tost')), findsNothing);
      // Hatalar alttaki bantta kalır.
      bildir('Hata', tur: MesajTur.hata);
      await t.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    }
    t.view.reset();
  });
}
