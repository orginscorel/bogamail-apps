import 'dart:async';
import 'dart:math' as math;

import 'package:boga_ortak/boga_ortak.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import '../ortak/simgeler.dart';

const _dinleyiciEtiketi = {'mx': 'MX (25)', 'submission': 'Gönderim (587)', 'submissions': 'Gönderim TLS (465)'};

String _oran(int a, int b) => b > 0 ? '%${(a / b * 100).round()}' : '—';

/// SMTP Trafiği (yalnızca platform yöneticisi): bağlantılar, TLS, AUTH hataları, en çok HELO/IP/ASN, yanıt kodları.
class SmtpTrafigiEkrani extends StatefulWidget {
  const SmtpTrafigiEkrani({super.key});
  @override
  State<SmtpTrafigiEkrani> createState() => _SmtpTrafigiEkraniState();
}

class _SmtpTrafigiEkraniState extends State<SmtpTrafigiEkrani> {
  int _saat = 24;
  final _yukleme = GlobalKey<TekYuklemeState<Map<String, dynamic>>>();
  Timer? _zamanlayici;

  @override
  void initState() {
    super.initState();
    // Web ile aynı: 30 saniyede bir yenilenir.
    _zamanlayici = Timer.periodic(const Duration(seconds: 30), (_) => _yukleme.currentState?.yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi) {
      return const Iskelet(baslik: 'SMTP Trafiği', govde: Kapali('Bu bölüm yalnızca platform yöneticilerine açıktır.'));
    }
    return Iskelet(
      baslik: 'SMTP Trafiği',
      alt: 'İleti içeriği tutulmaz; adresler maskelenir',
      yenile: () => _yukleme.currentState?.yenile(),
      govde: TekYukleme<Map<String, dynamic>>(
        key: _yukleme,
        getir: () async => harita(await Uyg.api.get('/api/v1/smtp-traffic', q: {'hours': '$_saat'})),
        icerik: _icerik,
      ),
    );
  }

