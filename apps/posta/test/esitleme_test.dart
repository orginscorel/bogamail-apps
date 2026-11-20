// Eşitleme göstergesi metinleri ve şerit davranışı. Ağ yok.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posta/ortak/esitleme.dart';
import 'package:posta/veri/canli.dart';

void main() {
  test('metinler: canlı, bağlanıyor, geri sayım, son eşitleme', () {
    final t = DateTime(2026, 11, 20, 12);
    expect(esitlemeMetni(const CanliDurumu(CanliTur.bagli), t), 'Canlı');
    expect(esitlemeMetni(const CanliDurumu(CanliTur.baglaniyor), t), 'Bağlanıyor…');
    expect(esitlemeMetni(CanliDurumu(CanliTur.yok, sonrakiDeneme: t.add(const Duration(seconds: 7))), t), 'Bağlantı yok — 8 sn sonra yeniden denenecek');
    expect(esitlemeMetni(CanliDurumu(CanliTur.yok, sonrakiDeneme: t.subtract(const Duration(seconds: 2))), t), 'Bağlantı yok — yeniden deneniyor');
    expect(sonEsitlemeMetni(null, t), 'Henüz eşitlenmedi');
    expect(sonEsitlemeMetni(t.subtract(const Duration(seconds: 2)), t), 'Son eşitleme: az önce');
    expect(sonEsitlemeMetni(t.subtract(const Duration(seconds: 42)), t), 'Son eşitleme: 42 sn önce');
    expect(sonEsitlemeMetni(t.subtract(const Duration(minutes: 5)), t), 'Son eşitleme: 5 dk önce');
  });

  testWidgets('şerit yalnız bağlantı yokken görünür ve geri sayar', (t) async {
    Canli.ben.durum.value = const CanliDurumu(CanliTur.bagli);
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        home: const Scaffold(body: EsitlemeDurumu(serit: true)),
      ),
    );
    expect(find.byKey(const ValueKey('esitleme-serit')), findsNothing);
    Canli.ben.durum.value = CanliDurumu(CanliTur.yok, sonrakiDeneme: DateTime.now().add(const Duration(seconds: 10)));
    await t.pump();
    expect(find.byKey(const ValueKey('esitleme-serit')), findsOneWidget);
    expect(find.textContaining('sn sonra yeniden denenecek'), findsOneWidget);
    expect(find.text('Şimdi eşitle'), findsOneWidget);
    Canli.ben.durum.value = const CanliDurumu(CanliTur.bagli);
    await t.pump();
    expect(find.byKey(const ValueKey('esitleme-serit')), findsNothing);
    Canli.ben.durum.value = const CanliDurumu(CanliTur.kapali);
    await t.pumpWidget(const SizedBox());
  });
}
