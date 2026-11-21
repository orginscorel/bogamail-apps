// Geniş ekran sol dar ray — web'deki "Uygulamalar" rayı gibi (w-[68px], bg-muted/30, sağ çizgi; öğeler w-14
// rounded-xl py-2, 20 px simge + 11 px etiket; etkin: primary/10 zemin + birincil renk). Bölümler üstte; altta
// sırayla Ayarlar, eşitleme noktası, sürüm ve etkin hesap avatarı. Genişlik sabittir; pencere kısa kalırsa önce
// sürüm gizlenir, bölümler kaydırılır.

import 'dart:async';
import 'dart:math' as math;

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ortak/esitleme.dart';
import '../veri/baglanti.dart';
import '../veri/kuyruk.dart';
import '../veri/canli.dart';
import 'hesap_menusu.dart';

const double rayGenisligi = 68;

/// Klasör kenar çubuğu genişliği (web: w-64).
const double kenarGenisligi = 224;

class SolRay extends StatelessWidget {
  const SolRay({
    super.key,
    required this.hedefler,
    required this.secili,
    required this.sec,
    required this.ayarlarSecili,
    required this.ayarlarAc,
    this.ayarlarIkonu,
  });

  /// Yalnız simge / seçili simge / etiket kullanılır.
  final List<NavigationRailDestination> hedefler;

  /// Üstteki hedeflerden seçili olan; Ayarlar seçiliyken null.
  final int? secili;
  final ValueChanged<int> sec;
  final bool ayarlarSecili;
  final VoidCallback ayarlarAc;

  /// Ayarlar simgesi (rozetli olabilir); yoksa düz simge.
  final Widget? ayarlarIkonu;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    // Kısa pencerede (≈ 640 px altı) sürüm satırı gizlenir.
    final kisa = MediaQuery.sizeOf(context).height < 640;
    return Semantics(
      container: true,
      label: 'Uygulamalar',
      child: Container(
        key: const ValueKey('sol-ray'),
        width: rayGenisligi,
        decoration: BoxDecoration(
          color: r.zemin,
          border: Border(right: BorderSide(color: r.kenar)),
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    for (final (i, h) in hedefler.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: RayOgesi(
                          key: ValueKey('ray-$i'),
                          ikon: secili == i ? (h.selectedIcon) : h.icon,
                          etiket: h.label,
                          secili: secili == i,
                          dokun: () => sec(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            RayOgesi(
              key: const ValueKey('ray-ayarlar'),
              ikon: ayarlarIkonu ?? const Icon(Simge.ayarlar),
              etiket: const Text('Ayarlar'),
              secili: ayarlarSecili,
              dokun: ayarlarAc,
            ),
            const SizedBox(height: 6),
            const RayEsitleme(),
            if (!kisa) ...[const SizedBox(height: 4), const SurumEtiketi(kisa: true)],
            const SizedBox(height: 4),
            const HesapRayDugmesi(),
          ],
        ),
      ),
    );
  }
}

/// Web ray öğesi: 56 px genişlik, rounded-xl, py-2, 20 px simge, 11 px etiket (sığmazsa küçülür).
class RayOgesi extends StatefulWidget {
  const RayOgesi({super.key, required this.ikon, required this.etiket, required this.secili, required this.dokun});
  final Widget ikon;
  final Widget etiket;
  final bool secili;
  final VoidCallback dokun;

