// Uygulamanın "uyumaması": alarm bildirimleri her zaman gelsin.
// - Android: düşük önemli kalıcı "BogaMail Yönetim bağlı" bildirimiyle ön plan hizmeti (flutter_foreground_task,
//   tür remoteMessaging). Hizmet kendi isolate'inde 60 sn'de bir alarmları yoklar; cihaz açılınca ve uygulama
//   güncellenince kendiliğinden yeniden başlar. Firebase yok.
// - Windows: oturum açılınca başlat (HKCU\...\Run, "--arkaplan" ile tepside gizli açılır) + sistem tepsisi; pencere
//   kapatılınca uygulama tepside çalışmayı sürdürür, alarmlar Windows bildirimi (toast) olarak gelir.
// - macOS: pencere kapatılınca uygulama çalışmayı sürdürür (AppDelegate.swift) + girişte başlat (SMAppService,
//   "boga/arkaplan" kanalı). Alarmlar APNs ile gelir.
// - Uygulama açıkken (Android'de hizmet kapalıysa, Windows, Linux) yoklamayı [UygulamaIzleyici] yapar.

import 'dart:async';
import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32_registry/win32_registry.dart';
import 'package:window_manager/window_manager.dart';

import '../oturum.dart';
import 'alarm_izleyici.dart';
import 'bildirim.dart';

const _arkaplanAnahtari = 'yonetim.arkaplan';
const _giristeAnahtari = 'yonetim.giriste_baslat';
const _baglantiBasligi = 'BogaMail Yönetim bağlı';
const _runAdi = 'BogaMail Yönetim';

/// Kalıcı bildirimin metni (etkin alarm sayısına göre).
String baglantiMetni(int etkinAlarm) => etkinAlarm == 0 ? 'Etkin alarm yok — yeni alarmlar anında bildirilir' : '$etkinAlarm etkin alarm';

/// Platform işlemleri (testlerde sahtesiyle değiştirilir).
class ArkaplanPlatformu {
  bool get android => !kIsWeb && Platform.isAndroid;
  bool get windows => !kIsWeb && Platform.isWindows;
  bool get macos => !kIsWeb && Platform.isMacOS;

  /// "Oturum açıldığında başlat" bu platformda var mı.
  bool get giristeBaslatVar => windows || macos;

  static const _mac = MethodChannel('boga/arkaplan');

  // ---- Android ön plan hizmeti ----

  void _hizmetiHazirla() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'baglanti',
        channelName: 'Bağlantı durumu',
        channelDescription: 'Uygulamanın arka planda bağlı olduğunu gösteren sessiz bildirim',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(alarmYoklamaAraligi.inMilliseconds),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> hizmetCalisiyor() async {
    if (!android) return false;
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  Future<void> hizmetiBaslat() async {
    if (!android) return;
    _hizmetiHazirla();
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceId: 4108,
        serviceTypes: const [ForegroundServiceTypes.remoteMessaging],
        notificationTitle: _baglantiBasligi,
        notificationText: baglantiMetni(0),
        notificationIcon: const NotificationIcon(metaDataName: 'com.bogahost.yonetim.BILDIRIM_SIMGESI'),
        callback: arkaplanGorevi,
      );
    } catch (_) {}
  }

  Future<void> hizmetiDurdur() async {
    if (!android) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  // ---- Oturum açıldığında başlat ----

  Future<bool> giristeBaslatAcik() async {
    try {
      if (windows) {
        final k = CURRENT_USER.open(r'Software\Microsoft\Windows\CurrentVersion\Run');
        try {
          return k.getString(_runAdi) != null;
        } finally {
          k.close();
        }
      }
      if (macos) return await _mac.invokeMethod<bool>('giristeBaslat') ?? false;
    } catch (_) {}
    return false;
  }

  Future<void> giristeBaslatAyarla(bool acik) async {
    try {
      if (windows) {
        final k = CURRENT_USER.create(r'Software\Microsoft\Windows\CurrentVersion\Run');
        try {
          if (acik) {
            k.setValue(_runAdi, RegistryValue.string('"${Platform.resolvedExecutable}" --arkaplan'));
          } else if (k.getString(_runAdi) != null) {
            k.removeValue(_runAdi);
          }
        } finally {
          k.close();
        }
      } else if (macos) {
        await _mac.invokeMethod('giristeBaslatAyarla', acik);
      }
    } catch (_) {}
  }

  // ---- Windows sistem tepsisi ----

  _Tepsi? _tepsi;

  Future<void> tepsiyiKur({required bool gizliBasla}) async {
    if (!windows || _tepsi != null) return;
    try {
      final t = _Tepsi(this);
      _tepsi = t;
      await windowManager.ensureInitialized();
      // Kapat düğmesi uygulamayı kapatmaz: pencere gizlenir, alarmlar tepsiden bildirilir.
      await windowManager.setPreventClose(true);
      windowManager.addListener(t);
      trayManager.addListener(t);
      await trayManager.setIcon('assets/tepsi.ico');
      await trayManager.setToolTip(_baglantiBasligi);
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'ac', label: 'BogaMail Yönetim\'i aç'),
            MenuItem.separator(),
            MenuItem(key: 'cikis', label: 'Çıkış'),
          ],
        ),
      );
      if (gizliBasla) await windowManager.hide();
    } catch (_) {}
  }

  void pencereyiGoster() {
    if (!windows) return;
    () async {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    }();
  }

  void tepsiMetni(String m) {
    if (_tepsi == null) return;
    trayManager.setToolTip('$_baglantiBasligi — $m').catchError((_) {});
  }

  Future<void> _cik() async {
    try {
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }
}

