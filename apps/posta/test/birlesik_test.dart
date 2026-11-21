// "Tüm hesaplar" birleşik gelen kutusu: sözleşme (internal/api/unified.go), liste/süzgeçler, işlemler, okuma ve
// yanıt için hesap geçişi, kenar menüsü girişi ve toplam okunmamış. Ağ yok.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/birlesik_ekrani.dart';
import 'package:posta/ekranlar/yan_menu.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/birlesik.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

const _u = '/api/v1/mail/unified';

final _liste = {
  'accounts': [
    {'id': 'k1', 'address': 'ayse@ornek.com', 'display_name': 'Ayşe', 'color': '#2563eb'},
    {'id': 'k2', 'address': 'satis@ornek.com', 'display_name': 'Satış', 'color': '#16a34a'},
  ],
  'items': [
    {
      'id': 'm1',
      'mailbox_id': 'k1',
      'account': 'ayse@ornek.com',
      'subject': 'Toplantı',
      'from': 'Ali <ali@a.com>',
      'seen': false,
      'date': '2026-11-20T10:00:00Z',
    },
    {
      'id': 'm2',
      'mailbox_id': 'k2',
      'account': 'satis@ornek.com',
      'subject': 'Sipariş 42',
      'from': 'Can <can@b.com>',
      'seen': true,
      'date': '2026-11-20T09:00:00Z',
    },
  ],
  'next_before': null,
};

Map<String, dynamic> _detay(String id, String kutu) => {
  'message': {'id': id, 'subject': 'Sipariş 42', 'from': 'Can <can@b.com>', 'seen': true},
  'view': {
    'subject': 'Sipariş 42',
    'from': [
      {'name': 'Can', 'email': 'can@b.com'},
    ],
    'to': [
      {'name': '', 'email': 'satis@ornek.com'},
    ],
    'cc': [],
    'reply_to': [],
    'date': '2026-11-20T09:00:00Z',
    'text': 'Sipariş onaylandı.',
    'html': '',
    'attachments': [],
  },
  'mailbox_id': kutu,
  'account': 'satis@ornek.com',
};

