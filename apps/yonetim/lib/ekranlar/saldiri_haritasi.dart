import 'dart:async';
import 'dart:math' as math;

import 'package:boga_ortak/boga_ortak.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/secimler.dart';
import '../veri/json.dart';
import '../veri/koruma_ulkeler.dart';
import '../ortak/simgeler.dart';
import 'smtp_trafigi.dart' show SiraliListeKarti;

const _turEtiketi = {
  'spam': 'Spam',
  'virus': 'Virüs',
  'phishing': 'Oltalama bağlantısı',
  'dmarc': 'DMARC hatası',
  'impersonation': 'Kimlik taklidi',
  'qr': 'QR oltalama',
  'sandbox': 'Zararlı ek',
  'blocked': 'Engelli ek',
  'greylist': 'Greylist (tekrar denemedi)',
};

/// Sabit sıra: bir tür her filtrede aynı rengi korur.
const _turSirasi = ['spam', 'phishing', 'impersonation', 'dmarc', 'qr', 'sandbox', 'virus', 'blocked', 'greylist'];
const _turRengi = {
  'spam': Color(0xFF0EA5E9),
  'phishing': Color(0xFFF97316),
  'impersonation': Color(0xFF8B5CF6),
  'dmarc': Color(0xFFFBBF24),
  'qr': Color(0xFFEC4899),
  'sandbox': Color(0xFFDC2626),
  'virus': Color(0xFF881337),
  'blocked': Color(0xFF0D9488),
  'greylist': Color(0xFF94A3B8),
};

/// Saldırı Haritası: gelen postadaki saldırıların kaynağı. Coğrafi harita yerine (web ile aynı) ülke yoğunluk ızgarası,
/// tür, ASN, IP ve hedef sıralamaları ve son saldırılar listesi gösterilir.
class SaldiriHaritasiEkrani extends StatefulWidget {
  const SaldiriHaritasiEkrani({super.key});
  @override
  State<SaldiriHaritasiEkrani> createState() => _SaldiriHaritasiEkraniState();
}

class _SaldiriHaritasiEkraniState extends State<SaldiriHaritasiEkrani> {
  int _saat = 24;
  String _tur = '', _ulke = '';
  String? _orgId, _orgAdi;
  final _yukleme = GlobalKey<TekYuklemeState<Map<String, dynamic>>>();
  Timer? _zamanlayici;

  @override
  void initState() {
    super.initState();
    // Web ile aynı: 15 saniyede bir yenilenir.
    _zamanlayici = Timer.periodic(const Duration(seconds: 15), (_) => _yukleme.currentState?.yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  void _degistir(VoidCallback f) {
    setState(f);
    _yukleme.currentState?.yenile();
  }

  Future<void> _musteriFiltresi() async {
    if (_orgId != null) {
      _degistir(() => _orgId = _orgAdi = null);
      return;
    }
    final o = await musteriSec(context);
    if (o != null) {
      _degistir(() {
        _orgId = o.id;
        _orgAdi = o.ad;
      });
    }
  }

  Future<void> _turSec() async {
    final v = await secimYap<String>(
      context,
      baslik: 'Saldırı türü',
      secili: _tur,
      secenekler: [('', 'Tüm saldırı türleri', null), for (final k in _turSirasi) (k, _turEtiketi[k]!, null)],
    );
    if (v != null) _degistir(() => _tur = v);
  }

  @override
  Widget build(BuildContext context) {
    return Iskelet(
      baslik: 'Saldırı Haritası',
      alt: Uyg.musteri ? 'Kullanıcılarınıza gelen zararlı iletilerin kaynağı' : 'Gelen postadaki saldırıların kaynağı',
      yenile: () => _yukleme.currentState?.yenile(),
      govde: TekYukleme<Map<String, dynamic>>(
        key: _yukleme,
        getir: () async => harita(
          await Uyg.api.get(
            '/api/v1/attacks',
            q: {'hours': '$_saat', if (_tur.isNotEmpty) 'kind': _tur, if (_ulke.isNotEmpty) 'country': _ulke, 'organization_id': ?_orgId},
          ),
        ),
        icerik: _icerik,
      ),
    );
  }

  Widget _filtreler() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SecimCipleri<int>(
        secenekler: const [(1, 'Son 1 saat'), (24, 'Son 24 saat'), (72, 'Son 3 gün'), (168, 'Son 7 gün'), (720, 'Son 30 gün')],
        secili: _saat,
        secildi: (v) => _degistir(() => _saat = v),
      ),
      InputChip(
        avatar: const Icon(Simgeler.category, size: 17),
        label: Text(_tur.isEmpty ? 'Tüm saldırı türleri' : _turEtiketi[_tur] ?? _tur),
        selected: _tur.isNotEmpty,
        showCheckmark: false,
        onPressed: _turSec,
        onDeleted: _tur.isEmpty ? null : () => _degistir(() => _tur = ''),
        deleteButtonTooltipMessage: 'Filtreyi kaldır',
      ),
      if (!Uyg.musteri)
        InputChip(
          avatar: const Icon(Simgeler.business, size: 17),
          label: Text(_orgAdi ?? 'Tüm müşteriler'),
          selected: _orgId != null,
          showCheckmark: false,
          onPressed: _musteriFiltresi,
          onDeleted: _orgId == null ? null : _musteriFiltresi,
          deleteButtonTooltipMessage: 'Filtreyi kaldır',
        ),
      if (_ulke.isNotEmpty)
        InputChip(
          avatar: const Icon(Simgeler.public, size: 17),
          label: Text(ulkeAdi(_ulke)),
          selected: true,
          showCheckmark: false,
          onDeleted: () => _degistir(() => _ulke = ''),
          deleteButtonTooltipMessage: 'Ülke filtresini kaldır',
        ),
    ],
  );

