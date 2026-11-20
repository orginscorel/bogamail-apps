import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ortak/sayfali.dart';
import 'package:yonetim/ortak/tablo.dart';
import 'package:yonetim/veri/json.dart';

import 'sahte_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  SayfaYukleyici<int> yukleyici() => SayfaYukleyici<int>((s, b) async {
    final l = [for (var i = (s - 1) * b; i < s * b && i < 60; i++) i];
    return Sayfa(l, 60);
  }, sayfaBoyu: 25);

  Widget tablo(SayfaYukleyici<int> y, {void Function(String, bool)? sirala, String? siralama}) => testUygulamasi(
    Scaffold(
      body: VeriTablosu<int>(
        yukleyici: y,
        bosMetin: 'Boş',
        siralama: siralama,
        siralamaDegisti: sirala,
        sutunlar: [
          Sutun('Numara', hucre: (_, i) => Text('No $i'), siralama: 'no'),
          Sutun('Çift mi', hucre: (_, i) => Text(i.isEven ? 'çift' : 'tek')),
        ],
        eylemler: (i) => [SatirEylemi(Icons.delete_outline, 'Sil', () {})],
        kart: (_, i) => VeriKarti(baslik: 'Kart $i', alanlar: [('Tür', i.isEven ? 'çift' : 'tek')]),
      ),
    ),
  );

  testWidgets('geniş ekranda başlık satırı, sayfalama ve sıralama', (t) async {
    ekranBoyutu(t, const Size(1400, 900));
    final y = yukleyici()..yenile();
    String? alan;
    bool? artan;
    await t.pumpWidget(tablo(y, sirala: (a, b) {
      alan = a;
      artan = b;
    }));
    await t.pumpAndSettle();
    expect(find.text('NUMARA'), findsOneWidget);
    expect(find.text('No 0'), findsOneWidget);
    expect(find.text('1–25 / 60 kayıt'), findsOneWidget);
    expect(find.text('Sayfa 1 / 3'), findsOneWidget);
    await t.tap(find.byTooltip('Sonraki sayfa'));
    await t.pumpAndSettle();
    expect(find.text('No 25'), findsOneWidget);
    expect(find.text('26–50 / 60 kayıt'), findsOneWidget);
    await t.tap(find.text('NUMARA'));
    expect(alan, 'no');
    expect(artan, isTrue);
    expect(find.byTooltip('İşlemler'), findsWidgets);
  });

  testWidgets('dar ekranda kartlar', (t) async {
    ekranBoyutu(t, const Size(400, 800));
    final y = yukleyici()..yenile();
    await t.pumpWidget(tablo(y));
    await t.pumpAndSettle();
    expect(find.text('Kart 0'), findsOneWidget);
    expect(find.text('NUMARA'), findsNothing);
  });

  testWidgets('etkin filtre çipleri temizlenir', (t) async {
    var a = true, b = true;
    await t.pumpWidget(testUygulamasi(StatefulBuilder(
      builder: (c, yenile) => Scaffold(
        body: FiltreCubugu(etkinler: [
          if (a) EtkinFiltre('Durum: Aktif', () => yenile(() => a = false)),
          if (b) EtkinFiltre('Alan: ornek.com', () => yenile(() => b = false)),
        ]),
      ),
    )));
    expect(find.text('Durum: Aktif'), findsOneWidget);
    await t.tap(find.text('Tümünü temizle'));
    await t.pump();
    expect(find.text('Durum: Aktif'), findsNothing);
    expect(find.text('Alan: ornek.com'), findsNothing);
  });

  test('yerel sayfalama', () async {
    final y = SayfaYukleyici.yerel<int>(() async => List.generate(120, (i) => i), sayfaBoyu: 50);
    await y.yenile();
    expect(y.ogeler.length, 50);
    expect(y.sayfaSayisi, 3);
    await y.sayfaGit(3);
    expect(y.ogeler.first, 100);
    expect(y.ilkSira, 100);
    expect(y.dahaVar, isFalse);
  });
}
