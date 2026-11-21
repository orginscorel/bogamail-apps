// Tasarım görüntüleri: ana ekranları 390x844 (telefon) ve 1280x800 (geniş) boyutlarında PNG olarak üretir.
// Yalnız GORUNTU_DIZIN verilince dosya yazar (yerel yazı tipleri yüklenir); aksi halde ekranların hatasız
// çizildiğini denetleyen sıradan bir testtir. GORUNTU_ONEK dosya adının başına eklenir (ör. once / sonra).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/ayarlar.dart';
import 'package:posta/ekranlar/birlesik_ekrani.dart';
import 'package:posta/ekranlar/ileti_listesi.dart';
import 'package:posta/ekranlar/ileti_satiri.dart';
import 'package:posta/ekranlar/okuyucu.dart';
import 'package:posta/ekranlar/sol_ray.dart';
import 'package:posta/ekranlar/yan_menu.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/birlesik.dart';
import 'package:posta/veri/canli.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'konusma_ornek.dart';
import 'sahte_sunucu.dart';

Future<void> _font(String aile, List<String> dosyalar) async {
  final l = FontLoader(aile);
  for (final d in dosyalar) {
    if (!File(d).existsSync()) return;
    final b = File(d).readAsBytesSync();
    l.addFont(Future.value(ByteData.view(b.buffer)));
  }
  await l.load();
}

String _iso(int saat) => DateTime.utc(2026, 11, 20, saat).toIso8601String();

final _iletiler = [
  {
    'id': 'a',
    'subject': 'Teklif: kurumsal paket yenileme',
    'from': 'Ayşe Yılmaz <ayse@ornek.com>',
    'preview': 'Merhaba, ekte güncel teklifi bulabilirsiniz.',
    'date': _iso(9),
    'seen': false,
    'has_attachments': true,
  },
  {
    'id': 'b',
    'subject': 'Toplantı notları',
    'from': 'Ali Veli <ali@ornek.com>',
    'preview': 'Bugünkü toplantının özetini paylaşıyorum.',
    'date': _iso(8),
    'seen': true,
    'flagged': true,
  },
  {'id': 'c', 'subject': 'Fatura #2026-114', 'from': 'Muhasebe <muhasebe@ornek.com>', 'preview': 'Kasım ayı faturanız hazır.', 'date': _iso(7), 'seen': false},
  {
    'id': 'd',
    'subject': 'Sunucu bakımı',
    'from': 'Bogahost <destek@bogahost.com>',
    'preview': 'Cumartesi 02:00–04:00 arasında planlı bakım.',
    'date': _iso(6),
    'seen': true,
  },
  {'id': 'e', 'subject': 'Yeni çalışan', 'from': 'İK <ik@ornek.com>', 'preview': 'Ekibimize katılan arkadaşımızı tanıtıyoruz.', 'date': _iso(5), 'seen': true},
];

