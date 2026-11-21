// Masaüstü okuyucu (Outlook düzeni): sabit başlık bloğu + bölmeyi dolduran tek gövde (kendi içinde kayar), ileti
// değişince aynı görüntüleyici; konuşmada sıkı satırlar ve etkin ileti değişimi; süzgeç sekmelerinin geometrisi
// seçim / sayı değişince sabit. Ağ yok (sahte sunucu).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/konusma.dart';
import 'package:posta/ekranlar/okuyucu.dart';
import 'package:posta/ortak/html_govde.dart';
import 'package:posta/ortak/liste_filtresi.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'konusma_ornek.dart';
import 'sahte_sunucu.dart';

Map<String, dynamic> _ileti(String id, String konu, String metin, {List<Map<String, Object>> ekler = const []}) => {
  'message': {'id': id, 'subject': konu, 'from': 'Ali <ali@a.com>', 'seen': true, 'folder_id': 'f1', 'date': '2026-11-20T09:00:00Z'},
  'view': {
    'subject': konu,
    'from': [
      {'name': 'Ali', 'email': 'ali@a.com'},
    ],
    'to': [
      {'name': 'Ben', 'email': 'ben@b.com'},
    ],
    'cc': [],
    'reply_to': [],
    'date': '2026-11-20T09:00:00Z',
    'text': metin,
    'html': '<p>$metin</p>',
    'attachments': ekler,
  },
};

