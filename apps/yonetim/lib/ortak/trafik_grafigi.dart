import 'package:boga_ortak/boga_ortak.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../veri/operasyon.dart';

/// Saatlik SMTP trafiği çizgi grafiği: kabul, teslim, ret (+ hata).
class TrafikGrafigi extends StatelessWidget {
  const TrafikGrafigi({super.key, required this.dilimler, this.yukseklik = 190});
  final List<TrafikDilimi> dilimler;
  final double yukseklik;

  static const kabulRengi = Marka.mavi;
  static const teslimRengi = Marka.zumrut;
  static const retRengi = Marka.gul;
  static const hataRengi = Marka.kehribar;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (dilimler.isEmpty) {
      return SizedBox(
        height: yukseklik,
        child: Center(
          child: Text('Bu aralıkta veri yok.', style: TextStyle(color: r.silik)),
        ),
      );
    }
    var enCok = 1;
    for (final d in dilimler) {
      for (final v in [d.kabul, d.teslim, d.ret, d.hata]) {
        if (v > enCok) enCok = v;
      }
    }
    final ust = _yuvarla(enCok);
    final gunluk = dilimler.length > 48;
    final saatB = DateFormat(gunluk ? 'd MMM' : 'HH:mm', 'tr_TR');
    final ipucuB = DateFormat('d MMM HH:mm', 'tr_TR');
    LineChartBarData seri(Color c, int Function(TrafikDilimi) f, {bool dolgu = false}) => LineChartBarData(
      spots: [for (final (i, d) in dilimler.indexed) FlSpot(i.toDouble(), f(d).toDouble())],
      color: c,
      barWidth: 2.2,
      isCurved: true,
      curveSmoothness: .2,
      preventCurveOverShooting: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: dolgu,
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: .22), c.withValues(alpha: 0)]),
      ),
    );
    final adim = (dilimler.length / (gunluk ? 7 : 6)).ceilToDouble().clamp(1, 1000).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: yukseklik,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: ust.toDouble(),
              minX: 0,
              maxX: (dilimler.length - 1).toDouble(),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: ust / 4,
                getDrawingHorizontalLine: (_) => FlLine(color: r.kenar, strokeWidth: 1, dashArray: const [4, 4]),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    interval: ust / 4,
                    getTitlesWidget: (v, m) => Text(sayiYaz(v.round()), style: TextStyle(color: r.silik, fontSize: 10.5)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: adim,
                    getTitlesWidget: (v, m) {
                      final i = v.round();
                      if (i < 0 || i >= dilimler.length || v != i.toDouble()) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(saatB.format(dilimler[i].saat), style: TextStyle(color: r.silik, fontSize: 10.5)),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Marka.grafit,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (noktalar) {
                    final adlar = ['Kabul', 'Teslim', 'Ret', 'Hata'];
                    return [
                      for (final (j, n) in noktalar.indexed)
                        LineTooltipItem(
                          '${j == 0 ? '${ipucuB.format(dilimler[n.x.round()].saat)}\n' : ''}${adlar[n.barIndex]}: ${sayiYaz(n.y.round())}',
                          TextStyle(color: n.bar.color, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                    ];
                  },
                ),
              ),
              lineBarsData: [
                seri(kabulRengi, (d) => d.kabul, dolgu: true),
                seri(teslimRengi, (d) => d.teslim, dolgu: true),
                seri(retRengi, (d) => d.ret),
                seri(hataRengi, (d) => d.hata),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _Lejant(kabulRengi, 'Kabul', dilimler.fold(0, (a, d) => a + d.kabul)),
            _Lejant(teslimRengi, 'Teslim', dilimler.fold(0, (a, d) => a + d.teslim)),
            _Lejant(retRengi, 'Ret', dilimler.fold(0, (a, d) => a + d.ret)),
            _Lejant(hataRengi, 'Hata', dilimler.fold(0, (a, d) => a + d.hata)),
          ],
        ),
      ],
    );
  }

  /// Eksen üst sınırını okunur bir sayıya yuvarlar (4'e bölünebilir).
  static int _yuvarla(int v) {
    if (v <= 4) return 4;
    var b = 1;
    while (b * 10 < v) {
      b *= 10;
    }
    for (final k in [1, 2, 4, 5, 8, 10]) {
      final u = k * b;
      if (u >= v && u % 4 == 0) return u;
    }
    return ((v + 3) ~/ 4) * 4;
  }
}

class _Lejant extends StatelessWidget {
  const _Lejant(this.renk, this.ad, this.toplam);
  final Color renk;
  final String ad;
  final int toplam;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 8),
      Text('$ad ', style: TextStyle(color: context.r.soluk, fontSize: 12.5)),
      Text(sayiYaz(toplam), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
    ],
  );
}
