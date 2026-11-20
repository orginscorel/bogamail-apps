// Takvim, davet ve görev istek gövdeleri: sunucu bilinmeyen alanları reddettiğinden yalnızca listelenen alanlar.

import 'package:flutter_test/flutter_test.dart';
import 'package:posta/veri/takvim_servisi.dart';

import 'sahte_sunucu.dart';

void main() {
  final s = YolSunucusu();
  setUpAll(s.kur);
  setUp(() {
    s.istekler.clear();
    s.yollar.clear();
  });

  test('etkinlik gövdesi calEvent alanlarıyla sınırlı, UTC zaman', () {
    final e = Etkinlik(
      takvimId: 'c1',
      baslik: ' Toplantı ',
      baslangic: DateTime.utc(2026, 11, 20, 9),
      bitis: DateTime.utc(2026, 11, 20, 10),
      hatirlatma: 15,
      tekrar: 'WEEKLY',
      katilimcilar: const [Katilimci(ad: 'Ayşe', eposta: 'ayse@ornek.com')],
    );
    final g = e.govde(davetGonder: true);
    expect(g.keys.toSet(), {
      'calendar_id',
      'title',
      'location',
      'description',
      'starts_at',
      'ends_at',
      'all_day',
      'rrule',
      'reminder_minutes',
      'attendees',
      'send_invites',
    });
    expect(g['title'], 'Toplantı');
    expect(g['starts_at'], '2026-11-20T09:00:00.000Z');
    expect(g['attendees'], [
      {'name': 'Ayşe', 'email': 'ayse@ornek.com'},
    ]);
    expect(e.govde().containsKey('send_invites'), isFalse);
  });

  test('etkinlik çözümleme ve gün çakışması', () {
    final e = Etkinlik.json({
      'id': 'e1',
      'title': 'Tatil',
      'starts_at': DateTime(2026, 11, 20).toUtc().toIso8601String(),
      'ends_at': DateTime(2026, 11, 22).toUtc().toIso8601String(),
      'all_day': true,
      'reminder_minutes': null,
      'attendees': [],
      'itip': {'role': 'attendee'},
    });
    expect(e.hatirlatma, isNull);
    expect(e.davetli, isTrue);
    expect(e.gununde(DateTime(2026, 11, 21)), isTrue);
    expect(e.gununde(DateTime(2026, 11, 22)), isFalse);
    expect(Etkinlik.json(null).baslik, '');
  });

  test('etkinlik kaydet / sil / aralık istekleri', () async {
    s.yollar['POST /api/v1/mail/calendar/events'] = (
      201,
      {'id': 'e9', 'title': 'X', 'starts_at': '2026-11-20T09:00:00Z', 'ends_at': '2026-11-20T10:00:00Z', 'invites_sent': true},
    );
    s.yollar['DELETE /api/v1/mail/calendar/events/e9'] = (204, null);
    s.yollar['GET /api/v1/mail/calendar/events'] = (200, {'items': []});
    final r = await TakvimApi.kaydet(Etkinlik(baslik: 'X', baslangic: DateTime.utc(2026, 11, 20, 9), bitis: DateTime.utc(2026, 11, 20, 10)), davetGonder: true);
    expect(r.davetGonderildi, isTrue);
    expect(r.etkinlik.id, 'e9');
    expect(s.istekler.last.json.containsKey('calendar_id'), isFalse);
    await TakvimApi.sil('e9', bildir: true);
    expect(s.istekler.last.sorgu, {'notify': '1'});
    await TakvimApi.etkinlikler(DateTime.utc(2026, 11), DateTime.utc(2026, 12));
    expect(s.istekler.last.sorgu, {'from': '2026-11-01T00:00:00.000Z', 'to': '2026-12-01T00:00:00.000Z'});
  });

  test('davet yanıtı', () async {
    s.yollar['POST /api/v1/mail/messages/m1/invite/respond'] = (200, {'event_id': 'e1', 'replied': true});
    final v = await TakvimApi.davetYanitla('m1', 'ACCEPTED');
    expect(v.yanitlandi, isTrue);
    expect(s.istekler.last.json, {'partstat': 'ACCEPTED', 'no_reply': false});
    final d = Davet.json({
      'invite': {
        'method': 'request',
        'title': 'Kurul',
        'attendees': [
          {'name': 'A', 'email': 'a@x.com', 'partstat': 'ACCEPTED'},
        ],
        'outdated': false,
        'is_organizer': false,
      },
    });
    expect(d.yontem, 'REQUEST');
    expect(d.katilimcilar.single.yanit, 'ACCEPTED');
  });

  test('görev: oluştur, atanan yalnızca durum, yorum', () async {
    s.yollar['POST /api/v1/mail/tasks'] = (201, {'id': 't1', 'title': 'Rapor', 'status': 'todo', 'priority': 'high', 'can_edit': true});
    s.yollar['PATCH /api/v1/mail/tasks/t1'] = (200, {});
    s.yollar['POST /api/v1/mail/tasks/t1/comments'] = (
      201,
      {
        'id': 3,
        'body': 'Tamam',
        'author': {'id': 'a', 'address': 'a@x.com', 'name': 'A'},
      },
    );
    s.yollar['GET /api/v1/mail/tasks'] = (200, {'items': []});

    final g = await GorevApi.olustur(baslik: ' Rapor ', oncelik: 'high', atananId: 'u2', iletiId: 'm5');
    expect(g.oncelik, 'high');
    expect(s.istekler.last.json, {
      'title': 'Rapor',
      'notes': '',
      'due_at': null,
      'priority': 'high',
      'status': 'todo',
      'assignee_id': 'u2',
      'message_id': 'm5',
    });
    await GorevApi.olustur(baslik: 'B');
    expect(s.istekler.last.json.containsKey('message_id'), isFalse);
    expect(s.istekler.last.json['assignee_id'], isNull);

    await GorevApi.durumDegistir('t1', 'done');
    expect(s.istekler.last.json, {'status': 'done'});
    final y = await GorevApi.yorumla('t1', ' Tamam ');
    expect(s.istekler.last.json, {'body': 'Tamam'});
    expect(y.yazar!.gorunen, 'A');

    await GorevApi.liste(kapsam: 'assigned', durum: 'open');
    expect(s.istekler.last.sorgu, {'scope': 'assigned', 'status': 'open'});
  });

  test('görev çözümleme: gecikme, eksik alanlar', () {
    final g = Gorev.json({
      'id': 't',
      'title': 'X',
      'due_at': '2020-01-01T00:00:00Z',
      'status': 'doing',
      'assignee': null,
      'message': {'id': null, 'subject': 'Konu'},
    });
    expect(g.gecikti, isTrue);
    expect(g.atanan, isNull);
    expect(g.iletiId, isNull);
    expect(g.iletiKonu, 'Konu');
    expect(Gorev.json(null).durum, 'todo');
  });
}
