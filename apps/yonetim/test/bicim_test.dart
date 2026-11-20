import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonetim/veri/bicim.dart';

void main() {
  group('kota', () {
    test('Sınırsız ön ayarı 1 PiB', () {
      expect(kotaOnAyarlari.last, ('Sınırsız', 1 << 50));
      expect(sinirsizMi(sinirsizKota), isTrue);
      expect(sinirsizMi(50 * gib), isFalse);
    });

    test('gbdenBayt virgüllü ve geçersiz girdiler', () {
      expect(gbdenBayt('5'), 5 * gib);
      expect(gbdenBayt('2,5'), (2.5 * gib).round());
      expect(gbdenBayt(' 1.5 '), (1.5 * gib).round());
      expect(gbdenBayt(''), isNull);
      expect(gbdenBayt('abc'), isNull);
      expect(gbdenBayt('0'), isNull);
      expect(gbdenBayt('-3'), isNull);
      expect(gbdenBayt('99999999999'), sinirsizKota);
    });

    test('baytGbMetni', () {
      expect(baytGbMetni(5 * gib), '5');
      expect(baytGbMetni((2.5 * gib).round()), '2,5');
      expect(baytGbMetni(gbdenBayt('0,25')!), '0,25');
    });

    test('kullanimOrani', () {
      expect(kullanimOrani(gib, 4 * gib), .25);
      expect(kullanimOrani(8 * gib, 4 * gib), 1.0);
      expect(kullanimOrani(gib, 0), isNull);
      expect(kullanimOrani(gib, sinirsizKota), isNull);
    });
  });

  group('süreler', () {
    test('yasYaz', () {
      expect(yasYaz(null), '—');
      expect(yasYaz(45), '45 sn');
      expect(yasYaz(12 * 60 + 5), '12 dk');
      expect(yasYaz(3 * 3600 + 5 * 60), '3 sa 5 dk');
      expect(yasYaz(2 * 86400 + 4 * 3600), '2 gün 4 sa');
    });

    test('suredir', () {
      final simdi = DateTime(2026, 1, 10, 12);
      expect(suredir(null), '');
      expect(suredir(simdi.subtract(const Duration(minutes: 5)), simdi: simdi), '5 dakikadır');
      expect(suredir(simdi.subtract(const Duration(hours: 3)), simdi: simdi), '3 saattir');
      expect(suredir(simdi.subtract(const Duration(days: 2)), simdi: simdi), '2 gündür');
      expect(suredir(simdi.add(const Duration(hours: 1)), simdi: simdi), '0 dakikadır');
    });

    test('sureYaz', () {
      expect(sureYaz(null), '—');
      expect(sureYaz(0), '—');
      expect(sureYaz(600), '10 dk');
      expect(sureYaz(90000.4), '1 gün 1 sa');
    });

    test('yasakSuresiEtiketi', () {
      expect(yasakSureleri.map((e) => e.$1), [1, 24, 168, 720, 0]);
      expect(yasakSuresiEtiketi(0), 'Süresiz');
      expect(yasakSuresiEtiketi(168), '7 gün');
      expect(yasakSuresiEtiketi(48), '2 gün');
      expect(yasakSuresiEtiketi(5), '5 saat');
    });
  });

  test('yuzdeYaz', () {
    expect(yuzdeYaz(98.456), '%98,5');
    expect(yuzdeYaz(100, basamak: 0), '%100');
  });

  group('sifreUret', () {
    test('uzunluk, karışık harf ve rakam', () {
      for (var i = 0; i < 200; i++) {
        final s = sifreUret();
        expect(s.length, 20);
        expect(s, matches(RegExp(r'[A-Z]')));
        expect(s, matches(RegExp(r'[a-z]')));
        expect(s, matches(RegExp(r'[0-9]')));
        expect(s, isNot(matches(RegExp(r'[0O1lI]'))), reason: 'karıştırılabilir karakterler alfabede yok');
      }
    });

    test('en az 12 karakter ve tohumla belirlenimli', () {
      expect(sifreUret(uzunluk: 4).length, 12);
      expect(sifreUret(rastgele: Random(7)), sifreUret(rastgele: Random(7)));
    });
  });

  test('rolEtiketi', () {
    expect(rolEtiketi('super_admin'), 'Süper Yönetici');
    expect(rolEtiketi('bilinmeyen'), 'bilinmeyen');
  });

  test('htmldenMetin betik ve stili atar, varlıkları çözer', () {
    const html = '<style>p{}</style><p>Merhaba&nbsp;<b>Ali</b></p><script>alert(1)</script><div>Fiyat &lt; 5 &amp; KDV</div>';
    expect(htmldenMetin(html), 'Merhaba Ali\nFiyat < 5 & KDV');
  });

  test('cihazAdi', () {
    expect(cihazAdi(''), 'Bilinmeyen cihaz');
    expect(cihazAdi('BogaMail-Yonetim/1.0.0 (1) (iOS 18.1)'), 'BogaMail Yönetim · iOS 18.1');
    expect(cihazAdi('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131.0 Safari/537.36'), 'Chrome · macOS');
    expect(cihazAdi('Mozilla/5.0 (Windows NT 10.0) Chrome/131.0 Safari/537.36 Edg/131.0'), 'Edge · Windows');
    expect(cihazAdi('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Version/18.0 Mobile Safari/604.1'), 'Safari · iOS');
  });

  test('adresleriAyir', () {
    expect(adresleriAyir('Ali@Firma.com, veli@firma.com;\nali@firma.com  ayse@firma.com'), ['ali@firma.com', 'veli@firma.com', 'ayse@firma.com']);
    expect(adresleriAyir('  \n '), isEmpty);
  });
}
