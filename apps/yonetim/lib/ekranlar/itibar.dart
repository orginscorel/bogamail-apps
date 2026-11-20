import 'package:boga_ortak/boga_ortak.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'altyapi_itibar_ip.dart';
import 'altyapi_ortak.dart';
import '../ortak/simgeler.dart';

/// İtibar (platform ve bayi): IP itibar puanı ve canlı DNS sağlığı (yalnız süper yönetici), teslim istatistikleri,
/// alıcı sağlayıcılar, müşteriler / göndericiler ve alan adı kimlik doğrulaması. web: admin/(panel)/reputation.
/// API: /reputation/overview|delivery|recipient-domains|senders|auth (range=24h|7d|30d), POST /reputation/ips/{id}/check,
/// POST /domains/{id}/dns-check.
class ItibarEkrani extends StatefulWidget {
  const ItibarEkrani({super.key});

  @override
  State<ItibarEkrani> createState() => _ItibarEkraniState();
}

const _donemler = [('24h', '24 saat'), ('7d', '7 gün'), ('30d', '30 gün')];

/// web: pct — yüzde, gereksiz ",0" olmadan.
String yuzdeMetni(Object? v, [int basamak = 1]) {
  if (v is! num) return '—';
  var s = v.toStringAsFixed(basamak);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return '%${s.replaceAll('.', ',')}';
}

Color? _oranRengi(Object? v, double uyari, double kotu) {
  if (v is! num) return null;
  return v >= kotu ? Marka.gul : (v >= uyari ? Marka.kehribar : null);
}

class _ItibarEkraniState extends State<ItibarEkrani> {
  String _donem = '7d';
  int _nesil = 0;

  bool get _platform => Uyg.platformYoneticisi;

  void _yenile() => setState(() => _nesil++);

  @override
  Widget build(BuildContext context) {
    final etiket = _donemler.firstWhere((d) => d.$1 == _donem).$2;
    final anahtar = '$_donem-$_nesil';
    final sekmeler = <(String, Widget)>[
      if (_platform) ('IP sağlığı', _IpSekmesi(key: ValueKey('ip$anahtar'), donem: _donem)),
      ('Teslim', _TeslimSekmesi(key: ValueKey('t$anahtar'), donem: _donem, platform: _platform)),
      ('Alıcı sağlayıcılar', _AliciSekmesi(key: ValueKey('a$anahtar'), donem: _donem)),
      ('Müşteriler ve göndericiler', _GondericiSekmesi(key: ValueKey('g$anahtar'), donem: _donem)),
      ('Kimlik doğrulama', _KimlikSekmesi(key: ValueKey('k$_nesil'))),
    ];
    return DefaultTabController(
      length: sekmeler.length,
      child: Iskelet(
        baslik: 'İtibar',
        alt: 'Gönderim itibarı ve teslim istatistikleri · $etiket',
        yenile: _yenile,
        eylemler: [
          PopupMenuButton<String>(
            tooltip: 'Dönem',
            initialValue: _donem,
            onSelected: (v) => setState(() => _donem = v),
            itemBuilder: (_) => [for (final (k, e) in _donemler) CheckedPopupMenuItem(value: k, checked: k == _donem, child: Text(e))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Simgeler.dateRange, size: 20), const SizedBox(width: 4), Text(etiket)]),
            ),
          ),
        ],
        sekmeler: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final s in sekmeler) Tab(text: s.$1)],
        ),
        govde: TabBarView(children: [for (final s in sekmeler) s.$2]),
      ),
    );
  }
}

// ---- IP sağlığı (süper yönetici) ---------------------------------------------------------------

class _IpSekmesi extends StatelessWidget {
  const _IpSekmesi({super.key, required this.donem});
  final String donem;

