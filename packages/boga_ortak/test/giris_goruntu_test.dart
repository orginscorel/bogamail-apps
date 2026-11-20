// Elle çalıştırılır: giriş ekranının görüntüsünü üretir (GORUNTU_DIZIN ortam değişkeni verilirse).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _font(String aile, List<String> dosyalar) async {
  final l = FontLoader(aile);
  for (final d in dosyalar) {
    final b = File(d).readAsBytesSync();
    l.addFont(Future.value(ByteData.view(b.buffer)));
  }
  await l.load();
}

void main() {
  final dizin = Platform.environment['GORUNTU_DIZIN'];
  setUpAll(() async {
    if (dizin == null) return; // fontlar yalnız görüntü üretirken (yerel yollar) yüklenir
    await _font('packages/boga_ortak/Poppins', ['assets/fonts/Poppins-Regular.ttf', 'assets/fonts/Poppins-Medium.ttf', 'assets/fonts/Poppins-SemiBold.ttf', 'assets/fonts/Poppins-Bold.ttf']);
    await _font('packages/boga_ortak/Jakarta', ['assets/fonts/PlusJakartaSans.ttf']);
    await _font('MaterialIcons', ['${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });
  for (final (k, isaret) in [(Kimlik.posta, AcilisIsaret.posta), (Kimlik.yonetim, AcilisIsaret.yonetim)]) {
    for (final (ad, boyut) in [('telefon', const Size(390, 844)), ('genis', const Size(1280, 800))]) {
      testWidgets('giriş ${k.name} $ad', (t) async {
        kimlikAyarla(k);
        t.view.physicalSize = boyut * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        final api = BogaApi(uygulama: k.name, csrfCerezi: 'x');
        final anahtar = GlobalKey();
        await t.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaKur(Brightness.light),
          home: RepaintBoundary(
            key: anahtar,
            child: GirisEkrani(
              api: api,
              baslik: k == Kimlik.posta ? 'BogaMail' : 'BogaMail Yönetim',
              aciklama: k == Kimlik.posta ? 'Kurumsal e-postanız, sohbetiniz ve takviminiz.' : 'Bogahost posta platformu yönetim paneli.',
              girisYolu: '/x',
              isaret: isaret,
              kaydetSecenegi: k == Kimlik.posta,
              girisYapildi: (_) async {},
            ),
          ),
        ));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Hoş geldiniz'), findsOneWidget);
        if (dizin != null) {
          final ro = anahtar.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await t.runAsync(() => ro.toImage(pixelRatio: 1));
          final b = await t.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
          File('$dizin/giris-${k.name}-$ad.png').writeAsBytesSync(b!.buffer.asUint8List());
        }
      });
    }
  }
}
