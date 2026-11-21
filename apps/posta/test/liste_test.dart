// İleti listesinin okunmuş/okunmamış görünümü ve üst süzgeçler. Ağ yok: Dio sahte bağdaştırıcıyla yanıtlanır.

import 'dart:convert';
import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/ileti_listesi.dart';
import 'package:posta/ekranlar/ileti_satiri.dart';
import 'package:posta/oturum.dart';
import 'package:posta/ortak/liste_filtresi.dart';
import 'package:posta/veri/durum.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/onyukleme.dart';

/// İstekleri kaydeder ve sahte ileti sayfası döndürür.
class SahteSunucu implements HttpClientAdapter {
  final istekler = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? govde, Future<void>? iptal) async {
    istekler.add(o);
    final filtre = o.queryParameters['filter'];
    final ogeler = [
      {'id': 'm1', 'subject': 'Okunmamış konu', 'from': 'Ayşe Yılmaz <ayse@ornek.com>', 'date': '2026-11-20T09:00:00Z', 'seen': false, 'has_attachments': true},
      if (filtre == null)
        {'id': 'm2', 'subject': 'Okunmuş konu', 'from': 'Ali Veli <ali@ornek.com>', 'date': '2026-11-19T09:00:00Z', 'seen': true, 'flagged': true},
    ];
    final v = {'items': ogeler, 'total': ogeler.length, 'page': 1, 'page_size': 50};
    return ResponseBody.fromString(
      jsonEncode(v),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _uygulama(Widget w) => MaterialApp(
  theme: temaKur(Brightness.light),
  home: Scaffold(body: w),
);

IletiSatiri _satir(IletiOzet m) => IletiSatiri(
  ileti: m,
  secili: false,
  acik: false,
  secimModu: false,
  copte: false,
  arsivde: false,
  dokun: () {},
  sec: () {},
  okundu: () {},
  yildiz: () {},
  arsivle: () {},
  sil: () {},
);

void main() {
  final sunucu = SahteSunucu();

  setUpAll(() async {
    Onyukleme.etkin = false; // istek sırasını denetleyen testler; önyükleme onbellek_test'te
    await initializeDateFormatting('tr_TR');
    Uyg.api.dio = Dio(BaseOptions(baseUrl: 'http://sahte.invalid', validateStatus: (_) => true))..httpClientAdapter = sunucu;
  });

  group('ileti satırı', () {
    testWidgets('okunmamış: nokta, sol çizgi, yarı kalın gönderen (600) ve konu (500)', (t) async {
      await t.pumpWidget(_uygulama(_satir(IletiOzet(id: 'a', kimden: 'Ayşe <ayse@ornek.com>', konu: 'Merhaba', okundu: false, ekVar: true))));
      expect(find.byKey(const ValueKey('okunmamis-nokta')), findsOneWidget);
      expect(find.byKey(const ValueKey('okunmamis-serit')), findsOneWidget);
      final ad = t.widget<Text>(find.text('Ayşe'));
      expect(ad.style!.fontWeight, FontWeight.w600);
      expect(t.widget<Text>(find.text('Merhaba')).style!.fontWeight, FontWeight.w600);
      expect(find.byIcon(Simge.ek), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Okunmamış')), findsOneWidget);
    });

    testWidgets('okunmuş: şerit yok, normal ağırlık, web soluklukları', (t) async {
      await t.pumpWidget(_uygulama(_satir(IletiOzet(id: 'b', kimden: 'Ali <ali@ornek.com>', konu: 'Rapor', okundu: true, yildizli: true))));
      expect(find.byKey(const ValueKey('okunmamis-nokta')), findsNothing);
      expect(find.byKey(const ValueKey('okunmamis-serit')), findsNothing);
      final r = Renkler.acik;
      final ad = t.widget<Text>(find.text('Ali'));
      expect(ad.style!.fontWeight, FontWeight.w400);
      // Web: gönderen foreground/90, konu foreground/80.
      expect(ad.style!.color, r.silik);
      expect(t.widget<Text>(find.text('Rapor')).style!.color, r.silik);
      expect(find.byIcon(Simge.yildizDolu), findsOneWidget);
    });

    testWidgets('web message-list yerleşimi: tarih 1. satırın sağında, ataç ve yıldız konu satırının SONUNDA', (t) async {
      t.view.physicalSize = const Size(520, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        _uygulama(
          _satir(IletiOzet(id: 'c', kimden: 'Ali <ali@ornek.com>', konu: 'Rapor', okundu: true, yildizli: true, ekVar: true, tarih: DateTime(2026, 11, 1))),
        ),
      );
      final satir = t.getRect(find.byType(IletiSatiri));
      final tarih = t.getRect(find.text(kisaZaman(DateTime(2026, 11, 1))));
      final konu = t.getRect(find.text('Rapor'));
      final yildiz = t.getRect(find.byIcon(Simge.yildizDolu));
      final atac = t.getRect(find.byIcon(Simge.ek));
      expect(satir.right - tarih.right, lessThan(16), reason: 'tarih sağ kenarda');
      expect(satir.right - yildiz.right, lessThan(16), reason: 'yıldız konu satırının sonunda');
      expect(yildiz.center.dy, closeTo(konu.center.dy, 3));
      expect(atac.center.dy, closeTo(konu.center.dy, 3));
      expect(atac.right, lessThanOrEqualTo(yildiz.left));
      expect(tarih.center.dy, lessThan(konu.top));
    });
  });

  group('süzgeç çubuğu', () {
    testWidgets('bölümler, okunmamış sayısı ve seçim', (t) async {
      ListeFiltresi? secilen;
      await t.pumpWidget(_uygulama(FiltreCubugu(secili: ListeFiltresi.tumu, degisti: (f) => secilen = f, sayilar: const {ListeFiltresi.okunmamis: 7})));
      for (final ad in ['Tümü', 'Okunmamış', 'Yıldızlı', 'Ekli']) {
        expect(find.text(ad), findsOneWidget);
      }
      expect(find.text('7'), findsNothing, reason: 'web gibi sekmede sayı yok');
      expect(find.byIcon(Simge.onay), findsNothing, reason: 'etkin bölüm dolu zeminle belirgin; onay simgesi yer kaplamaz (etiketler kesilmez)');
      await t.tap(find.byKey(const ValueKey('filtre-yildizli')));
      expect(secilen, ListeFiltresi.yildizli);
    });

    testWidgets('bant: açıklama ve Temizle', (t) async {
      var temizlendi = false;
      await t.pumpWidget(_uygulama(FiltreBandi(filtre: ListeFiltresi.okunmamis, temizle: () => temizlendi = true)));
      expect(find.text('Yalnızca okunmamış iletiler gösteriliyor'), findsOneWidget);
      await t.tap(find.text('Temizle'));
      expect(temizlendi, isTrue);
    });
  });

  testWidgets('liste: okunmamış süzgeci sunucuya filter=unread gönderir, bant görünür ve temizlenir', (t) async {
    PostaDurum.ben.klasorler = [Klasor(id: 'k1', ad: 'Projeler', okunmamis: 3, toplam: 2)];
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        home: IletiListesi(konum: const Konum.klasor('k1'), ac: (_) {}),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(sunucu.istekler.last.path, '/api/v1/mail/folders/k1/messages');
    expect(sunucu.istekler.last.queryParameters.containsKey('filter'), isFalse);
    expect(find.text('Projeler'), findsOneWidget);
    expect(find.byKey(const ValueKey('baslik-okunmamis')), findsOneWidget);
    expect(find.text('Okunmuş konu'), findsOneWidget);
    expect(find.byKey(const ValueKey('okunmamis-nokta')), findsOneWidget, reason: 'yalnızca okunmamış satırda nokta');

    await t.tap(find.byKey(const ValueKey('filtre-okunmamis')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(sunucu.istekler.last.queryParameters['filter'], 'unread');
    expect(find.textContaining('Yalnızca okunmamış iletiler gösteriliyor'), findsOneWidget);
    expect(find.text('Okunmuş konu'), findsNothing);

    await t.tap(find.text('Temizle'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(sunucu.istekler.last.queryParameters.containsKey('filter'), isFalse);
    expect(find.textContaining('Yalnızca okunmamış'), findsNothing);
    expect(find.text('Okunmuş konu'), findsOneWidget);
  });
}
