// Görev hatırlatmaları (Android / Windows zamanlayıcı), görevi takvime ekleme (.ics, Android Intent) ve Apple
// Hatırlatıcılar / hatırlatma kartı. Ağ yok (sahte sunucu), işletim sistemi zamanlayıcısı sahte.

import 'dart:convert';
import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/gorevler/gorev_hatirlatma_karti.dart';
import 'package:posta/ekranlar/gorevler/gorevler_ekrani.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/gorev_hatirlatma.dart';
import 'package:posta/veri/takvim_servisi.dart';
import 'package:posta/veri/takvime_ekle.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

class _SahteZamanlayici extends GorevZamanlayici {
  final planlanan = <int, GorevAnimsatmasi>{};
  final iptaller = <int>[];
  int planSayisi = 0;
  @override
  Future<bool> planla(GorevAnimsatmasi a) async {
    planSayisi++;
    planlanan[a.id] = a;
    return true;
  }

  @override
  Future<void> iptal(int id) async {
    iptaller.add(id);
    planlanan.remove(id);
  }
}

Map<String, dynamic> _g(String id, {DateTime? bitis, String durum = 'todo', String? atanan, String olusturan = 'k1', String baslik = 'Görev'}) => {
  'id': id,
  'title': baslik,
  'notes': '',
  'due_at': bitis?.toUtc().toIso8601String(),
  'priority': 'normal',
  'status': durum,
  'creator': {'id': olusturan, 'address': '$olusturan@ornek.com', 'name': ''},
  'assignee': atanan == null ? null : {'id': atanan, 'address': '$atanan@ornek.com', 'name': ''},
  'can_edit': true,
};

