import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../ortak/simgeler.dart';
import '../ortak/surukle.dart';
import '../veri/durum.dart';
import '../veri/modeller.dart';
import '../veri/yardimci.dart';

/// Liste satırı: okunmamışlar kalın + vurgu noktası + soldaki vurgu çizgisi + tonlu zemin; okunmuşlar normal ağırlık ve soluk renk.
/// Ayrıca yıldız, ek ataşı, önemli işareti, önizleme, etiket noktaları.
/// Telefonda kaydırma eylemleri (sağa: okundu/okunmadı, sola: arşivle/sil), masaüstünde fareyle üzerine gelince düğmeler.
class IletiSatiri extends StatefulWidget {
  const IletiSatiri({
    super.key,
    required this.ileti,
    required this.secili,
    required this.acik,
    required this.secimModu,
    required this.copte,
    required this.arsivde,
    required this.dokun,
    required this.sec,
    required this.okundu,
    required this.yildiz,
    required this.arsivle,
    required this.sil,
    this.hesapRengi,
    this.hesapEtiketi,
    this.surukle,
  });

  /// Masaüstü: satır kenar menüsündeki klasör/etiketlere sürüklenebilir (seçiliyse tüm seçim).
  final IletiSurukleme? surukle;

  final IletiOzet ileti;
  final bool secili;
  final bool acik;
  final bool secimModu;
  final bool copte;
  final bool arsivde;
  final VoidCallback dokun;
  final VoidCallback sec;
  final VoidCallback okundu;
  final VoidCallback yildiz;
  final VoidCallback arsivle;
  final VoidCallback sil;

  /// Birleşik görünüm: iletinin ait olduğu hesabın rengi ve kısa adı.
  final Color? hesapRengi;
  final String? hesapEtiketi;

  @override
  State<IletiSatiri> createState() => _IletiSatiriState();
}

class _IletiSatiriState extends State<IletiSatiri> {
  bool _uzerinde = false;

  void _titret(VoidCallback f) {
    HapticFeedback.mediumImpact();
    f();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final m = widget.ileti;
    final okunmamis = !m.okundu;
    final taslak = m.klasorRolu == 'drafts';
    final karsi = m.gidenMi ? m.kime : m.kimden;
    final ad = m.gidenMi ? (karsi.trim().isEmpty ? '(alıcı yok)' : 'Kime: ${gorunenAd(karsi)}') : gorunenAd(karsi);
    final tohum = adresCoz(adresListesiCoz(karsi).firstOrNull?.eposta ?? karsi).eposta;
    final etiketler = m.etiketler.map(PostaDurum.ben.etiket).whereType<Etiket>().toList();
    // Okunmamış: hafif vurgu tonlu zemin; seçili/açık durumlar daha belirgin.
    final arka = widget.secili
        ? r.vurguYumusak
        : widget.acik
        ? r.ic
        : okunmamis
        ? r.vurguYumusak.withValues(alpha: r.koyu ? .45 : .5)
        : r.kart;
    final adRengi = taslak ? Marka.gul : (okunmamis ? r.metin : r.soluk);

    Widget simge(IconData i, String etiket, {Color? renk, double boyut = 15}) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(i, size: boyut, color: renk ?? r.silik, semanticLabel: etiket),
    );

    // Masaüstü: daha ferah (≈ 78 px, 11 px dikey dolgu, 36 px avatar, satır yüksekliği 1.35) ama yazı boyutları aynı.
    final g = context.genis;
    final avatar = g ? 36.0 : 32.0;
    final sh = g ? 1.35 : 1.25;