void main() {
  final s = YolSunucusu();
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Onyukleme.etkin = false;
    SharedPreferences.setMockInitialValues({});
    s.kur();
  });
  setUp(() {
    masaustuZorla = true;
    HazirBelgeler.temizle();
    s
      ..istekler.clear()
      ..yollar.clear();
  });
  tearDown(() {
    masaustuZorla = null;
    PostaDurum.ben.sifirla();
  });

  Future<void> bekle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> kapat(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  }

  /// 1440×900 pencerede, liste yanında okuma bölmesi (900 px).
  Widget bolme(String id) => MaterialApp(
    theme: temaKur(Brightness.light),
    scaffoldMessengerKey: kokMesaj,
    home: Scaffold(
      body: Row(
        children: [
          const SizedBox(width: 540),
          Expanded(
            child: Okuyucu(key: const ValueKey('okuyucu'), id: id),
          ),
        ],
      ),
    ),
  );

  testWidgets('tek ileti: başlık üstte sabit, gövde bölmenin kalanını doldurur; ileti değişince aynı görüntüleyici, gövde aynı yerden başlar', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final uzun = List.filled(400, 'satır').join(' ');
    s.yollar
      ..['GET /api/v1/mail/messages/a/thread'] = (200, {'items': []})
      ..['GET /api/v1/mail/messages/b/thread'] = (200, {'items': []})
      ..['GET /api/v1/mail/messages/a'] = (200, _ileti('a', 'Birinci', uzun))
      ..['GET /api/v1/mail/messages/b'] = (200, _ileti('b', 'İkinci', 'kısa gövde'));
    await t.pumpWidget(bolme('a'));
    await bekle(t);
    expect(find.byKey(const ValueKey('masaustu-okuyucu')), findsOneWidget);
    expect(find.byKey(const ValueKey('yanit-dugmeleri')), findsNothing, reason: 'masaüstünde gövde sonunda değil, sabit çubukta');
    expect(find.byKey(const ValueKey('masaustu-yanit-cubugu')), findsOneWidget);
    final alan = t.getRect(find.byKey(const ValueKey('okuyucu-govde-alani')));
    final cubuk = t.getRect(find.byKey(const ValueKey('masaustu-yanit-cubugu')));
    final ust = t.getRect(find.byKey(const ValueKey('okuyucu-ust')));
    // Gövde başlığın hemen altından yanıt çubuğuna kadar; yanıt çubuğu bölmenin en altında.
    expect(cubuk.bottom, 900);
    expect(alan.bottom, cubuk.top);
    expect(alan.top, closeTo(ust.bottom + 1, .5));
    expect(alan.height, greaterThan(500));
    expect(alan.width, 900);
    // Dış kaydırma yok: gövde (uzun olsa da) bölmeyi aşmaz, başlık yerinde.
    expect(find.byType(ListView), findsNothing);
    final govdeDurumu = t.state(find.byKey(const ValueKey('okuyucu-html')));

    await t.pumpWidget(bolme('b'));
    await bekle(t);
    expect(find.text('İkinci'), findsOneWidget);
    expect(find.text('kısa gövde'), findsOneWidget);
    expect(identical(t.state(find.byKey(const ValueKey('okuyucu-html'))), govdeDurumu), isTrue, reason: 'web görünümü yeniden kurulmaz');
    final alan2 = t.getRect(find.byKey(const ValueKey('okuyucu-govde-alani')));
    expect(alan2.top, alan.top, reason: 'aynı başlık yapısında gövde aynı yerden başlar');
    expect(alan2.bottom, alan.bottom);
    await kapat(t);
  });

  testWidgets('konuşma: sıkı satırlar, etkin ileti vurgulu; satıra tıklayınca gövde aynı bölmede o iletiye geçer', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    konusmaKur(s);
    await t.pumpWidget(bolme('k8'));
    await bekle(t);
    expect(find.byKey(const ValueKey('konusma')), findsNothing, reason: 'masaüstünde ölçülen gövde yığını yok');
    expect(find.byKey(const ValueKey('konusma-satirlari')), findsOneWidget);
    expect(find.byKey(const ValueKey('konusma-daha')), findsOneWidget);
    expect(find.byKey(const ValueKey('konusma-satir-k8')), findsOneWidget);
    expect(find.byKey(const ValueKey('konusma-satir-k1')), findsNothing, reason: 'eski okunmuşlar "▸ N önceki ileti" arkasında');
    bool secili(String id) => t.widget<KonusmaSatiri>(find.byKey(ValueKey('konusma-satir-$id'))).secili;
    expect(secili('k8'), isTrue);
    expect(find.byType(HtmlGovde), findsOneWidget, reason: 'tek gövde');
    final govdeDurumu = t.state(find.byKey(const ValueKey('okuyucu-html')));
    final ustAlan = t.getRect(find.byKey(const ValueKey('okuyucu-govde-alani')));

    // Önceki iletileri aç, k1'e tıkla.
    await t.tap(find.byKey(const ValueKey('konusma-daha')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('konusma-satir-k1')));
    await bekle(t);
    expect(secili('k1'), isTrue);
    expect(secili('k8'), isFalse);
    expect(find.byType(HtmlGovde), findsOneWidget);
    expect(t.widget<HtmlGovde>(find.byType(HtmlGovde)).iletiId, 'k1');
    expect(find.textContaining('kurumsal e-posta geçişi için teklifimizi'), findsWidgets);
    // Etkin iletinin ekleri başlık bloğunda.
    expect(find.text('Teklif-2026-114.pdf'), findsOneWidget);
    expect(identical(t.state(find.byKey(const ValueKey('okuyucu-html'))), govdeDurumu), isTrue);
    expect(t.getRect(find.byKey(const ValueKey('okuyucu-govde-alani'))).bottom, ustAlan.bottom);
    await kapat(t);
  });

  testWidgets('süzgeç sekmeleri: seçim ve okunmamış sayısı değişince sekmelerin yeri / boyu aynı', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Future<Map<ListeFiltresi, Rect>> ciz(ListeFiltresi secili, Map<ListeFiltresi, int> sayilar) async {
      await t.pumpWidget(
        MaterialApp(
          theme: temaKur(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                child: FiltreCubugu(secili: secili, degisti: (_) {}, sayilar: sayilar),
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      return {for (final f in ListeFiltresi.values) f: t.getRect(find.byKey(ValueKey('filtre-${f.name}')))};
    }

    final ilk = await ciz(ListeFiltresi.tumu, const {});
    for (final (secili, sayilar) in [
      (ListeFiltresi.okunmamis, const <ListeFiltresi, int>{}),
      (ListeFiltresi.okunmamis, {ListeFiltresi.okunmamis: 7}),
      (ListeFiltresi.yildizli, {ListeFiltresi.okunmamis: 128}),
      (ListeFiltresi.ekli, {ListeFiltresi.okunmamis: 2048}),
      (ListeFiltresi.tumu, {ListeFiltresi.okunmamis: 1}),
    ]) {
      final r = await ciz(secili, sayilar);
      for (final f in ListeFiltresi.values) {
        expect(r[f], ilk[f], reason: '${f.name} sekmesi kaydı ($secili, $sayilar)');
      }
    }
  });
}
