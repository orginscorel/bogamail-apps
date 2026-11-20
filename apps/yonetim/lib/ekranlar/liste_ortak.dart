import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../ortak/bilesenler.dart';
import '../ortak/simgeler.dart';

/// Kayıt ayrıntısını açar: geniş ekranda sağdan kayan yan panel, telefonda tam sayfa.
/// Gövde kendi sayfasındaymış gibi davranabilir (Navigator.maybePop paneli kapatır).
Future<T?> ayrintiAc<T>(BuildContext context, String baslik, Widget govde, {List<Widget>? eylemler, double genislik = 620}) {
  if (!context.genis) return sayfaAc<T>(context, baslik, govde, eylemler: eylemler);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.black.withValues(alpha: .28),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (c, _, _) {
      final w = MediaQuery.sizeOf(c).width;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: w < genislik + 40 ? w : genislik,
          height: double.infinity,
          child: Material(
            elevation: 12,
            color: c.r.zemin,
            child: Scaffold(
              backgroundColor: c.r.zemin,
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: [
                  ...?eylemler,
                  IconButton(tooltip: 'Kapat', onPressed: () => Navigator.of(c).maybePop(), icon: const Icon(Simgeler.close)),
                  const SizedBox(width: 8),
                ],
              ),
              body: govde,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (c, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Birkaç büyük düğme içeren yönetim penceresi (web panelindeki "Yönet" iletişim kutusu): başlık, özet ve eylemler.
Future<void> yonetimPenceresi(BuildContext context, {required String baslik, String? alt, Widget? ozet, required List<SatirEylemiDugmesi> eylemler}) =>
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(baslik, maxLines: 2, overflow: TextOverflow.ellipsis, style: gosterim(18, agirlik: FontWeight.w600)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (alt != null && alt.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(alt, style: TextStyle(color: c.r.soluk, fontSize: 13))),
                if (ozet != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ozet),
                for (final (i, e) in eylemler.indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  EylemSatiri(
                    ikon: e.ikon,
                    baslik: e.baslik,
                    ipucu: e.ipucu,
                    tehlikeli: e.tehlikeli,
                    onTap: () {
                      Navigator.pop(c);
                      e.calistir();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
      ),
    );

/// [yonetimPenceresi] düğmesi.
class SatirEylemiDugmesi {
  const SatirEylemiDugmesi(this.ikon, this.baslik, this.calistir, {this.ipucu, this.tehlikeli = false});
  final IconData ikon;
  final String baslik;
  final String? ipucu;
  final VoidCallback calistir;
  final bool tehlikeli;
}

/// Küçük gösterge kutusu (kuyruk özeti gibi yoğun şeritler için).
class OzetKutusu extends StatelessWidget {
  const OzetKutusu(this.etiket, this.deger, {super.key, this.alt, this.renk, this.ikon});
  final String etiket, deger;
  final String? alt;
  final Color? renk;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(14), border: Border.all(color: r.kenar)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (ikon != null) ...[Icon(ikon, size: 14, color: renk ?? r.silik), const SizedBox(width: 5)],
              Expanded(child: Text(etiket, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 11.5, fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: 2),
          Text(deger, maxLines: 1, overflow: TextOverflow.ellipsis, style: gosterim(19, agirlik: FontWeight.w600, renk: renk ?? r.metin)),
          if (alt != null && alt!.isNotEmpty) Text(alt!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Dar, sabit genişlikli tablo hücresine sığmayan rozet / metni taşırmadan küçültür.
class Sigdir extends StatelessWidget {
  const Sigdir(this.child, {super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: child);
}