  @override
  Widget build(BuildContext context) => TekYukleme<Map<String, dynamic>>(
    getir: () async => harita(await Uyg.api.get('/api/v1/reputation/overview', q: {'range': donem})),
    icerik: (c, o, yenile) {
      final r = c.r;
      final ipler = haritalar(o['ips']);
      final oneriler = haritalar(o['recommendations']);
      final pol = harita(o['policy']);
      final ozet = Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Rozet('giden mod: ${tire(metin(o['outbound_mode']))}', renk: metin(o['outbound_mode']) == 'direct' ? Marka.zumrut : r.soluk),
          Text(
            [
              ipler.length > 1
                  ? 'HELO IP başına · varsayılan çıkış ${tire(metin(o['default_source']))}'
                  : 'HELO: ${ipler.isNotEmpty ? metin(ipler.first['helo_name']) : metin(o['helo_host'])}',
              'günlük ısınma limiti ${tamsayi(pol['daily_limit'])}',
              'alan adı başına ${tamsayi(pol['per_domain_per_minute'])}/dk',
              'geri dönme duraklatma eşiği %${metin(pol['bounce_pause_rate'])}',
              'güncellendi ${tamZaman(tarihOku(o['generated_at']))}',
            ].join(' · '),
            style: TextStyle(color: r.soluk, fontSize: 12),
          ),
        ],
      );
      if (ipler.isEmpty) {
        return IcerikListesi(
          children: [
            ozet,
            const SizedBox(height: 12),
            const SizedBox(
              height: 220,
              child: Durum.bos('Giden IP yok. IP Yönetimi\'nden rolü "giden" veya "gelen + giden" olan bir IP ekleyin.', ikon: Simgeler.starOutline),
            ),
            OnerilerKarti(oneriler: oneriler),
          ],
        );
      }
      return IcerikListesi(
        children: [
          ozet,
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (c, k) {
              final puanlar = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, ip) in ipler.indexed) ...[if (i > 0) const SizedBox(height: 12), PuanKarti(ip: ip, genel: o)],
                ],
              );
              final oner = OnerilerKarti(oneriler: oneriler);
              if (k.maxWidth < 1100) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [puanlar, const SizedBox(height: 12), oner]);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: puanlar),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: oner),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Gönderim IP\'leri', style: gosterim(17, agirlik: FontWeight.w600, renk: r.metin)),
          const SizedBox(height: 8),
          for (final ip in ipler) ...[IpSaglikKarti(ip: ip, denetlendi: yenile), const SizedBox(height: 12)],
        ],
      );
    },
  );
}

// ---- Teslim istatistikleri -----------------------------------------------------------------------

const _seriler = [
  ('delivered', 'Teslim', Marka.zumrut),
  ('deferred_rcpts', 'Ertelenen alıcı', Marka.kehribar),
  ('soft_bounces', 'Süresi dolan', Color(0xFFF08AA0)),
  ('hard_bounces', 'Kalıcı geri dönme', Marka.gul),
  ('refused', 'Politika reddi', Color(0xFF8A90A6)),
];

class _TeslimSekmesi extends StatelessWidget {
  const _TeslimSekmesi({super.key, required this.donem, required this.platform});
  final String donem;
  final bool platform;

