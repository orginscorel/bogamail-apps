import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../ortak/simgeler.dart';
import '../veri/durum.dart';
import '../veri/modeller.dart';
import '../veri/yardimci.dart';

/// Liste satırı: okunmamışlar kalın + nokta, yıldız, ek ataşı, önemli işareti, önizleme, etiket noktaları.
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
  });

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
    final arka = widget.secili
        ? r.birincilYumusak
        : widget.acik
        ? r.ic
        : Colors.transparent;

    final icerik = Material(
      color: r.kart,
      child: InkWell(
        onTap: widget.dokun,
        onLongPress: widget.sec,
        child: Container(
          color: arka,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                    child: widget.secili || (widget.secimModu)
                        ? Container(
                            key: const ValueKey('s'),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.secili ? r.birincil : r.ic),
                            child: Icon(widget.secili ? Icons.check_rounded : Icons.circle_outlined, color: widget.secili ? Colors.white : r.silik, size: 22),
                          )
                        : Avatar(gorunenAd(karsi), boyut: 40, tohum: tohum.isEmpty ? karsi : tohum),
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
                        if (okunmamis)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(color: r.birincil, shape: BoxShape.circle),
                          ),
                        Expanded(
                          child: Text(
                            taslak ? 'Taslak' : ad,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14.5, fontWeight: okunmamis ? FontWeight.w700 : FontWeight.w500, color: taslak ? Marka.gul : r.metin),
                          ),
                        ),
                        if (m.onemli)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.label_important_rounded, size: 16, color: Marka.kehribar, semanticLabel: 'Önemli'),
                          ),
                        if (m.ekVar)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.attach_file_rounded, size: 15, color: r.silik, semanticLabel: 'Ekli'),
                          ),
                        if (m.yanitlandi)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.reply_rounded, size: 15, color: r.silik, semanticLabel: 'Yanıtlandı'),
                          ),
                        const SizedBox(width: 6),
                        if (_uzerinde && !widget.secimModu)
                          ..._fareEylemleri(r)
                        else
                          Text(
                            kisaZaman(m.tarih),
                            style: TextStyle(fontSize: 12, color: okunmamis ? r.birincil : r.silik, fontWeight: okunmamis ? FontWeight.w700 : FontWeight.w500),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            m.konu.trim().isEmpty ? '(konu yok)' : m.konu,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, fontWeight: okunmamis ? FontWeight.w600 : FontWeight.w400, color: okunmamis ? r.metin : r.soluk),
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
                              child: Icon(m.yildizli ? Icons.star_rounded : Icons.star_border_rounded, size: 20, color: m.yildizli ? Marka.kehribar : r.kenar),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (m.onizleme.trim().isNotEmpty)
                      Text(
                        m.onizleme.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: r.silik, height: 1.35),
                      ),
                    if (etiketler.isNotEmpty || m.ertelemeBitis != null || m.takip)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (m.takip) const Rozet('Takip', renk: Marka.mavi, ikon: Icons.notifications_active_outlined),
                            if (m.ertelemeBitis != null) Rozet(kisaZaman(m.ertelemeBitis), renk: Marka.kehribar, ikon: Icons.snooze_rounded),
                            for (final e in etiketler) Rozet(e.ad, renk: etiketRengi(e.renk)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final satir = MouseRegion(
      onEnter: (_) => setState(() => _uzerinde = true),
      onExit: (_) => setState(() => _uzerinde = false),
      child: Semantics(label: '${okunmamis ? 'Okunmamış. ' : ''}$ad. ${m.konu}. ${kisaZaman(m.tarih)}', excludeSemantics: false, child: icerik),
    );

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
            icon: okunmamis ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
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
              icon: Icons.archive_outlined,
              label: 'Arşivle',
            ),
          SlidableAction(
            onPressed: (_) => _titret(widget.sil),
            backgroundColor: Marka.gul,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            label: 'Sil',
          ),
        ],
      ),
      child: satir,
    );
  }

  List<Widget> _fareEylemleri(Renkler r) {
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
      d(m.okundu ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined, m.okundu ? 'Okunmadı yap' : 'Okundu yap', widget.okundu),
      if (!widget.arsivde) d(Icons.archive_outlined, 'Arşivle', widget.arsivle),
      d(Icons.delete_outline_rounded, widget.copte ? 'Kalıcı sil' : 'Sil', widget.sil),
    ];
  }
}
