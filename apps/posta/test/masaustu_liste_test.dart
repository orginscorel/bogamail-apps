// Masaüstü liste: başlıkta "Sayfadaki tümünü seç", Ctrl/Cmd ve Shift ile tıklama seçimi, iletileri kenar menüsündeki
// klasör/etiketlere sürükleyip bırakma, "Klasör ara" süzgeci. Ağ yok (sahte sunucu).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/ileti_listesi.dart';
import 'package:posta/ekranlar/yan_menu.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

Map<String, dynamic> _ileti(String id, String konu) => {'id': id, 'subject': konu, 'from': 'Ali <ali@ornek.com>', 'date': '2026-11-20T09:00:00Z', 'seen': true};

void main() {
  final s = YolSunucusu();
  setUpAll(() async {
    Onyukleme.etkin = false;
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    s.kur();
  });
  setUp(() {
    s.istekler.clear();
    s.yollar
      ..clear()
      ..['GET /api/v1/mail/folders/g/messages'] = (
        200,
        {
          'items': [_ileti('a', 'Bir'), _ileti('b', 'İki'), _ileti('c', 'Üç'), _ileti('d', 'Dört')],
          'total': 4,
          'page': 1,
          'page_size': 50,
        },
      )
      ..['POST /api/v1/mail/messages/bulk'] = (200, {'updated': 1});
    PostaDurum.ben
      ..klasorler = [
        Klasor(id: 'g', ad: 'INBOX', rol: 'inbox'),
        Klasor(id: 's', ad: 'Sent', rol: 'sent'),
        for (var i = 1; i <= 10; i++) Klasor(id: 'u$i', ad: i == 7 ? 'İzmir Projesi' : 'Klasör $i'),
      ]
      ..etiketler = [Etiket(id: 'e1', ad: 'Acil', renk: 'red')]
      ..yuklendi = true;
  });
  tearDown(PostaDurum.ben.sifirla);

  Future<void> kur(WidgetTester t, {List<IletiOzet>? acilan}) async {
    t.view.physicalSize = const Size(1440, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(width: 300, child: YanMenu(sec: (_) {})),
              Expanded(
                child: IletiListesi(konum: const Konum.klasor('g'), ac: (m) => acilan?.add(m)),
              ),
            ],
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
  }

  Future<void> bitir(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  testWidgets('başlık kutusu tümünü seçer; Ctrl/Shift tıklama seçer, düz tıklama açar', (t) async {
    final acilan = <IletiOzet>[];
    await kur(t, acilan: acilan);
    expect(find.text('Bir'), findsOneWidget);
    final kutu = find.byKey(const ValueKey('hepsini-sec'));
    expect(kutu, findsOneWidget);

    await t.tap(kutu);
    await t.pump();
    expect(find.text('4 ileti seçildi'), findsOneWidget);
    await t.tap(kutu);
    await t.pump();
    expect(find.textContaining('seçildi'), findsNothing);

    // Ctrl+tıklama: tek seçim; Shift+tıklama: aralık.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.tap(find.text('Bir'));
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(find.text('1 ileti seçildi'), findsOneWidget);
    expect(acilan, isEmpty);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.tap(find.text('Üç'));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(find.text('3 ileti seçildi'), findsOneWidget);
    expect(t.widget<Checkbox>(kutu).value, isNull, reason: 'kısmi seçim');

    // Düz tıklama web gibi iletiyi açar, seçimi bozmaz.
    await t.tap(find.text('Dört'));
    await t.pump();
    expect(acilan.map((m) => m.id), ['d']);
    expect(find.text('3 ileti seçildi'), findsOneWidget);
    await bitir(t);
  });

  testWidgets('seçili iletiler klasöre sürüklenince taşınır, etikete sürüklenince etiketlenir', (t) async {
    await kur(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.tap(find.text('Bir'));
    await t.tap(find.text('İki'));
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();

    Future<void> surukle(String kaynak, Finder hedef) async {
      final g = await t.startGesture(t.getCenter(find.text(kaynak)), kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(-30, 0));
      await t.pump();
      expect(find.byKey(const ValueKey('surukleme-gorseli')), findsOneWidget);
      await g.moveTo(t.getCenter(hedef));
      await t.pump();
      await g.up();
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
    }

    // Etiket: seçim (2 ileti) etiketlenir, listede kalır.
    await surukle('Bir', find.text('Acil'));
    final etiket = s.bul('POST', '/api/v1/mail/messages/bulk').last.json;
    expect(etiket['action'], 'label');
    expect(etiket['label_id'], 'e1');
    expect(etiket['ids'], ['a', 'b']);
    expect(find.text('Bir'), findsOneWidget);

    // Gönderilmiş klasörü hedef değildir (web ile aynı).
    expect(find.byKey(const ValueKey('birak-klasor-s')), findsNothing);
    expect(find.byKey(const ValueKey('birak-klasor-g')), findsOneWidget);

    // Seçili olmayan tek ileti kullanıcı klasörüne taşınır.
    s.istekler.clear();
    await surukle('Dört', find.text('Klasör 1'));
    final tasi = s.bul('POST', '/api/v1/mail/messages/bulk').single.json;
    expect(tasi['action'], 'move');
    expect(tasi['folder_id'], 'u1');
    expect(tasi['ids'], ['d']);
    expect(find.text('Dört'), findsNothing);
    await bitir(t);
  });

  testWidgets('Klasör ara: 8\'den fazla kullanıcı klasöründe görünür, Türkçe harfle süzer', (t) async {
    await kur(t);
    final ara = find.byKey(const ValueKey('klasor-ara'));
    expect(ara, findsOneWidget);
    expect(find.text('Klasör 3'), findsOneWidget);
    await t.enterText(ara, 'izmir');
    await t.pump();
    expect(find.text('İzmir Projesi'), findsOneWidget);
    expect(find.text('Klasör 3'), findsNothing);
    expect(find.text('Gelen Kutusu'), findsWidgets, reason: 'sistem klasörleri süzülmez');
    await t.enterText(ara, 'yok');
    await t.pump();
    expect(find.text('Eşleşen klasör yok.'), findsOneWidget);
    await bitir(t);
  });
}
