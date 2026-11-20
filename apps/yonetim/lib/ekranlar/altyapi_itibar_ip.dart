// İtibar ekranı: IP itibar puanı, öneriler ve IP sağlık kartları (web: components/admin/reputation/ip-section.tsx).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/json.dart';
import 'taklit_islemleri.dart';
import '../ortak/simgeler.dart';

const _kullanimMetinleri = {'shared': 'Paylaşımlı', 'dedicated': 'Müşteriye özel', 'pool': 'IP havuzu', 'plan': 'Paket IP\'si', 'idle': 'Kullanılmıyor'};
const dereceMetinleri = {'iyi': 'İyi', 'orta': 'Orta', 'zayif': 'Zayıf', 'kritik': 'Kritik', 'bilinmiyor': 'Bilinmiyor'};

Color dereceRengi(BuildContext c, String d) => switch (d) {
  'iyi' => Marka.zumrut,
  'orta' || 'zayif' => Marka.kehribar,
  'kritik' => Marka.gul,
  _ => c.r.silik,
};

/// Durum simgesi (web: StatusIcon): ok | warn | fail | info | unknown.
class DurumSimgesi extends StatelessWidget {
  const DurumSimgesi(this.durum, {super.key, this.boyut = 16});
  final String durum;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    final (ikon, renk) = switch (durum) {
      'ok' => (Simgeler.checkCircle, Marka.zumrut),
      'warn' => (Simgeler.warningAmber, Marka.kehribar),
      'fail' => (Simgeler.cancel, Marka.gul),
      'info' => (Simgeler.infoOutline, context.r.silik),
      _ => (Simgeler.helpOutline, context.r.silik),
    };
    return Icon(ikon, size: boyut, color: renk);
  }
}

