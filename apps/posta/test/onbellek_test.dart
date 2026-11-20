// Önbellek (disk + bellek, LRU, hesap silme), önyükleme ve okuyucunun önbellekten ağsız açılışı. Ağ yok.

import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/okuyucu.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/onbellek.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

Map<String, dynamic> _ileti(String id, {bool seen = false, String konu = 'Teklif'}) => {
  'message': {'id': id, 'subject': konu, 'from': 'Ali <ali@a.com>', 'seen': seen, 'folder_id': 'f1'},
  'view': {
    'subject': konu,
    'from': [
      {'name': 'Ali', 'email': 'ali@a.com'},
    ],
    'to': [
      {'name': '', 'email': 'ben@firma.com'},
    ],
    'cc': [],
    'reply_to': [],
    'date': '2026-11-19T10:00:00Z',
    'text': 'Fiyat ekte.',
    'html': '',
    'attachments': [],
  },
};

void main() {
  late Directory kok;
  final s = YolSunucusu();
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    s.kur();
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() {
    kok = Directory.systemTemp.createTempSync('onbellek_');
    Onbellek.kok = () async => kok;
    Onbellek.ben.testSifirla();
    Onbellek.azamiDisk = 200 * 1024 * 1024;
    s.istekler.clear();
    s.yollar.clear();
  });
  tearDown(() {
    Onbellek.ben.testSifirla();
    kok.deleteSync(recursive: true);
  });

  test('diskten geri okuma, aynı içerik yeniden yazılmaz, hesap silinince gider', () async {
    final o = Onbellek.ben;
    await o.hesapAc('m1');
    expect(await o.yaz('ileti:1', {'a': 1}), isTrue);
    expect(await o.yaz('ileti:1', {'a': 1}), isFalse);
    o.testSifirla(); // uygulama yeniden açıldı: bellek boş
    await o.hesapAc('m1');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(o.hemen('ileti:1'), isNull);
    expect(await o.oku('ileti:1'), {'a': 1});
    expect(o.hemen('ileti:1'), {'a': 1});
    // Başka hesap kendi dizinini kullanır.
    await o.hesapAc('m2');
    expect(await o.oku('ileti:1'), isNull);
    await o.hesabiSil('m1');
    o.testSifirla();
    await o.hesapAc('m1');
    expect(await o.oku('ileti:1'), isNull);
  });

  test('boyut sınırı: en eski kullanılan silinir', () async {
    final o = Onbellek.ben;
    Onbellek.azamiDisk = 2500;
    await o.hesapAc('m1');
    final buyuk = 'x' * 1000;
    await o.yaz('a', buyuk);
    await o.yaz('b', buyuk);
    await o.oku('a'); // a yeniden kullanıldı → en eski b
    await o.yaz('c', buyuk);
    expect(o.var_('a'), isTrue);
    expect(o.var_('b'), isFalse);
    expect(o.var_('c'), isTrue);
    expect(o.diskBoyut, lessThanOrEqualTo(2500));
  });

  test('önyükleme: okunmamışlar önce, en çok 3 eşzamanlı, önbellekte olan atlanır', () async {
    await Onbellek.ben.hesapAc('m1');
    await Onbellek.ben.yaz('ileti:c', _ileti('c'));
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      s.yollar['GET /api/v1/mail/messages/$id'] = (200, _ileti(id));
    }
    final ogeler = [
      for (final (id, okundu) in [('a', true), ('b', false), ('c', false), ('d', true), ('e', false)])
        IletiOzet.json({'id': id, 'subject': id, 'seen': okundu}),
    ];
    Onyukleme.ben.iste(ogeler);
    // Okunmamışlar (b, e) önce; c önbellekte olduğu için istenmez.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.istekler.map((i) => i.yol.split('/').last), ['b', 'e', 'a', 'd']);
    expect(Onbellek.ben.var_('ileti:d'), isTrue);
  });

  testWidgets('önbellekteki ileti ağ beklenmeden açılır; okundu işareti yeniden GET yapmaz', (t) async {
    await t.runAsync(() async {
      await Onbellek.ben.hesapAc('m1');
      await Onbellek.ben.yaz('ileti:x', _ileti('x'));
    });
    // Ağ yanıt vermiyor (sunucu hatası): önbellekteki içerik yine görünmeli.
    s.yollar['GET /api/v1/mail/messages/x'] = (
      503,
      {
        'error': {'code': 'unavailable', 'message': 'yok'},
      },
    );
    s.yollar['PATCH /api/v1/mail/messages/x'] = (200, {'ok': true});
    s.yollar['GET /api/v1/mail/folders'] = (200, {'items': []});
    s.yollar['GET /api/v1/mail/labels'] = (200, {'items': []});
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        home: const Scaffold(body: Okuyucu(id: 'x')),
      ),
    );
    expect(find.text('Fiyat ekte.'), findsOneWidget, reason: 'bellekteki ileti ilk karede');
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Fiyat ekte.'), findsOneWidget);
    expect(find.text('İleti açılamadı.'), findsNothing);
    expect(s.bul('PATCH', '/api/v1/mail/messages/x').single.json, {'seen': true});
    // Sayılar tazelenir ama ileti ikinci kez indirilmez.
    expect(s.bul('GET', '/api/v1/mail/messages/x'), hasLength(1));
    expect(s.bul('GET', '/api/v1/mail/folders'), hasLength(1));
    expect(PostaDurum.ben.surum.value, 0);
    await t.pumpWidget(const SizedBox());
  });
}
