// Kayıtlı hesaplar: liste, şifresiz geçiş, çıkış (kayıtlı kalır / cihazdan kaldır). Ağ yok.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posta/ekranlar/hesaplar.dart';
import 'package:posta/oturum.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

const _k = '/api/v1/mail/auth';

void main() {
  final s = YolSunucusu();
  setUpAll(() {
    s.kur();
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() {
    s.istekler.clear();
    s.yollar
      ..clear()
      ..['GET $_k/accounts'] = (
        200,
        {
          'items': [
            {'id': 'a1', 'address': 'ayse@ornek.com', 'display_name': 'Ayşe', 'active': false, 'signed_out': true, 'unread': 4},
            {'id': 'a2', 'address': 'satis@ornek.com', 'display_name': '', 'active': false, 'signed_out': true, 'unread': 0},
          ],
        },
      );
  });

  test('hesap modeli', () {
    final h = KayitliHesap.json({'id': 'x', 'address': 'a@b.c', 'active': true, 'unread': 2});
    expect(h.etkin, isTrue);
    expect(h.okunmamis, 2);
    expect(h.gorunen, 'a@b.c');
    expect(KayitliHesap.json(null).id, '');
  });

  testWidgets('kayıtlı postalarınız: liste ve tek dokunuşla geçiş isteği', (t) async {
    s.yollar['POST $_k/switch'] = (401, {'error': {'code': 'unauthorized', 'message': 'Oturum yok'}});
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, navigatorKey: kokGezgin, home: const GirisKapisi()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Kayıtlı postalarınız'), findsOneWidget);
    expect(find.text('Ayşe'), findsOneWidget);
    expect(find.text('satis@ornek.com'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.byKey(const ValueKey('baska-hesap')), findsOneWidget);

    await t.tap(find.text('Ayşe'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(s.bul('POST', '$_k/switch').single.json, {'mailbox_id': 'a1'});
    // Geçiş reddedilince adres dolu giriş formu açılır ("Bu cihazda kayıtlı kalsın" seçeneğiyle).
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Bu cihazda kayıtlı kalsın'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  test('çıkış: forget ve push_token gövdesi; sonraki hesap yoksa giriş', () async {
    SharedPreferences.setMockInitialValues({'posta.push': 'jeton1'});
    s.yollar['POST $_k/logout'] = (200, {'next': null});
    await Uyg.cikis(unut: true);
    expect(s.bul('POST', '$_k/logout').single.json, {'forget': true, 'push_token': 'jeton1'});
  });

  test('hesabı cihazdan kaldır', () async {
    s.yollar['DELETE $_k/accounts/a2'] = (204, null);
    await Uyg.hesabiKaldir('a2');
    expect(s.bul('DELETE', '$_k/accounts/a2'), hasLength(1));
  });
}
