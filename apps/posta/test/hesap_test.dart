import 'package:flutter_test/flutter_test.dart';
import 'package:posta/veri/hesap_servisi.dart';

void main() {
  test('modeller eksik/yanlış alanlarda çökmez', () {
    for (final v in [null, 1, 'x', <String, dynamic>{}]) {
      expect(Planli.json(v).id, '');
      expect(Kisi.json(v).eposta, '');
      expect(Suzgec.json(v).kosullar, isEmpty);
      expect(Yonlendirme.json(v).kopyaKalsin, isTrue);
      expect(IkiAdimDurumu.json(v).acik, isFalse);
      expect(OtomatikKural.json(v).araGun, 4);
      expect(ImzaProfili.json(v).duzenlenebilir, isTrue);
      expect(YoneticiErisimi.json(v).olaylar, isEmpty);
    }
  });

  test('süzgeç gidiş-dönüş: sunucu alan adları korunur, değersiz eylemde value gönderilmez', () {
    final s = Suzgec.json({
      'id': 'f1',
      'name': 'Faturalar',
      'enabled': true,
      'match_all': false,
      'conditions': [
        {'field': 'from', 'op': 'contains', 'value': 'fatura'},
      ],
      'actions': [
        {'type': 'move', 'value': 'k1'},
        {'type': 'mark_read'},
      ],
      'stop': true,
    });
    final j = s.json();
    expect(j.keys.toSet(), {'id', 'name', 'enabled', 'position', 'match_all', 'conditions', 'actions', 'stop'});
    expect(j['conditions'], [
      {'field': 'from', 'op': 'contains', 'value': 'fatura'},
    ]);
    expect(j['actions'], [
      {'type': 'move', 'value': 'k1'},
      {'type': 'mark_read'},
    ]);
  });

  test('otomatik yanıt kuralı: düzenlenmeyen koşullar korunur', () {
    final k = OtomatikKural.json({
      'id': 'r1',
      'name': 'Mesai dışı',
      'enabled': true,
      'conditions': {
        'schedule': 'outside',
        'weekdays': [1, 2, 3, 4, 5],
        'start_time': '09:00',
        'end_time': '18:00',
        'sender': 'external',
        'senders': ['@ornek.com'],
        'subject_keywords': <String>[],
      },
      'subject': 'Mesai dışı',
      'body_html': 'Merhaba',
      'once_per_days': 2,
      'org_wide': false,
    });
    final j = k.json();
    expect(j.keys.toSet(), {'name', 'enabled', 'position', 'conditions', 'subject', 'body_html', 'once_per_days'});
    final c = j['conditions'] as Map;
    expect(c['senders'], ['@ornek.com']);
    expect(c['schedule'], 'outside');
    expect(c['weekdays'], [1, 2, 3, 4, 5]);
  });

  test('kişi gövdesi yalnızca sunucunun kabul ettiği alanları içerir', () {
    final k = Kisi.json({'id': 'c1', 'name': 'Ayşe', 'email': 'ayse@ornek.com', 'auto': true, 'use_count': 3});
    expect(k.govde().keys.toSet(), {'name', 'email', 'phone', 'company', 'note', 'favorite'});
    expect(k.kopya(favori: true).govde()['favorite'], isTrue);
  });
}
