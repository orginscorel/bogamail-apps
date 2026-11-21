// BogaMail bildirim sesleri: yeni posta ve sohbet için ayrı, kendine özgü iki ses.
// - iPhone/iPad/Mac: WAV'lar Runner'a gömülüdür; sunucu APNs'te "sound": "bogamail_posta.wav" / "bogamail_sohbet.wav"
//   gönderir, sistem çalar.
// - Android: res/raw altındadır; "posta_v2" / "sohbet_v2" kanalları bu sesle açılır (kanal sesi sonradan
//   değiştirilemediği için eski "yeni_posta" kanalı silinir).
// - Windows: toast sessiz gösterilir, ses runner'daki "boga/ses" kanalıyla (PlaySound, gömülü WAVE kaynağı) çalınır.
// Ayarlar › Bildirimler'deki "Sesi dinle" düğmeleri de aynı "boga/ses" kanalını kullanır.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum BildirimSesi {
  posta('posta_v2', 'Yeni e-postalar', 'Gelen Kutusu\'na yeni e-posta geldiğinde'),
  sohbet('sohbet_v2', 'Sohbet iletileri', 'Kurum içi sohbette yeni ileti geldiğinde');

  const BildirimSesi(this.kanalId, this.kanalAdi, this.kanalAciklamasi);

  /// Android bildirim kanalı.
  final String kanalId;
  final String kanalAdi;
  final String kanalAciklamasi;

  /// Android res/raw kaynak adı (uzantısız).
  String get kaynak => 'bogamail_$name';

  /// iOS/macOS paketindeki dosya (APNs "sound" alanıyla aynı).
  String get dosya => '$kaynak.wav';

  /// Bildirim yüküne göre ses: sohbet odası yükleri `sohbet:` ile başlar.
  static BildirimSesi yuktan(String yuk) => yuk.startsWith('sohbet:') ? sohbet : posta;
}

/// Eski, sesi değiştirilemeyen Android kanalları (açılışta silinir).
const eskiKanallar = ['yeni_posta'];

class SesCalar {
  SesCalar._();
  static const kanal = MethodChannel('boga/ses');

  /// Bu platformda "Sesi dinle" var mı.
  static bool get destekli => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

  /// Sesi çalar; çalınamadıysa false.
  static Future<bool> cal(BildirimSesi s) async {
    try {
      return await kanal.invokeMethod<bool>('cal', s.name) ?? false;
    } catch (_) {
      return false;
    }
  }
}
