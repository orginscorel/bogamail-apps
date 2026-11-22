// Uygulamanın "uyumaması": yeni posta ve sohbet bildirimleri her zaman gelsin (yönetim uygulamasıyla aynı yaklaşım).
// - Android: düşük önemli kalıcı "BogaMail bağlı" bildirimiyle ön plan hizmeti (flutter_foreground_task, tür
//   remoteMessaging). Hizmet kendi isolate'inde canlı akışı (GET /api/v1/mail/stream, SSE) tutar; sunucu cihazdaki
//   diğer açık hesapların yeni postasını aynı akışta "unified_new" olarak gönderir, yani tüm hesaplar tek bağlantıyla
//   izlenir. Yeni posta / sohbet iletisi yüksek önemli (üstten açılan) bildirim olarak gösterilir. Cihaz açılınca ve
//   uygulama güncellenince hizmet kendiliğinden yeniden başlar. Firebase yok. WorkManager 15 dk denetimi yedek kalır.
// - Windows: oturum açılınca başlat (HKCU\...\Run, "--arkaplan" ile tepside gizli açılır) + sistem tepsisi; pencere
//   kapatılınca uygulama tepside çalışmayı sürdürür, yeni posta Windows bildirimi (toast) olarak gelir.
// - macOS: pencere kapatılınca uygulama çalışmayı sürdürür (AppDelegate.swift) + girişte başlat (SMAppService,
//   "boga/arkaplan" kanalı). Bildirimler APNs ile gelir.
// İçerik (konu, gönderen) yalnız bildirimde görünür; hiçbir yere yazılmaz.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32_registry/win32_registry.dart';
import 'package:window_manager/window_manager.dart';

import 'bildirim.dart';
import 'yardimci.dart';

const _arkaplanAnahtari = 'posta.arkaplan';
const _giristeAnahtari = 'posta.giriste_baslat';
const baglantiBasligi = 'BogaMail bağlı';
const _runAdi = 'BogaMail';

/// Kalıcı bildirimin metinleri.
const baglantiMetniBagli = 'Yeni e-postalar anında bildirilir';
const baglantiMetniYok = 'Sunucuya ulaşılamıyor, yeniden denenecek';

/// Bildirim yükü: başka hesabın iletisi `hesap:<adres>|<ileti>|<kutu kimliği>` biçimindedir (dokununca önce o
/// hesaba geçilir; kutu kimliği yoksa adresle eşlenir, eski yükler `hesap:<adres>|<ileti>`).
const hesapOneki = 'hesap:';
String hesapYuku(String adres, String ileti, {String kutu = ''}) => '$hesapOneki${adres.toLowerCase()}|$ileti${kutu.isEmpty ? '' : '|$kutu'}';
({String adres, String ileti, String kutu})? hesapYukuCoz(String yuk) {
  if (!yuk.startsWith(hesapOneki)) return null;
  final p = yuk.substring(hesapOneki.length).split('|');
  if (p.length < 2) return null;
  return (adres: p[0], ileti: p[1], kutu: p.length > 2 ? p[2] : '');
}

