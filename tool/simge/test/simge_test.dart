// Tüm platform simgelerini açılış işaretinin son karesinden üretir:
//   cd tool/simge && flutter test
// iOS: tam kare opak zemin (köşeleri iOS yuvarlar). macOS: Big Sur ızgarasında yuvarlatılmış kare + gölge.
// Android: uyarlanabilir simge (mor zemin + şeffaf ön plan) ve eski cihazlar için yuvarlatılmış kare.
// Windows: çok boyutlu .ico (PNG gömülü).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const kok = '../../apps';

Future<Uint8List> _png(int boyut, void Function(Canvas c, double k) ciz) async {
  final kayit = ui.PictureRecorder();
  final c = Canvas(kayit);
  ciz(c, boyut / 1024);
  final img = await kayit.endRecording().toImage(boyut, boyut);
  final b = await img.toByteData(format: ui.ImageByteFormat.png);
  return b!.buffer.asUint8List();
}

/// Tam kare zemin + işaret (iOS, Android eski).
void _kare(Canvas c, double k, AcilisIsaret i, {double radius = 0}) {
  c.scale(k);
  const r = Rect.fromLTWH(0, 0, 1024, 1024);
  final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
  c.drawRRect(rr, Paint()..shader = isaretDegradesi(i).createShader(r));
  c.drawRRect(rr, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Colors.white.withValues(alpha: .18), Colors.white.withValues(alpha: 0)]).createShader(r));
  c.scale(1024 / 64);
  isaretCiz(c, i, zemin: false);
}

/// macOS: 1024 tuvalde 824'lük yuvarlatılmış kare, yumuşak gölge.
void _mac(Canvas c, double k, AcilisIsaret i) {
  c.scale(k);
  const r = Rect.fromLTWH(100, 100, 824, 824);
  final rr = RRect.fromRectAndRadius(r, const Radius.circular(185));
  c.drawRRect(rr.shift(const Offset(0, 10)), Paint()
    ..color = Colors.black.withValues(alpha: .28)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
  c.save();
  c.clipRRect(rr);
  c.drawRect(r, Paint()..shader = isaretDegradesi(i).createShader(r));
  c.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Colors.white.withValues(alpha: .18), Colors.white.withValues(alpha: 0)]).createShader(r));
  c.translate(100, 100);
  c.scale(824 / 64);
  isaretCiz(c, i, zemin: false);
  c.restore();
}

/// Android uyarlanabilir ön plan: içerik ortadaki güvenli alanda (~%60), şeffaf zemin.
void _onPlan(Canvas c, double k, AcilisIsaret i) {
  c.scale(k);
  c.translate(512, 512);
  c.scale(1024 / 108);
  c.translate(-32, -32);
  isaretCiz(c, i, zemin: false);
}

Uint8List _ico(List<(int, Uint8List)> pngler) {
  final b = BytesBuilder();
  final h = ByteData(6)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, pngler.length, Endian.little);
  b.add(h.buffer.asUint8List());
  var ofs = 6 + 16 * pngler.length;
  for (final (s, p) in pngler) {
    final e = ByteData(16)
      ..setUint8(0, s >= 256 ? 0 : s)
      ..setUint8(1, s >= 256 ? 0 : s)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, p.length, Endian.little)
      ..setUint32(12, ofs, Endian.little);
    b.add(e.buffer.asUint8List());
    ofs += p.length;
  }
  for (final (_, p) in pngler) {
    b.add(p);
  }
  return b.toBytes();
}

void main() {
  for (final (app, isaret) in [('posta', AcilisIsaret.posta), ('yonetim', AcilisIsaret.yonetim)]) {
    test('$app simgeleri', () async {
      final d = '$kok/$app';
      // iOS
      final ios = '$d/ios/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final f in Directory(ios).listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) {
        final m = RegExp(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$').firstMatch(f.path)!;
        final px = (double.parse(m[1]!) * int.parse(m[2]!)).round();
        f.writeAsBytesSync(await _png(px, (c, k) => _kare(c, k, isaret)));
      }
      // macOS
      for (final s in [16, 32, 64, 128, 256, 512, 1024]) {
        File('$d/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$s.png').writeAsBytesSync(await _png(s, (c, k) => _mac(c, k, isaret)));
      }
      // Android
      const yog = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      for (final e in yog.entries) {
        File('$d/android/app/src/main/res/mipmap-${e.key}/ic_launcher.png').writeAsBytesSync(await _png(e.value, (c, k) => _kare(c, k, isaret, radius: 230)));
        final on = e.value * 108 ~/ 48;
        Directory('$d/android/app/src/main/res/drawable-${e.key}').createSync(recursive: true);
        File('$d/android/app/src/main/res/drawable-${e.key}/ic_launcher_foreground.png').writeAsBytesSync(await _png(on, (c, k) => _onPlan(c, k, isaret)));
      }
      Directory('$d/android/app/src/main/res/mipmap-anydpi-v26').createSync(recursive: true);
      File('$d/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
''');
      File('$d/android/app/src/main/res/values/ic_launcher_background.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">${isaret == AcilisIsaret.posta ? "#5443D2" : "#1D2233"}</color>
</resources>
''');
      // Windows
      final pngler = <(int, Uint8List)>[];
      for (final s in [16, 24, 32, 48, 64, 128, 256]) {
        pngler.add((s, await _png(s, (c, k) => _kare(c, k, isaret, radius: 200))));
      }
      File('$d/windows/runner/resources/app_icon.ico').writeAsBytesSync(_ico(pngler));
      // Mağaza / belgeler için büyük logo
      Directory('$d/assets').createSync(recursive: true);
      File('$d/assets/simge-1024.png').writeAsBytesSync(await _png(1024, (c, k) => _kare(c, k, isaret)));
    });
  }
}