  Widget _icerik(BuildContext c, Map<String, dynamic> d, Future<void> Function() yenile) {
    final r = c.r;
    final toplam = tamsayi(d['total']);
    final ulkeler = haritalar(d['by_country']);
    final turler = haritalar(d['by_kind']);
    if (toplam == 0) {
      return IcerikListesi(
        children: [
          const SizedBox(height: 8),
          _filtreler(),
          const SizedBox(height: 48),
          Icon(Simgeler.verifiedUser, size: 44, color: r.silik),
          const SizedBox(height: 12),
          Text(
            'Saldırı kaydı yok',
            textAlign: TextAlign.center,
            style: gosterim(17, agirlik: FontWeight.w600, renk: r.metin),
          ),
          const SizedBox(height: 4),
          Text(
            'Seçilen aralıkta zararlı ileti veya tekrar denemeyen greylist kaydı yok.',
            textAlign: TextAlign.center,
            style: TextStyle(color: r.soluk),
          ),
        ],
      );
    }
    return IcerikListesi(
      children: [
        const SizedBox(height: 8),
        _filtreler(),
        const SizedBox(height: 12),
        Izgara(
          enAz: 200,
          children: [
            KpiKarti(ikon: Simgeler.gppBad, etiket: 'Toplam', deger: sayiYaz(toplam), renk: Marka.gul),
            KpiKarti(ikon: Simgeler.public, etiket: 'Ülke', deger: sayiYaz(ulkeler.length), renk: Marka.mavi),
            KpiKarti(
              ikon: Simgeler.category,
              etiket: 'En çok',
              deger: turler.isEmpty ? '—' : _turEtiketi[metin(turler.first['key'])] ?? metin(turler.first['key']),
              renk: Marka.kehribar,
            ),
            KpiKarti(ikon: Simgeler.flag, etiket: 'İlk ülke', deger: ulkeler.isEmpty ? '—' : ulkeAdi(metin(ulkeler.first['key'])), renk: Marka.lavanta),
          ],
        ),
        const SizedBox(height: 16),
        _zamanCizelgesi(c, d),
        const SizedBox(height: 16),
        Izgara(enAz: 440, bosluk: 16, children: [_ulkeIsisi(c, ulkeler, toplam), _turKarti(c, turler)]),
        const SizedBox(height: 16),
        Izgara(
          enAz: 320,
          bosluk: 16,
          children: [
            SiraliListeKarti(baslik: 'Kaynak ağlar (ASN)', ikon: Simgeler.hub, satirlar: haritalar(d['top_asn']), onEk: 'AS'),
            SiraliListeKarti(baslik: 'Kaynak IP\'ler', ikon: Simgeler.lan, satirlar: haritalar(d['top_ip']), mono: true),
            SiraliListeKarti(baslik: 'En çok hedef alınanlar', ikon: Simgeler.personPin, satirlar: haritalar(d['top_target'])),
          ],
        ),
        const SizedBox(height: 16),
        _sonSaldirilar(c, haritalar(d['recent'])),
      ],
    );
  }