/// Bir canlı olaydan gösterilecek bildirim (yoksa null). Hizmet ve testler kullanır.
/// [onPlanda]: uygulama açık ve önde; [acikOda]: açık sohbet odası; [benId]: oturumdaki kutu (kendi iletisi bildirilmez).
({String baslik, String metin, String yuk})? olayBildirimi(String tur, Map<String, dynamic> v, {bool onPlanda = false, String? acikOda, String? benId}) {
  String konu() {
    final k = '${v['subject'] ?? ''}'.trim();
    return k.isEmpty ? '(konu yok)' : k;
  }

  // Konu + içeriğin ilk satırı (sunucu "preview" gönderir; eski sunucuda yalnız konu).
  String konuVeOnizleme() {
    final p = '${v['preview'] ?? ''}'.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).join(' ');
    if (p.isEmpty) return konu();
    return '${konu()}\n${p.length > 160 ? '${p.substring(0, 159)}…' : p}';
  }

  switch (tur) {
    case 'new_mail':
      // Uygulama öndeyken liste zaten canlı güncellenir.
      if (onPlanda || v['folder_role'] != 'inbox' || v['snoozed'] == true) return null;
      final id = '${v['message_id'] ?? ''}';
      if (id.isEmpty) return null;
      return (baslik: gorunenAd('${v['from'] ?? ''}'), metin: konuVeOnizleme(), yuk: id);
    case 'unified_new':
      // Başka hesabın yeni postası: öndeyken de gösterilir (o hesap açık değil).
      final id = '${v['message_id'] ?? ''}';
      final hesap = '${v['account'] ?? ''}';
      if (id.isEmpty || hesap.isEmpty) return null;
      return (baslik: gorunenAd('${v['from'] ?? ''}'), metin: '$hesap · ${konuVeOnizleme()}', yuk: hesapYuku(hesap, id, kutu: '${v['mailbox_id'] ?? ''}'));
    case 'chat_message':
      final oda = '${v['room_id'] ?? ''}';
      if (oda.isEmpty || (benId != null && '${v['sender_id'] ?? ''}' == benId)) return null;
      if (onPlanda && oda == acikOda) return null;
      final kim = '${v['sender_name'] ?? ''}'.trim();
      return (
        baslik: kim.isEmpty ? 'Yeni sohbet iletisi' : (v['channel'] == true ? '$kim (kanal)' : kim),
        metin: '${v['preview'] ?? ''}',
        yuk: '${Bildirim.sohbetOneki}$oda',
      );
  }
  return null;
}

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
        // Akış kendi döngüsündedir; olay yalnız bağlantı bekçisi için (koptuysa yeniden bağlanır).
        eventAction: ForegroundTaskEventAction.repeat(60000),
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
        serviceId: 4107,
        serviceTypes: const [ForegroundServiceTypes.remoteMessaging],
        notificationTitle: baglantiBasligi,
        notificationText: baglantiMetniBagli,
        notificationIcon: const NotificationIcon(metaDataName: 'com.bogahost.posta.BILDIRIM_SIMGESI'),
        callback: postaArkaplanGorevi,
      );
    } catch (_) {}
  }

  Future<void> hizmetiDurdur() async {
    if (!android) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  /// Hizmete uygulamanın durumu (önde mi, açık oda) gönderilir: öndeyken gereksiz bildirim çıkmaz.
  void hizmeteBildir(Map<String, Object?> v) {
    if (!android) return;
    try {
      FlutterForegroundTask.sendDataToTask(v);
    } catch (_) {}
  }

  // ---- Pil kısıtlaması (Android) ----

  Future<bool> pilMuaf() async {
    if (!android) return true;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return true;
    }
  }

  Future<bool> pilMuafiyetiIste() async {
    if (!android) return true;
    try {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {
      return false;
    }
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
      // Kapat düğmesi uygulamayı kapatmaz: pencere gizlenir, yeni posta tepsiden bildirilir.
      await windowManager.setPreventClose(true);
      windowManager.addListener(t);
      trayManager.addListener(t);
      await trayManager.setIcon('assets/tepsi.ico');
      await trayManager.setToolTip(baglantiBasligi);
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'ac', label: 'BogaMail\'i aç'),
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

  /// main(): ayarlar, pencere / tepsi kurulumu (giriş gerektirmez).
  static Future<void> uygulamaAcildi(List<String> args) async {
    gizliBasla = args.contains('--arkaplan');
    try {
      final p = await SharedPreferences.getInstance();
      surekliBagli.value = p.getBool(_arkaplanAnahtari) ?? true;
      giristeBaslat.value = p.getBool(_giristeAnahtari) ?? true;
    } catch (_) {}
    if (platform.android) {
      try {
        FlutterForegroundTask.initCommunicationPort();
      } catch (_) {}
    }
    await platform.tepsiyiKur(gizliBasla: gizliBasla);
  }

  /// Giriş yapıldıktan sonra (Kabuk açılınca): hizmeti başlat, "girişte başlat" varsayılanını uygula.
  static Future<void> oturumAcildi() async {
    if (platform.android && surekliBagli.value) await platform.hizmetiBaslat();
    // Kullanıcı kapatmadıysa (varsayılan açık) her açılışta kayıt tazelenir: exe yolu değişmiş olabilir.
    if (platform.giristeBaslatVar && giristeBaslat.value) await platform.giristeBaslatAyarla(true);
  }

  /// Çıkışta (son hesap): hizmet durur.
  static Future<void> oturumKapandi() => platform.hizmetiDurdur();

  /// Uygulama öne geldi / arka plana gitti, açık oda değişti.
  static void durum({required bool onPlanda, String? acikOda}) => platform.hizmeteBildir({'onPlanda': onPlanda, 'oda': acikOda});

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
}

