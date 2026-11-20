// Sohbet: modeller, istek gövdeleri (sunucu katı JSON) ve ekranlar. Ağ yok: sahte API.

import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/sohbet/sohbet_ekrani.dart';
import 'package:posta/ekranlar/sohbet/sohbet_odasi.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/sohbet_servisi.dart';

import 'sahte_sunucu.dart';

const _k = '/api/v1/mail/chat';

Map<String, dynamic> _kisi(String id, String ad, {String presence = ''}) => {
  'mailbox_id': id,
  'address': '$id@ornek.com',
  'display_name': ad,
  'presence': presence,
  'status': '',
  'status_text': '',
  'title': '',
  'department': '',
};

final _odalar = [
  {
    'id': 'kanal1',
    'kind': 'channel',
    'name': 'Genel',
    'is_default': true,
    'member_count': 12,
    'members': <Object>[],
    'unread': 2,
    'last_message': {'id': 5, 'room_id': 'kanal1', 'sender_id': 'ali', 'sender_name': 'Ali Veli', 'body': 'Toplantı 3te', 'created_at': '2026-11-20T09:00:00Z'},
  },
  {
    'id': 'dm1',
    'kind': 'direct',
    'name': '',
    'member_count': 2,
    'members': [_kisi('ben', 'Ben'), _kisi('ayse', 'Ayşe Yılmaz', presence: 'online')],
    'unread': 3,
    'last_message': {'id': 9, 'room_id': 'dm1', 'sender_id': 'ayse', 'sender_name': 'Ayşe Yılmaz', 'body': 'Merhaba!', 'created_at': '2026-11-20T10:00:00Z'},
  },
  {
    'id': 'grup1',
    'kind': 'group',
    'name': 'Proje ekibi',
    'member_count': 3,
    'members': [_kisi('ben', 'Ben'), _kisi('ali', 'Ali Veli'), _kisi('ayse', 'Ayşe Yılmaz')],
    'unread': 0,
  },
];

Widget _uyg(Widget w) => MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: w);

