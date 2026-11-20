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
    t.view.physicalSize = const Size(1440, 1400);
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
    t.view.physicalSize = const Size(1440, 1400);
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
          ikon: Simge.pano,
          baslik: 'Şablonlar',
          sira: 45,
          olustur: (_) => ListView(children: const [Text('şablon içeriği')]),
        ),
      )
      ..add(AyarBolumu(id: 'gorunum', ikon: Simge.palet, baslik: 'Görünüm', sira: 30, olustur: (_) => const Text('yeni görünüm')));
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
    expect(find.text('PROFİL VE HESAP'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('Ayarlar gruplu: Profil ve hesap / Posta / Uygulama; telefonda profil kartı, tekrar yok', (t) async {
    // Masaüstü sol liste: grup başlıkları ve doğru gruplama.
    t.view.physicalSize = const Size(1440, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const AyarlarEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    double y(String k) => t.getTopLeft(find.byKey(ValueKey(k))).dy;
    expect(y('ayar-grup-profil'), lessThan(y('ayar-kategori-guvenlik')));
    expect(y('ayar-kategori-hesaplar'), lessThan(y('ayar-grup-posta')));
    expect(y('ayar-kategori-depolama'), lessThan(y('ayar-grup-posta')));
    for (final id in ['genel', 'imza', 'suzgecler', 'klasorler', 'etiketler', 'tasima', 'kurulum']) {
      expect(y('ayar-kategori-$id'), greaterThan(y('ayar-grup-posta')), reason: id);
      expect(y('ayar-kategori-$id'), lessThan(y('ayar-grup-uygulama')), reason: id);
    }
    for (final id in ['gorunum', 'bildirimler', 'uygulama', 'hakkinda']) {
      expect(y('ayar-kategori-$id'), greaterThan(y('ayar-grup-uygulama')), reason: id);
    }
    await t.pumpWidget(const SizedBox());

    // Telefon: profil kartı en üstte; her kategori tek satır (tekrar yok).
    t.view.physicalSize = const Size(400, 3000);
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const AyarlarEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('profil-karti')), findsOneWidget);
    expect(y('profil-karti'), lessThan(y('ayar-grup-profil')));
    for (final id in ['gorunum', 'genel', 'bildirimler', 'otomatik', 'hesaplar', 'guvenlik']) {
      expect(find.byKey(ValueKey('ayar-satir-$id')), findsOneWidget, reason: id);
    }
    expect(find.text('Uzak görselleri otomatik göster'), findsNothing);
    expect(find.text('DİĞER AYARLAR'), findsNothing);
    expect(y('ayar-satir-gorunum'), greaterThan(y('ayar-grup-uygulama')));
    await t.tap(find.byKey(const ValueKey('ayar-satir-hakkinda')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Sunucu'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });

  test('klasör simge ve renkleri web ile aynı', () {
    expect(klasorRengi('trash'), const Color(0xFFEF4444));
    expect(klasorRengi('junk'), const Color(0xFFF97316));
    expect(klasorRengi('inbox'), isNull);
    expect(klasorSimgesi('junk'), Simge.gereksiz);
    expect(gorunumRengi('starred'), yildizRengi);
    expect(etiketRengi('yellow'), const Color(0xFFFBBF24));
  });
}
