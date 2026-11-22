// Görev hatırlatmaları: son tarihi olan açık görevler işletim sisteminin bildirim zamanlayıcısına eklenir.
// - Android: AlarmManager (flutter_local_notifications zonedSchedule; "Alarmlar ve hatırlatıcılar" izni varsa tam
//   zamanlı, yoksa sistem birkaç dakika kaydırabilir). Uygulama kapalıyken ve cihaz yeniden başlayınca da çalar.
// - Windows: zamanlanmış Windows bildirimi (ToastNotifier.AddToSchedule); uygulama kapalıyken de sistem gösterir.
// - iPhone/iPad/Mac: CalDAV ile Apple Hatırlatıcılar (sunucu görevleri son tarih alarmıyla verir); burada zamanlanmaz.
// Zaman: sunucunun canlı hatırlatmasıyla aynı, son tarihten 15 dakika önce. Yalnızca sorumlu kişiye (atanan; atanmamışsa
// oluşturan). Her hesabın hatırlatmaları ayrı tutulur: hesap değiştirmek diğer hesabınkileri silmez, çıkış siler.
// Bildirime dokununca görev açılır (başka hesabınsa önce o hesaba geçilir). Görev içeriği hiçbir yere yazılmaz.

import 'dart:async';
import 'dart:convert';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bildirim.dart';
import 'takvim_servisi.dart';

/// Planlanacak tek hatırlatma.
typedef GorevAnimsatmasi = ({int id, DateTime zaman, String baslik, String metin, String yuk});

/// İşletim sistemi tarafı (testlerde sahtesiyle değiştirilir).
class GorevZamanlayici {
  Future<bool> planla(GorevAnimsatmasi a) => Bildirim.planla(id: a.id, zaman: a.zaman, baslik: a.baslik, metin: a.metin, yuk: a.yuk);
  Future<void> iptal(int id) => Bildirim.iptal(id);
}

class GorevHatirlatma {
  GorevHatirlatma._();

  static const onceden = Duration(minutes: 15);

  /// Android en çok 500 alarm tutar; hesap başına en yakın 50 görev yeter.
  static const azami = 50;

  static const yukOneki = 'gorev:';
  static const _acikAnahtar = 'posta.gorev_hatirlatma';
  static const _planOneki = 'posta.gorev_hatirlatma.plan.';

  @visibleForTesting
  static GorevZamanlayici zamanlayici = GorevZamanlayici();

  /// Testler: platform denetimini atla.
  @visibleForTesting
  static bool? destekliZorla;

  /// Bu platformda uygulama hatırlatmaları zamanlar mı (Android, Windows).
  static bool get destekli => destekliZorla ?? Bildirim.yerel;

  static String yuk(String kutu, String gorev) => '$yukOneki$kutu|$gorev';
  static ({String kutu, String gorev})? yukCoz(String y) {
    if (!y.startsWith(yukOneki)) return null;
    final i = y.indexOf('|');
    if (i < 0) return null;
    final g = y.substring(i + 1);
    return g.isEmpty ? null : (kutu: y.substring(yukOneki.length, i), gorev: g);
  }