/// Puan halkası (web: ScoreRing).
class PuanHalkasi extends StatelessWidget {
  const PuanHalkasi({super.key, required this.puan, required this.derece, this.boyut = 108});
  final int? puan;
  final String derece;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final v = puan ?? 0;
    final renk = puan == null ? r.silik : (v >= 85 ? Marka.zumrut : (v >= 50 ? Marka.kehribar : Marka.gul));
    return SizedBox(
      width: boyut,
      height: boyut,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(value: v / 100, strokeWidth: 9, color: renk, backgroundColor: r.ic, strokeCap: StrokeCap.round),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(puan == null ? '—' : '$v', style: gosterim(28, agirlik: FontWeight.w600, renk: r.metin)),
                Text(
                  dereceMetinleri[derece] ?? derece,
                  style: TextStyle(color: dereceRengi(context, derece), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// IP itibar puanı ve faktörleri (web: ScoreCard).
class PuanKarti extends StatelessWidget {
  const PuanKarti({super.key, required this.ip, required this.genel});
  final Map<String, dynamic> ip;
  final Map<String, dynamic> genel;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final s = harita(ip['score']);
    final pencere = metin(genel['score_window']);
    final faktorler = haritalar(s['factors']);
    return BolumKarti(
      baslik: 'İtibar puanı · ${metin(ip['address'])}',
      ikon: Simgeler.starOutline,
      altBaslik: 'Ölçülebilen faktörlerin ağırlıklı ortalaması (0–100). Kapsam: %${tamsayi(s['coverage'])}; ölçülemeyen faktörler (gri) puana katılmaz.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PuanHalkasi(puan: tamsayiYa(s['total']), derece: metin(s['grade'], 'bilinmiyor')),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Formül: puan = Σ(faktör puanı) ÷ Σ(ölçülen faktörlerin ağırlığı) × 100. Trafik oranları son '
                      '${pencere == '7d' ? '7 günden' : pencere} ve en az ${tamsayi(genel['min_sample'])} sonuçlanmış teslimden hesaplanır.',
                      style: TextStyle(color: r.metin, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Derece: 85+ İyi · 70–84 Orta · 50–69 Zayıf · <50 Kritik. ${metin(ip['attribution'])}',
                      style: TextStyle(color: r.soluk, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _PuanGecmisi(gecmis: haritalar(ip['history'])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (i, f) in faktorler.indexed) ...[
            if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: DurumSimgesi(metin(f['status']))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metin(f['label']),
                          style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                        Text(metin(f['rule']), style: TextStyle(color: r.silik, fontSize: 11.5)),
                        if (metinYa(f['value']) != null) Text(metin(f['value']), style: TextStyle(color: r.metin, fontSize: 12.5)),
                        if (metinYa(f['fix']) != null) Text(metin(f['fix']), style: TextStyle(color: r.soluk, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        metin(f['status']) == 'unknown' ? '—' : _puanYaz(ondalik(f['points'])),
                        style: TextStyle(color: r.metin, fontWeight: FontWeight.w600),
                      ),
                      Text('/ ${tamsayi(f['weight'])}', style: TextStyle(color: r.silik, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _puanYaz(double p) {
    final s = p.toStringAsFixed(1);
    return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s).replaceAll('.', ',');
  }
}

class _PuanGecmisi extends StatelessWidget {
  const _PuanGecmisi({required this.gecmis});
  final List<Map<String, dynamic>> gecmis;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final n = [
      for (final h in gecmis)
        if (h['score'] is num) tamsayi(h['score']),
    ];
    if (n.length < 2) {
      return Text(
        'Puan geçmişi: saatlik kayıt ${n.isEmpty ? 'henüz yok' : '1 nokta'} (arka plan işi her saat bir kayıt yazar).',
        style: TextStyle(color: r.silik, fontSize: 11.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          height: 40,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 100,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (final (i, v) in n.indexed) FlSpot(i.toDouble(), v.toDouble())],
                  color: r.birincil,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        Text('Puan geçmişi (${n.length} saatlik kayıt): ${n.first} → ${n.last}', style: TextStyle(color: r.silik, fontSize: 11)),
      ],
    );
  }
}

/// Öneriler (web: Recommendations).
class OnerilerKarti extends StatelessWidget {
  const OnerilerKarti({super.key, required this.oneriler});
  final List<Map<String, dynamic>> oneriler;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return BolumKarti(
      baslik: 'Öneriler',
      ikon: Simgeler.lightbulbOutline,
      altBaslik: 'Ölçülen sorunlardan üretilir; önem sırasına göre.',
      child: oneriler.isEmpty
          ? const Row(
              children: [
                Icon(Simgeler.checkCircle, color: Marka.zumrut, size: 18),
                SizedBox(width: 8),
                Text('Ölçülen bir sorun yok.', style: TextStyle(color: Marka.zumrut)),
              ],
            )
          : Column(
              children: [
                for (final o in oneriler)
                  Builder(
                    builder: (c) {
                      final sev = metin(o['severity']);
                      final renk = sev == 'critical' ? Marka.gul : (sev == 'warning' ? Marka.kehribar : r.silik);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: renk.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: renk.withValues(alpha: .35)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              sev == 'critical' ? Simgeler.report : (sev == 'warning' ? Simgeler.warningAmber : Simgeler.infoOutline),
                              color: renk,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    metin(o['title']),
                                    style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(metin(o['detail']), style: TextStyle(color: r.soluk, fontSize: 12.5)),
                                  const SizedBox(height: 2),
                                  Text.rich(
                                    TextSpan(
                                      text: 'Yapılacak: ',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      children: [
                                        TextSpan(
                                          text: metin(o['fix']),
                                          style: const TextStyle(fontWeight: FontWeight.w400),
                                        ),
                                      ],
                                    ),
                                    style: TextStyle(color: r.metin, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

const _blMetin = {'clean': 'temiz', 'listed': 'LİSTEDE', 'refused': 'bilinmiyor (sorgu reddedildi)', 'error': 'bilinmiyor (hata)'};

/// Gönderim IP'sinin canlı DNS sağlığı, kara listeler ve ısınma (web: IPCard).
class IpSaglikKarti extends StatefulWidget {
  const IpSaglikKarti({super.key, required this.ip, required this.denetlendi});
  final Map<String, dynamic> ip;
  final VoidCallback denetlendi;

  @override
  State<IpSaglikKarti> createState() => _IpSaglikKartiState();
}

class _IpSaglikKartiState extends State<IpSaglikKarti> {
  bool _mesgul = false;

  Future<void> _denetle() async {
    setState(() => _mesgul = true);
    try {
      final v = harita(await Uyg.api.post('/api/v1/reputation/ips/${metin(widget.ip['id'])}/check'));
      bildir(
        mantik(v['dnsbl_queried']) ? 'Denetim tamamlandı (kara listeler sorgulandı)' : 'PTR/HELO yenilendi; kara listeler 30 dk önbellekten',
        tur: MesajTur.basari,
      );
      widget.denetlendi();
    } catch (e) {
      bildir('Denetim başarısız', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Widget _satir(BuildContext c, bool? ok, String etiket, String deger) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: DurumSimgesi(ok == null ? 'unknown' : (ok ? 'ok' : 'fail'))),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiket,
                style: TextStyle(color: c.r.metin, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Text(deger, style: TextStyle(color: c.r.soluk, fontSize: 12.5)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _dns(BuildContext c, Map<String, dynamic>? rap) {
    final r = c.r;
    final baslik = Text(
      'Ters DNS ve HELO',
      style: TextStyle(color: r.metin, fontWeight: FontWeight.w600),
    );
    if (rap == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          baslik,
          const SizedBox(height: 4),
          Text('Veri yok; "Denetle" ile canlı sorgu yapın.', style: TextStyle(color: r.soluk, fontSize: 13)),
        ],
      );
    }
    final ptr = metinler(rap['ptr']);
    final ptrHata = metinYa(rap['ptr_error']);
    final helo = metin(rap['helo_host']);
    final heloAdr = metinler(rap['helo_addrs']);
    final fcrdns = mantik(rap['fcrdns']);
    final eslesme = mantik(rap['ptr_matches_hostname']);
    final heloIp = mantik(rap['helo_matches_ip']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        baslik,
        _satir(
          c,
          ptr.isNotEmpty ? true : (ptrHata != null ? null : false),
          'PTR (ters kayıt)',
          ptr.isNotEmpty ? ptr.join(', ') : (ptrHata != null ? 'Sorgu başarısız: $ptrHata' : 'PTR kaydı yok'),
        ),
        _satir(
          c,
          ptr.isNotEmpty ? fcrdns : false,
          'FCrDNS (ileri doğrulama)',
          fcrdns ? 'PTR adı bu IP\'ye geri çözülüyor' : (ptr.isNotEmpty ? '${ptr.first} bu IP\'ye çözülmüyor' : 'PTR olmadan doğrulanamaz'),
        ),
        _satir(c, eslesme, 'PTR = HELO adı', eslesme ? 'PTR, $helo ile aynı' : 'HELO: ${helo.isEmpty ? '—' : helo}'),
        _satir(
          c,
          helo.isNotEmpty ? heloIp : null,
          'HELO adı A kaydı',
          '$helo → ${heloAdr.isNotEmpty ? heloAdr.join(', ') : (metinYa(rap['helo_error']) ?? 'kayıt yok')}${!heloIp && heloAdr.isNotEmpty ? ' (bu IP değil)' : ''}',
        ),
      ],
    );
  }

  Widget _karaListe(BuildContext c, Map<String, dynamic>? rap) {
    final r = c.r;
    final ip = widget.ip;
    final zonlar = harita(ip['zones']);
    final dnsbl = haritalar(rap?['dnsbl']);
    final listede = tamsayi(rap?['listed']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Kara listeler (DNSBL)',
              style: TextStyle(color: r.metin, fontWeight: FontWeight.w600),
            ),
            if (rap?['dnsbl'] is List) Rozet(listede > 0 ? '$listede listede' : 'listede değil', renk: listede > 0 ? Marka.gul : Marka.zumrut),
          ],
        ),
        const SizedBox(height: 8),
        if (dnsbl.isEmpty)
          Text('Henüz sorgulanmadı.', style: TextStyle(color: r.soluk, fontSize: 13))
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: r.kenar),
            ),
            child: Column(
              children: [
                for (final (i, d) in dnsbl.indexed) ...[
                  if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
                  Builder(
                    builder: (c) {
                      final zon = metin(d['zone']);
                      final z = harita(zonlar[zon]);
                      final durum = metin(d['status']);
                      final kodlar = metinler(d['codes']);
                      final aciklama = metinYa(d['meaning']) ?? (durum == 'listed' ? metinYa(d['detail']) : null);
                      final kaldir = metinYa(z['delist']);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${metinYa(z['name']) ?? zon}${mantik(z['major']) ? '  · BÜYÜK' : ''}',
                                        style: TextStyle(color: r.metin, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        zon,
                                        style: TextStyle(color: r.silik, fontSize: 11, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _blMetin[durum] ?? durum,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: durum == 'listed' ? FontWeight.w600 : FontWeight.w500,
                                    color: switch (durum) {
                                      'clean' => Marka.zumrut,
                                      'listed' => Marka.gul,
                                      'error' => Marka.kehribar,
                                      _ => r.silik,
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if (aciklama != null)
                              Text('${kodlar.isNotEmpty ? '${kodlar.join(', ')} · ' : ''}$aciklama', style: TextStyle(color: r.soluk, fontSize: 11.5)),
                            if (durum == 'listed' && kaldir != null)
                              TextButton.icon(
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                onPressed: () => adresAc(Uri.parse(kaldir)),
                                icon: const Icon(SimgelerKalin.openInNew, size: 14),
                                label: const Text('Kaldırma sayfası', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Sorgular sistem DNS çözücüsü üzerinden yapılır ve en az 30 dk önbelleğe alınır'
          '${tarihOku(rap?['dnsbl_checked_at']) != null ? ' · son sorgu ${tamZaman(tarihOku(rap?['dnsbl_checked_at']))}' : ''}'
          '${tarihOku(ip['dnsbl_next_at']) != null ? ' · sonraki en erken ${tamZaman(tarihOku(ip['dnsbl_next_at']))}' : ''}. "Bilinmiyor" sonuçlar temiz sayılmaz.',
          style: TextStyle(color: r.silik, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _isinma(BuildContext c) {
    final r = c.r;
    final ip = widget.ip;
    final bugun = tamsayi(ip['sent_today']);
    final sinir = tamsayi(ip['daily_limit']);
    final kullanim = metin(ip['usage']);
    Widget kutu(String e, String d, [Color? renk]) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: r.kenar),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e, style: TextStyle(color: r.soluk, fontSize: 11.5)),
            Text(d, style: gosterim(18, agirlik: FontWeight.w600, renk: renk ?? r.metin)),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Isınma ve hacim',
          style: TextStyle(color: r.metin, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text('Bugün sonuçlanan teslim', style: TextStyle(color: r.soluk, fontSize: 12)),
            ),
            Text('${sayiYaz(bugun)} / ${sinir == 0 ? '∞' : sayiYaz(sinir)}', style: TextStyle(color: r.metin, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        if (sinir > 0) KullanimCubugu(kullanilan: bugun, toplam: sinir, yazi: false) else LinearProgressIndicator(value: 0, backgroundColor: r.ic),
        const SizedBox(height: 4),
        Text(
          'outbound.daily_limit = $sinir (platform ısınma hedefi; bugünkü dış gönderim bu değere ulaşınca yeni dış iletiler geçici olarak ertelenir, 451).'
          '${const {'dedicated', 'pool', 'plan'}.contains(kullanim) ? ' Müşteriye/havuza atanmış IP\'nin kendi ısınma limiti IP Yönetimi bölümündedir.' : ''}',
          style: TextStyle(color: r.silik, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        Row(children: [kutu('Bugün', sayiYaz(bugun)), const SizedBox(width: 8), kutu('Son 7 gün', sayiYaz(tamsayi(ip['sent_7d'])))]),
        if (mantik(ip['per_ip'])) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              kutu('teslim', sayiYaz(tamsayi(ip['delivered_7d'])), Marka.zumrut),
              const SizedBox(width: 8),
              kutu('kalıcı hata', sayiYaz(tamsayi(ip['hard_7d'])), Marka.gul),
              const SizedBox(width: 8),
              kutu('geçici hata', sayiYaz(tamsayi(ip['soft_7d'])), Marka.kehribar),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Sayılar: uzak sunucudan kesin yanıt alınan alıcılar (teslim + kalıcı/süresi dolmuş geri dönme). ${metin(ip['attribution'])}',
          style: TextStyle(color: r.silik, fontSize: 11.5),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ip = widget.ip;
    final rap = ip['report'] is Map ? harita(ip['report']) : null;
    final kullanim = metin(ip['usage'], 'shared');
    final denetim = tarihOku(ip['checked_at']);
    return BolumKarti(
      baslik: metin(ip['address']),
      ikon: Simgeler.lan,
      sag: OutlinedButton.icon(
        onPressed: _mesgul ? null : _denetle,
        icon: _mesgul ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Simgeler.refresh, size: 18),
        label: const Text('Denetle'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!mantik(ip['enabled'], true)) Rozet('devre dışı', renk: r.soluk),
              Rozet(_kullanimMetinleri[kullanim] ?? kullanim, renk: kullanim == 'idle' ? r.soluk : Marka.mor),
              if (mantik(ip['is_default'])) const Rozet('varsayılan çıkış', renk: Marka.mavi),
              if (metinYa(ip['organization_name']) != null) Rozet(metin(ip['organization_name']), renk: r.soluk),
              if (metinYa(ip['plan_name']) != null) Rozet('paket: ${metin(ip['plan_name'])}', renk: r.soluk),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'HELO ${metin(ip['helo_name'])} · ${metin(ip['role']) == 'both' ? 'gelen + giden' : 'giden'} · havuz ${metin(ip['pool'])}'
            '${denetim != null ? ' · son denetim ${goreliZaman(denetim)}' : ' · henüz denetlenmedi'}',
            style: TextStyle(color: r.soluk, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (c, k) {
              final parcalar = [_dns(c, rap), _karaListe(c, rap), _isinma(c)];
              if (k.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, p) in parcalar.indexed) ...[if (i > 0) const SizedBox(height: 16), p],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, p) in parcalar.indexed) ...[if (i > 0) const SizedBox(width: 20), Expanded(child: p)],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
