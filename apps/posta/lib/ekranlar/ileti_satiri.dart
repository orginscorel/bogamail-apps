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
    // Web (message-list.tsx) satır anatomisi: px-3 py-2.5, 36 px avatar; 1. satır gönderen (text-sm) + önemli /
    // yanıtlandı / iletildi simgeleri + tarih (text-xs, okunmamışsa kalın birincil); 2. satır konu (text-sm) + ataş +
    // yıldız (yalnız yıldızlıysa ya da fare üstündeyken); 3. satır önizleme (text-xs soluk); etiket çipleri.
    // Okunmamış: soldaki 3 px birincil şerit ve kalın yazı (zemin tonu yok). Açık: primary/8, seçili: primary/10.
    final arka = widget.secili
        ? r.birincil.withValues(alpha: .10)
        : widget.acik
        ? r.birincil.withValues(alpha: .08)
        : (_uzerinde ? r.ic.withValues(alpha: .6) : r.kart);
    // web-tasarim.md: okunmamış gönderen + konu w600 ön plan; okunmuş w400 muted-foreground.
    final adRengi = taslak ? Marka.gul : (okunmamis ? r.metin : r.silik);
    final konuRengi = okunmamis ? r.metin : r.silik;

    Widget simge(IconData i, String etiket, {Color? renk}) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(i, size: 14, color: renk ?? r.silik, semanticLabel: etiket),
    );
    final yildizGorunur = m.yildizli || _uzerinde;

    final icerik = Material(
      color: arka,
      child: InkWell(
        onTap: widget.dokun,
        onLongPress: widget.sec,
        hoverColor: Colors.transparent,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    button: true,
                    label: widget.secili ? 'Seçimi kaldır' : 'Seç',
                    child: GestureDetector(
                      onTap: widget.sec,
                      // Web: fare üstündeyken (ya da seçiliyken) avatarın yerine onay kutusu.
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: widget.secili || widget.secimModu || (_uzerinde && context.genis)
                            ? Center(
                                key: const ValueKey('s'),
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: widget.secili ? r.birincil : r.kart,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: widget.secili ? r.birincil : r.silik, width: 1.2),
                                  ),
                                  child: widget.secili ? const Icon(Simge.onay, color: Colors.white, size: 12) : null,
                                ),
                              )
                            : Avatar(gorunenAd(karsi), boyut: 36, tohum: tohum.isEmpty ? karsi : tohum),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Ad + simgeler sola, tarih sağ kenara (Spacer + Flexible boşluğu paylaşmasın).
                            Expanded(
                              child: Row(
                                children: [
                                  if (okunmamis)
                                    Container(
                                      key: const ValueKey('okunmamis-nokta'),
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(color: r.birincil, shape: BoxShape.circle),
                                    ),
                                  Flexible(
                                    child: Text(
                                      taslak ? 'Taslak' : ad,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 20 / 14,
                                        fontWeight: okunmamis ? FontWeight.w600 : FontWeight.w400,
                                        color: adRengi,
                                      ),
                                    ),
                                  ),
                                  if (widget.hesapRengi != null)
                                    Container(
                                      key: const ValueKey('hesap-etiketi'),
                                      constraints: const BoxConstraints(maxWidth: 130),
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(color: widget.hesapRengi!.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(color: widget.hesapRengi, shape: BoxShape.circle),
                                          ),
                                          if ((widget.hesapEtiketi ?? '').isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                widget.hesapEtiketi!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: widget.hesapRengi),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  if (m.onemli) simge(Simge.uyari, 'Önemli', renk: const Color(0xFFF97316)),
                                  if (m.yanitlandi) simge(Simge.yanitla, 'Yanıtlandı'),
                                  if (m.iletildi) simge(Simge.ilet, 'İletildi'),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              kisaZaman(m.tarih),
                              style: TextStyle(
                                fontSize: 12,
                                height: 16 / 12,
                                color: okunmamis ? r.birincil : r.silik,
                                fontWeight: okunmamis ? FontWeight.w600 : FontWeight.w400,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.konu.trim().isEmpty ? '(konu yok)' : m.konu,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: okunmamis ? FontWeight.w600 : FontWeight.w400, color: konuRengi),
                              ),
                            ),
                            if (m.ekVar) simge(Simge.ek, 'Ekli'),
                            // Web: fare üstündeyken Okundu / Okunmadı yap.
                            if (_uzerinde && !widget.secimModu)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: InkResponse(
                                  key: const ValueKey('satir-okundu'),
                                  onTap: widget.okundu,
                                  radius: 14,
                                  child: Tooltip(
                                    message: m.okundu ? 'Okunmadı yap' : 'Okundu yap',
                                    child: Icon(m.okundu ? Simge.posta : Simge.okunduYap, size: 16, color: r.silik),
                                  ),
                                ),
                              ),
                            Semantics(
                              button: true,
                              label: m.yildizli ? 'Yıldızı kaldır' : 'Yıldızla',
                              child: InkResponse(
                                onTap: widget.yildiz,
                                radius: 14,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Opacity(
                                    opacity: yildizGorunur ? 1 : 0,
                                    child: Icon(m.yildizli ? Simge.yildizDolu : Simge.yildiz, size: 16, color: m.yildizli ? yildizRengi : r.silik),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (m.onizleme.trim().isNotEmpty)
                          Text(
                            m.onizleme.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, height: 16 / 12, color: r.silik),
                          ),
                        if (etiketler.isNotEmpty || m.ertelemeBitis != null || m.takip)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                if (m.takip) const _Cip('Takip', renk: Color(0xFFF43F5E), ikon: Simge.hatirlatma),
                                if (m.ertelemeBitis != null) _Cip(kisaZaman(m.ertelemeBitis), renk: const Color(0xFFF59E0B), ikon: Simge.ertele),
                                for (final e in etiketler) _Cip(e.ad, renk: etiketRengi(e.renk)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Fare üzerindeyken arşivle/sil satırın sağ altında (önizleme satırı) yüzer: tarih, okundu düğmesi ve
            // yıldız web'deki yerlerinde görünür kalır; yerleşim hiç kaymaz.
            if (!widget.secimModu)
              Positioned(
                bottom: 6,
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
            // Web: okunmamış iletinin solunda 3 px birincil şerit.
            if (okunmamis)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(key: const ValueKey('okunmamis-serit'), width: 2, color: r.birincil),
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
            border: Border(bottom: BorderSide(color: r.kenar)),
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
    return [if (!widget.arsivde) d(Simge.arsiv, 'Arşivle', widget.arsivle), d(Simge.sil, widget.copte ? 'Kalıcı sil' : 'Sil', widget.sil)];
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

/// Web'deki küçük yuvarlak çip (text-[11px], renk/12 zemin).
class _Cip extends StatelessWidget {
  const _Cip(this.metin, {required this.renk, this.ikon});
  final String metin;
  final Color renk;
  final IconData? ikon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ikon != null) ...[Icon(ikon, size: 12, color: renk), const SizedBox(width: 4)],
        Text(
          metin,
          style: TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w500, color: renk),
        ),
      ],
    ),
  );
}