void main() {
  final s = YolSunucusu();
  late _SahteZamanlayici z;
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    s.kur();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    z = _SahteZamanlayici();
    GorevHatirlatma.zamanlayici = z;
    GorevHatirlatma.destekliZorla = true;
    s
      ..istekler.clear()
      ..yollar.clear();
    Uyg.kutu.value = {'mailbox_id': 'k1', 'address': 'info@ornek.com', 'display_name': 'Info'};
  });
  tearDown(() {
    GorevHatirlatma.destekliZorla = null;
    GorevHatirlatmaKarti.platformZorla = null;
    TakvimeEkle.yolZorla = null;
  });

  test('plan: yalnız sorumlu olunan, açık, son tarihi gelecekte olan görevler; 15 dk önce; en yakın 50', () {
    final simdi = DateTime.utc(2026, 11, 22, 8);
    final l = [
      _g('a', bitis: DateTime.utc(2026, 11, 22, 12)), // kendi, atanmamış
      _g('b', bitis: DateTime.utc(2026, 11, 22, 10), atanan: 'k1', olusturan: 'k9'), // bana atanan
      _g('c', bitis: DateTime.utc(2026, 11, 22, 10), atanan: 'k9'), // başkasına atadığım: ona hatırlatılır
      _g('d', bitis: DateTime.utc(2026, 11, 22, 10), durum: 'done'),
      _g('e', bitis: DateTime.utc(2026, 11, 21, 10)), // geçmiş
      _g('f'), // son tarih yok
      _g('g', bitis: DateTime.utc(2026, 11, 22, 8, 10)), // 10 dk kaldı: hemen
    ].map(Gorev.json).toList();
    final p = GorevHatirlatma.plan(l, kutu: 'k1', simdi: simdi);
    expect(p.map((a) => GorevHatirlatma.yukCoz(a.yuk)!.gorev), ['g', 'b', 'a']);
    expect(p[0].zaman.isAtSameMomentAs(simdi.add(const Duration(seconds: 5))), isTrue);
    expect(p[1].zaman.isAtSameMomentAs(DateTime.utc(2026, 11, 22, 9, 45)), isTrue);
    expect(p[2].zaman.isAtSameMomentAs(DateTime.utc(2026, 11, 22, 11, 45)), isTrue);
    expect(p[1].yuk, 'gorev:k1|b');
    expect(p[1].id, GorevHatirlatma.kimlik('k1', 'b'), reason: 'kimlik kalıcı');
    expect(p[1].id, inInclusiveRange(0x40000000, 0x7fffffff));
    expect(GorevHatirlatma.kimlik('k2', 'b'), isNot(p[1].id), reason: 'hesaplar ayrı');
    expect(p[1].metin, startsWith('Son tarih: '));

    final cok = [for (var i = 0; i < 80; i++) _g('t$i', bitis: simdi.add(Duration(hours: 1 + i)))].map(Gorev.json).toList();
    final pc = GorevHatirlatma.plan(cok, kutu: 'k1', simdi: simdi);
    expect(pc, hasLength(GorevHatirlatma.azami));
    expect(GorevHatirlatma.yukCoz(pc.last.yuk)!.gorev, 't49');
    expect(GorevHatirlatma.yukCoz('m1'), isNull);
    expect(GorevHatirlatma.yukCoz('gorev:k1|'), isNull);
  });

  test('eşitleme: yeniler zamanlanır, değişmeyen yeniden zamanlanmaz, biten / silinen iptal, paket kapalıysa hepsi iptal', () async {
    final yarin = DateTime.now().add(const Duration(days: 1));
    var gorevler = [_g('a', bitis: yarin), _g('b', bitis: yarin.add(const Duration(hours: 2)), baslik: 'Rapor')];
    s.yollar['GET /api/v1/mail/tasks'] = ((Istek i) {
      expect(i.sorgu['status'], 'open');
      return (200, {'items': gorevler});
    });
    await GorevHatirlatma.esitle(kutu: 'k1');
    expect(z.planlanan.keys.toSet(), {GorevHatirlatma.kimlik('k1', 'a'), GorevHatirlatma.kimlik('k1', 'b')});
    expect(z.planlanan[GorevHatirlatma.kimlik('k1', 'b')]!.baslik, 'Rapor');
    expect(z.planSayisi, 2);

    await GorevHatirlatma.esitle(kutu: 'k1');
    expect(z.planSayisi, 2, reason: 'değişmeyen yeniden zamanlanmaz');

    // a tamamlandı (açık listede yok), b'nin tarihi değişti.
    gorevler = [_g('b', bitis: yarin.add(const Duration(hours: 5)), baslik: 'Rapor')];
    await GorevHatirlatma.esitle(kutu: 'k1');
    expect(z.iptaller, [GorevHatirlatma.kimlik('k1', 'a')]);
    expect(z.planlanan.keys, [GorevHatirlatma.kimlik('k1', 'b')]);
    expect(z.planSayisi, 3);

    // Başka hesabın planı ayrı; bu hesabın çıkışı yalnız kendininkini iptal eder.
    s.yollar['GET /api/v1/mail/tasks'] = (
      200,
      {
        'items': [_g('x', bitis: yarin, olusturan: 'k2')],
      },
    );
    await GorevHatirlatma.esitle(kutu: 'k2');
    await GorevHatirlatma.hesapKapandi('k1');
    expect(z.planlanan.keys, [GorevHatirlatma.kimlik('k2', 'x')]);

    // Çevrimdışı: plan olduğu gibi kalır.
    s.cevrimdisi = true;
    await GorevHatirlatma.esitle(kutu: 'k2');
    s.cevrimdisi = false;
    expect(z.planlanan.keys, [GorevHatirlatma.kimlik('k2', 'x')]);

    // Görevler paketinde kapalı: hepsi iptal.
    s.yollar['GET /api/v1/mail/tasks'] = (403, {'error': 'feature_disabled'});
    await GorevHatirlatma.esitle(kutu: 'k2');
    expect(z.planlanan, isEmpty);
  });

  test('ayar kapatılınca tüm hesapların hatırlatmaları iptal, kapalıyken zamanlanmaz', () async {
    final yarin = DateTime.now().add(const Duration(days: 1));
    s.yollar['GET /api/v1/mail/tasks'] = (
      200,
      {
        'items': [_g('a', bitis: yarin)],
      },
    );
    await GorevHatirlatma.esitle(kutu: 'k1');
    expect(z.planlanan, hasLength(1));
    await GorevHatirlatma.ayarla(false);
    expect(z.planlanan, isEmpty);
    expect(await GorevHatirlatma.acik(), isFalse);
    await GorevHatirlatma.esitle(kutu: 'k1');
    expect(z.planlanan, isEmpty);
    await GorevHatirlatma.ayarla(true, kutu: 'k1');
    expect(z.planlanan, hasLength(1));
  });

  test('.ics: VEVENT son tarihte, 15 dk önce uyarı, metin kaçışlı, satırlar 75 baytı aşmaz', () {
    final g = Gorev.json(_g('t1', bitis: DateTime.utc(2026, 12, 1, 9, 30), baslik: 'Teklif; fiyat, KDV'));
    final g2 = Gorev(id: 't2', baslik: 'Uzun ${'ğüşiöç' * 20}', notlar: 'satır 1\nsatır 2', bitis: g.bitis);
    final ics = gorevIcs(g, DateTime.utc(2026, 11, 22, 8));
    expect(ics, contains('BEGIN:VEVENT\r\nUID:gorev-t1@bogamail\r\nDTSTAMP:20261122T080000Z\r\nDTSTART:20261201T093000Z\r\nDTEND:20261201T100000Z\r\n'));
    expect(ics, contains('SUMMARY:Teklif\\; fiyat\\, KDV\r\n'));
    expect(ics, contains('BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Teklif\\; fiyat\\, KDV\r\nTRIGGER:-PT15M\r\nEND:VALARM'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    final uzun = gorevIcs(g2, DateTime.utc(2026, 11, 22));
    for (final satir in uzun.split('\r\n')) {
      expect(utf8Uzunluk(satir), lessThanOrEqualTo(75));
    }
    expect(uzun.replaceAll('\r\n ', ''), contains('DESCRIPTION:satır 1\\nsatır 2\\n\\nBogaMail görevi'));
    expect(uzun.replaceAll('\r\n ', ''), contains('SUMMARY:Uzun ${'ğüşiöç' * 20}'));
  });

  test('takvime ekle: Android Intent kanalına başlık / zaman, Windows .ics açılır', () async {
    final b = DateTime.utc(2026, 12, 1, 9, 30);
    final g = Gorev.json(_g('t1', bitis: b, baslik: 'Teklif'));
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Map<Object?, Object?>? arg;
    m.setMockMethodCallHandler(TakvimeEkle.kanal, (c) async {
      arg = c.arguments as Map<Object?, Object?>;
      return true;
    });
    addTearDown(() => m.setMockMethodCallHandler(TakvimeEkle.kanal, null));
    TakvimeEkle.yolZorla = TakvimeEkleYolu.android;
    expect(await TakvimeEkle.ekle(g), isTrue);
    expect(arg, {'baslik': 'Teklif', 'notlar': '', 'baslangic': b.millisecondsSinceEpoch, 'bitis': b.millisecondsSinceEpoch + 30 * 60000});

    final gecici = Directory.systemTemp.createTempSync('ics_');
    addTearDown(() => gecici.deleteSync(recursive: true));
    const yp = MethodChannel('plugins.flutter.io/path_provider');
    m.setMockMethodCallHandler(yp, (c) async => gecici.path);
    addTearDown(() => m.setMockMethodCallHandler(yp, null));
    String? acilan;
    TakvimeEkle.dosyaAc = (y) async {
      acilan = y;
      return true;
    };
    TakvimeEkle.yolZorla = TakvimeEkleYolu.ics;
    expect(await TakvimeEkle.ekle(g), isTrue);
    expect(acilan, endsWith('BogaMail-gorev-t1.ics'));
    expect(File(acilan!).readAsStringSync(), contains('DTSTART:20261201T093000Z'));

    TakvimeEkle.yolZorla = TakvimeEkleYolu.apple;
    expect(await TakvimeEkle.ekle(g), isFalse, reason: "Apple'da kopya yok, CalDAV eşitlemesi");
    expect(await TakvimeEkle.ekle(Gorev(id: 'x')), isFalse, reason: 'son tarih yok');
  });

  Widget uyg(Widget w) => MaterialApp(
    theme: temaKur(Brightness.light),
    scaffoldMessengerKey: kokMesaj,
    home: Scaffold(body: SingleChildScrollView(child: w)),
  );

  testWidgets('kart (Android/Windows): "Görev hatırlatmaları" anahtarı kapatınca iptal eder', (t) async {
    GorevHatirlatmaKarti.platformZorla = HatirlatmaPlatformu.yerel;
    final yarin = DateTime.now().add(const Duration(days: 1));
    s.yollar['GET /api/v1/mail/tasks'] = (
      200,
      {
        'items': [_g('a', bitis: yarin)],
      },
    );
    await t.runAsync(() => GorevHatirlatma.esitle(kutu: 'k1'));
    expect(z.planlanan, hasLength(1));
    await t.pumpWidget(uyg(const GorevHatirlatmaKarti(ozellikler: {'tasks': true})));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
    expect(find.text('Görev hatırlatmaları'), findsWidgets);
    expect(find.text('Apple Hatırlatıcılar ile eşitle'), findsNothing);
    await t.tap(find.descendant(of: find.byKey(const ValueKey('gorev-hatirlatma')), matching: find.byType(Switch)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(z.planlanan, isEmpty);
    expect(find.text('Görev hatırlatmaları kapatıldı'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('kart (iPhone/Mac): Apple Hatırlatıcılar profili; IMAP kapalıysa elle CalDAV notu; görevler / CalDAV kapalıysa gizli', (t) async {
    GorevHatirlatmaKarti.platformZorla = HatirlatmaPlatformu.apple;
    var acildi = 0;
    GorevHatirlatmaKarti.profilAc = () async => acildi++;
    addTearDown(() => GorevHatirlatmaKarti.profilAc = appleProfiliniAc);
    await t.pumpWidget(uyg(const GorevHatirlatmaKarti(ozellikler: {'tasks': true, 'caldav': true})));
    expect(find.text('Apple Hatırlatıcılar ile eşitle'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('apple-hatirlaticilar')));
    await t.pump();
    expect(acildi, 1);
    await t.pumpWidget(uyg(const GorevHatirlatmaKarti(ozellikler: {'tasks': true, 'caldav': true}, imap: false, sunucu: 'posta.ornek.com')));
    expect(find.byKey(const ValueKey('apple-hatirlaticilar')), findsNothing);
    expect(find.textContaining('CalDAV hesabı; sunucu posta.ornek.com, kullanıcı adı info@ornek.com'), findsOneWidget);
    expect(GorevHatirlatmaKarti.gosterilir({'tasks': true, 'caldav': false}), isFalse);
    expect(GorevHatirlatmaKarti.gosterilir({'tasks': false, 'caldav': true}), isFalse);
    expect(GorevHatirlatmaKarti.gosterilir(null), isTrue);
    GorevHatirlatmaKarti.platformZorla = HatirlatmaPlatformu.yerel;
    expect(GorevHatirlatmaKarti.gosterilir({'tasks': true}), isTrue);
    GorevHatirlatmaKarti.platformZorla = HatirlatmaPlatformu.yok;
    expect(GorevHatirlatmaKarti.gosterilir({'tasks': true}), isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Görevler: Hatırlatmalar düğmesi kartı açar; ayrıntıda "Takvime ekle"; liste yüklenince hatırlatmalar kurulur', (t) async {
    GorevHatirlatmaKarti.platformZorla = HatirlatmaPlatformu.yerel;
    TakvimeEkle.yolZorla = TakvimeEkleYolu.android;
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final yarin = DateTime.now().add(const Duration(days: 1));
    s.yollar
      ..['GET /api/v1/mail/tasks'] = (
        200,
        {
          'items': [_g('a', bitis: yarin, baslik: 'Sunum hazırla')],
        },
      )
      ..['GET /api/v1/mail/tasks/a'] = (200, {'task': _g('a', bitis: yarin, baslik: 'Sunum hazırla'), 'comments': []});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var eklendi = 0;
    m.setMockMethodCallHandler(TakvimeEkle.kanal, (c) async {
      eklendi++;
      return true;
    });
    addTearDown(() => m.setMockMethodCallHandler(TakvimeEkle.kanal, null));
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const GorevlerEkrani()));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Sunum hazırla'), findsOneWidget);
    // Liste yüklendi: kısa gecikmeyle hatırlatma kurulur.
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(z.planlanan.keys, [GorevHatirlatma.kimlik('k1', 'a')]);

    await t.tap(find.byKey(const ValueKey('gorev-hatirlaticilar')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('gorev-hatirlatma-karti')), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();

    await t.tap(find.text('Sunum hazırla'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('gorev-takvime-ekle')));
    await t.pump();
    expect(eklendi, 1);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });
}

int utf8Uzunluk(String s) => const Utf8Encoder().convert(s).length;
