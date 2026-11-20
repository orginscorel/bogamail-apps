// APNs kaydı: her açılışta, hesap değişince ve anahtar değişince yapılır; öne gelişlerde seyreltilir; aynı anda
// gelen çağrılar birleşir; kayıttan önce cihaz çerezi için /auth/accounts çağrılır. Ağ yok.

import 'package:flutter_test/flutter_test.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/push_kaydi.dart';

import 'sahte_sunucu.dart';

void main() {
  final s = YolSunucusu();
  var gonderim = 0;
  var anahtar = 'aa' * 32;
  var zaman = DateTime(2026, 11, 20, 12);
  setUpAll(s.kur);
  setUp(() {
    s.istekler.clear();
    s.yollar
      ..clear()
      ..['GET /api/v1/mail/auth/accounts'] = (200, {'items': []});
    gonderim = 0;
    anahtar = 'aa' * 32;
    zaman = DateTime(2026, 11, 20, 12);
    PushKaydi.destekli = () => true;
    PushKaydi.anahtar = () async => anahtar;
    PushKaydi.gonder = () async {
      gonderim++;
      return true;
    };
    PushKaydi.simdi = () => zaman;
    PushKaydi.sifirla();
    Uyg.kutu.value = {'mailbox_id': 'k1', 'address': 'info@ornek.com'};
  });

  test('açılışta kaydeder, önce cihaz çerezi için hesap listesi istenir', () async {
    expect(await PushKaydi.kaydet(), isTrue);
    expect(gonderim, 1);
    expect(s.bul('GET', '/api/v1/mail/auth/accounts'), hasLength(1));
  });

  test('öne gelişte seyreltilir; süre dolunca, zorla, hesap ya da anahtar değişince yeniden kaydeder', () async {
    await PushKaydi.kaydet();
    await PushKaydi.kaydet();
    expect(gonderim, 1, reason: 'aynı hesap + anahtar, aralık dolmadı');
    zaman = zaman.add(PushKaydi.yenilemeAraligi + const Duration(minutes: 1));
    await PushKaydi.kaydet();
    expect(gonderim, 2);
    await PushKaydi.kaydet(zorla: true);
    expect(gonderim, 3);
    Uyg.kutu.value = {'mailbox_id': 'k2', 'address': 'semih@ornek.com'};
    await PushKaydi.kaydet();
    expect(gonderim, 4, reason: 'hesap değişti');
    anahtar = 'bb' * 32;
    await PushKaydi.kaydet();
    expect(gonderim, 5, reason: 'anahtar değişti');
  });

  test('aynı anda gelen çağrılar tek kayıt; izin yoksa hata kaydedilir', () async {
    await Future.wait([PushKaydi.kaydet(), PushKaydi.kaydet(), PushKaydi.kaydet()]);
    expect(gonderim, 1);
    PushKaydi.anahtar = () async => null;
    expect(await PushKaydi.kaydet(zorla: true), isFalse);
    expect(PushKaydi.sonHata, isNotNull);
  });

  test('desteklenmeyen platformda hiçbir şey yapılmaz', () async {
    PushKaydi.destekli = () => false;
    expect(await PushKaydi.kaydet(), isFalse);
    expect(s.istekler, isEmpty);
  });
}
