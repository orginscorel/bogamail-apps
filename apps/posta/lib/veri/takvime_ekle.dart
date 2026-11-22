// Bir görevi cihazın takvimine / hatırlatıcısına ekleme (tek seferlik kopya; eşitlenmez).
// - Android: takvim uygulamasının "yeni etkinlik" ekranı (Intent ACTION_INSERT, CalendarContract), MainActivity
//   "boga/takvim" kanalı. Hatırlatma süresini takvim uygulaması belirler (varsayılan bildirim).
// - Windows: VEVENT + VALARM (15 dk önce) içeren .ics dosyası varsayılan uygulamayla (Outlook / Takvim) açılır.
// - iPhone/iPad/Mac: kopya yerine CalDAV ile Apple Hatırlatıcılar eşitlemesi önerilir (çift kayıt olmasın).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'takvim_servisi.dart';

enum TakvimeEkleYolu { android, ics, apple, yok }

class TakvimeEkle {
  TakvimeEkle._();
  static const kanal = MethodChannel('boga/takvim');

  @visibleForTesting
  static TakvimeEkleYolu? yolZorla;

  static TakvimeEkleYolu get yol {
    final z = yolZorla;
    if (z != null) return z;
    if (kIsWeb) return TakvimeEkleYolu.yok;
    if (Platform.isAndroid) return TakvimeEkleYolu.android;
    if (Platform.isWindows) return TakvimeEkleYolu.ics;
    if (Platform.isIOS || Platform.isMacOS) return TakvimeEkleYolu.apple;
    return TakvimeEkleYolu.yok;
  }

  /// .ics dosyası açar (testlerde değiştirilir).
  @visibleForTesting
  static Future<bool> Function(String yol) dosyaAc = (y) async => (await OpenFilex.open(y)).type == ResultType.done;

  /// Görevi ekler; Android'de takvim uygulaması yoksa / açılamazsa false.
  static Future<bool> ekle(Gorev g) async {
    final b = g.bitis;
    if (b == null) return false;
    switch (yol) {
      case TakvimeEkleYolu.android:
        try {
          return await kanal.invokeMethod<bool>('ekle', {
                'baslik': g.baslik,
                'notlar': g.notlar,
                'baslangic': b.millisecondsSinceEpoch,
                'bitis': b.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
              }) ??
              false;
        } catch (_) {
          return false;
        }
      case TakvimeEkleYolu.ics:
        try {
          final d = await getTemporaryDirectory();
          final f = File('${d.path}${Platform.pathSeparator}BogaMail-gorev-${g.id}.ics');
          await f.writeAsString(gorevIcs(g, DateTime.now()), flush: true);
          return await dosyaAc(f.path);
        } catch (_) {
          return false;
        }
      case TakvimeEkleYolu.apple:
      case TakvimeEkleYolu.yok:
        return false;
    }
  }
}

String _utc(DateTime t) {
  final u = t.toUtc();
  String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  return '${p(u.year, 4)}${p(u.month)}${p(u.day)}T${p(u.hour)}${p(u.minute)}${p(u.second)}Z';
}

String _metin(String s) => s.replaceAll('\\', '\\\\').replaceAll(';', '\\;').replaceAll(',', '\\,').replaceAll('\r\n', '\\n').replaceAll('\n', '\\n');

/// RFC 5545 satır katlama: 75 baytı aşan satır, UTF-8 karakter bölünmeden boşlukla devam eder.
String _katla(String satir) {
  final b = utf8.encode(satir);
  if (b.length <= 75) return satir;
  final out = StringBuffer();
  var uzunluk = 0;
  var sinir = 75;
  for (final r in satir.runes) {
    final c = String.fromCharCode(r);
    final n = utf8.encode(c).length;
    if (uzunluk + n > sinir) {
      out.write('\r\n ');
      uzunluk = 0;
      sinir = 74;
    }
    out.write(c);
    uzunluk += n;
  }
  return out.toString();
}

/// Görevin takvim kaydı: son tarihte 30 dakikalık etkinlik, 15 dakika önce uyarı. Outlook ve Windows Takvim VTODO'yu
/// içe almadığı için VEVENT.
String gorevIcs(Gorev g, DateTime simdi) {
  final b = g.bitis!;
  final notlar = [if (g.notlar.trim().isNotEmpty) g.notlar.trim(), 'BogaMail görevi'].join('\n\n');
  final baslik = g.baslik.trim().isEmpty ? 'Görev' : g.baslik.trim();
  final satirlar = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//BogaMail//Posta//TR',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:gorev-${g.id}@bogamail',
    'DTSTAMP:${_utc(simdi)}',
    'DTSTART:${_utc(b)}',
    'DTEND:${_utc(b.add(const Duration(minutes: 30)))}',
    'SUMMARY:${_metin(baslik)}',
    'DESCRIPTION:${_metin(notlar)}',
    'BEGIN:VALARM',
    'ACTION:DISPLAY',
    'DESCRIPTION:${_metin(baslik)}',
    'TRIGGER:-PT15M',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${satirlar.map(_katla).join('\r\n')}\r\n';
}