// ---------------- Android ön plan hizmeti (ayrı isolate) ----------------

@pragma('vm:entry-point')
void postaArkaplanGorevi() {
  FlutterForegroundTask.setTaskHandler(_PostaGorevi());
}

class _PostaGorevi extends TaskHandler {
  BogaApi? _api;
  CancelToken? _iptal;
  bool _calisiyor = true;
  bool _bagli = false;
  bool _onPlanda = false;
  String? _acikOda;
  String? _benId;
  int _deneme = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    final api = BogaApi(uygulama: 'posta', csrfCerezi: 'bm_mail_csrf');
    await api.baslat();
    _api = api;
    await Bildirim.hazirla();
    unawaited(_dongu());
  }

  /// Bekçi: akış kopmuş ve yeniden deneme beklemiyorsa döngü zaten sürer; burada yalnız metin tazelenir.
  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_metin());
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      _onPlanda = data['onPlanda'] == true;
      final o = data['oda'];
      _acikOda = o is String && o.isNotEmpty ? o : null;
    }
  }

  Future<void> _metin() async {
    try {
      await FlutterForegroundTask.updateService(notificationTitle: baglantiBasligi, notificationText: _bagli ? baglantiMetniBagli : baglantiMetniYok);
    } catch (_) {}
  }

  Future<void> _dongu() async {
    while (_calisiyor) {
      final api = _api;
      if (api == null) return;
      try {
        if (_benId == null) {
          final me = await api.get('/api/v1/mail/auth/me');
          final k = me is Map ? me['mailbox'] : null;
          _benId = k is Map ? '${k['mailbox_id'] ?? ''}' : null;
        }
        await _akis(api);
      } on ApiHata catch (e) {
        if (e.durum == 401) {
          // Oturum kapanmış: izlenecek bir şey yok, kalıcı bildirim kalksın.
          _calisiyor = false;
          await FlutterForegroundTask.stopService();
          return;
        }
      } catch (_) {}
      _bagli = false;
      await _metin();
      if (!_calisiyor) return;
      _deneme++;
      await Future<void>.delayed(Duration(milliseconds: min(60000, 1000 * pow(2, min(_deneme, 6)).toInt()) + Random().nextInt(1000)));
    }
  }

  Future<void> _akis(BogaApi api) async {
    final iptal = CancelToken();
    _iptal = iptal;
    final c = await api.dio.get<ResponseBody>(
      '/api/v1/mail/stream',
      cancelToken: iptal,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'},
        receiveTimeout: const Duration(seconds: 75),
      ),
    );
    final d = c.statusCode ?? 0;
    if (d == 401) throw ApiHata(401, 'oturum yok');
    if (d != 200 || c.data == null) throw StateError('akış açılamadı');
    _bagli = true;
    _deneme = 0;
    await _metin();
    var olay = 'message';
    final veri = StringBuffer();
    await for (final satir in c.data!.stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
      if (satir.isEmpty) {
        if (olay == 'logout') throw ApiHata(401, 'çıkış');
        if (olay == 'mail' && veri.isNotEmpty) await _isle(veri.toString());
        olay = 'message';
        veri.clear();
      } else if (satir.startsWith('event:')) {
        olay = satir.substring(6).trim();
      } else if (satir.startsWith('data:')) {
        if (veri.isNotEmpty) veri.write('\n');
        veri.write(satir.substring(5).trimLeft());
      }
    }
  }

  Future<void> _isle(String ham) async {
    try {
      final m = jsonDecode(ham);
      if (m is! Map) return;
      final v = m['data'] is Map ? Map<String, dynamic>.from(m['data'] as Map) : <String, dynamic>{};
      final b = olayBildirimi('${m['kind'] ?? ''}', v, onPlanda: _onPlanda, acikOda: _acikOda, benId: _benId);
      if (b == null) return;
      await Bildirim.goster(iletiId: b.yuk, baslik: b.baslik, metin: b.metin);
      // WorkManager yedeği aynı iletiyi yeniden bildirmesin.
      if (!b.yuk.startsWith(Bildirim.sohbetOneki)) await Bildirim.goruldu(DateTime.now());
    } catch (_) {}
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _calisiyor = false;
    _iptal?.cancel();
    _iptal = null;
  }
}
