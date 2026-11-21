// Geniş ekran sol dar ray: bölümler (Posta/Sohbet/Takvim/Görevler) üstte; altta sırayla Ayarlar, eşitleme noktası,
// sürüm ve etkin hesap avatarı. Ray genişliği sabittir (80 px) — alt bölüm hiçbir zaman genişletmez; pencere kısa
// kalırsa önce sürüm gizlenir, bölümler kaydırılır.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ortak/esitleme.dart';
import '../veri/canli.dart';
import 'hesap_menusu.dart';

const double rayGenisligi = 80;

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
    // Kısa pencerede (≈ 640 px altı) sürüm satırı gizlenir; ipucu Ayarlar › Hakkında'da da var.
    final kisa = MediaQuery.sizeOf(context).height < 640;
    return NavigationRail(
      backgroundColor: r.zemin,
      selectedIndex: secili,
      minWidth: rayGenisligi,
      labelType: NavigationRailLabelType.all,
      groupAlignment: -1,
      scrollable: true,
      indicatorColor: r.vurguYumusak,
      onDestinationSelected: sec,
      // Etiketler 64 px'e sığdırılır (gerekirse küçültülür): uzun bir ad ya da büyük yazı ölçeği rayı genişletmez.
      destinations: [
        for (final h in hedefler)
          NavigationRailDestination(icon: h.icon, selectedIcon: h.selectedIcon, label: _sigdir(h.label), padding: h.padding, disabled: h.disabled),
      ],
      trailingAtBottom: true,
      trailing: SizedBox(
        width: rayGenisligi,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RayAyarlar(secili: ayarlarSecili, ac: ayarlarAc, ikon: ayarlarIkonu),
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

Widget _sigdir(Widget etiket) => ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: rayGenisligi - 16),
  child: FittedBox(fit: BoxFit.scaleDown, child: etiket),
);

/// Raydaki Ayarlar: üstteki hedeflerle aynı görünüm (56×32 gösterge + 12 px etiket).
class _RayAyarlar extends StatelessWidget {
  const _RayAyarlar({required this.secili, required this.ac, this.ikon});
  final bool secili;
  final VoidCallback ac;
  final Widget? ikon;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final tema = Theme.of(context);
    final rt = tema.navigationRailTheme;
    final etiket = (secili ? rt.selectedLabelTextStyle : rt.unselectedLabelTextStyle) ?? tema.textTheme.labelMedium ?? const TextStyle(fontSize: 12);
    final ikonTema = (secili ? rt.selectedIconTheme : rt.unselectedIconTheme) ?? IconThemeData(color: secili ? r.metin : r.soluk, size: 24);
    return Semantics(
      button: true,
      selected: secili,
      label: 'Ayarlar',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('ray-ayarlar'),
        onTap: ac,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 56,
                height: 32,
                decoration: BoxDecoration(color: secili ? r.vurguYumusak : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                child: IconTheme.merge(data: ikonTema, child: ikon ?? const Icon(Simge.ayarlar)),
              ),
              const SizedBox(height: 4),
              _sigdir(Text('Ayarlar', maxLines: 1, style: etiket)),
            ],
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
    Canli.ben.durum.addListener(_degisti);
    Canli.ben.sonOlay.addListener(_degisti);
    _saat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    Canli.ben.durum.removeListener(_degisti);
    Canli.ben.sonOlay.removeListener(_degisti);
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
    final ipucu = rayEsitlemeIpucu(d, Canli.ben.sonOlay.value, simdi);
    return Tooltip(
      message: '$ipucu\nDokun: Şimdi eşitle',
      child: Semantics(
        button: true,
        liveRegion: true,
        label: '$ipucu. Şimdi eşitle',
        excludeSemantics: true,
        child: InkResponse(
          key: const ValueKey('ray-esitleme'),
          onTap: simdiEsitle,
          radius: 16,
          child: SizedBox(
            width: 40,
            height: kalan > 0 ? 30 : 20,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  key: ValueKey('ray-esitleme-${d.tur.name}'),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: renk,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: renk.withValues(alpha: .35), blurRadius: 4)],
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

const double listeEnAz = 340, listeEnCok = 640;

/// Liste ile okuyucu arasındaki sürüklenebilir çizgi: 1 px görünür, 7 px tutma alanı; çift tık varsayılana döner.
class BolmeCizgisi extends StatefulWidget {
  const BolmeCizgisi({super.key, required this.renk, required this.surukle, required this.bitti, required this.sifirla});
  final Color renk;
  final ValueChanged<double> surukle;
  final VoidCallback bitti;
  final VoidCallback sifirla;

  @override
  State<BolmeCizgisi> createState() => _BolmeCizgisiState();
}

class _BolmeCizgisiState extends State<BolmeCizgisi> {
  bool _ustunde = false, _surukleniyor = false;

  @override
  Widget build(BuildContext context) {
    final etkin = _ustunde || _surukleniyor;
    return Semantics(
      label: 'Liste genişliği',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _ustunde = true),
        onExit: (_) => setState(() => _ustunde = false),
        child: GestureDetector(
          key: const ValueKey('liste-bolme'),
          behavior: HitTestBehavior.translucent,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (_) => setState(() => _surukleniyor = true),
          onHorizontalDragUpdate: (d) => widget.surukle(d.delta.dx),
          onHorizontalDragEnd: (_) {
            setState(() => _surukleniyor = false);
            widget.bitti();
          },
          onHorizontalDragCancel: () {
            setState(() => _surukleniyor = false);
            widget.bitti();
          },
          onDoubleTap: widget.sifirla,
          // 7 px tutma alanı (1 px çizgi ortada); yanlardaki boşluk zemin renginde kalır.
          child: SizedBox(
            width: 7,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: etkin ? 3 : 1,
                color: etkin ? context.r.vurgu.withValues(alpha: .6) : widget.renk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
