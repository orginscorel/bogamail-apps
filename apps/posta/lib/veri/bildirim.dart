// Yerel bildirimler (Android ve Windows). iPhone/iPad/Mac'te bildirimleri sunucu APNs ile gönderir (boga_ortak Push).
//
// Android: uygulama kapalıyken WorkManager ile periyodik denetim (Android'in izin verdiği en kısa aralık 15 dakika;
// pil tasarrufu modunda sistem daha da geciktirebilir). Görev, uygulamanın çerez deposunu kullanarak Gelen
// Kutusu'ndaki yeni okunmamış iletileri sorar ve son bildirilen tarihten yenileri için bildirim gösterir.
// Windows: uygulama açıkken pencere odakta değilse canlı "new_mail" olayı bildirim olarak gösterilir.

import 'dart:async';
import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'arkaplan.dart';
import 'bildirim_sesi.dart';
import 'gorev_hatirlatma.dart';
import 'modeller.dart';
import 'yardimci.dart';

const _gorevAdi = 'posta-yeni-ileti-denetimi';
const _sonAnahtar = 'posta.bildirim.son';
const _arkaPlanAnahtar = 'posta.bildirim.arkaplan';
const _sesAnahtar = 'posta.bildirim.ses';
const _masaustuAnahtar = 'posta.bildirim.masaustu';
const _renk = Color(0xFF5443D2);

class Bildirim {
  Bildirim._();
  static final _p = FlutterLocalNotificationsPlugin();
  static bool _hazir = false;
  static final _acildi = StreamController<String>.broadcast();

  /// Bildirime dokunuldu: ileti kimliği.
  static Stream<String> get acildi => _acildi.stream;

  static bool get android => !kIsWeb && Platform.isAndroid;
  static bool get windows => !kIsWeb && Platform.isWindows;

  /// Bu platformda yerel bildirim kullanılıyor mu.
  static bool get yerel => android || windows;

