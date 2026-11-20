import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

/// Birincil sayfa eylemi (geniş ekranda başlıkta dolu düğme, telefonda FAB).
class BirincilEylem {
  const BirincilEylem(this.ikon, this.etiket, this.calistir);
  final IconData ikon;
  final String etiket;
  final VoidCallback calistir;
}

/// Bölüm sayfası iskeleti: başlık + alt başlık, eylemler, birincil eylem, isteğe bağlı sekmeler.
/// Geniş ekranda başlık daha yüksek ve birincil eylem başlıkta; telefonda birincil eylem FAB olur.
class Iskelet extends StatelessWidget {
  const Iskelet({super.key, required this.baslik, required this.govde, this.alt, this.eylemler = const [], this.birincil, this.sekmeler, this.yenile});
  final String baslik;
  final String? alt;
  final Widget govde;
  final List<Widget> eylemler;
  final BirincilEylem? birincil;

  /// Verilirse AppBar altında sekme çubuğu (DefaultTabController çağıran tarafta kurulmalı).
  final PreferredSizeWidget? sekmeler;

  /// Verilirse başlıkta yenile düğmesi.
  final VoidCallback? yenile;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final genis = context.genis;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: genis ? 72 : kToolbarHeight,
        titleSpacing: genis ? 24 : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: gosterim(genis ? 22 : 19, agirlik: FontWeight.w700, renk: r.metin)),
            if (alt != null && alt!.isNotEmpty)
              Text(alt!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          ...eylemler,
          if (yenile != null) IconButton(tooltip: 'Yenile', onPressed: yenile, icon: const Icon(Icons.refresh_rounded)),
          if (genis && birincil != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                onPressed: birincil!.calistir,
                icon: Icon(birincil!.ikon, size: 19),
                label: Text(birincil!.etiket),
              ),
            ),
          SizedBox(width: genis ? 20 : 4),
        ],
        bottom: sekmeler,
      ),
      floatingActionButton: !genis && birincil != null
          ? FloatingActionButton.extended(onPressed: birincil!.calistir, icon: Icon(birincil!.ikon), label: Text(birincil!.etiket))
          : null,
      body: govde,
    );
  }
}

/// Tek istekle yüklenen gövde: yükleniyor / hata / içerik ve çekerek yenileme.
class TekYukleme<T> extends StatefulWidget {
  const TekYukleme({super.key, required this.getir, required this.icerik});
  final Future<T> Function() getir;

  /// [yenile] ile içerik yeniden yüklenir (işlemlerden sonra).
  final Widget Function(BuildContext context, T veri, Future<void> Function() yenile) icerik;

  @override
  State<TekYukleme<T>> createState() => TekYuklemeState<T>();
}