class _Tepsi with TrayListener, WindowListener {
  _Tepsi(this.p);
  final ArkaplanPlatformu p;

  @override
  void onWindowClose() {
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => p.pencereyiGoster();

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'ac') p.pencereyiGoster();
    if (menuItem.key == 'cikis') p._cik();
  }
}

/// Arka plan davranışının uygulama tarafı.
class Arkaplan {
  Arkaplan._();

  /// Testlerde sahtesiyle değiştirilir.
  static ArkaplanPlatformu platform = ArkaplanPlatformu();

  /// Android: sürekli bağlı kal (kalıcı bildirimli ön plan hizmeti). Varsayılan açık.
  static final surekliBagli = ValueNotifier<bool>(true);

  /// Windows / macOS: oturum açıldığında başlat. Varsayılan açık.
  static final giristeBaslat = ValueNotifier<bool>(true);

  /// Uygulama "--arkaplan" ile (oturum açılışında) başlatıldı mı.
  static bool gizliBasla = false;

  /// main(): pencere / tepsi kurulumu (giriş gerektirmez).
  static Future<void> uygulamaAcildi(List<String> args) async {
    gizliBasla = args.contains('--arkaplan');
    try {
      final p = await SharedPreferences.getInstance();
      surekliBagli.value = p.getBool(_arkaplanAnahtari) ?? true;
      giristeBaslat.value = p.getBool(_giristeAnahtari) ?? true;
    } catch (_) {}
    if (platform.android) FlutterForegroundTask.initCommunicationPort();
    await platform.tepsiyiKur(gizliBasla: gizliBasla);
  }

  /// Giriş yapıldıktan sonra (Kabuk açılınca): hizmeti başlat, "girişte başlat" varsayılanını uygula.
  static Future<void> oturumAcildi() async {
    if (platform.android && surekliBagli.value) await platform.hizmetiBaslat();
    if (platform.giristeBaslatVar) {
      // Kullanıcı kapatmadıysa (varsayılan açık) her açılışta kaydı tazele: exe yolu değişmiş olabilir.
      if (giristeBaslat.value) await platform.giristeBaslatAyarla(true);
    }
  }

  /// Çıkışta: hizmet durur (oturum yokken yoklayacak bir şey yok).
  static Future<void> oturumKapandi() async {
    await platform.hizmetiDurdur();
    await AlarmIzleyici.sifirla();
  }