  Widget _icerik(BuildContext c, Map<String, dynamic> d, Future<void> Function() yenile) {
    final dinleyiciler = haritalar(d['listeners']);
    int topla(String k) => dinleyiciler.fold(0, (a, l) => a + tamsayi(l[k]));
    final baglanti = topla('connections'), tls = topla('tls'), authHata = topla('auth_fail'), authOk = topla('auth_ok');
    final tepe = dinleyiciler.fold(0, (a, l) => math.max(a, tamsayi(l['peak_per_minute'])));
    final gelen = tamsayi(d['inbound_messages']);
    final r = c.r;
    final sinif = haritalar(d['our_classes']).map((k) => '${metin(k['key'])}: ${tamsayi(k['count'])}').join(' · ');
    final uzakSunucular = haritalar(d['remote_hosts']).take(5).map((k) => '${metin(k['key'])} (${tamsayi(k['count'])})').join(' · ');
    return IcerikListesi(
      children: [
        const SizedBox(height: 8),
        SecimCipleri<int>(
          secenekler: const [(1, 'Son 1 saat'), (6, 'Son 6 saat'), (24, 'Son 24 saat'), (168, 'Son 7 gün'), (720, 'Son 30 gün')],
          secili: _saat,
          secildi: (v) {
            setState(() => _saat = v);
            yenile();
          },
        ),
        const SizedBox(height: 12),
        Izgara(
          enAz: 220,
          children: [
            KpiKarti(ikon: Simgeler.cable, etiket: 'Bağlantı', deger: sayiYaz(baglanti), alt: 'dakikada en çok $tepe'),
            KpiKarti(
              ikon: Simgeler.lockOutline,
              etiket: 'TLS oranı (bağlantı)',
              deger: _oran(tls, baglanti),
              alt: 'gelen iletilerde ${_oran(tamsayi(d['inbound_tls_messages']), gelen)}',
              renk: Marka.zumrut,
            ),
            KpiKarti(
              ikon: Simgeler.keyOff,
              etiket: 'AUTH hatası',
              deger: sayiYaz(authHata),
              alt: 'başarılı ${sayiYaz(authOk)}',
              renk: authHata > 0 ? Marka.kehribar : null,
            ),
            KpiKarti(ikon: Simgeler.moveToInbox, etiket: 'Gelen ileti', deger: sayiYaz(gelen), alt: 'MX üzerinden işlenen', renk: Marka.mavi),
          ],
        ),
        const SizedBox(height: 16),
        _seriKarti(c, d),
        const SizedBox(height: 16),
        BolumKarti(
          baslik: 'Dinleyiciler',
          ikon: Simgeler.settingsInputAntenna,
          child: dinleyiciler.isEmpty
              ? Text('Bu aralıkta bağlantı kaydı yok (sayaçlar 30 saniyede bir yazılır).', style: TextStyle(color: r.soluk))
              : Column(
                  children: [
                    for (final l in dinleyiciler)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_dinleyiciEtiketi[metin(l['listener'])] ?? metin(l['listener']), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${sayiYaz(tamsayi(l['connections']))} bağlantı · TLS ${_oran(tamsayi(l['tls']), tamsayi(l['connections']))} · '
                          'işlem yapmadan kapanan ${sayiYaz(tamsayi(l['no_mail']))}'
                          '${metin(l['listener']) != 'mx' ? ' · AUTH ${tamsayi(l['auth_ok'])} başarılı / ${tamsayi(l['auth_fail'])} hatalı' : ''}',
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Izgara(
          enAz: 320,
          bosluk: 16,
          children: [
            SiraliListeKarti(baslik: 'En çok görülen HELO', ikon: Simgeler.wavingHand, satirlar: haritalar(d['top_helo']), mono: true),
            SiraliListeKarti(baslik: 'En çok bağlanan IP\'ler', ikon: Simgeler.lan, satirlar: haritalar(d['top_ip']), mono: true),
            SiraliListeKarti(baslik: 'En çok bağlanan ağlar (ASN)', ikon: Simgeler.hub, satirlar: haritalar(d['top_asn']), onEk: 'AS'),
          ],
        ),
        const SizedBox(height: 16),
        Izgara(
          enAz: 420,
          bosluk: 16,
          children: [
            BolumKarti(
              baslik: 'Verdiğimiz yanıtlar (gelen)',
              ikon: Simgeler.callReceived,
              altBaslik: sinif.isEmpty ? 'Veri yok' : sinif,
              child: KodListesi(satirlar: haritalar(d['our_codes'])),
            ),
            BolumKarti(
              baslik: 'Karşı sunucu yanıtları (giden)',
              ikon: Simgeler.callMade,
              altBaslik: uzakSunucular.isEmpty ? 'Veri yok' : uzakSunucular,
              child: KodListesi(satirlar: haritalar(d['remote_codes'])),
            ),
          ],
        ),
      ],
    );
  }

  Widget _seriKarti(BuildContext c, Map<String, dynamic> d) {
    final r = c.r;
    final kova = math.max(1, tamsayi(d['bucket_minutes'], 1));
    final noktalar = [
      for (final p in haritalar(d['series']))
        if (tarihOku(p['t']) != null) (tarihOku(p['t'])!, p),
    ];
    double dk(Object? v) => tamsayi(v) / kova;
    var enCok = 1.0;
    for (final (_, p) in noktalar) {
      enCok = math.max(enCok, dk(p['mx']) + dk(p['submission']));
    }
    final bicim = DateFormat(_saat > 48 ? 'd MMM' : 'HH:mm', 'tr_TR');
    final tam = DateFormat('d MMM HH:mm', 'tr_TR');
    final t0 = noktalar.isEmpty ? 0 : noktalar.first.$1.millisecondsSinceEpoch;
    double x(DateTime t) => (t.millisecondsSinceEpoch - t0) / 60000;
    LineChartBarData seri(Color renk, double Function(Map<String, dynamic>) f) => LineChartBarData(
      spots: [for (final (t, p) in noktalar) FlSpot(x(t), f(p))],
      color: renk,
      barWidth: 2,
      isCurved: true,
      curveSmoothness: .15,
      preventCurveOverShooting: true,
      dotData: const FlDotData(show: false),
    );
    return BolumKarti(
      baslik: 'Dakikadaki bağlantı',
      ikon: Simgeler.showChart,
      altBaslik:
          'Her nokta $kova dakikanın ortalaması; en yüksek ${enCok.toStringAsFixed(1).replaceAll('.', ',')}/dk.'
          '${noktalar.isNotEmpty ? ' ${tamZaman(noktalar.first.$1)} – ${tamZaman(noktalar.last.$1)}' : ''}',
      child: noktalar.length < 2
          ? Text('Grafik için yeterli veri yok.', style: TextStyle(color: r.soluk))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: enCok * 1.1,
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(color: r.kenar, strokeWidth: 1, dashArray: const [4, 4]),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            getTitlesWidget: (v, m) => Text(v.toStringAsFixed(v < 10 ? 1 : 0), style: TextStyle(color: r.silik, fontSize: 10.5)),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: math.max(1, x(noktalar.last.$1) / 5),
                            getTitlesWidget: (v, m) => Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                bicim.format(DateTime.fromMillisecondsSinceEpoch(t0 + (v * 60000).round())),
                                style: TextStyle(color: r.silik, fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => Marka.grafit,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItems: (l) => [
                            for (final (j, n) in l.indexed)
                              LineTooltipItem(
                                '${j == 0 ? '${tam.format(DateTime.fromMillisecondsSinceEpoch(t0 + (n.x * 60000).round()))}\n' : ''}'
                                '${const ['Toplam', 'Gönderim', 'AUTH hatası'][n.barIndex]}: ${n.y.toStringAsFixed(1)}/dk',
                                TextStyle(color: n.bar.color, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ),
                      lineBarsData: [
                        seri(Marka.gok, (p) => dk(p['mx']) + dk(p['submission'])),
                        seri(Marka.lavanta, (p) => dk(p['submission'])),
                        seri(Marka.gul, (p) => dk(p['auth_fail'])),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  children: [
                    for (final (renk, ad) in const [(Marka.gok, 'Toplam'), (Marka.lavanta, 'Gönderim (587/465)'), (Marka.gul, 'AUTH hatası')])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 14, height: 3, color: renk),
                          const SizedBox(width: 8),
                          Text(ad, style: TextStyle(color: r.soluk, fontSize: 12)),
                        ],
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Sıralı anahtar–sayı listesi ({key, label?, count}) ve oransal çubuk.
class SiraliListeKarti extends StatelessWidget {
  const SiraliListeKarti({super.key, required this.baslik, required this.satirlar, this.ikon, this.mono = false, this.onEk = '', this.enFazla = 15});
  final String baslik;
  final IconData? ikon;
  final List<Map<String, dynamic>> satirlar;
  final bool mono;
  final String onEk;
  final int enFazla;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final tepe = satirlar.isEmpty ? 1 : math.max(1, tamsayi(satirlar.first['count']));
    return BolumKarti(
      baslik: baslik,
      ikon: ikon,
      child: satirlar.isEmpty
          ? Text('Veri yok.', style: TextStyle(color: r.soluk))
          : Column(
              children: [
                for (final k in satirlar.take(enFazla))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '$onEk${metin(k['key'])}',
                                      style: TextStyle(fontFamily: mono ? 'monospace' : null, fontSize: mono ? 12 : 13.5),
                                    ),
                                    if (metinYa(k['label']) != null)
                                      TextSpan(
                                        text: '  ${metin(k['label'])}',
                                        style: TextStyle(color: r.silik, fontSize: 12.5),
                                      ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(sayiYaz(tamsayi(k['count'])), style: TextStyle(color: r.soluk, fontSize: 12.5)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: tamsayi(k['count']) / tepe,
                            minHeight: 4,
                            backgroundColor: r.ic,
                            color: r.vurgu.withValues(alpha: .7),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// SMTP yanıt kodu listesi: 2xx yeşil, 4xx kehribar, 5xx kırmızı.
class KodListesi extends StatelessWidget {
  const KodListesi({super.key, required this.satirlar});
  final List<Map<String, dynamic>> satirlar;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (satirlar.isEmpty) return Text('Veri yok.', style: TextStyle(color: r.soluk));
    return Column(
      children: [
        for (final (i, k) in satirlar.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: i == 0 ? null : Border(top: BorderSide(color: r.kenar)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metin(k['key']),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: metin(k['key']).startsWith('5') ? Marka.gul : (metin(k['key']).startsWith('4') ? Marka.kehribar : Marka.zumrut),
                        ),
                      ),
                      if (metinYa(k['label']) != null)
                        Text(
                          metin(k['label']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: r.silik, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(sayiYaz(tamsayi(k['count'])), style: TextStyle(color: r.soluk, fontSize: 12.5)),
              ],
            ),
          ),
      ],
    );
  }
}