void main() {
  final dizin = Platform.environment['GORUNTU_DIZIN'];
  final onek = Platform.environment['GORUNTU_ONEK'] ?? 'goruntu';
  final s = YolSunucusu();
  setUpAll(() async {
    Onyukleme.etkin = false;
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    s.kur();
    Guncelleme.surum = '1.4.2';
    Guncelleme.derleme = 11;
    Canli.ben.durum.value = const CanliDurumu(CanliTur.bagli);
    Canli.ben.sonOlay.value = DateTime.now().subtract(const Duration(seconds: 21));
    if (dizin == null) return;
    const f = '../../packages/boga_ortak/assets/fonts';
    await _font('packages/boga_ortak/Poppins', ['$f/Poppins-Regular.ttf', '$f/Poppins-Medium.ttf', '$f/Poppins-SemiBold.ttf', '$f/Poppins-Bold.ttf']);
    await _font('packages/boga_ortak/Jakarta', ['$f/PlusJakartaSans.ttf']);
    await _font('MaterialIcons', ['${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    await _font('packages/boga_ortak/PhosphorLight', ['$f/PhosphorLight.ttf']);
    await _font('packages/boga_ortak/PhosphorFill', ['$f/PhosphorFill.ttf']);
  });
  setUp(() {
    s.istekler.clear();
    s.yollar
      ..clear()
      ..['GET /api/v1/mail/folders/g/messages'] = (200, {'items': _iletiler, 'total': 5, 'page': 1, 'page_size': 50})
      ..['GET /api/v1/mail/unified/messages'] = (
        200,
        {
          'accounts': [
            {'id': 'k1', 'address': 'semih@ornek.com', 'display_name': 'Semih', 'color': '#2563eb'},
            {'id': 'k2', 'address': 'info@ornek.com', 'display_name': 'Info', 'color': '#16a34a'},
          ],
          'items': [
            for (final (i, m) in _iletiler.indexed) {...m, 'mailbox_id': i.isEven ? 'k1' : 'k2', 'account': i.isEven ? 'semih@ornek.com' : 'info@ornek.com'},
          ],
          'next_before': null,
        },
      )
      ..['GET /api/v1/mail/settings'] = (200, {'display_name': 'Semih Boğa', 'page_size': 50, 'features': {}})
      ..['GET /api/v1/mail/auth/accounts'] = (200, {'items': []})
      ..['GET /api/v1/mail/auth/me'] = (
        200,
        {
          'mailbox': {'mailbox_id': 'm1', 'address': 'semih@ornek.com', 'display_name': 'Semih Boğa'},
        },
      );
    Uyg.kutu.value = {'mailbox_id': 'm1', 'address': 'semih@ornek.com', 'display_name': 'Semih Boğa'};
    PostaDurum.ben
      ..klasorler = [
        Klasor(id: 'g', ad: 'INBOX', rol: 'inbox', okunmamis: 2, toplam: 5),
        Klasor(id: 't', ad: 'Drafts', rol: 'drafts', toplam: 1),
        Klasor(id: 's', ad: 'Sent', rol: 'sent'),
        Klasor(id: 'a', ad: 'Archive', rol: 'archive'),
        Klasor(id: 'j', ad: 'Junk', rol: 'junk'),
        Klasor(id: 'c', ad: 'Trash', rol: 'trash'),
        Klasor(id: 'u1', ad: 'Projeler', okunmamis: 1),
        Klasor(id: 'u2', ad: 'Faturalar'),
      ]
      ..etiketler = [Etiket(id: 'e1', ad: 'Acil', renk: 'red'), Etiket(id: 'e2', ad: 'Müşteri', renk: 'blue')]
      ..yuklendi = true;
    BirlesikDurum.ben
      ..hesapSayisi = 2
      ..toplamOkunmamis = 584
      ..hesapOkunmamis = {'k1': 584, 'k2': 0};
  });
  tearDown(() {
    PostaDurum.ben.sifirla();
    BirlesikDurum.ben.sifirla();
  });

  Future<void> ciz(WidgetTester t, String ad, Size boyut, Widget Function() ekran, {Future<void> Function()? hazirla}) async {
    t.view.physicalSize = boyut * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final anahtar = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        home: RepaintBoundary(key: anahtar, child: ekran()),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    if (hazirla != null) {
      await hazirla();
      await t.pump(const Duration(milliseconds: 300));
    }
    final satir = find.byType(IletiSatiri);
    if (satir.evaluate().isNotEmpty) {
      final y = t.getSize(satir.first).height;
      debugPrint('[satır] $onek-$ad: ileti satırı yüksekliği ${y.toStringAsFixed(1)} px');
    }
    if (dizin != null) {
      final ro = anahtar.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await t.runAsync(() => ro.toImage(pixelRatio: 2));
      final b = await t.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
      File('$dizin/$onek-$ad.png').writeAsBytesSync(b!.buffer.asUint8List());
    }
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  }

  // Kabuk'un geniş düzeni: sabit 80 px sol ray (bölümler üstte; Ayarlar, eşitleme, sürüm, hesap altta), klasör
  // çubuğu, liste (1280'de 420, 1400+'da 460 px) ve okuyucu.
  Widget genis(Widget liste, {Widget? okuyucu, double kenar = 280, double listeEni = 420}) => Scaffold(
    body: Row(
      children: [
        SolRay(
          hedefler: const [
            NavigationRailDestination(icon: Icon(Simge.posta), label: Text('Posta')),
            NavigationRailDestination(icon: Icon(Simge.sohbet), label: Text('Sohbet')),
            NavigationRailDestination(icon: Icon(Simge.takvimAy), label: Text('Takvim')),
            NavigationRailDestination(icon: Icon(Simge.gorev), label: Text('Görevler')),
          ],
          secili: 0,
          sec: (_) {},
          ayarlarSecili: false,
          ayarlarAc: () {},
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: kenar,
          child: YanMenu(sec: (_) {}, yeniIleti: () {}),
        ),
        const VerticalDivider(width: 1),
        SizedBox(width: listeEni, child: liste),
        BolmeCizgisi(renk: const Color(0xFFE5E7EB), surukle: (_) {}, bitti: () {}, sifirla: () {}),
        Expanded(child: okuyucu ?? const SizedBox()),
      ],
    ),
  );

  const telefon = Size(390, 844);
  const masaustu = Size(1280, 800);

  testWidgets('tüm hesaplar', (t) async {
    await ciz(t, 'birlesik-telefon', telefon, () => BirlesikListe(ac: (_, _) {}, klasorler: () {}, klasorRozeti: 584));
    await ciz(t, 'birlesik-genis', masaustu, () => genis(BirlesikListe(ac: (_, _) {})));
  });

  testWidgets('gelen kutusu', (t) async {
    await ciz(t, 'gelen-telefon', telefon, () => IletiListesi(konum: const Konum.klasor('g'), ac: (_) {}, klasorler: () {}));
    await ciz(t, 'gelen-genis', masaustu, () => genis(IletiListesi(konum: const Konum.klasor('g'), ac: (_) {})));
    await ciz(t, 'gelen-genis-1440', const Size(1440, 900), () => genis(IletiListesi(konum: const Konum.klasor('g'), ac: (_) {}), listeEni: 460));
  });

  testWidgets('sol ray (kısa ve orta pencere)', (t) async {
    for (final h in [600.0, 800.0]) {
      await ciz(t, 'ray-${h.round()}', Size(1280, h), () => genis(IletiListesi(konum: const Konum.klasor('g'), ac: (_) {})));
    }
  });

  testWidgets('okuyucu (geniş, tek ileti)', (t) async {
    s.yollar
      ..['GET /api/v1/mail/messages/a/thread'] = (
        200,
        {
          'items': [_iletiler.first],
        },
      )
      ..['GET /api/v1/mail/messages/a'] = (
        200,
        {
          'message': _iletiler.first,
          'view': {
            'subject': 'Teklif: kurumsal paket yenileme ve 2027 yılı için güncellenmiş hizmet koşulları hakkında bilgilendirme',
            'from': [
              {'name': 'Ayşe Yılmaz', 'email': 'ayse@ornek.com'},
            ],
            'to': [
              {'name': 'Semih Boğa', 'email': 'semih@ornek.com'},
            ],
            'cc': [
              {'name': 'Can Demir', 'email': 'can@ornek.com'},
            ],
            'reply_to': [],
            'date': _iso(9),
            'text': 'Merhaba Semih Bey,\n\nEkte güncel teklifi bulabilirsiniz.',
            'html':
                '<p>Merhaba Semih Bey,</p><p>Kurumsal paketinizin yenileme dönemi yaklaşıyor. Ekte 2027 yılı için güncel teklifi ve hizmet '
                'koşullarını bulabilirsiniz.</p><p>Sorularınız için bu iletiyi yanıtlayabilirsiniz.</p><p>Saygılarımla,<br>Ayşe</p>',
            'attachments': [],
          },
        },
      )
      ..['PATCH /api/v1/mail/messages/a'] = (200, {'ok': true});
    await ciz(
      t,
      'okuyucu-genis',
      masaustu,
      () => genis(
        IletiListesi(konum: const Konum.klasor('g'), ac: (_) {}, seciliId: 'a'),
        okuyucu: const Okuyucu(id: 'a'),
      ),
    );
  });

  testWidgets('kenar menüsü (telefon)', (t) async {
    await ciz(t, 'klasorler-telefon', telefon, () => YanMenu(sec: (_) {}, sayfa: true));
  });

  testWidgets('konuşma (8 ileti, ekli)', (t) async {
    konusmaKur(s);
    await ciz(t, 'konusma-telefon', telefon, () => const Okuyucu(id: 'k8', sayfa: true));
    // Ortadaki iletiler açılmış, ekli ileti (görseller + belge) açık.
    await ciz(
      t,
      'konusma-acik-telefon',
      telefon,
      () => const Okuyucu(id: 'k8', sayfa: true),
      hazirla: () async {
        await t.tap(find.byKey(const ValueKey('konusma-daha')));
        await t.pump();
        await t.tap(find.byKey(const ValueKey('konusma-kapali-k3')));
        await t.pump(const Duration(milliseconds: 100));
        await t.scrollUntilVisible(find.byKey(const ValueKey('konusma-ileti-k3')), -100, scrollable: find.byType(Scrollable).first);
        await t.pump();
      },
    );
    await ciz(
      t,
      'konusma-genis',
      masaustu,
      () => Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 240,
              child: YanMenu(sec: (_) {}, yeniIleti: () {}),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 360,
              child: IletiListesi(konum: const Konum.klasor('g'), ac: (_) {}),
            ),
            const VerticalDivider(width: 1),
            const Expanded(child: Okuyucu(id: 'k8')),
          ],
        ),
      ),
    );
  });

  testWidgets('ayarlar', (t) async {
    await ciz(t, 'ayarlar-telefon', telefon, () => const AyarlarEkrani());
    await ciz(t, 'ayarlar-genis', masaustu, () => const AyarlarEkrani());
  });
}
