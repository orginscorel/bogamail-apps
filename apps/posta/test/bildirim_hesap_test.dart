// Çok hesaplı bildirim: etkin olmayan hesabın postasına / sohbetine dokununca o hesaba geçilir ve ileti / oda açılır
// (geniş ve telefon düzeni, soğuk açılış). Etkin hesapta başka bölüm açıkken de ileti açılır. Ağ yok (sahte sunucu).

import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/kabuk.dart';
import 'package:posta/ekranlar/gorevler/gorevler_ekrani.dart';
import 'package:posta/ekranlar/okuyucu.dart';
import 'package:posta/ekranlar/sohbet/sohbet_odasi.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/onbellek.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

Map<String, dynamic> _ileti(String id, String konu, String klasor) => {
  'message': {'id': id, 'subject': konu, 'from': 'Ali <ali@a.com>', 'seen': true, 'folder_id': klasor, 'date': '2026-11-20T09:00:00Z'},
  'view': {
    'subject': konu,
    'from': [
      {'name': 'Ali', 'email': 'ali@a.com'},
    ],
    'to': [
      {'name': 'Ben', 'email': 'ben@b.com'},
    ],
    'cc': [],
    'reply_to': [],
    'date': '2026-11-20T09:00:00Z',
    'text': 'gövde metni',
    'html': '',
    'attachments': [],
  },
};

