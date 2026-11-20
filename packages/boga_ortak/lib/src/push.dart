import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Apple anlık bildirimleri (APNs). Yerel taraf uygulamanın AppDelegate.swift dosyasındaki BogaPush sınıfıdır
/// ("boga/push" kanalı). Sunucu yeni postayı / alarmı doğrudan Apple'a gönderir; uygulama kapalıyken de gelir.
class Push {
  Push._();
  static const _k = MethodChannel('boga/push');
  static final _acildi = StreamController<Map<String, dynamic>>.broadcast();
  static final _geldi = StreamController<Map<String, dynamic>>.broadcast();
  static bool _hazir = false;

  /// Bu platformda anlık bildirim var mı (iPhone, iPad, Mac).
  static bool get destekli => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// Bildirime dokunulunca (yük: sunucunun gönderdiği alanlar, ör. message_id).
  static Stream<Map<String, dynamic>> get acildi => _acildi.stream;

  /// Uygulama öndeyken bildirim geldi.
  static Stream<Map<String, dynamic>> get geldi => _geldi.stream;

  static void _baslat() {
    if (_hazir || !destekli) return;
    _hazir = true;
    _k.setMethodCallHandler((c) async {
      final v = c.arguments is Map ? Map<String, dynamic>.from(c.arguments as Map) : <String, dynamic>{};
      if (c.method == 'acildi') {
        await _k.invokeMethod('baslangic'); // tüketildi: soğuk açılışta tekrar verilmesin
        _acildi.add(v);
      } else if (c.method == 'geldi') {
        _geldi.add(v);
      } else if (c.method == 'gosterilsinMi') {
        // Uygulama öndeyken gelen bildirim: o oda/ileti zaten açıksa banner gösterilmez (yerel taraf 300 ms bekler).
        try {
          return gosterilsinMi(v);
        } catch (_) {
          return true;
        }
      }
      return null;
    });
  }

  /// Öndeyken gelen bildirim gösterilsin mi (uygulama, açık oda/iletiyle karşılaştırır). Varsayılan: göster.
  static bool Function(Map<String, dynamic> veri) gosterilsinMi = (_) => true;

  /// Bildirim izni: 'verildi' | 'reddedildi' | 'sorulmadi' (desteklenmiyorsa null).
  static Future<String?> izin() async {
    if (!destekli) return null;
    _baslat();
    try {
      return await _k.invokeMethod<String>('izin');
    } catch (_) {
      return null;
    }
  }

  /// Soğuk açılışta uygulamayı açan bildirim (bir kez döner).
  static Future<Map<String, dynamic>?> baslangic() async {
    if (!destekli) return null;
    _baslat();
    try {
      final v = await _k.invokeMethod('baslangic');
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  /// İzin ister ve cihaz anahtarını döndürür (izin yoksa null).
  static Future<String?> anahtar() async {
    if (!destekli) return null;
    _baslat();
    try {
      return await _k.invokeMethod<String>('kaydol');
    } catch (_) {
      return null;
    }
  }

  static Future<void> rozet(int n) async {
    if (!destekli) return;
    try {
      await _k.invokeMethod('rozet', n);
    } catch (_) {}
  }

  static Future<String> _cihazAdi() async {
    try {
      final d = DeviceInfoPlugin();
      if (Platform.isIOS) return (await d.iosInfo).name;
      if (Platform.isMacOS) return (await d.macOsInfo).computerName;
    } catch (_) {}
    return '';
  }

  /// Cihazı sunucuya kaydeder. [yol]: posta → /api/v1/mail/app/push, yönetim → /api/v1/app/push.
  /// Dönüş: kayıt yapıldıysa true. Sunucuda kapalıysa ya da izin verilmediyse false.
  static Future<bool> kaydet(BogaApi api, {required String yol, required String konu}) async {
    final t = await anahtar();
    if (t == null) return false;
    try {
      await api.post(yol, {'platform': Platform.isIOS ? 'ios' : 'macos', 'token': t, 'topic': konu, 'sandbox': kDebugMode, 'device_name': await _cihazAdi()});
      final p = await SharedPreferences.getInstance();
      await p.setString('${api.uygulama}.push', t);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Çıkışta bu cihazın kaydını siler (başka hesap bildirimlerini almasın).
  static Future<void> sil(BogaApi api, {required String yol}) async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString('${api.uygulama}.push');
    if (t == null) return;
    try {
      await api.post('$yol/remove', {'token': t});
    } catch (_) {}
    await p.remove('${api.uygulama}.push');
  }
}
