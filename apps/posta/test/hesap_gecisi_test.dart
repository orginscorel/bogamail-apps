// Hesap geçişi beklemesiz: hedef hesabın önbellekteki klasör ve listesi ağ beklenmeden (sunucu hata verse bile)
// gösterilir, yükleme ekranı çıkmaz, açık klasör rolü korunur (Gelen → Gelen), bildirim gösterilir. Ağ yok.

import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/kabuk.dart';
import 'package:posta/oturum.dart';
import 'package:posta/ortak/iskelet.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/onbellek.dart';
import 'package:posta/veri/onyukleme.dart';
import 'package:posta/veri/posta_servisi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

void main() {
  late Directory kok;
  final s = YolSunucusu();
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Onyukleme.etkin = false;
    SharedPreferences.setMockInitialValues({});
    s.kur();
  });
  setUp(() {
    kok = Directory.systemTemp.createTempSync('gecis_');
    Onbellek.kok = () async => kok;
    Onbellek.ben.testSifirla();
  });
  tearDown(() {
    Onbellek.ben.testSifirla();
    kok.deleteSync(recursive: true);
  });

  testWidgets('geçişte hedef hesabın önbelleği hemen görünür, yükleme ekranı yok', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // Hedef hesabın (k2) önbelleği: klasörler ve Gelen listesi.
    await t.runAsync(() async {
      s.yollar
        ..['GET /api/v1/mail/folders'] = (
          200,
          {
            'items': [
              {'id': 'g2', 'name': 'INBOX', 'role': 'inbox', 'unseen': 1, 'total': 1},
            ],
          },
        )
        ..['GET /api/v1/mail/labels'] = (200, {'items': []})
        ..['GET /api/v1/mail/folders/g2/messages'] = (
          200,
          {
            'items': [
              {'id': 'x', 'subject': 'Önbellekten gelen ileti', 'from': 'Can <can@b.com>', 'date': '2026-11-20T09:00:00Z', 'seen': false},
            ],
            'total': 1,
            'page': 1,
            'page_size': 50,
          },
        );
      await Onbellek.ben.hesapAc('k2');
      await Posta.klasorler();
      await Posta.etiketler();
      await Posta.liste(klasorId: 'g2');
      await Future<void>.delayed(const Duration(milliseconds: 700)); // dizin yazımı
      await Onbellek.ben.hesapAc('k1');
    });
    // Geçişten sonra sunucu yavaş/hatalı olsa bile içerik önbellekten gelmeli.
    s.yollar
      ..clear()
      ..['POST /api/v1/mail/auth/switch'] = (200, {'mailbox_id': 'k2'})
      ..['GET /api/v1/mail/auth/me'] = (
        200,
        {
          'mailbox': {'mailbox_id': 'k2', 'address': 'satis@ornek.com', 'display_name': 'Satış'},
        },
      )
      ..['GET /api/v1/mail/folders'] = (500, null)
      ..['GET /api/v1/mail/folders/g2/messages'] = (500, null);
    Uyg.kutu.value = {'mailbox_id': 'k1', 'address': 'info@ornek.com', 'display_name': 'Info'};
    PostaDurum.ben
      ..klasorler = []
      ..yuklendi = false;

    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), navigatorKey: kokGezgin, scaffoldMessengerKey: kokMesaj, home: const SizedBox()));
    PostaDurum.ben.gecisRolu = 'inbox';
    await t.runAsync(
      () => Uyg.hesabaGec(
        hesap: const KayitliHesap(id: 'k2', adres: 'satis@ornek.com', ad: 'Satış'),
      ),
    );
    // Önbellek okuması gerçek disk G/Ç'sidir: kısa gerçek beklemelerle kareler ilerletilir.
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 40));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await t.pump(const Duration(milliseconds: 250));
    expect(find.byType(Kabuk), findsOneWidget);
    expect(Uyg.adres, 'satis@ornek.com', reason: 'kutu bilgisi hemen güncellenir');
    expect(PostaDurum.ben.konum, const Konum.klasor('g2'), reason: 'Gelen → Gelen');
    expect(find.text('Önbellekten gelen ileti'), findsOneWidget);
    expect(find.text('satis@ornek.com hesabına geçildi'), findsOneWidget);
    expect(find.byType(ListeIskeleti), findsNothing, reason: 'yükleme iskeleti yok');
    expect(find.byType(AcilisEkrani), findsNothing, reason: 'açılış ekranı yok');
    expect(find.textContaining('hata oluştu'), findsNothing, reason: 'sunucu hatası önbellekli listeyi bozmaz');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
