// Bildirim izni ve yerel bildirimler.
// - iPhone/iPad/Mac: alarm bildirimleri sunucudan APNs ile gelir (boga_ortak Push). İzin durumu AppDelegate.swift'teki
//   BogaPush'un "izin" yöntemiyle okunur; izin istemek Push.kaydet ile olur (aynı anda cihaz da kaydedilir).
// - Android / Windows / Linux: APNs yok; uygulama alarmları 60 sn'de bir yoklar ve yerel bildirim gösterir
//   (Android'de ön plan hizmetinin içinden, bkz. arkaplan.dart).
// Platform işlemleri [BildirimPlatformu] arkasındadır; testler [Bildirim.platform]'u sahtesiyle değiştirir.

import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../oturum.dart';

enum IzinDurumu {
  /// Bildirimler açık.
  verildi,

  /// Kullanıcı reddetti ya da sistem ayarlarından kapattı: yalnızca ayarlardan açılabilir.
  reddedildi,

  /// Henüz sorulmadı: istendiğinde sistem izin penceresi çıkar.
  sorulmadi,

  /// Bu platformda izin kavramı yok (Windows, Linux) ya da bildirim desteklenmiyor.
  gerekmiyor,
}

/// Yerel bildirim kanalı (Android) ve uygulama kimliği (Windows) — ön plan hizmeti de aynılarını kullanır.
const alarmKanali = AndroidNotificationDetails(
  'alarmlar',
  'Alarmlar',
  channelDescription: 'Kritik alarmlar, kuyruk birikmesi ve güvenlik olayları',
  importance: Importance.high,
  priority: Priority.high,
  category: AndroidNotificationCategory.alarm,
  color: Color(0xFF5443D2),
);
const _windowsAyari = WindowsInitializationSettings(
  appName: 'BogaMail Yönetim',
  appUserModelId: 'Bogahost.BogaMail.Yonetim',
  guid: '3c1f7a64-52d9-4e0b-8a3f-9d2e6b71c4f5',
);
const bildirimBaslatmaAyari = InitializationSettings(
  android: AndroidInitializationSettings('ic_bildirim'),
  windows: _windowsAyari,
  linux: LinuxInitializationSettings(defaultActionName: 'Aç'),
);

/// Bildirime dokunulunca gelen yük: `alarm:<rule_id>`.
const alarmYukOneki = 'alarm:';

class BildirimPlatformu {
  static final _p = FlutterLocalNotificationsPlugin();
  static const _apple = MethodChannel('boga/push');
  static final _acildi = StreamController<String>.broadcast();
  static bool _hazir = false;
  static const _soruldu = 'yonetim.bildirim.soruldu';

  bool get android => !kIsWeb && Platform.isAndroid;
  bool get apple => !kIsWeb && (Platform.isIOS || Platform.isMacOS);
  bool get masaustu => !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// Yerel bildirimi uygulamanın kendisi gösterir mi (APNs olmayan platformlar).
  bool get yerel => android || masaustu;

  Stream<String> get acildi => _acildi.stream;

  Future<void> hazirla() async {
    if (_hazir || !yerel) return;
    try {
      await _p.initialize(
        settings: bildirimBaslatmaAyari,
        onDidReceiveNotificationResponse: (r) {
          final y = r.payload;
          if (y != null && y.isNotEmpty) _acildi.add(y);
        },
      );
      _hazir = true;
    } catch (_) {}
  }

  /// Soğuk açılışta uygulamayı açan bildirimin yükü (bir kez).
  Future<String?> baslangic() async {
    if (!yerel) return null;
    await hazirla();
    try {
      final d = await _p.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) return d!.notificationResponse?.payload;
    } catch (_) {}
    return null;
  }

  AndroidFlutterLocalNotificationsPlugin? get _a => _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> _sorulduMu() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_soruldu) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _sorulduIsaretle() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_soruldu, true);
    } catch (_) {}
  }

  Future<IzinDurumu> izinDurumu() async {
    if (apple) {
      try {
        final v = await _apple.invokeMethod<String>('izin');
        return switch (v) {
          'verildi' => IzinDurumu.verildi,
          'reddedildi' => IzinDurumu.reddedildi,
          _ => IzinDurumu.sorulmadi,
        };
      } catch (_) {
        return IzinDurumu.gerekmiyor;
      }
    }
    if (android) {
      await hazirla();
      try {
        if (await _a?.areNotificationsEnabled() ?? false) return IzinDurumu.verildi;
      } catch (_) {
        return IzinDurumu.gerekmiyor;
      }
      return await _sorulduMu() ? IzinDurumu.reddedildi : IzinDurumu.sorulmadi;
    }
    return IzinDurumu.gerekmiyor;
  }

  /// Sistem izin penceresini açar (Apple'da cihaz APNs'e de kaydedilir). Dönüş: izin verildi mi.
  Future<bool> izinIste() async {
    await _sorulduIsaretle();
    if (apple) return Push.kaydet(Uyg.api, yol: Uyg.pushYolu, konu: Uyg.pushKonu);
    if (android) {
      await hazirla();
      try {
        return await _a?.requestNotificationsPermission() ?? false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Uygulamanın sistem bildirim ayarlarını açar.
  Future<void> ayarlariAc() async {
    try {
      if (!kIsWeb && Platform.isMacOS) {
        await launchUrl(Uri.parse('x-apple.systempreferences:com.apple.Notifications-Settings.extension'));
      } else if (!kIsWeb && Platform.isWindows) {
        await launchUrl(Uri.parse('ms-settings:notifications'));
      } else {
        await AppSettings.openAppSettings(type: AppSettingsType.notification);
      }
    } catch (_) {}
  }

  /// Android: uygulama pil iyileştirmesinden muaf mı (değilse sistem arka plandaki uygulamayı uyutabilir).
  Future<bool> pilMuaf() async {
    if (!android) return true;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return true;
    }
  }

  /// Android: "pil iyileştirmesini yoksay" sistem penceresini açar.
  Future<bool> pilMuafiyetiIste() async {
    if (!android) return true;
    try {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {
      return false;
    }
  }

  Future<void> goster({required int id, required String baslik, required String metin, required String yuk}) async {
    await hazirla();
    if (!_hazir) return;
    try {
      await _p.show(
        id: id,
        title: baslik,
        body: metin,
        notificationDetails: const NotificationDetails(android: alarmKanali, windows: WindowsNotificationDetails()),
        payload: yuk,
      );
    } catch (_) {}
  }
}

class Bildirim {
  Bildirim._();

  /// Testlerde sahtesiyle değiştirilir.
  static BildirimPlatformu platform = BildirimPlatformu();

  /// Son okunan izin durumu (bant ve ayarlar dinler).
  static final durum = ValueNotifier<IzinDurumu?>(null);

  /// Android: pil iyileştirmesinden muaf mı (diğer platformlarda hep true).
  static final pilMuaf = ValueNotifier<bool>(true);

  static Future<IzinDurumu> yenile() async {
    final d = await platform.izinDurumu();
    durum.value = d;
    pilMuaf.value = await platform.pilMuaf();
    return d;
  }
}
