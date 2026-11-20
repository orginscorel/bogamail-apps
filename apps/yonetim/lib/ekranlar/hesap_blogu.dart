import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/simgeler.dart';
import '../veri/bicim.dart';
import '../veri/tercihler.dart';
import 'ayarlar.dart';
import 'bolumler.dart';
import 'hesap_avatar.dart';
import 'kabuk.dart' show cikisOnayi;

/// Yan menünün altındaki oturum açmış kullanıcı bloğu (posta uygulamasıyla aynı düzen): 32 px resim, ad, e-posta.
/// Dokununca hesap menüsü açılır: masaüstünde bloğun üstünde ~280 px açılır kutu, telefonda alt sayfa.
class HesapBlogu extends StatelessWidget {
  const HesapBlogu({super.key, required this.ac, this.dolgu = const EdgeInsets.fromLTRB(8, 8, 8, 8)});
  final void Function(Bolum) ac;
  final EdgeInsets dolgu;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ad = Uyg.ad.isNotEmpty ? Uyg.ad : Uyg.adres;
    return Padding(
      padding: dolgu,
      child: Builder(
        builder: (bc) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => hesapMenusuAc(bc, ac),
          child: Semantics(
            button: true,
            label: 'Hesap menüsü: $ad',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  const ProfilResmi(boyut: 32, duzenlenebilir: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: r.metin)),
                        if (Uyg.ad.isNotEmpty)
                          Text(Uyg.adres, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: r.soluk)),
                      ],
                    ),
                  ),
                  Icon(Simgeler.unfoldMore, size: 18, color: r.silik),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hesap menüsünü açar: geniş ekranda bloğun üstüne yaslanan açılır kutu, telefonda alt sayfa.
Future<void> hesapMenusuAc(BuildContext context, void Function(Bolum) ac) async {
  final genis = MediaQuery.sizeOf(context).width >= 600;
  void sec(_HesapSecimi s) {
    switch (s) {
      case _HesapSecimi.profil:
        AyarlarEkrani.istenenBolum.value = 'hesap';
        ac(Bolum.ayarlar);
      case _HesapSecimi.ayarlar:
        AyarlarEkrani.istenenBolum.value = null;
        ac(Bolum.ayarlar);
      case _HesapSecimi.cikis:
        cikisOnayi(kokGezgin.currentContext ?? context);
    }
  }

  if (!genis) {
    final s = await showModalBottomSheet<_HesapSecimi>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: _HesapMenusu(sec: (v) => Navigator.pop(c, v)))),
    );
    if (s != null) sec(s);
    return;
  }
  final kutu = context.findRenderObject() as RenderBox?;
  final ekran = MediaQuery.sizeOf(context);
  final ust = kutu == null ? Offset.zero : kutu.localToGlobal(Offset.zero);
  final s = await showGeneralDialog<_HesapSecimi>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (c, a, _, w) => FadeTransition(
      opacity: a,
      child: SlideTransition(position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(a), child: w),
    ),
    pageBuilder: (c, _, _) => Stack(
      children: [
        Positioned(
          left: ust.dx + 8,
          bottom: ekran.height - ust.dy + 4,
          width: 280,
          child: Material(
            color: c.r.kart,
            elevation: 2,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.r.kenar)),
            clipBehavior: Clip.antiAlias,
            child: _HesapMenusu(sec: (v) => Navigator.pop(c, v)),
          ),
        ),
      ],
    ),
  );
  if (s != null) sec(s);
}

enum _HesapSecimi { profil, ayarlar, cikis }

class _HesapMenusu extends StatelessWidget {
  const _HesapMenusu({required this.sec});
  final void Function(_HesapSecimi) sec;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ad = Uyg.ad.isNotEmpty ? Uyg.ad : Uyg.adres;
    final taklit = Uyg.taklit != null;
    Widget oge(IconData i, String t, _HesapSecimi s, {Color? renk}) => ListTile(
      dense: true,
      leading: Icon(i, size: 20, color: renk ?? r.soluk),
      title: Text(t, style: TextStyle(fontSize: 14, color: renk ?? r.metin)),
      onTap: () => sec(s),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const ProfilResmi(boyut: 40, duzenlenebilir: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    Text(Uyg.adres, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: r.soluk)),
                    Text(rolEtiketi(Uyg.rol), style: TextStyle(fontSize: 12, color: r.vurgu)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 8, color: r.kenar.withValues(alpha: .6)),
        oge(Simgeler.person, 'Profil ve güvenlik', _HesapSecimi.profil),
        oge(Simgeler.settings, 'Ayarlar', _HesapSecimi.ayarlar),
        ListTile(
          dense: true,
          leading: Icon(Simgeler.palette, size: 20, color: r.soluk),
          title: Text('Tema', style: TextStyle(fontSize: 14, color: r.metin)),
          trailing: ValueListenableBuilder<ThemeMode>(
            valueListenable: temaKipi,
            builder: (c, m, _) => SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Simgeler.brightnessAuto, size: 18), tooltip: 'Sistem'),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Simgeler.lightMode, size: 18), tooltip: 'Açık'),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Simgeler.darkMode, size: 18), tooltip: 'Koyu'),
              ],
              selected: {m},
              onSelectionChanged: (s) => temaKaydet(s.first),
            ),
          ),
        ),
        Divider(height: 8, color: r.kenar.withValues(alpha: .6)),
        oge(Simgeler.logout, taklit ? 'Görünümden çık' : 'Çıkış yap', _HesapSecimi.cikis, renk: Marka.gul),
        const SizedBox(height: 8),
      ],
    );
  }
}
