import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/ayarlar.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    kullaniciAyarla();
    Uyg.api = SahteApi({
      'GET /api/v1/auth/mfa': {'enabled': true},
      'GET /api/v1/auth/sessions': {'items': <Object>[]},
    });
  });

  testWidgets('geniş pencerede solda kategori listesi, sağda içerik', (t) async {
    ekranBoyutu(t, const Size(1400, 900));
    await t.pumpWidget(testUygulamasi(const AyarlarEkrani()));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Hesap ve güvenlik'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Görünüm'), findsOneWidget);
    expect(find.text('Tema'), findsNothing);
    await t.tap(find.widgetWithText(ListTile, 'Görünüm'));
    await t.pumpAndSettle();
    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('Çıkış yap'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('telefonda tek sütun, kategori listesi yok', (t) async {
    ekranBoyutu(t, const Size(400, 3000));
    await t.pumpWidget(testUygulamasi(const AyarlarEkrani()));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Görünüm'), findsNothing);
    expect(find.text('Tema'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