  /// Kalıcı bildirim kimliği (FNV-1a; String.hashCode çalıştırmalar arasında aynı olmak zorunda değil).
  static int kimlik(String kutu, String gorev) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode('gorev:$kutu:$gorev')) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    // Yerel posta bildirimleriyle (ileti kimliğinin hashCode'u) çakışmasın diye üst bit ayrı bir aralık seçer.
    return (h & 0x3fffffff) | 0x40000000;
  }

  /// Hatırlatılacak görevler (saf; testler doğrudan dener). [kutu]: hesabın kutu kimliği (görevdeki kişi kimliğiyle aynı).
  static List<GorevAnimsatmasi> plan(List<Gorev> l, {required String kutu, required DateTime simdi}) {
    final out = <GorevAnimsatmasi>[];
    for (final g in l) {
      final b = g.bitis;
      if (g.bitti || b == null || !b.isAfter(simdi)) continue;
      final sorumlu = g.atanan?.id ?? g.olusturan?.id ?? '';
      if (sorumlu.isNotEmpty && sorumlu != kutu) continue;
      var z = b.subtract(onceden);
      // Son tarihe 15 dakikadan az kaldıysa hemen (birkaç saniye sonra).
      if (!z.isAfter(simdi)) z = simdi.add(const Duration(seconds: 5));
      final yerel = b.toLocal();
      final saat = '${yerel.hour.toString().padLeft(2, '0')}:${yerel.minute.toString().padLeft(2, '0')}';
      final gun = '${yerel.day.toString().padLeft(2, '0')}.${yerel.month.toString().padLeft(2, '0')}.${yerel.year}';
      final bugun = yerel.year == simdi.toLocal().year && yerel.month == simdi.toLocal().month && yerel.day == simdi.toLocal().day;
      out.add((
        id: kimlik(kutu, g.id),
        zaman: z,
        baslik: g.baslik.trim().isEmpty ? 'Görev' : g.baslik.trim(),
        metin: 'Son tarih: ${bugun ? 'bugün' : gun} $saat',
        yuk: yuk(kutu, g.id),
      ));
    }
    out.sort((a, b) => a.zaman.compareTo(b.zaman));
    return out.take(azami).toList();
  }

  /// "Görev hatırlatmaları" ayarı (cihazda; varsayılan açık).
  static Future<bool> acik() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_acikAnahtar) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> ayarla(bool v, {String? kutu}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_acikAnahtar, v);
    if (!v) {
      for (final k in p.getKeys().where((k) => k.startsWith(_planOneki)).toList()) {
        await hesapKapandi(k.substring(_planOneki.length));
      }
    } else if (kutu != null) {
      await esitle(kutu: kutu);
    }
  }

  static final _kilit = <String, Future<void>>{};

  /// Hesabın hatırlatmalarını görev listesine göre yeniden kurar: yeni / değişenler zamanlanır, bitenler, silinenler
  /// ve artık sorumlusu olmadıkları iptal edilir. [gorevler] verilmezse açık görevler sunucudan alınır ([api] ya da
  /// oturumdaki istemci). Görevler paketinde kapalıysa (403) hepsi iptal edilir.
  static Future<void> esitle({required String kutu, List<Gorev>? gorevler, BogaApi? api}) async {
    if (!destekli || kutu.isEmpty) return;
    // Aynı hesap için art arda gelen çağrılar sıraya girer.
    final onceki = _kilit[kutu];
    final f = (onceki ?? Future<void>.value()).catchError((_) {}).then((_) => _esitle(kutu, gorevler, api));
    _kilit[kutu] = f;
    try {
      await f;
    } finally {
      if (identical(_kilit[kutu], f)) _kilit.remove(kutu);
    }
  }

  static Future<void> _esitle(String kutu, List<Gorev>? gorevler, BogaApi? api) async {
    if (!await acik()) return;
    var l = gorevler;
    if (l == null) {
      try {
        if (api != null) {
          final v = await api.get('/api/v1/mail/tasks', q: {'status': 'open'});
          final ogeler = v is Map && v['items'] is List ? v['items'] as List : const [];
          l = ogeler.map(Gorev.json).toList();
        } else {
          l = await GorevApi.liste(durum: 'open');
        }
      } on ApiHata catch (e) {
        if (e.durum == 403 || e.durum == 404) l = const [];
      } catch (_) {}
      if (l == null) return; // çevrimdışı: eski plan kalır
    }
    final yeni = plan(l, kutu: kutu, simdi: DateTime.now());
    final p = await SharedPreferences.getInstance();
    // Ön plan hizmeti / WorkManager ayrı izolatlarda da kurar: diskteki son plan okunur.
    try {
      await p.reload();
    } catch (_) {}
    final eski = _okuPlan(p, kutu);
    final kimlikler = {for (final a in yeni) a.id};
    for (final id in eski.keys.where((id) => !kimlikler.contains(id))) {
      await zamanlayici.iptal(id);
    }
    final kayit = <int, String>{};
    for (final a in yeni) {
      final imza = '${a.zaman.millisecondsSinceEpoch}|${a.baslik}|${a.metin}';
      if (eski[a.id] == imza) {
        kayit[a.id] = imza;
        continue;
      }
      if (await zamanlayici.planla(a)) kayit[a.id] = imza;
    }
    if (kayit.isEmpty) {
      await p.remove('$_planOneki$kutu');
    } else {
      await p.setString('$_planOneki$kutu', jsonEncode({for (final e in kayit.entries) '${e.key}': e.value}));
    }
  }

  static Map<int, String> _okuPlan(SharedPreferences p, String kutu) {
    try {
      final v = jsonDecode(p.getString('$_planOneki$kutu') ?? '{}');
      if (v is Map) return {for (final e in v.entries) int.parse('${e.key}'): '${e.value}'};
    } catch (_) {}
    return {};
  }

  /// Sistem bildirimlerinin hepsi silindi (çıkış): kayıtlı planlar unutulur, sonraki eşitleme yeniden kurar.
  static Future<void> planlariUnut() async {
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().where((k) => k.startsWith(_planOneki)).toList()) {
      await p.remove(k);
    }
  }

  /// Hesaptan çıkıldı (ya da ayar kapatıldı): o hesabın hatırlatmaları iptal edilir.
  static Future<void> hesapKapandi(String kutu) async {
    if (kutu.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    for (final id in _okuPlan(p, kutu).keys) {
      await zamanlayici.iptal(id);
    }
    await p.remove('$_planOneki$kutu');
  }

  // ---- oturumdaki hesap için kısayollar ----

  static Timer? _gecikme;

  /// Görev değişti (oluşturma, düzenleme, durum, silme, canlı olay): kısa gecikmeyle yeniden kurulur.
  static void tazele({required String kutu, Duration gecikme = const Duration(milliseconds: 800)}) {
    if (!destekli) return;
    _gecikme?.cancel();
    _gecikme = Timer(gecikme, () => unawaited(esitle(kutu: kutu)));
  }
}