void main() {
  final s = YolSunucusu();
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Onyukleme.etkin = false;
    s.kur();
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() {
    s.istekler.clear();
    s.yollar
      ..clear()
      ..['GET $_u/messages'] = (200, _liste)
      ..['POST $_u/actions'] = ((Istek i) => (200, {'done': (i.json['items'] as List).length}))
      ..['GET $_u/counts'] = (
        200,
        {
          'total_unread': 5,
          'accounts': [
            {'id': 'k1', 'unread': 3},
            {'id': 'k2', 'unread': 2},
          ],
        },
      );
    BirlesikDurum.ben.sifirla();
  });

  Widget uyg(Widget w) => MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, navigatorKey: kokGezgin, home: w);

  test('sözleşme: liste, işlem gövdesi, sayılar', () async {
    final p = await Birlesik.liste(klasor: 'unread');
    expect(s.istekler.last.sorgu, {'folder': 'unread', 'limit': 50});
    expect(p.hesaplar.map((h) => h.renk), [const Color(0xFF2563EB), const Color(0xFF16A34A)]);
    expect(p.ogeler.first.anahtar, 'k1/m1');
    expect(await Birlesik.eylem([p.ogeler.last], 'archive'), 1);
    expect(s.bul('POST', '$_u/actions').single.json, {
      'items': [
        {'mailbox_id': 'k2', 'message_id': 'm2'},
      ],
      'action': 'archive',
    });
    final (t, m) = await Birlesik.sayilar();
    expect(t, 5);
    expect(m, {'k1': 3, 'k2': 2});
  });

  test('durum: birden çok açık hesap varsa kullanılabilir ve toplam okunmamış gelir', () async {
    s.yollar['GET /api/v1/mail/auth/accounts'] = (
      200,
      {
        'items': [
          {'id': 'k1', 'address': 'ayse@ornek.com', 'active': true, 'signed_out': false},
          {'id': 'k2', 'address': 'satis@ornek.com', 'active': false, 'signed_out': false},
          {'id': 'k3', 'address': 'eski@ornek.com', 'active': false, 'signed_out': true},
        ],
      },
    );
    await BirlesikDurum.ben.hesaplariYenile();
    expect(BirlesikDurum.ben.hesapSayisi, 2);
    expect(BirlesikDurum.ben.kullanilabilir, isTrue);
    expect(BirlesikDurum.ben.toplamOkunmamis, 5);
    BirlesikDurum.ben.sifirla();
  });

  testWidgets('liste: hesap etiketleri, hesap süzgeci, yıldız işlemi, açınca okundu', (t) async {
    BirlesikOge? acilan;
    await t.pumpWidget(uyg(BirlesikListe(ac: (o, _) => acilan = o)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Toplantı'), findsOneWidget);
    expect(find.text('Sipariş 42'), findsOneWidget);
    expect(find.byKey(const ValueKey('hesap-etiketi')), findsNWidgets(2));
    expect(find.text('satis'), findsWidgets);

    await t.tap(find.byKey(const ValueKey('birlesik-hesap-k2')));
    await t.pump();
    expect(find.text('Toplantı'), findsNothing);
    expect(find.text('Sipariş 42'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('birlesik-hesap-hepsi')));
    await t.pump();

    await t.tap(find.byKey(const ValueKey('birlesik-klasor-sec')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('birlesik-klasor-flagged')));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 50));
    expect(s.bul('GET', '$_u/messages').last.sorgu['folder'], 'flagged');

    await t.tap(find.text('Toplantı'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(acilan?.anahtar, 'k1/m1');
    expect(s.bul('POST', '$_u/actions').single.json['action'], 'seen');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('liste: kutucukla seçim ve toplu işlem (seçili tüm hesaplardaki iletiler)', (t) async {
    await t.pumpWidget(uyg(BirlesikListe(ac: (_, _) {})));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    // Avatar/kutucuk alanına dokunmak (ya da uzun basmak) seçer.
    await t.longPress(find.text('Toplantı'));
    await t.pump();
    expect(find.byKey(const ValueKey('birlesik-secim')), findsOneWidget);
    expect(find.text('1 seçili'), findsOneWidget);
    await t.tap(find.byTooltip('Tümünü seç'));
    await t.pump();
    expect(find.text('2 seçili'), findsOneWidget);
    await t.tap(find.byTooltip('Arşivle'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    final items = (s.bul('POST', '$_u/actions').last.json['items'] as List).map((e) => (e as Map)['mailbox_id']).toSet();
    expect(items, {'k1', 'k2'});
    expect(find.byKey(const ValueKey('birlesik-secim')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('okuyucu: hesap değiştirmeden okur; yanıtla önce o hesaba geçer', (t) async {
    Uyg.kutu.value = {'mailbox_id': 'k1', 'address': 'ayse@ornek.com'};
    s.yollar['GET $_u/messages/k2/m2'] = (200, _detay('m2', 'k2'));
    s.yollar['POST /api/v1/mail/auth/switch'] = (
      401,
      {
        'error': {'code': 'unauthorized', 'message': 'yok'},
      },
    );
    final o = BirlesikOge.json((_liste['items'] as List)[1]);
    await t.pumpWidget(uyg(Scaffold(body: BirlesikOkuyucu(oge: o))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Sipariş onaylandı.'), findsOneWidget);
    expect(find.byKey(const ValueKey('birlesik-hesap-cipi')), findsOneWidget);
    expect(s.bul('POST', '/api/v1/mail/auth/switch'), isEmpty, reason: 'okumak için hesap değişmez');

    await t.tap(find.byKey(const ValueKey('birlesik-arsiv')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(s.bul('POST', '$_u/actions').single.json['action'], 'archive');

    await t.tap(find.byKey(const ValueKey('birlesik-yanitla')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(s.bul('POST', '/api/v1/mail/auth/switch').single.json, {'mailbox_id': 'k2'});
    expect(Uyg.bekleyenYazma, isNull, reason: 'geçiş başarısızsa bekleyen yazma temizlenir');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
    Uyg.kutu.value = null;
  });

  testWidgets('kenar menüsü: birden çok hesapta "Tüm hesaplar" klasörlerin üstünde, toplam okunmamışla', (t) async {
    PostaDurum.ben
      ..klasorler = [Klasor(id: 'g', ad: 'INBOX', rol: 'inbox', okunmamis: 1)]
      ..yuklendi = true;
    Konum? secilen;
    await t.pumpWidget(uyg(Scaffold(body: YanMenu(sec: (k) => secilen = k))));
    await t.pump();
    expect(find.byKey(const ValueKey('yan-tum-hesaplar')), findsNothing);
    BirlesikDurum.ben
      ..hesapSayisi = 2
      ..toplamOkunmamis = 7
      ..notifyListeners();
    await t.pump();
    expect(find.byKey(const ValueKey('yan-tum-hesaplar')), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    final ust = t.getTopLeft(find.byKey(const ValueKey('yan-tum-hesaplar'))).dy;
    expect(ust, lessThan(t.getTopLeft(find.text('Gelen Kutusu')).dy));
    await t.tap(find.text('Tüm hesaplar'));
    expect(secilen, const Konum.birlesik());
    BirlesikDurum.ben.sifirla();
    PostaDurum.ben.sifirla();
    await t.pumpWidget(const SizedBox());
  });
}
