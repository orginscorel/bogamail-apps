// Etkin alarmları yoklayıp yeni çıkanlar için bildirim üretir (APNs olmayan platformlar: Android, Windows, Linux).
// Sunucuda yönetim için canlı olay akışı yok (SSE yalnızca webmail'de), bu yüzden GET /api/v1/alerts/active
// 60 sn'de bir yoklanır. Bir alarmın kimliği kural + konu + başlama zamanıdır: aynı alarm tekrar bildirilmez,
// kapanıp yeniden başlayan alarm yeniden bildirilir. Görülenler SharedPreferences'ta tutulur; böylece uygulama
// ile Android ön plan hizmeti (ayrı isolate) aynı alarmı iki kez bildirmez.

import 'package:shared_preferences/shared_preferences.dart';

import 'json.dart';

/// Yoklama aralığı.
const alarmYoklamaAraligi = Duration(seconds: 60);

class EtkinAlarm {
  const EtkinAlarm({required this.anahtar, required this.kuralId, required this.ad, required this.kritik, required this.konu, required this.ayrinti});

  factory EtkinAlarm.json(Map<String, dynamic> j) {
    final kural = metin(j['rule_id']);
    final konu = metin(j['subject']).isNotEmpty ? metin(j['subject']) : metin(j['label']);
    return EtkinAlarm(
      anahtar: '$kural|$konu|${metin(j['since'])}',
      kuralId: kural,
      ad: metin(j['name']),
      kritik: metin(j['severity']) == 'critical',
      konu: konu,
      ayrinti: metin(j['detail']),
    );
  }

  final String anahtar;
  final String kuralId;
  final String ad;
  final bool kritik;
  final String konu;
  final String ayrinti;

  String get bildirimBasligi => '${kritik ? 'Kritik alarm' : 'Alarm'}: $ad';
  String get bildirimMetni => [konu, ayrinti].where((s) => s.isNotEmpty).join(' — ');
  int get bildirimId => anahtar.hashCode & 0x7fffffff;
}

/// Yoklama sonucu: [etkin] tüm etkin alarmlar, [yeni] bu yoklamada ilk kez görülenler.
typedef AlarmYoklamasi = ({List<EtkinAlarm> etkin, List<EtkinAlarm> yeni});

class AlarmIzleyici {
  AlarmIzleyici(this.getir);

  /// GET /api/v1/alerts/active (uygulamada Uyg.api.get, hizmette kendi BogaApi'si).
  final Future<dynamic> Function() getir;

  static const _anahtar = 'yonetim.alarm.gorulen';

  /// Etkin alarmları getirir, görülmemiş olanları ayırır ve görüleni kaydeder.
  Future<AlarmYoklamasi> yokla() async {
    final v = await getir();
    final etkin = [for (final j in haritalar(harita(v)['items'])) EtkinAlarm.json(j)];
    final p = await SharedPreferences.getInstance();
    await p.reload(); // diğer isolate'in yazdıkları
    final gorulen = (p.getStringList(_anahtar) ?? const []).toSet();
    final yeni = [for (final a in etkin) if (!gorulen.contains(a.anahtar)) a];
    // Yalnızca hâlâ etkin olanlar saklanır: kapanan alarm yeniden başlarsa tekrar bildirilir.
    await p.setStringList(_anahtar, [for (final a in etkin) a.anahtar]);
    return (etkin: etkin, yeni: yeni);
  }

  /// Çıkışta: başka hesapla girilirse eski görülenler karışmasın.
  static Future<void> sifirla() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_anahtar);
    } catch (_) {}
  }
}