class TekYuklemeState<T> extends State<TekYukleme<T>> {
  T? _veri;
  String? _hata;
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    yenile();
  }

  Future<void> yenile() async {
    setState(() => _yukleniyor = true);
    try {
      final v = await widget.getir();
      if (!mounted) return;
      setState(() {
        _veri = v;
        _hata = null;
        _yukleniyor = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hata = hataMetni(e);
        _yukleniyor = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _veri;
    if (v == null) {
      if (_hata != null) return Durum.hata(_hata!, tekrar: yenile);
      return const Durum.yukleniyor();
    }
    return Stack(
      children: [
        Positioned.fill(child: RefreshIndicator.adaptive(onRefresh: yenile, child: widget.icerik(context, v, yenile))),
        if (_yukleniyor) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator(minHeight: 2)),
      ],
    );
  }
}

/// Kaydırılabilir, genişliği sınırlı içerik sütunu (ayrıntı ve gösterge sayfaları).
class IcerikListesi extends StatelessWidget {
  const IcerikListesi({super.key, required this.children, this.enFazla = 1280});
  final List<Widget> children;
  final double enFazla;

  @override
  Widget build(BuildContext context) {
    final yatay = MediaQuery.sizeOf(context).width >= 700 ? 24.0 : 12.0;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(yatay, 4, yatay, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: enFazla),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

/// Genişliğe göre sütun sayısı ayarlanan kart ızgarası (her kart en az [enAz] piksel).
class Izgara extends StatelessWidget {
  const Izgara({super.key, required this.children, this.enAz = 180, this.bosluk = 12});
  final List<Widget> children;
  final double enAz, bosluk;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, k) {
      if (children.isEmpty) return const SizedBox.shrink();
      final sutun = ((k.maxWidth + bosluk) / (enAz + bosluk)).floor().clamp(1, children.length);
      final g = (k.maxWidth - bosluk * (sutun - 1)) / sutun;
      return Wrap(
        spacing: bosluk,
        runSpacing: bosluk,
        children: [for (final c in children) SizedBox(width: g, child: c)],
      );
    },
  );
}

/// Gösterge kartı: renkli ikon kutusu, etiket, büyük değer, değişim (delta) ve alt satır. Dokununca [onTap].
class KpiKarti extends StatelessWidget {
  const KpiKarti({super.key, required this.ikon, required this.etiket, required this.deger, this.alt, this.renk, this.degisim, this.degisimIyi = true, this.onTap, this.ek});
  final IconData ikon;
  final String etiket, deger;
  final String? alt;
  final Color? renk;

  /// Yüzde değişim (ör. +12.5); null ise gösterilmez.
  final double? degisim;

  /// Artış iyi mi (yeşil) yoksa kötü mü (kırmızı).
  final bool degisimIyi;
  final VoidCallback? onTap;
  final Widget? ek;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ton = renk ?? r.vurgu;
    return Material(
      color: r.kart,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: r.kenar)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: ton.withValues(alpha: r.koyu ? .2 : .12), borderRadius: BorderRadius.circular(11)),
                    child: Icon(ikon, size: 19, color: ton),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(etiket, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  if (onTap != null) Icon(Icons.arrow_forward_rounded, size: 16, color: r.silik),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: Text(deger, maxLines: 1, overflow: TextOverflow.ellipsis, style: gosterim(26, renk: r.metin))),
                  if (degisim != null) ...[const SizedBox(width: 8), Padding(padding: const EdgeInsets.only(bottom: 4), child: DegisimHapi(degisim!, iyi: degisimIyi))],
                ],
              ),
              if (ek != null) ...[const SizedBox(height: 8), ek!],
              if (alt != null && alt!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(alt!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Yüzde değişim hapı: ↑ %12 (yeşil/kırmızı, [iyi] yönüne göre).
class DegisimHapi extends StatelessWidget {
  const DegisimHapi(this.yuzde, {super.key, this.iyi = true});
  final double yuzde;
  final bool iyi;

  @override
  Widget build(BuildContext context) {
    final sabit = yuzde.abs() < .5;
    final olumlu = (yuzde > 0) == iyi;
    final renk = sabit ? context.r.silik : (olumlu ? Marka.zumrut : Marka.gul);
    final ikon = sabit ? Icons.trending_flat_rounded : (yuzde > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded);
    final metin = sabit ? '%0' : '%${yuzde.abs() >= 100 ? yuzde.abs().toStringAsFixed(0) : yuzde.abs().toStringAsFixed(1).replaceAll('.', ',')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 14, color: renk),
          const SizedBox(width: 3),
          Text(metin, style: TextStyle(color: renk, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Yüzde değişim: önceki 0 ise null.
double? degisimYuzdesi(num simdi, num onceki) => onceki == 0 ? null : (simdi - onceki) / onceki * 100;

/// Küçük durum noktası + metin (sağlık listeleri).
class DurumNoktasi extends StatelessWidget {
  const DurumNoktasi(this.renk, {super.key, this.boyut = 8});
  final Color renk;
  final double boyut;
  @override
  Widget build(BuildContext context) => Container(
    width: boyut,
    height: boyut,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: renk,
      boxShadow: [BoxShadow(color: renk.withValues(alpha: .35), blurRadius: 6)],
    ),
  );
}

/// Yetkisiz / pakette olmayan bölüm uyarısı.
class Kapali extends StatelessWidget {
  const Kapali(this.metin, {super.key, this.ikon = Icons.lock_outline_rounded});
  final String metin;
  final IconData ikon;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 44, color: context.r.silik),
          const SizedBox(height: 12),
          Text(metin, textAlign: TextAlign.center, style: TextStyle(color: context.r.soluk)),
        ],
      ),
    ),
  );
}
