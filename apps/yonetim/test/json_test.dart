import 'package:flutter_test/flutter_test.dart';
import 'package:yonetim/veri/json.dart';

void main() {
  test('metin / metinYa', () {
    expect(metin(null), '');
    expect(metin(null, 'x'), 'x');
    expect(metin(12), '12');
    expect(metin(true), 'true');
    expect(metin({'a': 1}), '');
    expect(metinYa('  '), isNull);
    expect(metinYa(' a '), 'a');
  });

  test('tamsayi / tamsayiYa', () {
    expect(tamsayi(5), 5);
    expect(tamsayi(5.9), 5);
    expect(tamsayi('42'), 42);
    expect(tamsayi('4.2'), 4);
    expect(tamsayi('x', 7), 7);
    expect(tamsayi(double.nan, 3), 3);
    expect(tamsayi(null), 0);
    expect(tamsayiYa(null), isNull);
    expect(tamsayiYa('x'), isNull);
    expect(tamsayiYa(3.0), 3);
  });

  test('ondalik / mantik', () {
    expect(ondalik('2,5'), 2.5);
    expect(ondalik(3), 3.0);
    expect(ondalik(null, 1), 1);
    expect(ondalikYa('x'), isNull);
    expect(mantik(true), isTrue);
    expect(mantik(1), isTrue);
    expect(mantik('true'), isTrue);
    expect(mantik('hayır'), isFalse);
    expect(mantik(null, true), isTrue);
  });

  test('tarihOku', () {
    expect(tarihOku(null), isNull);
    expect(tarihOku(''), isNull);
    expect(tarihOku('bozuk'), isNull);
    expect(tarihOku('2026-03-01T10:00:00Z')!.toUtc(), DateTime.utc(2026, 3, 1, 10));
  });

  test('harita / haritalar / metinler hoşgörülü', () {
    expect(harita(null), isEmpty);
    expect(harita([1]), isEmpty);
    expect(harita({1: 'a'}), {'1': 'a'});
    expect(haritalar([{'a': 1}, 3, null, {'b': 2}]), [{'a': 1}, {'b': 2}]);
    expect(haritalar('x'), isEmpty);
    expect(metinler(['a', null, 2]), ['a', '2']);
    expect(metinler(null), isEmpty);
  });

  group('Sayfa.coz', () {
    test('items + total', () {
      final s = Sayfa.coz({'items': [{'id': 1}, {'id': 2}], 'total': 40, 'page': 1}, (m) => m['id']);
      expect(s.ogeler, [1, 2]);
      expect(s.toplam, 40);
    });
    test('total yoksa öğe sayısı, items yoksa boş', () {
      expect(Sayfa.coz({'items': [{'id': 1}]}, (m) => m['id']).toplam, 1);
      final bos = Sayfa.coz(null, (m) => m);
      expect(bos.ogeler, isEmpty);
      expect(bos.toplam, 0);
    });
  });
}
