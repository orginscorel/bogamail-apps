// Yazma ekranı: compose_html ayarı (biçimli/düz başlangıç), biçimli gövdenin web ile aynı yapıda gönderilmesi
// (yazı bloğu + [data-signature] imza), "Yüksek önem" (priority: high), düz metne geçiş. Ağ yok (sahte sunucu).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/yazma.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/yazma_hazirla.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

void main() {
  final s = YolSunucusu();
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    s.kur();
  });
  setUp(() {
    s.istekler.clear();
    s.yollar
      ..clear()
      ..['POST /api/v1/mail/send'] = (200, {'queued': true})
      ..['GET /api/v1/mail/folders'] = (200, {'items': []})
      ..['GET /api/v1/mail/labels'] = (200, {'items': []});
  });
  tearDown(PostaDurum.ben.sifirla);

  Future<void> ac(WidgetTester t, {required bool bicimli}) async {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    PostaDurum.ben.ayarlar = PostaAyarlari.json({
      'settings': {'display_name': 'Ayşe', 'compose_html': bicimli, 'signature_html': '<b>Ayşe</b> Yılmaz'},
    });
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => YazmaEkrani(
              baslangic: YazmaBaslangic(kime: const [Adres('Ali', 'ali@ornek.com')], konu: 'Selam'),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('compose_html açık: biçimli düzenleyici; gövde web yapısında, Yüksek önem priority=high', (t) async {
    await ac(t, bicimli: true);
    expect(find.byKey(const ValueKey('zengin-duzenleyici')), findsOneWidget);
    expect(find.byKey(const ValueKey('bicimlendirme')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('zengin-metin')), 'Merhaba');
    await t.tap(find.byKey(const ValueKey('yuksek-onem')));
    await t.pump();
    expect(find.text('Yüksek önem'), findsWidgets);
    await t.tap(find.text('Gönder'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final r = s.bul('POST', '/api/v1/mail/send').single.json;
    expect(r['html'], '<div>Merhaba</div><div><br></div><div data-signature=""><b>Ayşe</b> Yılmaz</div>');
    expect(r['text'], contains('Merhaba'));
    expect(r['text'], contains('Ayşe Yılmaz'));
    expect(r['priority'], 'high');
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('compose_html kapalı: düz metin; menüden biçimliye geçilebilir', (t) async {
    await ac(t, bicimli: false);
    expect(find.byKey(const ValueKey('zengin-duzenleyici')), findsNothing);
    expect(find.byKey(const ValueKey('bicimlendirme')), findsNothing);
    await t.tap(find.byTooltip('Diğer seçenekler'));
    await t.pumpAndSettle();
    expect(find.text('Biçimli metne geç'), findsOneWidget);
    await t.tap(find.text('Biçimli metne geç'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('zengin-duzenleyici')), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });
}
