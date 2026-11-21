// Konuşma görünümü: yığın (kapalı satırlar, "N ileti daha"), okunmamış/son ileti açık, ilk okunmamışa kaydırma,
// alıntı ve tekrarlanan imzanın "•••" arkasına katlanması, sıkı ek şeridi; alıntı/imza ayırma kuralları (web ile
// aynı). Ağ yok (sahte sunucu).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/konusma.dart';
import 'package:posta/ekranlar/okuyucu.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/html_temizle.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:posta/veri/yardimci.dart';
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

  Future<void> kapat(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  }

  Future<void> ac(WidgetTester t, {Size boyut = const Size(390, 844)}) async {
    t.view.physicalSize = boyut;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        home: const Okuyucu(id: 'k8', sayfa: true),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('web düzeni: önceki 6 ileti tek "▸ N önceki ileti" arkasında; hemen önceki (okunmamış) ve açılan açık', (t) async {
    await ac(t);
    expect(find.byKey(const ValueKey('konusma')), findsOneWidget);
    expect(find.text('6 önceki ileti'), findsOneWidget);
    for (final id in ['k1', 'k2', 'k3', 'k4', 'k5', 'k6']) {
      expect(find.byKey(ValueKey('konusma-kapali-$id')), findsNothing);
    }
    expect(find.byKey(const ValueKey('konusma-ileti-k7')), findsOneWidget);
    expect(find.byKey(const ValueKey('konusma-ileti-k8')), findsOneWidget);
    // Konu bir kez, üstte.
    expect(find.text('Re: $konusmaKonu'), findsOneWidget);
    expect(find.text('8 ileti · 3 kişi'), findsOneWidget);
    // Açılan okunmamış ileti (k7) okundu işaretlenir.
    expect(s.bul('PATCH', '/api/v1/mail/messages/k7').map((i) => i.json['seen']), contains(true));

    // Okunmamışlar "● okunmadı" (açılışta okundu sayılsa da işaret kalır); açılan dışındakiler "Bu iletiyi aç".
    expect(t.widget<OkunduIsareti>(find.descendant(of: find.byKey(const ValueKey('konusma-ileti-k7')), matching: find.byType(OkunduIsareti))).okundu, isFalse);
    expect(find.descendant(of: find.byKey(const ValueKey('konusma-ileti-k7')), matching: find.byKey(const ValueKey('ileti-ayri-ac'))), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('konusma-ileti-k8')), matching: find.byKey(const ValueKey('ileti-ayri-ac'))), findsNothing);

    await t.tap(find.text('6 önceki ileti'));
    await t.pump();
    expect(find.text('6 önceki iletiyi gizle'), findsOneWidget);
    for (final id in ['k1', 'k2', 'k3', 'k4', 'k5', 'k6']) {
      expect(find.byKey(ValueKey('konusma-kapali-$id')), findsOneWidget);
    }
    expect(find.descendant(of: find.byKey(const ValueKey('konusma-kapali-k1')), matching: find.byType(Avatar)), findsOneWidget);
    expect(t.widget<Avatar>(find.descendant(of: find.byKey(const ValueKey('konusma-kapali-k1')), matching: find.byType(Avatar))).boyut, 24);
    // Kapalı satıra dokununca açılır; ekler tek satırlık şeritte.
    await t.tap(find.byKey(const ValueKey('konusma-kapali-k3')));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final k3 = find.byKey(const ValueKey('konusma-ileti-k3'));
    expect(k3, findsOneWidget);
    expect(find.descendant(of: k3, matching: find.byKey(const ValueKey('ek-seridi'))), findsOneWidget);
    expect(t.getSize(find.descendant(of: k3, matching: find.byKey(const ValueKey('ek-seridi')))).height, lessThanOrEqualTo(64));
    expect(find.text('Gecis-Plani-v2.docx'), findsOneWidget);
    // Başlığa dokununca yeniden kapanır.
    await t.tapAt(t.getTopLeft(find.descendant(of: k3, matching: find.byKey(const ValueKey('ileti-basligi')))) + const Offset(70, 12));
    await t.pump();
    expect(find.byKey(const ValueKey('konusma-kapali-k3')), findsOneWidget);
    await kapat(t);
  });

  testWidgets('alıntılanan geçmiş ve tekrarlanan imza "•••" arkasında; alıcı özeti genişler', (t) async {
    await ac(t);
    final k8 = find.byKey(const ValueKey('konusma-ileti-k8'));
    expect(find.descendant(of: k8, matching: find.textContaining('Takvim davetini gönderiyorum')), findsOneWidget);
    expect(find.descendant(of: k8, matching: find.textContaining('şunu yazdı')), findsNothing);
    expect(
      find.descendant(of: k8, matching: find.textContaining('Satış Müdürü')),
      findsNothing,
      reason: 'Ayşe\'nin imzası konuşmada tekrar',
    );
    await t.ensureVisible(find.descendant(of: k8, matching: find.byKey(const ValueKey('alinti-ac'))));
    await t.tap(find.descendant(of: k8, matching: find.byKey(const ValueKey('alinti-ac'))));
    await t.pump();
    expect(find.descendant(of: k8, matching: find.textContaining('şunu yazdı')), findsOneWidget);
    expect(find.descendant(of: k8, matching: find.textContaining('Satış Müdürü')), findsOneWidget);

    expect(find.descendant(of: k8, matching: find.byKey(const ValueKey('alici-ayrinti'))), findsNothing);
    await t.tap(find.descendant(of: k8, matching: find.byKey(const ValueKey('alici-ozeti'))));
    await t.pump();
    expect(find.descendant(of: k8, matching: find.byKey(const ValueKey('alici-ayrinti'))), findsOneWidget);
    expect(find.byKey(const ValueKey('hizli-yanit')), findsOneWidget);
    await kapat(t);
  });

  testWidgets('açılışta ilk okunmamış iletiye kaydırılır (en üste değil)', (t) async {
    await ac(t, boyut: const Size(390, 520));
    final ust = t.getTopLeft(find.byKey(const ValueKey('konusma-ileti-k7'))).dy;
    final baslikAlti = t.getBottomLeft(find.byKey(const ValueKey('konusma-baslik'))).dy;
    expect((ust - baslikAlti).abs(), lessThan(4), reason: 'ilk okunmamış ileti yapışkan başlığın hemen altında');
    expect(find.byKey(const ValueKey('konusma-daha')).hitTestable(), findsNothing);
    // Başlık kaydı: 32 px şerit "Ad · zaman".
    expect(t.getSize(find.byKey(const ValueKey('konusma-baslik'))).height, 32);
    await kapat(t);
  });

  test('HTML alıntı/imza ayırma (web kuralları)', () {
    var r = htmlAlintiAyir('<p>Yeni</p><div class="gmail_quote"><div>X şunu yazdı:</div><blockquote>eski</blockquote></div>');
    expect(r.katlandi, isTrue);
    expect(r.ana, contains('Yeni'));
    expect(r.ana, isNot(contains('eski')));
    // Sınıfsız atıf satırı.
    r = htmlAlintiAyir('<div>Tamam.</div><div>20 Kas 2026 tarihinde Ali şunu yazdı:</div><div>eski metin</div>');
    expect(r.katlandi, isTrue);
    expect(r.ana, isNot(contains('eski metin')));
    r = htmlAlintiAyir('<p>On Mon, Nov 3, 2026 at 10:00 Ali &lt;a@b.com&gt; wrote:</p><p>old</p>');
    expect(r.katlandi, isFalse, reason: 'alıntı iletinin tamamı: katlanmaz');
    // Sondaki sınıfsız blockquote.
    r = htmlAlintiAyir('<p>Evet</p><blockquote>önceki</blockquote>');
    expect(r.ana, isNot(contains('önceki')));
    // İmza yalnız istenince.
    const imzali = '<p>Merhaba</p><div class="gmail_signature">Ayşe<br>Satış</div>';
    expect(htmlAlintiAyir(imzali).katlandi, isFalse);
    r = htmlAlintiAyir(imzali, imza: true);
    expect(r.katlandi, isTrue);
    expect(r.ana, isNot(contains('Satış')));
  });

  Map<String, dynamic> ozet(String id) => (((s.yollar['GET /api/v1/mail/messages/$id']! as Yanit).$2! as Map)['message'] as Map).cast<String, dynamic>();

  testWidgets('konuşmayı sunucu kurar: thread tek ileti dönerse istemci konu araması yapmaz, tek ileti görünümü', (t) async {
    s.yollar['GET /api/v1/mail/messages/k8/thread'] = (
      200,
      {
        'items': [ozet('k8')],
      },
    );
    await ac(t, boyut: const Size(900, 900));
    expect(find.byKey(const ValueKey('konusma')), findsNothing);
    expect(s.istekler.any((i) => i.sorgu['in'] == 'subject'), isFalse);
    expect(find.textContaining('Bu konuşmada'), findsNothing);
    await kapat(t);
  });

  testWidgets('tek ileti: web gibi başlık (konu 18 px, 32 px avatar, "Kime: bana"), Biçimli/Düz metin, gövde sonunda yanıt düğmeleri', (t) async {
    Uyg.kutu.value = {'mailbox_id': 'm1', 'address': 'semih@ornek.com', 'display_name': 'Semih Boğa'};
    addTearDown(() => Uyg.kutu.value = null);
    s.yollar
      ..['GET /api/v1/mail/messages/k8/thread'] = (
        200,
        {
          'items': [ozet('k8')],
        },
      )
      ..['GET /api/v1/mail/messages'] = (
        200,
        {
          'items': [ozet('k8')],
          'total': 1,
          'page': 1,
          'page_size': 25,
        },
      );
    await ac(t, boyut: const Size(900, 900));
    expect(find.byKey(const ValueKey('konusma')), findsNothing);
    final konu = t.widget<SelectableText>(find.byKey(const ValueKey('okuyucu-konu')));
    expect(konu.style!.fontSize, 18);
    expect(t.widget<Text>(find.byKey(const ValueKey('okuyucu-kime'))).data, startsWith('Kime: bana'));
    expect(find.byWidgetPredicate((w) => w is Avatar && w.boyut == 32), findsOneWidget);
    expect(find.byKey(const ValueKey('bicim-secimi')), findsOneWidget);
    expect(find.byKey(const ValueKey('yanit-dugmeleri')), findsOneWidget);
    await t.tap(find.text('Düz metin'));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('gonderen-karti')));
    await t.pump();
    expect(find.text('Kimden'), findsOneWidget);
    await kapat(t);
  });

  test('geniş HTML yatay kaymaz: sabit 650 px tablo okuyucuya sığacak oranda küçültülür (web zoom, en az 0.5)', () {
    // İş Bankası bildirimi gibi: <table width="650"> içinde sabit hücreler.
    const banka =
        '<table width="650" align="center" style="width:650px"><tr><td style="padding:0;width:650px">'
        '<table width="100%"><tr><td width="325">Hesap</td><td width="325">Tutar</td></tr></table></td></tr></table>';
    expect(dogalGenislik(banka), 650);
    expect(dogalGenislik('<p>Akışkan metin</p><table width="100%"><tr><td>x</td></tr></table>'), 0);
    expect(dogalGenislik('<div style="max-width:600px">yalnız üst sınır</div>'), 0);
    expect(dogalGenislik('<table width="700px"><tr><td>x</td></tr></table>'), 700);
    expect(sigdirmaOrani(650, 1000), 1, reason: 'sığıyor');
    expect(sigdirmaOrani(650, 520), closeTo(520 / 682, 1e-9));
    expect(sigdirmaOrani(650, 200), .5, reason: 'en az 0.5');
    expect(sigdirmaOrani(0, 300), 1);
    final b = gorunumBelgesi(banka);
    expect(sigdirilmisBelge(b, 1), b);
    expect(sigdirilmisBelge(b, .762), contains('<style>body{zoom:0.762}</style></head>'));
  });

  test('düz metin imza ayırma ("-- " ayıracı)', () {
    const m = 'Merhaba\n\n-- \nAyşe\nSatış';
    expect(alintiVeImzaAyir(m).ana, m);
    final p = alintiVeImzaAyir(m, imza: true);
    expect(p.ana, 'Merhaba');
    expect(p.alinti, startsWith('-- '));
    expect(alintiVeImzaAyir('-- \nyalnız imza', imza: true).ana, '-- \nyalnız imza');
  });
}
