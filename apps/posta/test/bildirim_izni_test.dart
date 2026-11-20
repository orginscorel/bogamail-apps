// Bildirim izni: açıklama sayfası (izin vermeden önce), "Şimdi değil" ya da anahtar alınamazsa uyarı bandı
// (kapatılabilir, izin açılınca kaybolur). Ağ yok.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/bildirim_izni.dart';
import 'package:posta/veri/push_kaydi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

void main() {
  final s = YolSunucusu();
  setUpAll(s.kur);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BildirimIzni.kapali.value = null;
    BildirimIzni.gizlendi.value = false;
    BildirimIzni.apple = () => true;
    BildirimIzni.android = () => false;
  });

  Widget uyg(Widget w) => MaterialApp(
    theme: temaKur(Brightness.light),
    scaffoldMessengerKey: kokMesaj,
    home: Scaffold(body: w),
  );

  testWidgets('ilk açılışta açıklama; "Şimdi değil" izin istemez ve bandı gösterir; ikinci kez sorulmaz', (t) async {
    bool? sonuc;
    await t.pumpWidget(
      uyg(
        Builder(
          builder: (c) => Column(
            children: [
              TextButton(onPressed: () async => sonuc = await BildirimIzni.tanitimGerekirse(c), child: const Text('başla')),
              const BildirimIzniBandi(),
            ],
          ),
        ),
      ),
    );
    await t.tap(find.text('başla'));
    await t.pumpAndSettle();
    expect(find.text('Yeni postadan anında haberdar olun'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('bildirim-simdi-degil')));
    await t.pumpAndSettle();
    expect(sonuc, isFalse);
    expect(find.byKey(const ValueKey('bildirim-izni-bandi')), findsOneWidget);
    expect(find.text('Ayarları aç'), findsOneWidget);

    await t.tap(find.text('başla'));
    await t.pumpAndSettle();
    expect(find.text('Yeni postadan anında haberdar olun'), findsNothing, reason: 'açıklama bir kez');
    expect(sonuc, isTrue);

    await t.tap(find.byKey(const ValueKey('bildirim-bandi-kapat')));
    await t.pump();
    expect(find.byKey(const ValueKey('bildirim-izni-bandi')), findsNothing);
  });

  testWidgets('push anahtarı alınamazsa band çıkar, izin gelince kaybolur', (t) async {
    PushKaydi.destekli = () => true;
    PushKaydi.gonder = () async => true;
    PushKaydi.sifirla();
    Uyg.kutu.value = {'mailbox_id': 'k1', 'address': 'info@ornek.com'};
    s.yollar['GET /api/v1/mail/auth/accounts'] = (200, {'items': []});
    await t.pumpWidget(uyg(const BildirimIzniBandi()));
    String? anahtar;
    PushKaydi.anahtar = () async => anahtar;
    await t.runAsync(() => PushKaydi.kaydet());
    await t.pump();
    expect(find.byKey(const ValueKey('bildirim-izni-bandi')), findsOneWidget);
    anahtar = 'bb' * 32;
    await t.runAsync(() => PushKaydi.kaydet(zorla: true));
    await t.pump();
    expect(find.byKey(const ValueKey('bildirim-izni-bandi')), findsNothing);
  });
}
