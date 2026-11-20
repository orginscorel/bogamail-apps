// Konuşma görünümü: yığın (kapalı satırlar, "N ileti daha"), okunmamış/son ileti açık, ilk okunmamışa kaydırma,
// alıntı ve tekrarlanan imzanın "•••" arkasına katlanması, sıkı ek şeridi; alıntı/imza ayırma kuralları (web ile
// aynı). Ağ yok (sahte sunucu).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/okuyucu.dart';
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

  testWidgets('yığın: ilk ileti kapalı satır, ortadaki 5 ileti toplanır, okunmamışlar ve son ileti açık', (t) async {
    await ac(t);
    expect(find.byKey(const ValueKey('konusma')), findsOneWidget);
    expect(find.byKey(const ValueKey('konusma-kapali-k1')), findsOneWidget);
    expect(find.text('5 ileti daha'), findsOneWidget);
    for (final id in ['k2', 'k3', 'k4', 'k5', 'k6']) {
      expect(find.byKey(ValueKey('konusma-kapali-$id')), findsNothing);
    }
    expect(find.byKey(const ValueKey('konusma-ileti-k7')), findsOneWidget);
    expect(find.byKey(const ValueKey('konusma-ileti-k8')), findsOneWidget);
    // Konu bir kez, üstte.
    expect(find.text('Re: $konusmaKonu'), findsOneWidget);
    expect(find.text('8 ileti · 3 kişi'), findsOneWidget);
    // Açılan okunmamış ileti (k7) okundu işaretlenir.
    expect(s.bul('PATCH', '/api/v1/mail/messages/k7').map((i) => i.json['seen']), contains(true));

    await t.tap(find.text('5 ileti daha'));
    await t.pump();
    for (final id in ['k2', 'k3', 'k4', 'k5', 'k6']) {
      expect(find.byKey(ValueKey('konusma-kapali-$id')), findsOneWidget);
    }
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
    expect(find.byKey(const ValueKey('konusma-kapali-k1')).hitTestable(), findsNothing);
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

  test('düz metin imza ayırma ("-- " ayıracı)', () {
    const m = 'Merhaba\n\n-- \nAyşe\nSatış';
    expect(alintiVeImzaAyir(m).ana, m);
    final p = alintiVeImzaAyir(m, imza: true);
    expect(p.ana, 'Merhaba');
    expect(p.alinti, startsWith('-- '));
    expect(alintiVeImzaAyir('-- \nyalnız imza', imza: true).ana, '-- \nyalnız imza');
  });
}