  static Future<void> surekliBagliAyarla(bool v) async {
    surekliBagli.value = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(_arkaplanAnahtari, v);
    } catch (_) {}
    if (v) {
      await platform.hizmetiBaslat();
    } else {
      await platform.hizmetiDurdur();
    }
  }

  static Future<void> giristeBaslatAyarla(bool v) async {
    giristeBaslat.value = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(_giristeAnahtari, v);
    } catch (_) {}
    await platform.giristeBaslatAyarla(v);
  }

  /// Uygulama içi yoklamayı bu platformda uygulama mı yapar (Android'de hizmet açıksa hizmet yapar; Apple'da APNs).
  static Future<bool> uygulamaYoklar() async {
    if (!Bildirim.platform.yerel) return false;
    if (platform.android) return !await platform.hizmetCalisiyor();
    return true;
  }
}

/// Uygulama açıkken alarm yoklaması (Windows, Linux; Android'de hizmet kapalıysa).
class UygulamaIzleyici {
  UygulamaIzleyici({AlarmIzleyici? izleyici}) : _izleyici = izleyici ?? AlarmIzleyici(() => Uyg.api.get('/api/v1/alerts/active'));

  final AlarmIzleyici _izleyici;
  Timer? _sayac;

  void baslat() {
    _sayac?.cancel();
    _sayac = Timer.periodic(alarmYoklamaAraligi, (_) => yokla());
    yokla();
  }

  Future<void> yokla() async {
    if (!await Arkaplan.uygulamaYoklar()) return;
    try {
      final y = await _izleyici.yokla();
      for (final a in y.yeni) {
        await Bildirim.platform.goster(id: a.bildirimId, baslik: a.bildirimBasligi, metin: a.bildirimMetni, yuk: '$alarmYukOneki${a.kuralId}');
      }
      Arkaplan.platform.tepsiMetni(baglantiMetni(y.etkin.length));
    } catch (_) {}
  }

  void durdur() {
    _sayac?.cancel();
    _sayac = null;
  }
}

// ---------------- Android ön plan hizmeti (ayrı isolate) ----------------

@pragma('vm:entry-point')
void arkaplanGorevi() {
  FlutterForegroundTask.setTaskHandler(_AlarmGorevi());
}

class _AlarmGorevi extends TaskHandler {
  AlarmIzleyici? _izleyici;
  final _bildirim = FlutterLocalNotificationsPlugin();
  bool _calisiyor = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    final api = BogaApi(uygulama: 'yonetim', csrfCerezi: 'bm_csrf');
    await api.baslat();
    _izleyici = AlarmIzleyici(() => api.get('/api/v1/alerts/active'));
    try {
      await _bildirim.initialize(settings: bildirimBaslatmaAyari);
    } catch (_) {}
    await _yokla();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => _yokla();

  Future<void> _yokla() async {
    final iz = _izleyici;
    if (iz == null || _calisiyor) return;
    _calisiyor = true;
    try {
      final y = await iz.yokla();
      for (final a in y.yeni) {
        await _bildirim.show(
          id: a.bildirimId,
          title: a.bildirimBasligi,
          body: a.bildirimMetni,
          notificationDetails: const NotificationDetails(android: alarmKanali),
          payload: '$alarmYukOneki${a.kuralId}',
        );
      }
      await FlutterForegroundTask.updateService(notificationTitle: _baglantiBasligi, notificationText: baglantiMetni(y.etkin.length));
    } on ApiHata catch (e) {
      if (e.durum == 401) {
        // Oturum kapanmış: yoklayacak bir şey yok, kalıcı bildirim kalksın.
        await FlutterForegroundTask.stopService();
      } else {
        await FlutterForegroundTask.updateService(notificationTitle: _baglantiBasligi, notificationText: 'Sunucuya ulaşılamıyor, yeniden denenecek');
      }
    } catch (_) {
      await FlutterForegroundTask.updateService(notificationTitle: _baglantiBasligi, notificationText: 'Sunucuya ulaşılamıyor, yeniden denenecek');
    } finally {
      _calisiyor = false;
    }
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _izleyici = null;
  }
}
