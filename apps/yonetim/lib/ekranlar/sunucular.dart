import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../oturum.dart';
import '../veri/json.dart';
import '../ortak/simgeler.dart';

/// Sunucular (web: /admin/nodes): düğüm durumu, kaynaklar, diskler ve dinleyiciler. GET /system (yalnızca süper yönetici),
/// 10 saniyede bir kendiliğinden yenilenir.
class SunucularEkrani extends StatefulWidget {
  const SunucularEkrani({super.key});

  @override
  State<SunucularEkrani> createState() => _SunucularEkraniState();
}

class _SunucularEkraniState extends State<SunucularEkrani> {
  final _anahtar = GlobalKey<TekYuklemeState<SistemDurumu>>();
  Timer? _zamanlayici;

  @override
  void initState() {
    super.initState();
    _zamanlayici = Timer.periodic(const Duration(seconds: 10), (_) => _anahtar.currentState?.yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi) {
      return const Iskelet(baslik: 'Sunucular', govde: Kapali('Bu bölüm yalnızca platform yöneticilerine açıktır.'));
    }
    return Iskelet(
      baslik: 'Sunucular',
      alt: 'Düğüm durumu · 10 sn\'de bir yenilenir',
      yenile: () => _anahtar.currentState?.yenile(),
      govde: TekYukleme<SistemDurumu>(
        key: _anahtar,
        getir: () async => SistemDurumu.coz(harita(await Uyg.api.get('/api/v1/system'))),
        icerik: (c, v, _) => IcerikListesi(
          children: [
            if (v.not.isNotEmpty) ...[Bant(v.not, ikon: Simgeler.dns), const SizedBox(height: 12)],
            if (v.dugumler.isEmpty) const Kapali('Düğüm bilgisi alınamadı.', ikon: Simgeler.dns),
            for (final d in v.dugumler) ...[DugumKarti(dugum: d), const SizedBox(height: 16)],
          ],
        ),
      ),
    );
  }
}

/// GET /system yanıtı.
class SistemDurumu {
  const SistemDurumu(this.dugumler, this.not);
  final List<Dugum> dugumler;
  final String not;
  factory SistemDurumu.coz(Map<String, dynamic> m) => SistemDurumu(haritalar(m['nodes']).map(Dugum.coz).toList(), metin(m['note']));
}

class Disk {
  const Disk(this.toplam, this.kullanilan, this.bos);
  final int toplam, kullanilan, bos;
  static Disk? coz(Object? v) {
    if (v is! Map) return null;
    final m = harita(v);
    return Disk(tamsayi(m['total_bytes']), tamsayi(m['used_bytes']), tamsayi(m['free_bytes']));
  }
}

class Dinleyici {
  const Dinleyici(this.ad, this.adres, this.durum, this.ayrinti);
  final String ad, adres, durum;
  final String? ayrinti;
  bool get acik => durum == 'ok';
  factory Dinleyici.coz(Map<String, dynamic> m) => Dinleyici(metin(m['name']), metin(m['addr']), metin(m['status']), metinYa(m['detail']));
}

class Dugum {
  const Dugum({
    required this.ad,
    required this.rol,
    required this.surum,
    required this.goSurumu,
    required this.isletim,
    required this.cpu,
    required this.surecSuresi,
    required this.sunucuSuresi,
    required this.yuk,
    required this.bellekToplam,
    required this.bellekBos,
    required this.surecBellek,
    required this.goroutine,
    required this.kuyruk,
    required this.havuz,
    required this.depo,
    required this.spool,
    required this.dinleyiciler,
  });
  final String ad, rol, surum, goSurumu, isletim;
  final int cpu, bellekToplam, bellekBos, surecBellek, goroutine, kuyruk;
  final double surecSuresi, sunucuSuresi;
  final List<double>? yuk;
  final Map<String, dynamic> havuz;
  final Disk? depo, spool;
  final List<Dinleyici> dinleyiciler;

  int get bellekKullanilan => bellekToplam - bellekBos;