  Widget _turKarti(BuildContext c, List<Map<String, dynamic>> turler) {
    final r = c.r;
    final tepe = turler.isEmpty ? 1 : math.max(1, tamsayi(turler.first['count']));
    return BolumKarti(
      baslik: 'Saldırı türleri',
      ikon: Simgeler.category,
      altBaslik: 'Bir türe dokunarak filtreleyin.',
      child: turler.isEmpty
          ? Text('Veri yok.', style: TextStyle(color: r.soluk))
          : Column(
              children: [
                for (final k in turler)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _degistir(() => _tur = _tur == metin(k['key']) ? '' : metin(k['key'])),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(color: _turRengi[metin(k['key'])] ?? r.silik, borderRadius: BorderRadius.circular(3)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _turEtiketi[metin(k['key'])] ?? metin(k['key']),
                                  style: TextStyle(fontWeight: _tur == metin(k['key']) ? FontWeight.w600 : FontWeight.w500),
                                ),
                              ),
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
                              color: (_turRengi[metin(k['key'])] ?? r.vurgu).withValues(alpha: .8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _ulkeIsisi(BuildContext c, List<Map<String, dynamic>> ulkeler, int toplam) {
    final r = c.r;
    final tepe = ulkeler.isEmpty ? 1 : math.max(1, tamsayi(ulkeler.first['count']));
    return BolumKarti(
      baslik: 'Ülkelere göre',
      ikon: Simgeler.public,
      altBaslik: 'Renk yoğunluğu saldırı sayısını gösterir (ülke: Team Cymru). Bir ülkeye dokunarak filtreleyin.',
      child: ulkeler.isEmpty
          ? Text('Veri yok.', style: TextStyle(color: r.soluk))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Izgara(
                  enAz: 150,
                  bosluk: 6,
                  children: [
                    for (final u in ulkeler.take(30))
                      Tooltip(
                        message: '${ulkeAdi(metin(u['key']))}: ${tamsayi(u['count'])} (%${(tamsayi(u['count']) / math.max(1, toplam) * 100).round()})',
                        child: Material(
                          color: Color.alphaBlend(Marka.gul.withValues(alpha: (.12 + .88 * tamsayi(u['count']) / tepe) * .35), r.kart),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: _ulke == metin(u['key']) ? r.vurgu : r.kenar, width: _ulke == metin(u['key']) ? 2 : 1),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: metin(u['key']).isEmpty ? null : () => _degistir(() => _ulke = _ulke == metin(u['key']) ? '' : metin(u['key'])),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      metin(u['key']).isEmpty ? 'Bilinmiyor' : '${metin(u['key'])} · ${ulkeAdi(metin(u['key']))}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Text(sayiYaz(tamsayi(u['count'])), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (ulkeler.length > 30)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('+${ulkeler.length - 30} ülke daha', style: TextStyle(color: r.silik, fontSize: 12)),
                  ),
              ],
            ),
    );
  }

  Widget _zamanCizelgesi(BuildContext c, Map<String, dynamic> d) {
    final r = c.r;
    // Web ile aynı kovalama: 24 saate kadar saatlik, daha uzun aralıklarda en çok 24 çubuk.
    final saat = math.max(1, tamsayi(d['hours'], _saat));
    final genislik = saat <= 24 ? 1 : (saat / 24).ceil();
    final n = (saat / genislik).ceil();
    final simdi = DateTime.now();
    final son = DateTime(simdi.year, simdi.month, simdi.day, simdi.hour);
    final bas = son.subtract(Duration(hours: (n - 1) * genislik));
    final kovalar = List.generate(n, (i) => (bas.add(Duration(hours: i * genislik)), <String, int>{}));
    for (final b in haritalar(d['timeline'])) {
      final t = tarihOku(b['hour']);
      if (t == null) continue;
      final i = (t.difference(bas).inMinutes / (genislik * 60)).floor().clamp(0, n - 1);
      harita(b['kinds']).forEach((k, v) => kovalar[i].$2[k] = (kovalar[i].$2[k] ?? 0) + tamsayi(v));
    }
    int toplamOf(Map<String, int> m) => m.values.fold(0, (a, v) => a + v);
    final enCok = kovalar.fold<int>(1, (a, k) => math.max(a, toplamOf(k.$2)));
    final mevcut = _turSirasi.where((k) => kovalar.any((b) => (b.$2[k] ?? 0) > 0)).toList();
    final bicim = DateFormat(genislik == 1 ? 'HH:mm' : 'd MMM', 'tr_TR');
    final tam = DateFormat('d MMM HH:mm', 'tr_TR');
    final adim = (n / 6).ceil().clamp(1, 1000);
    return BolumKarti(
      baslik: 'Zaman çizelgesi',
      ikon: Simgeler.timeline,
      altBaslik: 'Her çubuk ${genislik == 1 ? 'bir saat' : '$genislik saat'}; en yüksek $enCok.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: enCok * 1.1,
                alignment: BarChartAlignment.spaceBetween,
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
                      reservedSize: 34,
                      getTitlesWidget: (v, m) => Text(sayiYaz(v.round()), style: TextStyle(color: r.silik, fontSize: 10.5)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, m) {
                        final i = v.round();
                        if (i < 0 || i >= n || i % adim != 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(bicim.format(kovalar[i].$1), style: TextStyle(color: r.silik, fontSize: 10)),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => Marka.grafit,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (g, gi, rod, ri) {
                      final k = kovalar[g.x];
                      final satirlar = [
                        for (final t in _turSirasi)
                          if ((k.$2[t] ?? 0) > 0) '${_turEtiketi[t]}: ${k.$2[t]}',
                      ];
                      return BarTooltipItem(
                        '${tam.format(k.$1)} · ${toplamOf(k.$2)}${satirlar.isEmpty ? '' : '\n${satirlar.join('\n')}'}',
                        const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (final (i, k) in kovalar.indexed)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: toplamOf(k.$2).toDouble(),
                          width: (300 / n).clamp(2, 14).toDouble(),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                          color: Colors.transparent,
                          rodStackItems: _yigin(k.$2),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final t in mevcut)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _turRengi[t], borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 8),
                    Text(_turEtiketi[t]!, style: TextStyle(color: r.soluk, fontSize: 12)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  static List<BarChartRodStackItem> _yigin(Map<String, int> m) {
    final l = <BarChartRodStackItem>[];
    var y = 0.0;
    for (final t in _turSirasi) {
      final v = (m[t] ?? 0).toDouble();
      if (v <= 0) continue;
      l.add(BarChartRodStackItem(y, y + v, _turRengi[t]!));
      y += v;
    }
    return l;
  }

  Widget _sonSaldirilar(BuildContext c, List<Map<String, dynamic>> l) {
    final r = c.r;
    return BolumKarti(
      baslik: 'Son saldırılar',
      ikon: Simgeler.history,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: l.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Veri yok.', style: TextStyle(color: r.soluk)),
            )
          : Column(
              children: [
                for (final e in l)
                  ListeSatiri(
                    baslik: '${metinYa(e['ip']) ?? '—'} · ${ulkeAdi(metin(e['country']))}',
                    alt: [if (tamsayi(e['asn']) > 0) 'AS${tamsayi(e['asn'])} ${metin(e['as_name'])}'.trim(), tamZaman(tarihOku(e['at']))].join(' · '),
                    alt2: metinYa(e['target']) == null ? null : '→ ${metin(e['target'])}',
                    sag: Rozet(_turEtiketi[metin(e['kind'])] ?? metin(e['kind']), renk: _turRengi[metin(e['kind'])] ?? Marka.mavi),
                  ),
              ],
            ),
    );
  }
}
