// Geniş ekran: etkin hesap sol rayın en altında (36 px avatar, ipucu "Ad — adres", diğer hesaplarda okunmamış
// varsa nokta); dokununca hesap menüsü rayın sağında açılır. Klasör kenar çubuğunda hesap kartı ve ikinci "Ayarlar"
// yok; telefonda (çekmece) hesap bloğu altta kalır. Ağ yok.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posta/ekranlar/sol_ray.dart';
import 'package:posta/ekranlar/yan_menu.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/birlesik.dart';
import 'package:posta/veri/canli.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/tercihler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

void main() {
  final s = YolSunucusu();
  setUpAll(s.kur);
  setUp(() {
    s.yollar
      ..clear()
      ..['GET /api/v1/mail/auth/accounts'] = (200, {'items': []});
    Uyg.kutu.value = {'mailbox_id': 'k1', 'address': 'info@bogahost.com', 'display_name': 'Semih Yılmaz'};
    PostaDurum.ben
      ..klasorler = [Klasor(id: 'g', ad: 'INBOX', rol: 'inbox')]
      ..yuklendi = true;
  });
  setUpAll(() {
    Guncelleme.surum = '1.4.2';
    Guncelleme.derleme = 11;
  });
  tearDown(() {
    Canli.ben.durum.value = const CanliDurumu(CanliTur.kapali);
    Canli.ben.sonOlay.value = null;
    PostaDurum.ben.sifirla();
    BirlesikDurum.ben.sifirla();
  });

  Future<void> genis(WidgetTester t, {double yukseklik = 800, bool ayarlarSecili = false, VoidCallback? ayarlarAc}) async {
    t.view.physicalSize = Size(1280, yukseklik);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        home: Scaffold(
          body: Row(
            children: [
              SolRay(
                hedefler: const [
                  NavigationRailDestination(icon: Icon(Simge.posta), label: Text('Posta')),
                  NavigationRailDestination(icon: Icon(Simge.sohbet), label: Text('Sohbet')),
                  NavigationRailDestination(icon: Icon(Simge.takvimAy), label: Text('Takvim')),
                  NavigationRailDestination(icon: Icon(Simge.gorev), label: Text('Görevler')),
                ],
                secili: ayarlarSecili ? null : 0,
                sec: (_) {},
                ayarlarSecili: ayarlarSecili,
                ayarlarAc: ayarlarAc ?? () {},
              ),
              SizedBox(
                width: 280,
                child: YanMenu(sec: (_) {}, yeniIleti: () {}),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('hesap sol rayın altında; klasör çubuğunda kart ve ikinci Ayarlar yok; menü sağda açılır', (t) async {
    await genis(t);
    final ray = find.byKey(const ValueKey('ray-hesap'));
    expect(ray, findsOneWidget);
    expect(t.getCenter(ray).dy, greaterThan(700), reason: 'rayın en altında');
    expect(t.getSize(find.descendant(of: ray, matching: find.byType(Avatar))).width, 36);
    expect(find.byTooltip('Semih Yılmaz — info@bogahost.com'), findsOneWidget);
    expect(find.byKey(const ValueKey('hesap-blogu')), findsNothing);
    expect(find.text('Ayarlar'), findsOneWidget, reason: 'yalnız raydaki');
    expect(find.byKey(const ValueKey('ray-hesap-nokta')), findsNothing);

    await t.tap(ray);
    await t.pumpAndSettle();
    final ekle = find.byKey(const ValueKey('menu-hesap-ekle'));
    expect(ekle, findsOneWidget);
    expect(t.getTopLeft(ekle).dx, greaterThan(t.getTopRight(ray).dx), reason: 'rayın sağında');
  });

  testWidgets('diğer hesapta okunmamış varsa rayda nokta', (t) async {
    BirlesikDurum.ben.hesapOkunmamis = {'k1': 0, 'k2': 3};
    await genis(t);
    expect(find.byKey(const ValueKey('ray-hesap-nokta')), findsOneWidget);
  });

  testWidgets('telefon çekmecesinde hesap bloğu altta kalır', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        home: Scaffold(body: YanMenu(sec: (_) {}, cekmecede: true)),
      ),
    );
    await t.pump();
    expect(find.byKey(const ValueKey('hesap-blogu')), findsOneWidget);
    expect(find.text('Semih Yılmaz'), findsOneWidget);
  });

  testWidgets('ray altı: Ayarlar, eşitleme noktası, sürüm, avatar sırayla; klasör çubuğunun altı boş', (t) async {
    Canli.ben.durum.value = const CanliDurumu(CanliTur.bagli);
    Canli.ben.sonOlay.value = DateTime.now().subtract(const Duration(seconds: 21));
    var acildi = 0;
    await genis(t, ayarlarAc: () => acildi++);
    final ayar = find.byKey(const ValueKey('ray-ayarlar'));
    final nokta = find.byKey(const ValueKey('ray-esitleme'));
    final surum = find.text('1.4.2');
    final hesap = find.byKey(const ValueKey('ray-hesap'));
    expect(t.getCenter(ayar).dy, greaterThan(t.getCenter(find.text('Görevler')).dy + 100), reason: 'Ayarlar altta');
    expect(t.getCenter(nokta).dy, greaterThan(t.getCenter(ayar).dy));
    expect(t.getCenter(surum).dy, greaterThan(t.getCenter(nokta).dy));
    expect(t.getCenter(hesap).dy, greaterThan(t.getCenter(surum).dy));
    expect(find.byKey(const ValueKey('ray-esitleme-bagli')), findsOneWidget);
    expect(find.byTooltip('Canlı · Son eşitleme 21 sn önce\nDokun: Şimdi eşitle'), findsOneWidget);
    expect(find.byTooltip('Sürüm 1.4.2 (11)'), findsOneWidget);
    expect(t.widget<Text>(surum).style!.fontSize, 10);
    expect(t.getSize(find.byKey(const ValueKey('sol-ray'))).width, rayGenisligi);
    // Klasör çubuğunda eşitleme / sürüm / hesap yok.
    expect(find.byKey(const ValueKey('esitleme-durumu')), findsNothing);
    expect(find.textContaining('Sürüm 1.4.2'), findsNothing);
    await t.tap(ayar);
    expect(acildi, 1);
  });

  testWidgets('bağlantı yokken nokta kırmızı ve geri sayım gösterir', (t) async {
    Canli.ben.durum.value = CanliDurumu(CanliTur.yok, sonrakiDeneme: DateTime.now().add(const Duration(seconds: 12)));
    await genis(t);
    expect(find.byKey(const ValueKey('ray-esitleme-yok')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^1[12] sn$')), findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('sol-ray'))).width, rayGenisligi);
  });

  for (final h in [600.0, 700.0, 800.0, 900.0, 1000.0]) {
    testWidgets('ray ${h.round()} px yükseklikte taşmaz, genişlemez', (t) async {
      Canli.ben.durum.value = CanliDurumu(CanliTur.yok, sonrakiDeneme: DateTime.now().add(const Duration(seconds: 12)));
      await genis(t, yukseklik: h, ayarlarSecili: true);
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byKey(const ValueKey('sol-ray'))).width, rayGenisligi);
      expect(t.getBottomRight(find.byKey(const ValueKey('ray-hesap'))).dy, lessThanOrEqualTo(h));
      // Kısa pencerede önce sürüm gizlenir.
      expect(find.text('1.4.2'), h < 640 ? findsNothing : findsOneWidget);
    });
  }

  testWidgets('liste/okuyucu bölme çizgisi sürüklenir; genişlik saklanır', (t) async {
    SharedPreferences.setMockInitialValues({});
    var en = 420.0;
    var bitti = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, yenile) => Row(
              children: [
                SizedBox(width: en),
                BolmeCizgisi(
                  renk: Colors.grey,
                  surukle: (dx) => yenile(() => en = bolmeBoyu(alan: 1280, oran: (en + dx) / 1280, enAz: 340, enCok: 600, kalan: 600)),
                  bitti: () => bitti++,
                  sifirla: () {},
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await t.drag(find.byKey(const ValueKey('liste-bolme')), const Offset(60, 0));
    await t.pump();
    expect(en, closeTo(480, 1));
    expect(bitti, 1);
    await t.drag(find.byKey(const ValueKey('liste-bolme')), const Offset(-400, 0));
    await t.pump();
    expect(en, 340);
    // Web mail-view.tsx: %36 varsayılan, 340–600 px, okumaya ≥ 600 px; oran saklanır.
    expect(bolmeBoyu(alan: 1200, oran: .36, enAz: 340, enCok: 600, kalan: 600), 432);
    expect(bolmeBoyu(alan: 1000, oran: .36, enAz: 340, enCok: 600, kalan: 600), 360);
    expect(bolmeBoyu(alan: 900, oran: .36, enAz: 340, enCok: 600, kalan: 600), 340, reason: 'okumaya 600 kalmasa da en az 340');
    expect(bolmeBoyu(alan: 2400, oran: .36, enAz: 340, enCok: 600, kalan: 600), 600);
    await Tercihler.listeOraniAyarla(.5);
    Tercihler.listeOrani.value = null;
    await Tercihler.yukle();
    expect(Tercihler.listeOrani.value, .5);
    await Tercihler.listeOraniAyarla(null);
    await t.pump(const Duration(seconds: 1));
  });
}
