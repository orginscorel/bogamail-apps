import 'package:flutter_test/flutter_test.dart';
import 'package:yonetim/veri/denetim.dart';

void main() {
  test('bilinen eylem etiketleri', () {
    final e = denetimEylemi('mailbox.create');
    expect(e.etiket, 'Posta kutusu oluşturuldu');
    expect(e.grup, 'mailbox');
    expect(denetimEylemi('auth.login_failed').ton, 'danger');
  });

  test('bilinmeyen eylem okunur gösterilir', () {
    final e = denetimEylemi('foo.bar_baz');
    expect(e.etiket, 'Foo bar baz');
    expect(e.grup, 'other');
    expect(denetimEylemi('foo.sync_failed').ton, 'danger');
    expect(koduOkunur('import.started'), 'İmport started');
  });

  test('eylemAra Türkçe etiketlerle eşleşir', () {
    expect(eylemAra('a'), isEmpty);
    final l = eylemAra('POSTA KUTUSU');
    expect(l, contains('mailbox.create'));
    expect(eylemAra('İçe'), everyElement(isA<String>()));
    expect(eylemAra('posta', enFazla: 3).length, lessThanOrEqualTo(3));
  });

  test('trKucuk', () {
    expect(trKucuk('İSTANBUL'), 'istanbul');
    expect(trKucuk('ILIK'), 'ılık');
  });

  test('sayiMetni', () {
    expect(sayiMetni(0), '0');
    expect(sayiMetni(1234567), '1.234.567');
    expect(sayiMetni(-1500), '-1.500');
    expect(sayiMetni(2.5), '2,50');
  });

  test('denetimAyrintilari kimlikleri gizler', () {
    final r = denetimAyrintilari({'mailbox_id': 'x', 'organization_id': 'y', 'queue_id': 'Q1', 'boş': null});
    expect(r.map((e) => e.$2), contains('Q1'));
    expect(r.map((e) => e.$2), isNot(contains('x')));
    expect(denetimAyrintilari(null), isEmpty);
  });

  test('denetimOzeti en fazla N satır ve +kalan', () {
    final o = denetimOzeti({'a': 1, 'b': 2, 'c': 3, 'd': 4, 'e': 5}, enFazla: 2);
    expect(o.split(' · ').length, 3);
    expect(o.endsWith('+3'), isTrue);
  });

  test('denetimHedefi', () {
    expect(denetimHedefi('', '', null, const {}), isNull);
    expect(denetimHedefi('mailbox', 'id', null, const {'address': 'ali@firma.com'}), contains('ali@firma.com'));
  });
}