  @override
  Widget build(BuildContext context) => TekYukleme<Map<String, dynamic>>(
    getir: () async => harita(await Uyg.api.get('/api/v1/reputation/delivery', q: {'range': donem})),
    icerik: (c, d, _) {
      final r = c.r;
      final t = harita(d['totals']);
      final o = harita(d['rates']);
      final kurallar = haritalar(d['refusal_rules']);
      final sinyal = harita(d['signals']);
      final enCokKural = kurallar.fold<int>(1, (a, x) => tamsayi(x['messages']) > a ? tamsayi(x['messages']) : a);
      return IcerikListesi(
        children: [
          if (!platform)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Bant(
                'IP sağlığı, itibar puanı ve öneriler platform geneli olduğu için yalnızca süper yöneticiye gösterilir. Buradaki istatistikler yalnızca sizin müşterilerinizi kapsar.',
              ),
            ),
          Izgara(
            enAz: 160,
            bosluk: 8,
            children: [
              SayacKutusu(etiket: 'Kuyruğa alınan (dış)', deger: sayiYaz(tamsayi(t['queued'])), ipucu: 'alıcı'),
              SayacKutusu(etiket: 'Teslim edilen', deger: sayiYaz(tamsayi(t['delivered'])), ipucu: 'teslim oranı ${yuzdeMetni(o['delivery_rate'])}'),
              SayacKutusu(
                etiket: 'Ertelenen',
                deger: sayiYaz(tamsayi(t['deferred_rcpts'])),
                ipucu: '${tamsayi(t['deferrals'])} deneme · ${yuzdeMetni(o['deferral_rate'])}',
              ),
              SayacKutusu(
                etiket: 'Kalıcı geri dönme',
                deger: sayiYaz(tamsayi(t['hard_bounces'])),
                ipucu: yuzdeMetni(o['hard_bounce_rate']),
                kotu: ondalik(o['hard_bounce_rate']) > 5,
              ),
              SayacKutusu(etiket: 'Süresi dolan', deger: sayiYaz(tamsayi(t['soft_bounces'])), ipucu: 'yumuşak · ${yuzdeMetni(o['soft_bounce_rate'])}'),
              SayacKutusu(
                etiket: 'Politika reddi',
                deger: sayiYaz(tamsayi(t['refused'])),
                ipucu: '${tamsayi(t['refused_messages'])} ileti · ${yuzdeMetni(o['refusal_rate'])}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TeslimGrafigi(veri: d, donem: donem),
          const SizedBox(height: 12),
          Izgara(
            enAz: 380,
            children: [
              BolumKarti(
                baslik: 'Politika retleri: kural dağılımı',
                ikon: Simgeler.rule,
                altBaslik: 'Giden tarayıcının reddettiği iletiler, tetiklenen kurala göre. Toplu gönderim retleri: ${tamsayi(t['bulk_refused'])} alıcı.',
                child: kurallar.isEmpty
                    ? Text('Bu dönemde politika reddi yok.', style: TextStyle(color: r.soluk))
                    : Column(
                        children: [
                          for (final x in kurallar)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 150,
                                    child: Text(
                                      metin(x['rule']) == 'TARAYICI_YOK' ? 'kural yok (tarayıcı kullanılamadı)' : metin(x['rule']),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: r.metin, fontSize: 12, fontFamily: 'monospace'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: tamsayi(x['messages']) / enCokKural,
                                        minHeight: 8,
                                        backgroundColor: r.ic,
                                        color: r.soluk,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${tamsayi(x['messages'])}', style: TextStyle(color: r.metin, fontSize: 12)),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              BolumKarti(
                baslik: 'Şikâyet benzeri sinyaller',
                ikon: Simgeler.flag,
                altBaslik: 'Bastırma listesine bu dönemde eklenen kayıtlar.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SayacKutusu(etiket: 'Şikâyet', deger: sayiYaz(tamsayi(sinyal['complaints']))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SayacKutusu(etiket: 'Kalıcı hata', deger: sayiYaz(tamsayi(sinyal['hard_bounce_suppressions']))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SayacKutusu(etiket: 'Abonelikten çıkma', deger: sayiYaz(tamsayi(sinyal['unsubscribes']))),
                        ),
                      ],
                    ),
                    if (metinYa(sinyal['fbl']) != null) ...[
                      const SizedBox(height: 8),
                      Text('${metin(sinyal['fbl'])}.', style: TextStyle(color: r.silik, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tanımlar: Teslim = uzak sunucu 2xx · Kalıcı geri dönme = 5xx yanıt · Süresi dolan = yeniden denemeler sonunda vazgeçilen (4.x.x) · '
            'Ertelenen = en az bir 4xx alan alıcı · Politika reddi = giden içerik/güvenlik denetiminin gönderimi reddettiği alıcı. '
            'Dış gönderim kapalıyken yazılan ertelemeler sayılmaz.',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
        ],
      );
    },
  );
}

class _TeslimGrafigi extends StatefulWidget {
  const _TeslimGrafigi({required this.veri, required this.donem});
  final Map<String, dynamic> veri;
  final String donem;

  @override
  State<_TeslimGrafigi> createState() => _TeslimGrafigiState();
}

class _TeslimGrafigiState extends State<_TeslimGrafigi> {
  bool _tablo = false;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final seri = haritalar(widget.veri['series']);
    final saat = tamsayi(widget.veri['bucket_seconds'], 3600) / 3600;
    final bicim = DateFormat(widget.donem == '30d' ? 'd MMM' : 'd MMM HH:mm', 'tr_TR');
    String etiket(Map<String, dynamic> b) {
      final at = tarihOku(b['at']);
      return at == null ? '' : bicim.format(at);
    }

    var enCok = 1.0;
    for (final b in seri) {
      final t = _seriler.fold<int>(0, (a, s) => a + tamsayi(b[s.$1]));
      if (t > enCok) enCok = t.toDouble();
    }
    return BolumKarti(
      baslik: 'Teslim sonuçları zaman içinde',
      ikon: Simgeler.barChart,
      altBaslik: 'Her çubuk ${saat >= 24 ? '1 gün' : '${saat.round()} saat'} (UTC aralıkları). Alıcı başına sayılır.',
      sag: TextButton(onPressed: () => setState(() => _tablo = !_tablo), child: Text(_tablo ? 'Grafik' : 'Tablo')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final s in _seriler)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: s.$3, borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 5),
                    Text(s.$2, style: TextStyle(color: r.soluk, fontSize: 12)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (seri.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Text('Bu dönemde veri yok.', style: TextStyle(color: r.silik)),
              ),
            )
          else if (_tablo)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 34,
                    dataRowMinHeight: 28,
                    dataRowMaxHeight: 32,
                    columnSpacing: 18,
                    columns: [
                      const DataColumn(label: Text('Aralık')),
                      for (final s in _seriler) DataColumn(label: Text(s.$2), numeric: true),
                    ],
                    rows: [
                      for (final b in seri) DataRow(cells: [DataCell(Text(etiket(b))), for (final s in _seriler) DataCell(Text('${tamsayi(b[s.$1])}'))]),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  maxY: enCok,
                  alignment: BarChartAlignment.spaceBetween,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(bottom: BorderSide(color: r.kenar)),
                  ),
                  titlesData: const FlTitlesData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => r.kart,
                      getTooltipItem: (g, _, _, _) {
                        final b = seri[g.x];
                        return BarTooltipItem(
                          '${etiket(b)}\n${_seriler.map((s) => '${s.$2}: ${tamsayi(b[s.$1])}').join('\n')}',
                          TextStyle(color: r.metin, fontSize: 11.5),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (final (i, b) in seri.indexed)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          () {
                            var y = 0.0;
                            final parcalar = <BarChartRodStackItem>[];
                            for (final s in _seriler) {
                              final v = tamsayi(b[s.$1]).toDouble();
                              if (v > 0) parcalar.add(BarChartRodStackItem(y, y + v, s.$3));
                              y += v;
                            }
                            return BarChartRodData(
                              toY: y,
                              width: (360 / seri.length).clamp(2.0, 16.0),
                              rodStackItems: parcalar,
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                            );
                          }(),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(etiket(seri.first), style: TextStyle(color: r.silik, fontSize: 11)),
                const Spacer(),
                Text('en yüksek çubuk: ${enCok.round()} alıcı', style: TextStyle(color: r.silik, fontSize: 11)),
                const Spacer(),
                Text('şimdi', style: TextStyle(color: r.silik, fontSize: 11)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Yerel sayfalanan tablolar --------------------------------------------------------------------

/// Tüm listeyi tek istekte alan, yerelde sayfalayan tablo sarmalayıcısı.
class _YerelTablo extends StatefulWidget {
  const _YerelTablo({super.key, required this.getir, required this.tablo});
  final Future<List<Map<String, dynamic>>> Function() getir;
  final Widget Function(SayfaYukleyici<Map<String, dynamic>> y) tablo;

  @override
  State<_YerelTablo> createState() => _YerelTabloState();
}

class _YerelTabloState extends State<_YerelTablo> {
  late final _y = SayfaYukleyici.yerel<Map<String, dynamic>>(widget.getir, sayfaBoyu: 25)..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.tablo(_y);
}

Widget _oranHucresi(BuildContext c, Object? v, double uyari, double kotu) => Text(
  yuzdeMetni(v),
  style: TextStyle(color: _oranRengi(v, uyari, kotu) ?? c.r.metin, fontSize: 13, fontWeight: FontWeight.w500),
);

List<Sutun<Map<String, dynamic>>> _oranSutunlari() => [
  Sutun('Teslim %', esnek: 1, sagaYasla: true, hucre: (c, x) => SolukMetin(yuzdeMetni(harita(x['rates'])['delivery_rate']))),
  Sutun('Erteleme %', esnek: 1, sagaYasla: true, hucre: (c, x) => _oranHucresi(c, harita(x['rates'])['deferral_rate'], 10, 25)),
  Sutun('Geri dönme %', esnek: 1, sagaYasla: true, hucre: (c, x) => _oranHucresi(c, harita(x['rates'])['hard_bounce_rate'], 2, 5)),
];

String _oranOzeti(Map<String, dynamic> x) {
  final o = harita(x['rates']);
  return 'teslim ${yuzdeMetni(o['delivery_rate'])} · erteleme ${yuzdeMetni(o['deferral_rate'])} · geri dönme ${yuzdeMetni(o['hard_bounce_rate'])}';
}

class _AliciSekmesi extends StatelessWidget {
  const _AliciSekmesi({super.key, required this.donem});
  final String donem;

  String _sonHata(Map<String, dynamic> d) {
    final f = d['last_failure'];
    if (f is! Map) return '';
    final m = harita(f);
    return '${metin(m['event']) == 'deferred' ? 'erteleme' : 'hata'} · ${goreliZaman(tarihOku(m['at']))}'
        '${metinYa(m['enhanced_code']) != null ? ' · ${m['enhanced_code']}' : ''}: ${metin(m['text'])}';
  }

  @override
  Widget build(BuildContext context) => _YerelTablo(
    getir: () async => haritalar(harita(await Uyg.api.get('/api/v1/reputation/recipient-domains', q: {'range': donem}))['items']),
    tablo: (y) => VeriTablosu<Map<String, dynamic>>(
      yukleyici: y,
      ust: Padding(
        padding: EdgeInsets.fromLTRB(context.genis ? 16 : 0, 4, context.genis ? 16 : 0, 8),
        child: Text(
          'Uzak teslim denemesi yapılan alıcı alan adları (ilk 100). Son hata: alıcı sunucunun yanıtı; adreslerin yerel kısmı maskelenir, ileti içeriği tutulmaz.',
          style: TextStyle(color: context.r.soluk, fontSize: 12.5),
        ),
      ),
      bosMetin: 'Bu dönemde uzak teslim denemesi yok.',
      bosIkon: Simgeler.public,
      tabloEnAz: 900,
      sutunlar: [
        Sutun('Alan adı', esnek: 3, hucre: (c, d) => IkiSatir(metin(d['domain']), alt: metinYa(d['provider']), mono: true)),
        Sutun('Alıcı', esnek: 1, sagaYasla: true, hucre: (c, d) => SolukMetin(sayiYaz(tamsayi(d['attempted'])))),
        Sutun('Teslim', esnek: 1, sagaYasla: true, hucre: (c, d) => SolukMetin(sayiYaz(tamsayi(d['delivered'])))),
        Sutun('Kalıcı / dolan', esnek: 1, sagaYasla: true, hucre: (c, d) => SolukMetin('${tamsayi(d['hard_bounces'])} / ${tamsayi(d['soft_bounces'])}')),
        ..._oranSutunlari(),
        Sutun(
          'Son hata yanıtı',
          esnek: 4,
          hucre: (c, d) => Text(
            _sonHata(d).isEmpty ? '—' : _sonHata(d),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.r.soluk, fontSize: 11.5, fontFamily: 'monospace'),
          ),
        ),
      ],
      kart: (c, d) => VeriKarti(
        baslik: metin(d['domain']),
        alt: metinYa(d['provider']),
        alanlar: [
          ('Alıcı', sayiYaz(tamsayi(d['attempted']))),
          ('Teslim', sayiYaz(tamsayi(d['delivered']))),
          ('Ertelenen', sayiYaz(tamsayi(d['deferred_rcpts']))),
          ('Kalıcı', sayiYaz(tamsayi(d['hard_bounces']))),
          ('Oranlar', _oranOzeti(d)),
          if (_sonHata(d).isNotEmpty) ('Son hata', _sonHata(d)),
        ],
      ),
    ),
  );
}

class _GondericiSekmesi extends StatefulWidget {
  const _GondericiSekmesi({super.key, required this.donem});
  final String donem;

  @override
  State<_GondericiSekmesi> createState() => _GondericiSekmesiState();
}

class _GondericiSekmesiState extends State<_GondericiSekmesi> {
  bool _gondericiler = false;
  Map<String, dynamic>? _veri;
  late final Future<Map<String, dynamic>> _istek = Uyg.api.get('/api/v1/reputation/senders', q: {'range': widget.donem}).then((v) {
    final m = harita(v);
    if (mounted) setState(() => _veri = m);
    return m;
  });

  Widget _durum(BuildContext c, Map<String, dynamic> s) {
    final rozet = <Widget>[
      if (mantik(s['over_pause_threshold'])) const Rozet('eşik aşıldı', renk: Marka.gul),
      if (metin(s['mailbox_status']) == 'suspended') const Rozet('kutu askıda', renk: Marka.kehribar),
      if (s['external_send'] == false) const Rozet('dış gönderim kapalı', renk: Marka.kehribar),
      if (s['mailbox_id'] == null) Rozet('gateway/röle', renk: c.r.soluk),
    ];
    if (rozet.isEmpty) return const SolukMetin('normal');
    return Wrap(spacing: 4, runSpacing: 4, children: rozet);
  }

  Widget _ust(BuildContext context) {
    final r = context.r;
    final d = _veri;
    final pause = harita(d?['pause']);
    final esik = haritalar(d?['senders']).where((s) => mantik(s['over_pause_threshold'])).length;
    return Padding(
      padding: EdgeInsets.fromLTRB(context.genis ? 16 : 0, 4, context.genis ? 16 : 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SecimCipleri<bool>(
            secenekler: const [(false, 'Müşteriler'), (true, 'Göndericiler')],
            secili: _gondericiler,
            secildi: (v) => setState(() => _gondericiler = v),
          ),
          const SizedBox(height: 8),
          if (!_gondericiler)
            Text('Müşteri bazında giden hacim ve oranlar (ilk 100, hacme göre).', style: TextStyle(color: r.soluk, fontSize: 12.5))
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (esik > 0) Rozet('$esik eşik üstünde', renk: Marka.gul, ikon: Simgeler.pauseCircleOutline),
                Text(
                  'Duraklatma eşiği: son 24 saatte en az ${tamsayi(pause['min_sends'])} sonuçlanmış teslimde kalıcı geri dönme ≥ %${metin(pause['rate'])}'
                  '${metinYa(pause['note']) != null ? '. ${metin(pause['note'])}' : ''}.',
                  style: TextStyle(color: r.soluk, fontSize: 12.5),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _istek,
    builder: (c, s) {
      if (s.hasError) return Durum.hata(hataMetni(s.error!));
      if (!s.hasData) return const Durum.yukleniyor();
      final d = s.data!;
      if (!_gondericiler) {
        return _YerelTablo(
          key: const ValueKey('org'),
          getir: () async => haritalar(d['organizations']),
          tablo: (y) => VeriTablosu<Map<String, dynamic>>(
            yukleyici: y,
            ust: _ust(context),
            bosMetin: 'Bu dönemde müşteri gönderimi yok.',
            bosIkon: Simgeler.apartment,
            tabloEnAz: 900,
            sutunlar: [
              Sutun('Müşteri', esnek: 3, hucre: (c, o) => IkiSatir(metin(o['organization_name']), alt: '${tamsayi(o['senders'])} gönderici')),
              Sutun('Kuyruğa alınan', esnek: 1, sagaYasla: true, hucre: (c, o) => SolukMetin(sayiYaz(tamsayi(o['queued'])))),
              Sutun('Teslim', esnek: 1, sagaYasla: true, hucre: (c, o) => SolukMetin(sayiYaz(tamsayi(o['delivered'])))),
              Sutun('Kalıcı', esnek: 1, sagaYasla: true, hucre: (c, o) => SolukMetin(sayiYaz(tamsayi(o['hard_bounces'])))),
              ..._oranSutunlari(),
              Sutun(
                'Politika / toplu ret',
                esnek: 1,
                sagaYasla: true,
                hucre: (c, o) => Text(
                  '${tamsayi(o['refused'])} / ${tamsayi(o['bulk_refused'])}',
                  style: TextStyle(color: tamsayi(o['refused']) > 0 ? Marka.kehribar : c.r.soluk, fontSize: 13),
                ),
              ),
            ],
            kart: (c, o) => VeriKarti(
              baslik: metin(o['organization_name']),
              alt: '${tamsayi(o['senders'])} gönderici',
              alanlar: [
                ('Kuyruğa alınan', sayiYaz(tamsayi(o['queued']))),
                ('Teslim', sayiYaz(tamsayi(o['delivered']))),
                ('Kalıcı', sayiYaz(tamsayi(o['hard_bounces']))),
                ('Ret', '${tamsayi(o['refused'])} politika · ${tamsayi(o['bulk_refused'])} toplu'),
                ('Oranlar', _oranOzeti(o)),
              ],
            ),
          ),
        );
      }
      return _YerelTablo(
        key: const ValueKey('snd'),
        getir: () async => haritalar(d['senders']),
        tablo: (y) => VeriTablosu<Map<String, dynamic>>(
          yukleyici: y,
          ust: _ust(context),
          bosMetin: 'Bu dönemde gönderici yok.',
          bosIkon: Simgeler.personOutline,
          tabloEnAz: 900,
          vurgulu: (s) => mantik(s['over_pause_threshold']),
          sutunlar: [
            Sutun('Gönderici', esnek: 3, hucre: (c, s) => IkiSatir(metin(s['address']), alt: metinYa(s['organization_name']), mono: true)),
            Sutun('Teslim', esnek: 1, sagaYasla: true, hucre: (c, s) => SolukMetin(sayiYaz(tamsayi(s['delivered'])))),
            Sutun('Kalıcı', esnek: 1, sagaYasla: true, hucre: (c, s) => SolukMetin(sayiYaz(tamsayi(s['hard_bounces'])))),
            ..._oranSutunlari(),
            Sutun(
              '24 sa geri dönme',
              esnek: 1,
              sagaYasla: true,
              hucre: (c, s) => Text(
                '${yuzdeMetni(s['hard_rate_24h'])} (${tamsayi(s['hard_24h'])}/${tamsayi(s['finished_24h'])})',
                style: TextStyle(color: mantik(s['over_pause_threshold']) ? Marka.gul : c.r.metin, fontSize: 12.5),
              ),
            ),
            Sutun('Durum', esnek: 2, hucre: _durum),
          ],
          kart: (c, s) => VeriKarti(
            baslik: metin(s['address']),
            alt: metinYa(s['organization_name']),
            vurgulu: mantik(s['over_pause_threshold']),
            ek: _durum(c, s),
            alanlar: [
              ('Kuyruğa alınan', sayiYaz(tamsayi(s['queued']))),
              ('Teslim', sayiYaz(tamsayi(s['delivered']))),
              ('Kalıcı', sayiYaz(tamsayi(s['hard_bounces']))),
              ('24 sa', '${yuzdeMetni(s['hard_rate_24h'])} (${tamsayi(s['hard_24h'])}/${tamsayi(s['finished_24h'])})'),
              ('Ret', '${tamsayi(s['refused'])} / ${tamsayi(s['bulk_refused'])}'),
              ('Oranlar', _oranOzeti(s)),
            ],
          ),
        ),
      );
    },
  );
}

// ---- Alan adı kimlik doğrulaması ------------------------------------------------------------------

const _kimlikDurumlari = {
  'ok': ('ok', 'tamam'),
  'warn': ('warn', 'eksik'),
  'fail': ('fail', 'yok/hatalı'),
  'error': ('unknown', 'DNS hatası'),
  'info': ('info', 'bilgi'),
  'not_built': ('unknown', 'Faz'),
};

class _KimlikHucresi extends StatelessWidget {
  const _KimlikHucresi(this.etiket, this.durum);
  final String? etiket;
  final String durum;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (durum.isEmpty) {
      return Text('${etiket != null ? '$etiket ' : ''}—', style: TextStyle(color: r.silik, fontSize: 12));
    }
    final m = _kimlikDurumlari[durum] ?? ('unknown', durum);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (etiket != null) ...[Text(etiket!, style: TextStyle(color: r.silik, fontSize: 12)), const SizedBox(width: 3)],
        DurumSimgesi(m.$1, boyut: 14),
        const SizedBox(width: 3),
        Text(m.$2, style: TextStyle(color: r.metin, fontSize: 12)),
      ],
    );
  }
}

class _KimlikSekmesi extends StatefulWidget {
  const _KimlikSekmesi({super.key});

  @override
  State<_KimlikSekmesi> createState() => _KimlikSekmesiState();
}

class _KimlikSekmesiState extends State<_KimlikSekmesi> {
  late final _y = SayfaYukleyici.yerel<Map<String, dynamic>>(
    () async => haritalar(harita(await Uyg.api.get('/api/v1/reputation/auth'))['items']),
    sayfaBoyu: 25,
  )..yenile();
  String? _mesgul;

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  bool get _denetler => Uyg.yetki('domains.manage');

  Future<void> _denetle(Map<String, dynamic> d) async {
    setState(() => _mesgul = metin(d['id']));
    final v = await islem(() => Uyg.api.post('/api/v1/domains/${metin(d['id'])}/dns-check'), tamam: '${metin(d['name'])} denetlendi');
    if (!mounted) return;
    setState(() => _mesgul = null);
    if (v != null) await _y.yenile();
  }

  Widget _dogrulama(Map<String, dynamic> d) {
    final ok = tarihOku(d['verified_at']) != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DurumSimgesi(ok ? 'ok' : 'fail', boyut: 14),
        const SizedBox(width: 3),
        Text(ok ? 'doğrulandı' : 'bekliyor', style: TextStyle(color: context.r.metin, fontSize: 12)),
      ],
    );
  }

  String _alt(Map<String, dynamic> d) =>
      '${metin(d['mode']) == 'gateway' ? 'gateway' : 'barındırma'} · ${metin(d['organization_name'])}'
      '${!mantik(d['dkim_key']) && metin(d['mode']) == 'hosting' ? ' · DKIM anahtarı yok' : ''}';

  @override
  Widget build(BuildContext context) => VeriTablosu<Map<String, dynamic>>(
    yukleyici: _y,
    ust: Padding(
      padding: EdgeInsets.fromLTRB(context.genis ? 16 : 0, 4, context.genis ? 16 : 0, 8),
      child: Text(
        'Son DNS denetiminin sonucu (canlı DNS sorgusu; "Denetle" ile yenilenir). Gönderim hacmine göre sıralı. Gateway alan adlarında DKIM müşterinin sunucusunda yönetilir.',
        style: TextStyle(color: context.r.soluk, fontSize: 12.5),
      ),
    ),
    bosMetin: 'Alan adı yok.',
    bosIkon: Simgeler.domain,
    tabloEnAz: 960,
    eylemler: _denetler ? (d) => [SatirEylemi(Simgeler.refresh, 'DNS denetimi', () => _denetle(d))] : null,
    sutunlar: [
      Sutun(
        'Alan adı',
        esnek: 3,
        hucre: (c, d) => IkiSatir(
          metin(d['name']),
          alt: _alt(d),
          mono: true,
          sol: _mesgul == metin(d['id']) ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : null,
        ),
      ),
      Sutun('Doğrulama', esnek: 2, hucre: (c, d) => _dogrulama(d)),
      Sutun('SPF', esnek: 1, hucre: (c, d) => _KimlikHucresi(null, metin(d['spf']))),
      Sutun('DKIM', esnek: 1, hucre: (c, d) => _KimlikHucresi(null, metin(d['dkim']))),
      Sutun('DMARC', esnek: 1, hucre: (c, d) => _KimlikHucresi(null, metin(d['dmarc']))),
      Sutun('MX', esnek: 1, hucre: (c, d) => _KimlikHucresi(null, metin(d['mx']))),
      Sutun('30 gün', esnek: 1, sagaYasla: true, hucre: (c, d) => SolukMetin(sayiYaz(tamsayi(d['sent_30d'])))),
      Sutun('Son denetim', esnek: 1, hucre: (c, d) => SolukMetin(tarihOku(d['checked_at']) == null ? 'hiç' : goreliZaman(tarihOku(d['checked_at'])))),
    ],
    kart: (c, d) => VeriKarti(
      baslik: metin(d['name']),
      alt: _alt(d),
      eylemler: _denetler ? [SatirEylemi(Simgeler.refresh, 'DNS denetimi', () => _denetle(d))] : const [],
      ek: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          _dogrulama(d),
          _KimlikHucresi('SPF', metin(d['spf'])),
          _KimlikHucresi('DKIM', metin(d['dkim'])),
          _KimlikHucresi('DMARC', metin(d['dmarc'])),
          _KimlikHucresi('MX', metin(d['mx'])),
        ],
      ),
      alanlar: [
        ('30 gün gönderim', sayiYaz(tamsayi(d['sent_30d']))),
        ('Son denetim', tarihOku(d['checked_at']) == null ? 'hiç' : goreliZaman(tarihOku(d['checked_at']))),
      ],
    ),
  );
}
