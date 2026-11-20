import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../veri/json.dart';

// Mail Gateway modelleri ve ortak parçaları (internal/api/gateway.go).

const gwDurumEtiketi = {'closed': 'Çalışıyor', 'open': 'Erişilemiyor (devre açık)', 'half_open': 'Yarı açık (deneniyor)'};
const gwSaglikEtiketi = {'ok': 'Sağlıklı', 'degraded': 'Kısmi arıza', 'down': 'Tüm hedefler kapalı', 'unconfigured': 'Hedef yok'};
const gwTlsEtiketi = {'opportunistic': 'Fırsatçı TLS', 'required': 'TLS zorunlu', 'verify': 'TLS zorunlu + sertifika doğrulama'};
const gwUyariEtiketi = {
  'target_down': 'Hedef kapandı',
  'target_up': 'Hedef düzeldi',
  'target_half_open': 'Yoklama başarılı',
  'all_down': 'Tüm hedefler kapalı',
  'recovered': 'Teslim yeniden başladı',
  'continuity_on': 'Kesinti modu açıldı',
  'continuity_off': 'Kesinti modu kapandı',
  'continuity_quota': 'Kesinti modu kotası doldu',
};

Color gwSaglikRengi(String h) => switch (h) {
  'ok' => Marka.zumrut,
  'down' => Marka.gul,
  _ => Marka.kehribar,
};

Color gwHedefRengi(GwHedef t, Color kapali) => !t.etkin
    ? kapali
    : switch (t.durum) {
        'closed' => Marka.zumrut,
        'half_open' => Marka.kehribar,
        _ => Marka.gul,
      };

/// Saniye cinsinden yaş: "5 dk", "2 sa 10 dk", "3 gün 4 sa".
String gwYas(int sn) {
  if (sn < 60) return '$sn sn';
  if (sn < 3600) return '${sn ~/ 60} dk';
  if (sn < 86400) return '${sn ~/ 3600} sa ${(sn % 3600) ~/ 60} dk';
  return '${sn ~/ 86400} gün ${(sn % 86400) ~/ 3600} sa';
}

/// Teslim hedefi (gwTarget).
class GwHedef {
  const GwHedef(this.m);
  final Map<String, dynamic> m;
  String get id => metin(m['id']);
  String get sunucu => metin(m['host']);
  int get port => tamsayi(m['port'], 25);
  int get oncelik => tamsayi(m['priority']);
  String get tls => metin(m['tls_policy'], 'opportunistic');
  String get kimlikTuru => metin(m['auth_mode'], 'none');
  String get kullanici => metin(m['auth_username']);
  bool get parolaVar => mantik(m['auth_password_set']);
  bool get etkin => mantik(m['enabled'], true);
  String get durum => metin(m['state'], 'closed');
  int get ardisikHata => tamsayi(m['consecutive_failures']);
  DateTime? get sonBasari => tarihOku(m['last_success_at']);
  String get sonHata => metin(m['last_error']);
  DateTime? get sonrakiYoklama => tarihOku(m['next_probe_at']);
}

/// Gateway alan adı (gwDomain).
class GwAlan {
  const GwAlan(this.m);
  final Map<String, dynamic> m;
  factory GwAlan.coz(Map<String, dynamic> m) => GwAlan(m);
  String get id => metin(m['id']);
  String get ad => metin(m['unicode_name'], metin(m['name']));
  String get durum => metin(m['status']);
  bool get dogrulandi => mantik(m['verified']);
  String get orgAdi => metin(m['organization_name']);
  String get saglik => metin(m['health'], 'unconfigured');
  List<GwHedef> get hedefler => haritalar(m['targets']).map(GwHedef.new).toList();
  Map<String, dynamic> get ayar => harita(m['settings']);
  Map<String, dynamic> get kuyruk => harita(m['queue']);
  int get teslimSaat => tamsayi(m['delivered_last_hour']);
  int get ertelenenSaat => tamsayi(m['deferred_last_hour']);
  int get basarisizSaat => tamsayi(m['failed_last_hour']);
  String get sonHata => metin(m['last_error']);
  bool get failover => mantik(harita(m['features'])['gateway_failover']);
  bool get continuityOzellik => mantik(harita(m['features'])['continuity']);
  Map<String, dynamic> get kesinti => harita(m['continuity']);
  bool get kesintiAktif => mantik(kesinti['active']);
}

/// Bağlantı testi sonucu (gateway.ProbeResult).
class SondaSonucu extends StatelessWidget {
  const SondaSonucu(this.r, {super.key});
  final Map<String, dynamic> r;

  static const _asama = {'resolve': 'Adres çözümleme', 'connect': 'Bağlantı', 'greeting': 'Karşılama', 'ehlo': 'EHLO', 'starttls': 'STARTTLS', 'done': 'Tamam'};

  @override
  Widget build(BuildContext context) {
    final ok = mantik(r['ok']);
    final renk = ok ? Marka.zumrut : Marka.gul;
    final asama = metin(r['stage']);
    final adres = metin(r['address']), karsilama = metin(r['banner']), hata = metin(r['error']);
    final starttls = mantik(r['starttls_offered'])
        ? (mantik(r['tls'])
              ? 'kuruldu (${metin(r['tls_version'], 'TLS')}${mantik(r['cert_verified']) ? ', sertifika doğrulandı' : ''})'
              : 'sunuldu, kurulamadı')
        : 'sunulmuyor';
    const kucuk = TextStyle(fontSize: 12.5);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: .08),
        border: Border.all(color: renk.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${ok ? 'Bağlantı başarılı' : 'Başarısız: ${_asama[asama] ?? asama} aşaması'} · ${tamsayi(r['duration_ms'])} ms',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          if (adres.isNotEmpty) Text('Adres: $adres', style: kucuk),
          if (karsilama.isNotEmpty) Text('Karşılama: $karsilama', style: kucuk, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text('STARTTLS: $starttls', style: kucuk),
          if (hata.isNotEmpty) Text('Hata: $hata', style: kucuk),
        ],
      ),
    );
  }
}