  static Future<void> hazirla() async {
    if (_hazir || !yerel) return;
    try {
      await _p.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_bildirim'),
          windows: WindowsInitializationSettings(appName: 'BogaMail', appUserModelId: 'Bogahost.BogaMail.Posta', guid: '6f0b9a52-8d3e-4c71-9b2a-3e5f1d7c4a90'),
        ),
        onDidReceiveNotificationResponse: (r) {
          final id = r.payload;
          if (id != null && id.isNotEmpty) _acildi.add(id);
        },
      );
      _hazir = true;
    } catch (_) {}
    final a = _a;
    if (_hazir && a != null) await kanallariKur(a);
  }

  /// Android kanalları: posta ve sohbet ayrı, kendi BogaMail sesleriyle, yüksek önemli. Kanal sesi oluşturulduktan
  /// sonra değiştirilemez; bu yüzden yeni kimlikli kanallar açılır, eski sessiz/varsayılan sesli kanal silinir.
  /// ("baglanti" ön plan hizmetinin kalıcı, sessiz kanalıdır; iletiler orada gösterilmez, dokunulmaz.)
  @visibleForTesting
  static Future<void> kanallariKur(AndroidFlutterLocalNotificationsPlugin a) async {
    for (final k in eskiKanallar) {
      try {
        await a.deleteNotificationChannel(channelId: k);
      } catch (_) {}
    }
    for (final s in BildirimSesi.values) {
      try {
        await a.createNotificationChannel(
          AndroidNotificationChannel(
            s.kanalId,
            s.kanalAdi,
            description: s.kanalAciklamasi,
            importance: Importance.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(s.kaynak),
            enableVibration: true,
          ),
        );
      } catch (_) {}
    }
    try {
      await a.createNotificationChannel(
        const AndroidNotificationChannel(
          gorevKanali,
          'Görev hatırlatmaları',
          description: 'Görevlerin son tarihi yaklaşınca',
          importance: Importance.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('bogamail_posta'),
          enableVibration: true,
        ),
      );
    } catch (_) {}
  }

  /// Görev hatırlatmalarının Android kanalı (gorev_hatirlatma.dart).
  static const gorevKanali = 'gorev_v1';

  /// Görev hatırlatması için ayrıntı: kendi kanalı, BogaMail sesi. Windows'ta zamanlanmış bildirim sistem tarafından
  /// (uygulama kapalıyken de) gösterilir; uygulama ses çalamayacağı için sistem sesi kullanılır.
  @visibleForTesting
  static NotificationDetails gorevAyrintisi(String metin, {required bool ses}) => NotificationDetails(
    android: AndroidNotificationDetails(
      gorevKanali,
      'Görev hatırlatmaları',
      channelDescription: 'Görevlerin son tarihi yaklaşınca',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      color: _renk,
      playSound: ses,
      sound: const RawResourceAndroidNotificationSound('bogamail_posta'),
      silent: !ses,
      styleInformation: BigTextStyleInformation(metin),
    ),
    windows: WindowsNotificationDetails(audio: ses ? null : WindowsNotificationAudio.silent()),
  );

  /// Bildirimi işletim sistemine zamanlar (Android AlarmManager, Windows zamanlanmış bildirim). Android'de tam zamanlı
  /// alarm izni yoksa (Android 12+ "Alarmlar ve hatırlatıcılar") sistem birkaç dakika kaydırabilir (inexact).
  static Future<bool> planla({required int id, required DateTime zaman, required String baslik, required String metin, required String yuk}) async {
    await hazirla();
    if (!_hazir) return false;
    var ses = true;
    try {
      ses = (await SharedPreferences.getInstance()).getBool(_sesAnahtar) ?? true;
    } catch (_) {}
    try {
      var kip = AndroidScheduleMode.inexactAllowWhileIdle;
      if (android && (await _a?.canScheduleExactNotifications() ?? false)) kip = AndroidScheduleMode.exactAllowWhileIdle;
      await _p.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(zaman.toUtc(), tz.UTC),
        notificationDetails: gorevAyrintisi(metin, ses: ses),
        androidScheduleMode: kip,
        title: baslik,
        body: metin,
        payload: yuk,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> iptal(int id) async {
    await hazirla();
    if (!_hazir) return;
    try {
      await _p.cancel(id: id);
    } catch (_) {}
  }

  /// Android 12+: tam zamanlı alarm izni var mı (yoksa hatırlatmalar birkaç dakika gecikebilir).
  static Future<bool> tamZamanliAlarm() async {
    if (!android) return true;
    await hazirla();
    try {
      return await _a?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android 12+: "Alarmlar ve hatırlatıcılar" ayar sayfasını açar.
  static Future<void> tamZamanliAlarmIste() async {
    if (!android) return;
    await hazirla();
    try {
      await _a?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  /// Uygulamayı bir bildirim açtıysa ileti kimliği (soğuk açılış).
  static Future<String?> baslangic() async {
    if (!yerel) return null;
    await hazirla();
    try {
      final d = await _p.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) {
        final id = d!.notificationResponse?.payload;
        if (id != null && id.isNotEmpty) return id;
      }
    } catch (_) {}
    return null;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _a => _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Android 13+ çalışma zamanı izni.
  static Future<bool> izinIste() async {
    if (!android) return true;
    await hazirla();
    try {
      return await _a?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> izinVar() async {
    if (!android) return true;
    await hazirla();
    try {
      return await _a?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sunucudaki posta ayarları (notify_desktop, notify_sound): cihazda saklanır ki arka plan görevi de uysun.
  /// Masaüstü bildirimleri yalnızca Windows'taki canlı bildirimleri; ses tüm yerel bildirimleri etkiler.
  static Future<void> tercihleriUygula({required bool masaustu, required bool ses}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_masaustuAnahtar, masaustu);
      await p.setBool(_sesAnahtar, ses);
    } catch (_) {}
  }

  /// Kanal ayarı + açılınca tam metin (konu ve içerik önizlemesi birden fazla satır). Ses kanaldan gelir (Android 8+);
  /// eski sürümler için bildirimde de belirtilir. Kullanıcı sesi kapattıysa (notify_sound) sessiz gösterilir.
  @visibleForTesting
  static AndroidNotificationDetails androidAyrinti(BildirimSesi tur, bool ses, String metin) => AndroidNotificationDetails(
    tur.kanalId,
    tur.kanalAdi,
    channelDescription: tur.kanalAciklamasi,
    importance: Importance.high,
    priority: Priority.high,
    category: tur == BildirimSesi.sohbet ? AndroidNotificationCategory.message : AndroidNotificationCategory.email,
    color: _renk,
    playSound: ses,
    sound: RawResourceAndroidNotificationSound(tur.kaynak),
    silent: !ses,
    styleInformation: BigTextStyleInformation(metin),
  );

  /// Windows toast'ı her zaman sessizdir: ses (açıksa) [SesCalar] ile ayrıca çalınır, çift ses olmaz.
  @visibleForTesting
  static WindowsNotificationDetails windowsAyrinti() => WindowsNotificationDetails(audio: WindowsNotificationAudio.silent());

  static Future<void> goster({required String iletiId, required String baslik, required String metin}) async {
    await hazirla();
    if (!_hazir) return;
    var ses = true;
    try {
      final p = await SharedPreferences.getInstance();
      if (windows && !(p.getBool(_masaustuAnahtar) ?? true)) return;
      ses = p.getBool(_sesAnahtar) ?? true;
    } catch (_) {}
    final tur = BildirimSesi.yuktan(iletiId);
    try {
      await _p.show(
        id: iletiId.hashCode & 0x7fffffff,
        title: baslik,
        body: metin,
        notificationDetails: NotificationDetails(android: androidAyrinti(tur, ses, metin), windows: windowsAyrinti()),
        payload: iletiId,
      );
      if (windows && ses) await SesCalar.cal(tur);
    } catch (_) {}
  }

  /// Canlı "new_mail" olayından bildirim (Windows'ta pencere odakta değilken).
  /// Windows'ta pencere odakta değilken (tepsideyken de); diğer hesapların postası ("unified_new") dahil.
  static Future<void> canliOlay(CanliOlay o) async {
    if (!windows || (o.tur != 'new_mail' && o.tur != 'unified_new')) return;
    final onde = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final b = olayBildirimi(o.tur, o.veri, onPlanda: onde);
    if (b == null) return;
    await goster(iletiId: b.yuk, baslik: b.baslik, metin: b.metin);
  }

  /// Bildirim yükü bir sohbet odasıysa `sohbet:<oda>` biçimindedir.
  static const sohbetOneki = 'sohbet:';

  /// Canlı "chat_message" olayından bildirim: pencere odakta değilken (Windows; Android'de akış ön plandayken açıktır).
  static Future<void> sohbetOlayi(CanliOlay o) async {
    if (!yerel || o.tur != 'chat_message') return;
    final oda = '${o.veri['room_id'] ?? ''}';
    if (oda.isEmpty || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return;
    final kim = '${o.veri['sender_name'] ?? ''}'.trim();
    await goster(
      iletiId: '$sohbetOneki$oda',
      baslik: kim.isEmpty ? 'Yeni sohbet iletisi' : (o.veri['channel'] == true ? '$kim (kanal)' : kim),
      metin: '${o.veri['preview'] ?? ''}',
    );
  }

  // ---- Android arka plan denetimi ----

  static Future<bool> arkaPlanAcik() async {
    if (!android) return false;
    final p = await SharedPreferences.getInstance();
    return p.getBool(_arkaPlanAnahtar) ?? true;
  }

  /// Periyodik görevi kurar veya kaldırır.
  static Future<void> arkaPlanAyarla(bool acik) async {
    if (!android) return;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_arkaPlanAnahtar, acik);
    try {
      await Workmanager().initialize(arkaPlanGorevi);
      if (acik) {
        await Workmanager().registerPeriodicTask(
          _gorevAdi,
          _gorevAdi,
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      } else {
        await Workmanager().cancelByUniqueName(_gorevAdi);
      }
    } catch (_) {}
  }

  /// Uygulama açıkken kullanıcı gelen kutusunu gördü: arka plan görevi bundan eskiler için bildirim göstermez.
  static Future<void> goruldu(DateTime? enYeni) async {
    if (!android) return;
    final p = await SharedPreferences.getInstance();
    final simdi = enYeni ?? DateTime.now();
    final eski = DateTime.tryParse(p.getString(_sonAnahtar) ?? '');
    if (eski == null || simdi.isAfter(eski)) await p.setString(_sonAnahtar, simdi.toUtc().toIso8601String());
  }

  /// Çıkışta: görev ve işaret temizlenir.
  static Future<void> temizle() async {
    if (!android) return;
    try {
      await Workmanager().cancelByUniqueName(_gorevAdi);
      // Yalnızca görünen bildirimler kalkar; diğer hesapların zamanlanmış görev hatırlatmaları kalır (çıkılan hesabınkiler
      // GorevHatirlatma.hesapKapandi ile ayrıca iptal edilir).
      for (final b in await _p.getActiveNotifications()) {
        final id = b.id;
        if (id != null) await _p.cancel(id: id, tag: b.tag);
      }
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    await p.remove(_sonAnahtar);
  }
}

/// WorkManager arka plan girişi (ayrı izolat).
@pragma('vm:entry-point')
void arkaPlanGorevi() {
  Workmanager().executeTask((gorev, _) async {
    try {
      await _yeniIletileriDenetle();
    } catch (_) {}
    return true;
  });
}

Future<void> _yeniIletileriDenetle() async {
  final api = BogaApi(uygulama: 'posta', csrfCerezi: 'bm_mail_csrf');
  await api.baslat();
  if (!await api.oturumVar()) return;
  final p = await SharedPreferences.getInstance();
  if (!(p.getBool(_arkaPlanAnahtar) ?? true)) return;
  // Uygulama kapalıyken (ör. webmail'de) eklenen / değişen görevlerin hatırlatmaları da güncellenir.
  try {
    final me = await api.get('/api/v1/mail/auth/me');
    final k = me is Map && me['mailbox'] is Map ? '${(me['mailbox'] as Map)['mailbox_id'] ?? ''}' : '';
    if (k.isNotEmpty) await GorevHatirlatma.esitle(kutu: k, api: api);
  } catch (_) {}
  final kv = await api.get('/api/v1/mail/folders');
  final klasorler = ((kv is Map ? kv['items'] : null) as List? ?? const []).map(Klasor.json);
  final gelen = klasorler.where((k) => k.rol == 'inbox').firstOrNull;
  if (gelen == null || gelen.okunmamis == 0) return;
  final lv = await api.get('/api/v1/mail/folders/${gelen.id}/messages', q: {'page': 1, 'page_size': 20, 'filter': 'unread'});
  final ogeler = Sayfa.json(lv).ogeler.where((m) => !m.okundu && m.tarih != null).toList();
  final son = DateTime.tryParse(p.getString(_sonAnahtar) ?? '');
  final yeni = ogeler.where((m) => son == null || m.tarih!.isAfter(son)).toList();
  if (son == null) {
    // İlk çalışma: geçmiş için bildirim yağdırma, yalnızca işareti koy.
    if (ogeler.isNotEmpty) await p.setString(_sonAnahtar, ogeler.map((m) => m.tarih!).reduce((a, b) => a.isAfter(b) ? a : b).toUtc().toIso8601String());
    return;
  }
  if (yeni.isEmpty) return;
  await Bildirim.hazirla();
  for (final m in yeni.take(5)) {
    await Bildirim.goster(
      iletiId: m.id,
      baslik: gorunenAd(m.kimden),
      metin: [m.konu.trim().isEmpty ? '(konu yok)' : m.konu.trim(), if (m.onizleme.trim().isNotEmpty) m.onizleme.trim()].join('\n'),
    );
  }
  if (yeni.length > 5) {
    await Bildirim.goster(iletiId: '', baslik: 'BogaMail', metin: '${yeni.length - 5} yeni e-posta daha');
  }
  final enYeni = yeni.map((m) => m.tarih!).reduce((a, b) => a.isAfter(b) ? a : b);
  await p.setString(_sonAnahtar, enYeni.toUtc().toIso8601String());
}