    final icerik = Material(
      color: arka,
      child: InkWell(
        onTap: widget.dokun,
        onLongPress: widget.sec,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(g ? 16 : 14, g ? 11 : 7, g ? 14 : 12, g ? 11 : 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    button: true,
                    label: widget.secili ? 'Seçimi kaldır' : 'Seç',
                    child: GestureDetector(
                      onTap: widget.sec,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: widget.secili || widget.secimModu
                            ? Container(
                                key: const ValueKey('s'),
                                width: avatar,
                                height: avatar,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.secili ? r.vurgu : r.kart,
                                  border: widget.secili ? null : Border.all(color: r.kenar, width: 2),
                                ),
                                child: widget.secili ? const Icon(Simge.onay, color: Colors.white, size: 18) : null,
                              )
                            : Opacity(
                                opacity: okunmamis ? 1 : .85,
                                child: Avatar(gorunenAd(karsi), boyut: avatar, tohum: tohum.isEmpty ? karsi : tohum),
                              ),
                      ),
                    ),
                  ),
                  SizedBox(width: g ? 14 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (okunmamis)
                              Container(
                                key: const ValueKey('okunmamis-nokta'),
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: 7),
                                decoration: BoxDecoration(color: r.vurgu, shape: BoxShape.circle),
                              ),
                            Expanded(
                              child: Text(
                                taslak ? 'Taslak' : ad,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, height: sh, fontWeight: okunmamis ? FontWeight.w600 : FontWeight.w400, color: adRengi),
                              ),
                            ),
                            if (widget.hesapRengi != null)
                              Container(
                                key: const ValueKey('hesap-etiketi'),
                                constraints: const BoxConstraints(maxWidth: 130),
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                decoration: BoxDecoration(color: widget.hesapRengi!.withValues(alpha: .13), borderRadius: BorderRadius.circular(20)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(color: widget.hesapRengi, shape: BoxShape.circle),
                                    ),
                                    if ((widget.hesapEtiketi ?? '').isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          widget.hesapEtiketi!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: widget.hesapRengi),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            if (m.onemli) simge(Simge.onemliDolu, 'Önemli', renk: Marka.kehribar, boyut: 16),
                            if (m.ekVar) simge(Simge.ek, 'Ekli'),
                            if (m.yanitlandi) simge(Simge.yanitla, 'Yanıtlandı'),
                            if (m.iletildi) simge(Simge.ilet, 'İletildi'),
                            const SizedBox(width: 6),
                            Text(
                              kisaZaman(m.tarih),
                              style: TextStyle(fontSize: 12, color: okunmamis ? r.vurgu : r.silik, fontWeight: okunmamis ? FontWeight.w600 : FontWeight.w400),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.konu.trim().isEmpty ? '(konu yok)' : m.konu,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: sh,
                                  fontWeight: okunmamis ? FontWeight.w500 : FontWeight.w400,
                                  color: okunmamis ? r.metin : r.soluk,
                                ),
                              ),
                            ),
                            Semantics(
                              button: true,
                              label: m.yildizli ? 'Yıldızı kaldır' : 'Yıldızla',
                              child: InkResponse(
                                onTap: widget.yildiz,
                                radius: 18,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(
                                    m.yildizli ? Simge.yildizDolu : Simge.yildiz,
                                    size: 18,
                                    color: m.yildizli ? yildizRengi : r.silik.withValues(alpha: .6),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (m.onizleme.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              m.onizleme.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: r.soluk, height: sh),
                            ),
                          ),
                        if (etiketler.isNotEmpty || m.ertelemeBitis != null || m.takip)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (m.takip) const Rozet('Takip', renk: Marka.mavi, ikon: Simge.hatirlatma),
                                if (m.ertelemeBitis != null) Rozet(kisaZaman(m.ertelemeBitis), renk: Marka.kehribar, ikon: Simge.ertele),
                                for (final e in etiketler) Rozet(e.ad, renk: etiketRengi(e.renk), ikon: Simge.etiket),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Fare üzerindeyken eylemler satırın sağ üstünde yüzer; yerleşim (ad, tarih, yükseklik) hiç kaymaz.
            if (!widget.secimModu)
              Positioned(
                top: g ? 9 : 5,
                right: 8,
                child: IgnorePointer(
                  ignoring: !_uzerinde,
                  child: AnimatedOpacity(
                    opacity: _uzerinde ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: r.kart,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: r.kenar),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 6, offset: const Offset(0, 1))],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        child: Row(mainAxisSize: MainAxisSize.min, children: _fareEylemleri(r)),
                      ),
                    ),
                  ),
                ),
              ),
            // Sol kenardaki ince vurgu çizgisi: okunmamış (veya okuyucuda açık) iletiler.
            if (okunmamis || widget.acik)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(key: okunmamis ? const ValueKey('okunmamis-serit') : null, width: 3, color: r.vurgu),
              ),
          ],
        ),
      ),
    );

    final satir = MouseRegion(
      onEnter: (_) => setState(() => _uzerinde = true),
      onExit: (_) => setState(() => _uzerinde = false),
      child: Semantics(
        label: '${okunmamis ? 'Okunmamış' : 'Okundu'}. $ad. ${m.konu}. ${kisaZaman(m.tarih)}',
        excludeSemantics: false,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: r.kenar.withValues(alpha: .7))),
          ),
          child: icerik,
        ),
      ),
    );

    final s = widget.surukle;
    if (s != null) {
      // Fareyle sürükleme; kaydırma eylemleri yerine fare üzerindeki düğmeler kullanılır.
      return Draggable<IletiSurukleme>(
        data: s,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _SuruklemeGorseli(sayi: s.idler.length, konu: m.konu, r: r),
        childWhenDragging: Opacity(opacity: .5, child: satir),
        child: satir,
      );
    }
    if (widget.secimModu) return satir;
    return Slidable(
      key: ValueKey('kaydir-${m.id}'),
      groupTag: 'liste',
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: .28,
        children: [
          SlidableAction(
            onPressed: (_) => _titret(widget.okundu),
            backgroundColor: Marka.mavi,
            foregroundColor: Colors.white,
            icon: okunmamis ? Simge.okunduYap : Simge.okunmadiYap,
            label: okunmamis ? 'Okundu' : 'Okunmadı',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: widget.arsivde ? .28 : .52,
        dismissible: widget.copte ? null : DismissiblePane(onDismissed: () => _titret(widget.sil)),
        children: [
          if (!widget.arsivde)
            SlidableAction(
              onPressed: (_) => _titret(widget.arsivle),
              backgroundColor: Marka.zumrut,
              foregroundColor: Colors.white,
              icon: Simge.arsiv,
              label: 'Arşivle',
            ),
          SlidableAction(onPressed: (_) => _titret(widget.sil), backgroundColor: Marka.gul, foregroundColor: Colors.white, icon: Simge.sil, label: 'Sil'),
        ],
      ),
      child: satir,
    );
  }

  List<Widget> _fareEylemleri(Renkler r) {
    if (widget.secimModu) return const [];
    Widget d(IconData i, String t, VoidCallback f) => SizedBox(
      width: 30,
      height: 22,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        tooltip: t,
        onPressed: f,
        icon: Icon(i, color: r.soluk),
      ),
    );
    final m = widget.ileti;
    return [
      d(m.okundu ? Simge.okunmadiYap : Simge.okunduYap, m.okundu ? 'Okunmadı yap' : 'Okundu yap', widget.okundu),
      if (!widget.arsivde) d(Simge.arsiv, 'Arşivle', widget.arsivle),
      d(Simge.sil, widget.copte ? 'Kalıcı sil' : 'Sil', widget.sil),
    ];
  }
}

class _SuruklemeGorseli extends StatelessWidget {
  const _SuruklemeGorseli({required this.sayi, required this.konu, required this.r});
  final int sayi;
  final String konu;
  final Renkler r;
  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('surukleme-gorseli'),
    color: r.kart,
    elevation: 6,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Simge.tasi, size: 18, color: r.vurgu),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              sayi > 1 ? '$sayi ileti' : (konu.trim().isEmpty ? '(konu yok)' : konu),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: r.metin, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}