  factory Dugum.coz(Map<String, dynamic> m) {
    final diskler = harita(m['disks']);
    final y = m['load_avg'];
    return Dugum(
      ad: metin(m['hostname']),
      rol: metin(m['role']),
      surum: metin(m['version']),
      goSurumu: metin(m['go_version']),
      isletim: metin(m['os']),
      cpu: tamsayi(m['cpus']),
      surecSuresi: ondalik(m['process_uptime']),
      sunucuSuresi: ondalik(m['host_uptime']),
      yuk: y is List ? [for (final x in y) ondalik(x)] : null,
      bellekToplam: tamsayi(m['mem_total']),
      bellekBos: tamsayi(m['mem_available']),
      surecBellek: tamsayi(m['process_rss']),
      goroutine: tamsayi(m['goroutines']),
      kuyruk: tamsayi(m['queue_depth'], -1),
      havuz: harita(m['db_pool']),
      depo: Disk.coz(diskler['store']),
      spool: Disk.coz(diskler['spool']),
      dinleyiciler: haritalar(m['listeners']).map(Dinleyici.coz).toList(),
    );
  }
}

/// Web'deki süre biçimi: "3 g 4 sa", "5 sa 2 dk", "12 dk".
String dugumSuresi(double sn) {
  final s = sn.floor();
  final g = s ~/ 86400, sa = (s % 86400) ~/ 3600, dk = (s % 3600) ~/ 60;
  if (g > 0) return '$g g $sa sa';
  if (sa > 0) return '$sa sa $dk dk';
  return '$dk dk';
}

class DugumKarti extends StatelessWidget {
  const DugumKarti({super.key, required this.dugum});
  final Dugum dugum;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = dugum;
    final h = d.havuz;
    final bilgiler = Column(
      children: [
        BilgiSatiri('Süreç çalışma süresi', dugumSuresi(d.surecSuresi)),
        BilgiSatiri('Sunucu çalışma süresi', dugumSuresi(d.sunucuSuresi)),
        BilgiSatiri('CPU', '${d.cpu} çekirdek'),
        BilgiSatiri('Yük (1/5/15 dk)', d.yuk == null ? '—' : d.yuk!.map((x) => x.toStringAsFixed(2)).join(' / ')),
        BilgiSatiri('Kuyruk', d.kuyruk < 0 ? '—' : sayiYaz(d.kuyruk)),
        BilgiSatiri('DB havuzu', '${tamsayi(h['acquired'])} kullanımda / ${tamsayi(h['total'])} açık / ${tamsayi(h['max'])} en fazla'),
      ],
    );
    Widget cubuk(String etiket, String deger, int kullanilan, int toplam) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(etiket, style: TextStyle(color: r.silik, fontSize: 13))),
              Text(deger, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          if (toplam > 0) KullanimCubugu(kullanilan: kullanilan, toplam: toplam, yazi: false),
        ],
      ),
    );
    final kaynaklar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cubuk('Bellek', '${boyutYaz(d.bellekKullanilan)} / ${boyutYaz(d.bellekToplam)}', d.bellekKullanilan, d.bellekToplam),
        for (final (ad, disk) in [('ileti deposu', d.depo), ('spool', d.spool)])
          cubuk('Disk ($ad)', disk == null ? '—' : '${boyutYaz(disk.bos)} boş', disk?.kullanilan ?? 0, disk?.toplam ?? 0),
        Text('bogamaild: ${boyutYaz(d.surecBellek)} ayrılmış · ${sayiYaz(d.goroutine)} goroutine', style: TextStyle(color: r.silik, fontSize: 12)),
      ],
    );
    final dinleyiciler = Column(
      children: [
        for (final l in d.dinleyiciler)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                DurumNoktasi(l.acik ? Marka.zumrut : r.silik.withValues(alpha: .5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.ad, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                ),
                if (l.acik)
                  Text(l.adres, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: r.silik))
                else
                  Rozet(l.ayrinti ?? 'kapalı', renk: r.silik),
              ],
            ),
          ),
      ],
    );
    return BolumKarti(
      ikon: Simgeler.dns,
      baslik: d.ad,
      altBaslik: '${d.rol} · bogamaild ${d.surum} · ${d.goSurumu} · ${d.isletim}',
      child: LayoutBuilder(
        builder: (c, k) {
          if (k.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: bilgiler),
                const SizedBox(width: 24),
                Expanded(child: kaynaklar),
                const SizedBox(width: 24),
                Expanded(child: dinleyiciler),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [bilgiler, const Divider(height: 24), kaynaklar, const Divider(height: 24), dinleyiciler],
          );
        },
      ),
    );
  }
}