void main() {
  late Directory kok;
  final s = YolSunucusu();
  late String etkin;
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Onyukleme.etkin = false;
    s.kur();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kok = Directory.systemTemp.createTempSync('bildirim_hesap_');
    Onbellek.kok = () async => kok;
    Onbellek.ben.testSifirla();
    etkin = 'k1';
    final kutular = {
      'k1': {'mailbox_id': 'k1', 'address': 'info@ornek.com', 'display_name': 'Info'},
      'k2': {'mailbox_id': 'k2', 'address': 'satis@ornek.com', 'display_name': 'Satış'},
    };
    s
      ..istekler.clear()
      ..yollar.clear()
      ..yollar['GET /api/v1/mail/auth/accounts'] = ((Istek _) => (
        200,
        {
          'items': [
            for (final k in kutular.values)
              {'id': k['mailbox_id'], 'address': k['address'], 'display_name': k['display_name'], 'active': k['mailbox_id'] == etkin},
          ],
        },
      ))
      ..yollar['POST /api/v1/mail/auth/switch'] = ((Istek i) {
        etkin = '${i.json['mailbox_id']}';
        return (200, {'mailbox_id': etkin});
      })
      ..yollar['GET /api/v1/mail/auth/me'] = ((Istek _) => (200, {'mailbox': kutular[etkin]}))
      ..yollar['GET /api/v1/mail/folders'] = ((Istek _) => (
        200,
        {
          'items': [
            {'id': 'gelen-$etkin', 'name': 'INBOX', 'role': 'inbox', 'unseen': 0, 'total': 0},
            {'id': 'proje-$etkin', 'name': 'Proje', 'unseen': 0, 'total': 0},
          ],
        },
      ))
      ..yollar['GET /api/v1/mail/labels'] = (200, {'items': []})
      ..yollar['GET /api/v1/mail/chat/rooms'] = (200, {'items': []})
      ..yollar['GET /api/v1/mail/tasks'] = (200, {'items': []})
      ..yollar['GET /api/v1/mail/tasks/t5'] = ((Istek _) => etkin == 'k2'
          ? (
              200,
              {
                'task': {'id': 't5', 'title': 'Teklif hatırlatması', 'status': 'todo', 'priority': 'normal', 'can_edit': true},
                'comments': [],
              },
            )
          : (404, {'error': 'yok'}))
      ..yollar['GET /api/v1/mail/folders/gelen-k1/messages'] = (200, {'items': [], 'total': 0, 'page': 1, 'page_size': 50})
      ..yollar['GET /api/v1/mail/folders/gelen-k2/messages'] = (200, {'items': [], 'total': 0, 'page': 1, 'page_size': 50})
      ..yollar['GET /api/v1/mail/messages/m9'] = ((Istek _) => etkin == 'k2' ? (200, _ileti('m9', 'Satış teklifi', 'proje-k2')) : (404, {'error': 'yok'}))
      ..yollar['GET /api/v1/mail/messages/m9/thread'] = (200, {'items': []})
      ..yollar['GET /api/v1/mail/messages/m1'] = ((Istek _) => etkin == 'k1' ? (200, _ileti('m1', 'Info iletisi', 'gelen-k1')) : (404, {'error': 'yok'}))
      ..yollar['GET /api/v1/mail/messages/m1/thread'] = (200, {'items': []});
    for (final k in ['k1', 'k2']) {
      s.yollar['GET /api/v1/mail/folders/proje-$k/messages'] = (200, {'items': [], 'total': 0, 'page': 1, 'page_size': 50});
    }
    Uyg.kutu.value = {'mailbox_id': 'k1', 'address': 'info@ornek.com', 'display_name': 'Info'};
    Uyg.bekleyenBildirim = null;
    Kabuk.acilisBildirimi = () async => null;
  });
  tearDown(() {
    Onbellek.ben.testSifirla();
    PostaDurum.ben.sifirla();
    kok.deleteSync(recursive: true);
  });

  Future<void> bekle(WidgetTester t, [int n = 12]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 60));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    }
  }

  Future<void> ac(WidgetTester t, Size boyut) async {
    t.view.physicalSize = boyut;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), navigatorKey: kokGezgin, scaffoldMessengerKey: kokMesaj, home: const Kabuk()));
    await bekle(t);
  }

  Future<void> kapat(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  }

  const yuk = {'account': 'satis@ornek.com', 'mailbox_id': 'k2', 'kind': 'mail', 'message_id': 'm9'};

  void acikIleti(String id, String konu) {
    expect(find.byWidgetPredicate((w) => w is Okuyucu && w.id == id), findsOneWidget);
    expect(find.text(konu), findsWidgets);
  }

  testWidgets('geniş: etkin olmayan hesabın postasına dokununca o hesaba geçilir, ileti (listede olmasa da) açılır, klasörü seçilir', (t) async {
    await ac(t, const Size(1280, 800));
    expect(Uyg.adres, 'info@ornek.com');
    await t.runAsync(() => Kabuk.bildirimeDokun(Map.of(yuk)));
    await bekle(t, 20);
    expect(Uyg.adres, 'satis@ornek.com');
    expect(s.bul('POST', '/api/v1/mail/auth/switch').single.json, {'mailbox_id': 'k2'});
    acikIleti('m9', 'Satış teklifi');
    expect(PostaDurum.ben.konum, const Konum.klasor('proje-k2'), reason: 'iletinin klasörü seçilir');
    expect(Uyg.bekleyenBildirim, isNull);
    await kapat(t);
  });

  testWidgets('telefon: etkin olmayan hesabın postasına dokununca o hesaba geçilir ve ileti açılır', (t) async {
    await ac(t, const Size(390, 844));
    await t.runAsync(() => Kabuk.bildirimeDokun(Map.of(yuk)));
    await bekle(t, 20);
    expect(Uyg.adres, 'satis@ornek.com');
    acikIleti('m9', 'Satış teklifi');
    await kapat(t);
  });

  testWidgets('hesap kutu kimliğiyle eşlenir: adres listedekinden farklı yazılsa da (ör. IDN) doğru hesaba geçilir', (t) async {
    await ac(t, const Size(1280, 800));
    await t.runAsync(() => Kabuk.bildirimeDokun({...yuk, 'account': 'satis@xn--rnek-0qa.com'}));
    await bekle(t, 20);
    expect(Uyg.adres, 'satis@ornek.com');
    acikIleti('m9', 'Satış teklifi');
    await kapat(t);
  });

  testWidgets('eski yük (yalnız adres, farklı büyük/küçük harf) de çalışır', (t) async {
    await ac(t, const Size(1280, 800));
    await t.runAsync(() => Kabuk.bildirimeDokun({'account': 'Satis@Ornek.com', 'kind': 'mail', 'message_id': 'm9'}));
    await bekle(t, 20);
    expect(Uyg.adres, 'satis@ornek.com');
    acikIleti('m9', 'Satış teklifi');
    await kapat(t);
  });

  testWidgets('soğuk açılış: uygulamayı açan bildirim başka hesabınsa o hesaba geçilip ileti açılır', (t) async {
    Kabuk.acilisBildirimi = () async => Map.of(yuk);
    await ac(t, const Size(1280, 800));
    await bekle(t, 20);
    expect(Uyg.adres, 'satis@ornek.com');
    expect(s.bul('POST', '/api/v1/mail/auth/switch'), hasLength(1), reason: 'yeni kabuk açılış bildirimini yeniden işlemez');
    acikIleti('m9', 'Satış teklifi');
    await kapat(t);
  });

  testWidgets('soğuk açılış telefonda', (t) async {
    Kabuk.acilisBildirimi = () async => Map.of(yuk);
    await ac(t, const Size(390, 844));
    await bekle(t, 20);
    expect(Uyg.adres, 'satis@ornek.com');
    acikIleti('m9', 'Satış teklifi');
    await kapat(t);
  });

  testWidgets('başka hesabın sohbet bildirimi: o hesaba geçilir, Sohbet bölümünde oda açılır', (t) async {
    await ac(t, const Size(1280, 800));
    await t.runAsync(() => Kabuk.bildirimeDokun({'account': 'satis@ornek.com', 'mailbox_id': 'k2', 'kind': 'chat', 'room_id': 'oda7'}));
    await bekle(t, 20);
    expect(Uyg.adres, 'satis@ornek.com');
    expect(find.byWidgetPredicate((w) => w is SohbetOdasiEkrani && w.odaId == 'oda7'), findsOneWidget);
    await kapat(t);
  });

  testWidgets('etkin hesapta birleşik görünüm / başka bölüm açıkken bildirime dokununca ileti açılır', (t) async {
    await ac(t, const Size(1280, 800));
    PostaDurum.ben.git(const Konum.birlesik());
    await bekle(t, 4);
    await t.runAsync(() => Kabuk.bildirimeDokun({'account': 'info@ornek.com', 'mailbox_id': 'k1', 'kind': 'mail', 'message_id': 'm1'}));
    await bekle(t, 12);
    expect(s.bul('POST', '/api/v1/mail/auth/switch'), isEmpty);
    acikIleti('m1', 'Info iletisi');
    expect(PostaDurum.ben.konum, const Konum.klasor('gelen-k1'));

    // Sohbet bölümü açıkken de.
    await t.runAsync(() => Kabuk.bildirimeDokun({'account': 'info@ornek.com', 'mailbox_id': 'k1', 'kind': 'chat', 'room_id': 'oda1'}));
    await bekle(t, 6);
    expect(find.byWidgetPredicate((w) => w is SohbetOdasiEkrani && w.odaId == 'oda1'), findsOneWidget);
    await t.runAsync(() => Kabuk.bildirimeDokun({'account': 'info@ornek.com', 'mailbox_id': 'k1', 'kind': 'mail', 'message_id': 'm1'}));
    await bekle(t, 8);
    acikIleti('m1', 'Info iletisi');
    await kapat(t);
  });

  testWidgets('telefonda etkin hesapta başka bölüm açıkken ileti açılır', (t) async {
    await ac(t, const Size(390, 844));
    await t.runAsync(() => Kabuk.bildirimeDokun({'account': 'info@ornek.com', 'mailbox_id': 'k1', 'kind': 'chat', 'room_id': 'oda1'}));
    await bekle(t, 6);
    expect(find.byWidgetPredicate((w) => w is SohbetOdasiEkrani && w.odaId == 'oda1'), findsOneWidget);
    await t.runAsync(() => Kabuk.bildirimeDokun({'account': 'info@ornek.com', 'mailbox_id': 'k1', 'kind': 'mail', 'message_id': 'm1'}));
    await bekle(t, 10);
    expect(find.byType(SohbetOdasiEkrani), findsNothing);
    acikIleti('m1', 'Info iletisi');
    await kapat(t);
  });

  testWidgets('hesap bu cihazda yoksa uyarı; bekleyen bildirim kalmaz', (t) async {
    await ac(t, const Size(1280, 800));
    await t.runAsync(() => Kabuk.bildirimeDokun({'account': 'yok@ornek.com', 'kind': 'mail', 'message_id': 'm5'}));
    await bekle(t, 6);
    expect(Uyg.adres, 'info@ornek.com');
    expect(Uyg.bekleyenBildirim, isNull);
    expect(find.text('Hesap bu cihazda bulunamadı'), findsOneWidget);
    await kapat(t);
  });

  testWidgets('başka hesabın görev hatırlatmasına dokununca o hesaba geçilir, görev açılır', (t) async {
    await ac(t, const Size(390, 844));
    await t.runAsync(() => Kabuk.bildirimeDokun({'mailbox_id': 'k2', 'kind': 'task', 'task_id': 't5'}));
    await bekle(t, 20);
    expect(Uyg.adres, 'satis@ornek.com');
    expect(find.byWidgetPredicate((w) => w is GorevAyrinti && w.gorevId == 't5'), findsOneWidget);
    expect(find.text('Teklif hatırlatması'), findsWidgets);
    await kapat(t);
  });
}