void main() {
  final s = YolSunucusu();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    s.kur();
    Uyg.kutu.value = {'mailbox_id': 'ben', 'address': 'ben@ornek.com', 'display_name': 'Ben'};
  });

  setUp(() {
    s.istekler.clear();
    s.yollar
      ..clear()
      ..['GET $_k/rooms'] = (200, {'items': _odalar})
      ..['POST $_k/rooms/dm1/read'] = (204, null)
      ..['GET $_k/rooms/dm1/messages'] = (
        200,
        {
          'items': [
            {'id': 8, 'room_id': 'dm1', 'sender_id': 'ben', 'sender_name': 'Ben', 'body': 'Selam', 'created_at': '2026-11-20T09:59:00Z', 'mine': true},
            {
              'id': 9,
              'room_id': 'dm1',
              'sender_id': 'ayse',
              'sender_name': 'Ayşe Yılmaz',
              'body': 'Merhaba @ben',
              'created_at': '2026-11-20T10:00:00Z',
              'attachments': [
                {'id': 'f1', 'name': 'rapor.pdf', 'size': 1200, 'content_type': 'application/pdf', 'url': '/api/v1/mail/chat/attachments/f1'},
              ],
              'reactions': [
                {
                  'emoji': '👍',
                  'count': 2,
                  'mine': false,
                  'names': ['Ali Veli', 'Ayşe Yılmaz'],
                },
              ],
            },
          ],
        },
      )
      ..['POST $_k/rooms/dm1/messages/9/reactions'] = ((Istek i) => (
        200,
        {
          'message_id': 9,
          'reactions': [
            {
              'emoji': i.json['emoji'],
              'count': 3,
              'mine': true,
              'names': ['Ali Veli', 'Ayşe Yılmaz', 'Ben'],
            },
          ],
        },
      ))
      ..['POST $_k/rooms/dm1/messages'] = (Istek i) => (
        201,
        {'id': 10, 'room_id': 'dm1', 'sender_id': 'ben', 'sender_name': 'Ben', 'body': i.json['body'], 'created_at': '2026-11-20T10:01:00Z', 'mine': true},
      );
    SohbetDurum.ben.sifirla();
  });

  group('modeller', () {
    test('oda: birebirde karşı taraf başlık olur, kanalda # öneki', () {
      final l = _odalar.map(SohbetOdasi.json).toList();
      expect(l[0].baslik('ben'), '# Genel');
      expect(l[0].kanal, isTrue);
      expect(l[1].birebir, isTrue);
      expect(l[1].baslik('ben'), 'Ayşe Yılmaz');
      expect(l[1].karsi('ben')!.cevrimici, 'online');
      expect(l[1].sonMesaj!.metin, 'Merhaba!');
      expect(l[2].baslik('ben'), 'Proje ekibi');
    });

    test('eksik/yanlış alanlarda çökmez', () {
      for (final v in [null, 1, 'x', <String, dynamic>{}]) {
        expect(SohbetOdasi.json(v).tur, 'direct');
        expect(SohbetMesaji.json(v).id, 0);
        expect(SohbetKisi.json(v).gorunen, '');
        expect(Kanal.json(v).katildi, isFalse);
        expect(SohbetProfili.json(v).cevrimiciGoster, isTrue);
      }
    });

    test('çevrimiçi metni', () {
      expect(varlikMetni(SohbetKisi(id: 'a', cevrimici: 'online')).cevrimici, isTrue);
      expect(varlikMetni(SohbetKisi(id: 'a', cevrimici: 'away')).uzakta, isTrue);
      expect(varlikMetni(SohbetKisi(id: 'a')).metin, '');
    });
  });

  group('istekler', () {
    test('oda oluştur, gönder, profil, kanal: yalnızca sunucu alanları', () async {
      s.yollar['POST $_k/rooms'] = (201, {'id': 'yeni'});
      s.yollar['PUT $_k/me'] = (200, {'show_presence': false, 'status': 'busy'});
      s.yollar['PATCH $_k/channels/c1'] = (204, null);
      s.yollar['POST $_k/channels'] = (201, {'id': 'c2'});

      expect(await Sohbet.odaOlustur(['ayse']), 'yeni');
      expect(s.bul('POST', '$_k/rooms').last.json, {
        'members': ['ayse'],
        'name': '',
      });
      await Sohbet.odaOlustur(['ayse', 'ali'], ad: ' Ekip ');
      expect(s.bul('POST', '$_k/rooms').last.json, {
        'members': ['ayse', 'ali'],
        'name': 'Ekip',
      });

      await Sohbet.gonder('dm1', '  selam  ');
      expect(s.bul('POST', '$_k/rooms/dm1/messages').last.json, {'body': 'selam'});

      final p = await Sohbet.benKaydet(durum: 'busy');
      expect(s.bul('PUT', '$_k/me').last.json, {'status': 'busy'});
      expect(p.cevrimiciGoster, isFalse);
      await Sohbet.benKaydet(cevrimiciGoster: false, durumMetni: 'Toplantı', bitisGonder: true);
      expect(s.bul('PUT', '$_k/me').last.json, {'show_presence': false, 'status_text': 'Toplantı', 'status_until': null});

      await Sohbet.kanalGuncelle('c1', arsiv: true);
      expect(s.bul('PATCH', '$_k/channels/c1').last.json, {'archived': true});
      expect(await Sohbet.kanalOlustur('duyurular', ''), 'c2');
      expect(s.bul('POST', '$_k/channels').last.json, {'name': 'duyurular', 'description': ''});

      await Sohbet.mesajlar('dm1', once: 8);
      expect(s.bul('GET', '$_k/rooms/dm1/messages').last.sorgu, {'before': 8});
    });

    test('ekler ve tepkiler: çözümleme, yükleme, gönderim, aç/kapat', () async {
      final m = SohbetMesaji.json({
        'id': 1,
        'body': '',
        'attachments': [
          {
            'id': 'a',
            'name': 'foto.jpg',
            'size': 10,
            'content_type': 'image/jpeg',
            'url': '/api/v1/mail/chat/attachments/a',
            'thumb_url': '/api/v1/mail/chat/attachments/a?thumb=1',
          },
          {'id': 'b', 'name': 'x.zip', 'size': 5, 'content_type': 'application/zip'},
        ],
        'reactions': [
          {
            'emoji': '🎉',
            'count': 1,
            'mine': true,
            'names': ['Ben'],
          },
          {'emoji': '', 'count': 1},
        ],
      });
      expect(m.ekler.first.resim, isTrue);
      expect(m.ekler.first.kucukUrl, contains('thumb=1'));
      expect(m.ekler.last.url, '/api/v1/mail/chat/attachments/b');
      expect(m.tepkiler.single.benim, isTrue);

      s.yollar['POST $_k/rooms/dm1/attachments'] = (201, {'id': 'e1', 'name': 'a.txt', 'size': 3, 'content_type': 'text/plain'});
      final ek = await Sohbet.ekYukle('dm1', 'a.txt', Uint8List.fromList([1, 2, 3]));
      expect(ek.id, 'e1');
      final g = s.bul('POST', '$_k/rooms/dm1/attachments').single.govde;
      expect(g, isA<FormData>());
      expect((g! as FormData).files.single.key, 'file');
      expect((g as FormData).files.single.value.filename, 'a.txt');

      s.yollar['POST $_k/rooms/dm1/attachments'] = (
        422,
        {
          'error': {'code': 'attachment_virus', 'message': 'virus'},
        },
      );
      await expectLater(
        Sohbet.ekYukle('dm1', 'k.exe', Uint8List(1)),
        throwsA(isA<ApiHata>().having((e) => e.kod, 'kod', 'attachment_virus').having((e) => e.mesaj, 'mesaj', contains('virüs'))),
      );

      await Sohbet.gonder('dm1', '', ekler: ['e1']);
      expect(s.bul('POST', '$_k/rooms/dm1/messages').last.json, {
        'body': '',
        'attachments': ['e1'],
      });

      final t = await Sohbet.tepki('dm1', 9, '👍');
      expect(s.bul('POST', '$_k/rooms/dm1/messages/9/reactions').last.json, {'emoji': '👍'});
      expect(t.single.sayi, 3);
      expect(t.single.benim, isTrue);
    });

    test('okunmamış toplamı ve okundu işaretleme', () async {
      await SohbetDurum.ben.yenile();
      expect(SohbetDurum.ben.okunmamis.value, 5);
      await SohbetDurum.ben.okunduIsaretle('dm1');
      expect(SohbetDurum.ben.okunmamis.value, 2);
      expect(s.bul('POST', '$_k/rooms/dm1/read'), hasLength(1));
    });

    test('sohbet kapalı (403 feature_disabled): sekme gizlenir', () async {
      s.yollar['GET $_k/rooms'] = (
        403,
        {
          'error': {'code': 'feature_disabled', 'message': 'Kurum içi mesajlaşma paketinizde yok'},
        },
      );
      await SohbetDurum.ben.yenile();
      expect(SohbetDurum.ben.kapali, isTrue);
    });
  });

  group('ekranlar', () {
    testWidgets('liste: odalar, okunmamış hapları, sekme süzgeci', (t) async {
      await t.pumpWidget(_uyg(const SohbetEkrani()));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('# Genel'), findsOneWidget);
      expect(find.text('Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Proje ekibi'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      await t.tap(find.text('Kanallar (2)'));
      await t.pump();
      expect(find.text('Ayşe Yılmaz'), findsNothing);
      expect(find.text('# Genel'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('oda: iletiler gösterilir, okundu bildirilir, yazılan ileti gönderilir', (t) async {
      await t.runAsync(SohbetDurum.ben.yenile);
      await t.pumpWidget(_uyg(const SohbetOdasiEkrani(odaId: 'dm1')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byType(MesajBalonu), findsNWidgets(2));
      expect(s.bul('POST', '$_k/rooms/dm1/read'), isNotEmpty);
      expect(find.text('Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Çevrimiçi'), findsOneWidget);
      // ek kartı ve tepki hapı
      expect(find.text('rapor.pdf'), findsOneWidget);
      expect(find.text('👍 2'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('tepki-👍')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(s.bul('POST', '$_k/rooms/dm1/messages/9/reactions').single.json, {'emoji': '👍'});
      expect(find.text('👍 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('sohbet-ek')), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey('sohbet-yaz')), 'Nasılsın?');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('sohbet-gonder')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(s.bul('POST', '$_k/rooms/dm1/messages').last.json, {'body': 'Nasılsın?'});
      expect(find.byType(MesajBalonu), findsNWidgets(3));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
