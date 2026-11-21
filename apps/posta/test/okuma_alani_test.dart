// Okuma alanı (sunucu ayarı reading_pane, web ile ortak): ayarlardan okunur, Ayarlar › Okuma alanı PATCH eder.
// Ağ yok (sahte sunucu).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posta/ekranlar/ayarlar/okuma_alani_ayari.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/modeller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

void main() {
  final s = YolSunucusu();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    s.kur();
  });
  tearDown(PostaDurum.ben.sifirla);

  test('reading_pane çözümü: right | bottom | off, bilinmeyen değer Sağda', () {
    expect(PostaAyarlari.json({'settings': {}}).okumaAlani, 'right');
    expect(
      PostaAyarlari.json({
        'settings': {'reading_pane': 'bottom'},
      }).okumaAlani,
      'bottom',
    );
    expect(
      PostaAyarlari.json({
        'settings': {'reading_pane': 'off'},
      }).okumaAlani,
      'off',
    );
    expect(
      PostaAyarlari.json({
        'settings': {'reading_pane': 'left'},
      }).okumaAlani,
      'right',
    );
  });

  testWidgets('Ayarlar › Okuma alanı: seçim sunucuya reading_pane olarak yazılır, hata olursa geri alınır', (t) async {
    s.istekler.clear();
    s.yollar
      ..clear()
      ..['PATCH /api/v1/mail/settings'] = (200, {'ok': true});
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        home: const Scaffold(body: OkumaAlaniAyari()),
      ),
    );
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Sağda')).selected, isTrue);
    await t.tap(find.text('Altta'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(PostaDurum.ben.okumaAlani.value, 'bottom');
    expect(s.bul('PATCH', '/api/v1/mail/settings').single.json, {'reading_pane': 'bottom'});
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Altta')).selected, isTrue);

    s.yollar['PATCH /api/v1/mail/settings'] = (422, {'error': 'invalid', 'field': 'reading_pane'});
    await t.tap(find.text('Kapalı'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(PostaDurum.ben.okumaAlani.value, 'bottom', reason: 'sunucu reddetti: geri alındı');
    await t.pump(const Duration(seconds: 5));
  });
}