  @override
  State<RayOgesi> createState() => _RayOgesiState();
}

class _RayOgesiState extends State<RayOgesi> {
  bool _uzerinde = false;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final s = widget.secili;
    final renk = s ? r.birincil : (_uzerinde ? r.metin : r.silik);
    return Semantics(
      button: true,
      selected: s,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _uzerinde = true),
        onExit: (_) => setState(() => _uzerinde = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.dokun,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: s ? r.birincil.withValues(alpha: _uzerinde ? .15 : .10) : (_uzerinde ? r.ic : Colors.transparent),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme.merge(
                  data: IconThemeData(size: 20, color: renk),
                  child: widget.ikon,
                ),
                const SizedBox(height: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 52),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: DefaultTextStyle.merge(
                      style: TextStyle(fontSize: 11, height: 1.25, color: renk, fontWeight: s ? FontWeight.w500 : FontWeight.w400),
                      maxLines: 1,
                      child: widget.etiket,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// İpucu metni: "Canlı · Son eşitleme 21 sn önce".
String rayEsitlemeIpucu(CanliDurumu d, DateTime? son, DateTime simdi) =>
    '${esitlemeMetni(d, simdi)} · ${sonEsitlemeMetni(son, simdi).replaceFirst('Son eşitleme:', 'Son eşitleme')}';

/// Eşitleme durumu tek renkli nokta olarak: yeşil Canlı, kehribar Bağlanıyor, kırmızı Bağlantı yok (altında geri
/// sayım), gri durdu. Dokununca Şimdi eşitle.
class RayEsitleme extends StatefulWidget {
  const RayEsitleme({super.key});

  @override
  State<RayEsitleme> createState() => _RayEsitlemeState();
}

class _RayEsitlemeState extends State<RayEsitleme> {
  Timer? _saat;

  @override
  void initState() {
    super.initState();
    esitlemeDinleyicisi.addListener(_degisti);
    _saat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    esitlemeDinleyicisi.removeListener(_degisti);
    _saat?.cancel();
    super.dispose();
  }

  void _degisti() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = Canli.ben.durum.value;
    final simdi = DateTime.now();
    final renk = switch (d.tur) {
      CanliTur.bagli => Marka.zumrut,
      CanliTur.baglaniyor => Marka.kehribar,
      CanliTur.yok => Marka.gul,
      CanliTur.kapali => r.silik,
    };
    final kalan = d.tur == CanliTur.yok && d.sonrakiDeneme != null ? d.sonrakiDeneme!.difference(simdi).inSeconds + 1 : 0;
    final cd = cevrimdisiMi;
    final bekleyen = bekleyenMetni();
    final ipucu = [
      cd ? cevrimdisiMetni(Baglanti.ben.sonEsitleme.value ?? Canli.ben.sonOlay.value, simdi) : rayEsitlemeIpucu(d, Canli.ben.sonOlay.value, simdi),
      ?bekleyen,
    ].join('\n');
    final ozet = cd || bekleyen != null;
    final nokta = cd ? Marka.gul : renk;
    return Tooltip(
      message: '$ipucu\nDokun: ${ozet ? 'Ayrıntılar' : 'Şimdi eşitle'}',
      child: Semantics(
        button: true,
        liveRegion: true,
        label: '$ipucu. Şimdi eşitle',
        excludeSemantics: true,
        child: InkResponse(
          key: const ValueKey('ray-esitleme'),
          onTap: ozet ? () => bekleyenleriGoster(context) : simdiEsitle,
          radius: 16,
          child: SizedBox(
            width: 40,
            height: (kalan > 0 ? 30 : 20) + (bekleyen != null ? 12 : 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  key: ValueKey('ray-esitleme-${cd ? 'cevrimdisi' : d.tur.name}'),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: nokta,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: nokta.withValues(alpha: .35), blurRadius: 4)],
                  ),
                ),
                if (bekleyen != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${GidenKutusu.ben.ogeler.value.length + IslemKuyrugu.ben.ogeler.value.length}',
                      key: const ValueKey('ray-bekleyen'),
                      maxLines: 1,
                      style: const TextStyle(fontSize: 9.5, height: 1.1, fontWeight: FontWeight.w700, color: Marka.kehribar),
                    ),
                  ),
                if (kalan > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('$kalan sn', maxLines: 1, style: TextStyle(fontSize: 9.5, height: 1.1, color: r.silik)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Web useSplit: liste [oran] × alan, [enAz]–[enCok] px arasında ve okumaya en az [kalan] px bırakarak.
double bolmeBoyu({required double alan, required double oran, required double enAz, required double enCok, required double kalan}) {
  final ust = math.max(enAz, math.min(enCok, alan - kalan));
  return math.min(ust, math.max(enAz, oran * alan));
}

/// Liste ile okuma alanı arasındaki sürüklenebilir ayraç (web: 4 px, fare üstünde primary %30, col/row-resize):
/// 1 px çizgi + tutma alanı; çift tık varsayılana döner. [yatay]: okuma alanı altta (satır ayracı).
class BolmeCizgisi extends StatefulWidget {
  const BolmeCizgisi({super.key, required this.renk, required this.surukle, required this.bitti, required this.sifirla, this.yatay = false});
  final Color renk;
  final ValueChanged<double> surukle;
  final VoidCallback bitti;
  final VoidCallback sifirla;
  final bool yatay;

  @override
  State<BolmeCizgisi> createState() => _BolmeCizgisiState();
}

class _BolmeCizgisiState extends State<BolmeCizgisi> {
  bool _ustunde = false, _surukleniyor = false;

  void _bitir() {
    setState(() => _surukleniyor = false);
    widget.bitti();
  }

  @override
  Widget build(BuildContext context) {
    final etkin = _ustunde || _surukleniyor;
    final y = widget.yatay;
    final cizgi = Container(width: y ? null : 1, height: y ? 1 : null, color: widget.renk);
    return Semantics(
      label: 'Liste boyutunu ayarla (çift tıklayınca sıfırlanır)',
      child: MouseRegion(
        cursor: y ? SystemMouseCursors.resizeRow : SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _ustunde = true),
        onExit: (_) => setState(() => _ustunde = false),
        child: GestureDetector(
          key: const ValueKey('liste-bolme'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: y ? null : (_) => setState(() => _surukleniyor = true),
          onHorizontalDragUpdate: y ? null : (d) => widget.surukle(d.delta.dx),
          onHorizontalDragEnd: y ? null : (_) => _bitir(),
          onHorizontalDragCancel: y ? null : _bitir,
          onVerticalDragStart: y ? (_) => setState(() => _surukleniyor = true) : null,
          onVerticalDragUpdate: y ? (d) => widget.surukle(d.delta.dy) : null,
          onVerticalDragEnd: y ? (_) => _bitir() : null,
          onVerticalDragCancel: y ? _bitir : null,
          onDoubleTap: widget.sifirla,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: y ? double.infinity : 5,
            height: y ? 5 : double.infinity,
            color: etkin ? context.r.birincil.withValues(alpha: .3) : Colors.transparent,
            alignment: Alignment.center,
            child: cizgi,
          ),
        ),
      ),
    );
  }
}
