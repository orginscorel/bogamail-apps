// Masaüstü düzeni: geniş pencerede Ayarlar iki bölmeli (kategoriler + içerik), alt sayfalar sağ bölmede açılır.
// Klasör simge/renkleri web ile aynı. Ağ yok.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/ayarlar.dart';
import 'package:posta/ekranlar/ayarlar/bolum.dart';
import 'package:posta/ekranlar/ayarlar/bolumler.dart';
import 'package:posta/ortak/simgeler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

void main() {
  final s = YolSunucusu();
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    s.kur();
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() {
    s.istekler.clear();
    s.yollar
      ..clear()
      ..['GET /api/v1/mail/settings'] = (200, {'display_name': 'Ayşe', 'page_size': 50, 'features': {}})
      ..['GET /api/v1/mail/auth/accounts'] = (200, {'items': []})
      ..['GET /api/v1/mail/auth/me'] = (
        200,
        {
          'mailbox': {'mailbox_id': 'm1', 'address': 'ayse@ornek.com'},
        },
      );
  });

  testWidgets('geniş pencerede Ayarlar: kategori listesi ve sağ bölme', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const AyarlarEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('ayar-kategori-hesaplar')), findsOneWidget);
    expect(find.byKey(const ValueKey('ayar-kategori-guvenlik')), findsOneWidget);
    expect(find.text('BU CİHAZDAKİ HESAPLAR'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('ayar-kategori-gorunum')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Tema'), findsOneWidget);
    // Sol liste yerinde kalır (tam ekran sayfaya geçilmez).
    expect(find.byKey(const ValueKey('ayar-kategori-hesaplar')), findsOneWidget);

    // Güvenlik alt sayfası sağ bölmenin kendi gezgininde açılır; kategori listesi görünür kalır.
    await t.tap(find.byKey(const ValueKey('ayar-kategori-guvenlik')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Şifre değiştir'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('ayar-kategori-hesaplar')), findsOneWidget);
    expect(find.byType(Navigator), findsNWidgets(2));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('eklenen ayar bölümü sol listede görünür, aynı id yerleşiğin yerine geçer', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final onceki = [...ekAyarBolumleri];
    addTearDown(
      () => ekAyarBolumleri
        ..clear()
        ..addAll(onceki),
    );
    ekAyarBolumleri
      ..removeWhere((b) => b.id == 'sablonlar' || b.id == 'gorunum')
      ..add(
        AyarBolumu(
          id: 'sablonlar',
          ikon: Icons.space_dashboard_outlined,
          baslik: 'Şablonlar',
          sira: 45,
          olustur: (_) => ListView(children: const [Text('şablon içeriği')]),
        ),
      )
      ..add(AyarBolumu(id: 'gorunum', ikon: Icons.palette_outlined, baslik: 'Görünüm', sira: 30, olustur: (_) => const Text('yeni görünüm')));
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const AyarlarEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byKey(const ValueKey('ayar-kategori-sablonlar')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('şablon içeriği'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ayar-kategori-gorunum')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('yeni görünüm'), findsOneWidget);
    expect(find.byKey(const ValueKey('ayar-kategori-gorunum')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('dar pencerede Ayarlar tek sütun', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const AyarlarEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('ayar-kategori-hesaplar')), findsNothing);
    expect(find.text('HESAPLAR VE OTURUM'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('telefonda yerine geçen bölümler yerinde satır olur, eski kartlar ve tekrarlar yok', (t) async {
    t.view.physicalSize = const Size(400, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const AyarlarEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final ekIdler = ekAyarBolumleri.map((b) => b.id).toSet();
    for (final id in ['genel', 'gorunum', 'bildirimler', 'otomatik'].where(ekIdler.contains)) {
      expect(find.byKey(ValueKey('ayar-satir-$id')), findsOneWidget, reason: id);
    }
    if (ekIdler.contains('gorunum')) expect(find.text('Uzak görselleri otomatik göster'), findsNothing);
    if (ekIdler.contains('genel')) {
      expect(find.text('Sayfa başına ileti'), findsNothing);
      expect(find.byKey(const ValueKey('imza-ac')), findsOneWidget);
    }
    // Yerleşik karşılığı olanlar "Diğer ayarlar"ın altında değil, kendi başlıklarının altında.
    if (ekIdler.contains('gorunum')) {
      expect(t.getTopLeft(find.byKey(const ValueKey('ayar-satir-gorunum'))).dy, lessThan(t.getTopLeft(find.text('DİĞER AYARLAR')).dy));
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });

  test('klasör simge ve renkleri web ile aynı', () {
    expect(klasorRengi('trash'), const Color(0xFFEF4444));
    expect(klasorRengi('junk'), const Color(0xFFF97316));
    expect(klasorRengi('inbox'), isNull);
    expect(klasorSimgesi('junk'), Icons.gpp_maybe_outlined);
    expect(gorunumRengi('starred'), yildizRengi);
    expect(etiketRengi('yellow'), const Color(0xFFFBBF24));
  });
}
