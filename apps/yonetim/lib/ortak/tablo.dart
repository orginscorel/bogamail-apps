import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import 'sayfali.dart';

/// Tablo sütunu. [esnek] genişlik payı; [genislik] verilirse sabit genişlik. [siralama]: sunucunun `sort`
/// parametresindeki ad (verilirse başlığa dokununca sıralanır).
class Sutun<T> {
  const Sutun(this.baslik, {required this.hucre, this.esnek = 2, this.genislik, this.siralama, this.sagaYasla = false});
  final String baslik;
  final Widget Function(BuildContext, T) hucre;
  final int esnek;
  final double? genislik;
  final String? siralama;
  final bool sagaYasla;
}

/// Satır menüsündeki eylem.
class SatirEylemi {
  const SatirEylemi(this.ikon, this.etiket, this.calistir, {this.tehlikeli = false});
  final IconData ikon;
  final String etiket;
  final VoidCallback calistir;
  final bool tehlikeli;
}

/// Satırın "⋮" menüsü (tablo satırları ve telefon kartları).
class SatirMenusu extends StatelessWidget {
  const SatirMenusu(this.eylemler, {super.key, this.ipucu = 'İşlemler'});
  final List<SatirEylemi> eylemler;
  final String ipucu;

  @override
  Widget build(BuildContext context) {
    if (eylemler.isEmpty) return const SizedBox(width: 40);
    final r = context.r;
    return PopupMenuButton<int>(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 340),
      tooltip: ipucu,
      icon: Icon(Icons.more_vert_rounded, color: r.soluk, size: 20),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: r.kenar)),
      color: r.kart,
      onSelected: (i) => eylemler[i].calistir(),
      itemBuilder: (_) => [
        for (final (i, e) in eylemler.indexed)
          PopupMenuItem<int>(
            value: i,
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(e.ikon, size: 18, color: e.tehlikeli ? Marka.gul : r.soluk),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    e.etiket,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: e.tehlikeli ? Marka.gul : r.metin),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Duyarlı veri tablosu: geniş alanda başlık satırı sabit, hizalı sütunlar, sıralama, satır üzerine gelme,
/// satır menüsü ve sayfalama; dar alanda (telefon) [kart] ile çizilen kartlar ve sonsuz kaydırma.
class VeriTablosu<T> extends StatefulWidget {
  const VeriTablosu({
    super.key,
    required this.yukleyici,
    required this.sutunlar,
    required this.kart,
    required this.bosMetin,
    this.bosIkon = Icons.inbox_rounded,
    this.onTap,
    this.eylemler,
    this.siralama,
    this.artan = true,
    this.siralamaDegisti,
    this.ust,
    this.secili,
    this.vurgulu,
    this.tabloEnAz = 720,
  });

  final SayfaYukleyici<T> yukleyici;
  final List<Sutun<T>> sutunlar;
  final Widget Function(BuildContext, T) kart;
  final String bosMetin;
  final IconData bosIkon;
  final void Function(T)? onTap;
  final List<SatirEylemi> Function(T)? eylemler;
  final String? siralama;
  final bool artan;
  final void Function(String alan, bool artan)? siralamaDegisti;

  /// Tablonun / listenin üstündeki alan (filtre çubuğu, özet kutuları). Tabloda sabit kalır, listede kayar.
  final Widget? ust;
  final bool Function(T)? secili;
  final bool Function(T)? vurgulu;

  /// Bu genişlikten itibaren tablo çizilir.
  final double tabloEnAz;

  @override
  State<VeriTablosu<T>> createState() => _VeriTablosuState<T>();
}

class _VeriTablosuState<T> extends State<VeriTablosu<T>> {
  final _kaydirma = ScrollController();

  @override
  void dispose() {
    _kaydirma.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, k) {
      if (k.maxWidth < widget.tabloEnAz) {
        return SayfaliListe<T>(
          yukleyici: widget.yukleyici,
          ayrac: false,
          ust: widget.ust,
          bosMetin: widget.bosMetin,
          bosIkon: widget.bosIkon,
          dolgu: const EdgeInsets.fromLTRB(12, 4, 12, 88),
          oge: widget.kart,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?widget.ust,
          Expanded(
            child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), child: _tablo(context)),
          ),
        ],
      );
    },
  );

  Widget _tablo(BuildContext context) {
    final r = context.r;
    final eylemVar = widget.eylemler != null;
    return Container(
      decoration: BoxDecoration(
        color: r.kart,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: r.kenar),
        boxShadow: r.hafifGolge,
      ),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: widget.yukleyici,
        builder: (context, _) {
          final y = widget.yukleyici;
          Widget govde;
          if (y.ogeler.isEmpty) {
            if (y.hata != null) {
              govde = Durum.hata(y.hata!, tekrar: y.yenile);
            } else if (y.yukleniyor || y.ilkYukleme) {
              govde = const Durum.yukleniyor();
            } else {
              govde = Durum.bos(widget.bosMetin, ikon: widget.bosIkon);
            }
          } else {
            govde = RefreshIndicator.adaptive(
              onRefresh: () => y.sayfaGit(y.sayfa < 1 ? 1 : y.sayfa),
              child: Scrollbar(
                controller: _kaydirma,
                child: ListView.builder(
                  controller: _kaydirma,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: y.ogeler.length,
                  itemBuilder: (c, i) {
                    final o = y.ogeler[i];
                    return _TabloSatiri(
                      secili: widget.secili?.call(o) ?? false,
                      vurgulu: widget.vurgulu?.call(o) ?? false,
                      son: i == y.ogeler.length - 1,
                      onTap: widget.onTap == null ? null : () => widget.onTap!(o),
                      children: [
                        for (final s in widget.sutunlar) _hucre(s, Align(alignment: s.sagaYasla ? Alignment.centerRight : Alignment.centerLeft, child: s.hucre(c, o))),
                        if (eylemVar) SizedBox(width: 44, child: SatirMenusu(widget.eylemler!(o))),
                      ],
                    );
                  },
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: r.ic.withValues(alpha: r.koyu ? .6 : .7),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(
                  children: [
                    for (final s in widget.sutunlar) _hucre(s, _baslikHucresi(context, s)),
                    if (eylemVar) const SizedBox(width: 44),
                  ],
                ),
              ),
              Divider(height: 1, color: r.kenar),
              SizedBox(
                height: 2,
                child: y.yukleniyor && y.ogeler.isNotEmpty ? LinearProgressIndicator(minHeight: 2, color: r.vurgu, backgroundColor: Colors.transparent) : null,
              ),
              Expanded(child: govde),
              Divider(height: 1, color: r.kenar),
              _altBilgi(context, y),
            ],
          );
        },
      ),
    );
  }

  Widget _hucre(Sutun<T> s, Widget w) => s.genislik != null
      ? SizedBox(
          width: s.genislik,
          child: Padding(padding: const EdgeInsets.only(right: 12), child: w),
        )
      : Expanded(
          flex: s.esnek,
          child: Padding(padding: const EdgeInsets.only(right: 12), child: w),
        );

  Widget _baslikHucresi(BuildContext context, Sutun<T> s) {
    final r = context.r;
    final aktif = s.siralama != null && s.siralama == widget.siralama;
    final stil = TextStyle(color: aktif ? r.metin : r.silik, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .5);
    final yazi = Text(trBuyuk(s.baslik), maxLines: 1, overflow: TextOverflow.ellipsis, style: stil);
    if (s.siralama == null || widget.siralamaDegisti == null) {
      return Align(alignment: s.sagaYasla ? Alignment.centerRight : Alignment.centerLeft, child: yazi);
    }
    return Align(
      alignment: s.sagaYasla ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => widget.siralamaDegisti!(s.siralama!, aktif ? !widget.artan : true),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: yazi),
              const SizedBox(width: 3),
              Icon(
                aktif ? (widget.artan ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded) : Icons.unfold_more_rounded,
                size: 14,
                color: aktif ? r.vurgu : r.silik.withValues(alpha: .6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _altBilgi(BuildContext context, SayfaYukleyici<T> y) {
    final r = context.r;
    final bas = y.ogeler.isEmpty ? 0 : y.ilkSira + 1;
    final son = y.ilkSira + y.ogeler.length;
    final sayfa = y.sayfa < 1 ? 1 : y.sayfa;
    final n = y.sayfaSayisi;
    Widget dugme(IconData i, String ipucu, int? hedef) => IconButton(
      tooltip: ipucu,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      onPressed: hedef == null || y.yukleniyor ? null : () => y.sayfaGit(hedef),
      icon: Icon(i),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              y.toplam == 0 ? 'Kayıt yok' : '${sayiYaz(bas)}–${sayiYaz(son)} / ${sayiYaz(y.toplam)} kayıt',
              style: TextStyle(color: r.silik, fontSize: 12.5),
            ),
          ),
          if (n > 1) ...[
            dugme(Icons.first_page_rounded, 'İlk sayfa', sayfa > 1 ? 1 : null),
            dugme(Icons.chevron_left_rounded, 'Önceki sayfa', sayfa > 1 ? sayfa - 1 : null),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('Sayfa $sayfa / $n', style: TextStyle(fontSize: 12.5, color: r.soluk, fontWeight: FontWeight.w600)),
            ),
            dugme(Icons.chevron_right_rounded, 'Sonraki sayfa', sayfa < n ? sayfa + 1 : null),
            dugme(Icons.last_page_rounded, 'Son sayfa', sayfa < n ? n : null),
          ],
        ],
      ),
    );
  }
}

class _TabloSatiri extends StatefulWidget {
  const _TabloSatiri({required this.children, this.onTap, this.secili = false, this.vurgulu = false, this.son = false});
  final List<Widget> children;
  final VoidCallback? onTap;
  final bool secili, vurgulu, son;
  @override
  State<_TabloSatiri> createState() => _TabloSatiriState();
}

class _TabloSatiriState extends State<_TabloSatiri> {
  bool _ustunde = false;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final renk = widget.secili
        ? r.vurguYumusak
        : widget.vurgulu
        ? Marka.kehribar.withValues(alpha: .12)
        : (_ustunde ? r.ic.withValues(alpha: .7) : Colors.transparent);
    return MouseRegion(
      onEnter: (_) => setState(() => _ustunde = true),
      onExit: (_) => setState(() => _ustunde = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: Material(
        color: renk,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: widget.secili ? r.vurgu : Colors.transparent, width: 3),
                bottom: widget.son ? BorderSide.none : BorderSide(color: r.kenar.withValues(alpha: .7)),
              ),
            ),
            child: Row(children: widget.children),
          ),
        ),
      ),
    );
  }
}

/// Tablo hücresi: kalın başlık + soluk alt satır.
class IkiSatir extends StatelessWidget {
  const IkiSatir(this.ust, {super.key, this.alt, this.mono = false, this.sol, this.kalin = true});
  final String ust;
  final String? alt;
  final bool mono, kalin;
  final Widget? sol;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final yazi = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ust.isEmpty ? '—' : ust,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: kalin ? FontWeight.w600 : FontWeight.w500, fontSize: 13.5, fontFamily: mono ? 'monospace' : null),
        ),
        if (alt != null && alt!.isNotEmpty)
          Text(alt!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 12)),
      ],
    );
    if (sol == null) return yazi;
    return Row(
      children: [
        sol!,
        const SizedBox(width: 10),
        Flexible(child: yazi),
      ],
    );
  }
}

/// Soluk tek satırlık hücre metni.
class SolukMetin extends StatelessWidget {
  const SolukMetin(this.metin, {super.key, this.mono = false});
  final String metin;
  final bool mono;
  @override
  Widget build(BuildContext context) => Text(
    metin.isEmpty ? '—' : metin,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(color: context.r.soluk, fontSize: 13, fontFamily: mono ? 'monospace' : null),
  );
}

/// Telefon kartı: tablo satırıyla aynı bilgileri taşır (başlık, alt satır, rozetler, etiket–değer çiftleri, menü).
class VeriKarti extends StatelessWidget {
  const VeriKarti({
    super.key,
    required this.baslik,
    this.alt,
    this.sol,
    this.rozetler = const [],
    this.alanlar = const [],
    this.eylemler = const [],
    this.onTap,
    this.secili = false,
    this.vurgulu = false,
    this.ek,
  });
  final String baslik;
  final String? alt;
  final Widget? sol;
  final List<Widget> rozetler;

  /// (etiket, değer) çiftleri: küçük ızgara olarak gösterilir.
  final List<(String, String)> alanlar;
  final List<SatirEylemi> eylemler;
  final VoidCallback? onTap;
  final bool secili, vurgulu;

  /// Alanların altında ek içerik (kullanım çubuğu vb.).
  final Widget? ek;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: secili ? r.vurguYumusak : (vurgulu ? Marka.kehribar.withValues(alpha: .12) : r.kart),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: secili ? r.vurgu : r.kenar)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sol != null) ...[sol!, const SizedBox(width: 12)],
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(baslik, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                            if (alt != null && alt!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(alt!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 12.5)),
                              ),
                            if (rozetler.isNotEmpty) ...[const SizedBox(height: 6), Wrap(spacing: 6, runSpacing: 4, children: rozetler)],
                          ],
                        ),
                      ),
                    ),
                    if (eylemler.isNotEmpty) SatirMenusu(eylemler) else const SizedBox(width: 10),
                  ],
                ),
                if (alanlar.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        for (final (e, d) in alanlar)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(e, style: TextStyle(color: r.silik, fontSize: 11)),
                              Text(d.isEmpty ? '—' : d, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
                if (ek != null) ...[const SizedBox(height: 10), Padding(padding: const EdgeInsets.only(right: 10), child: ek!)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Etkin filtre: çip olarak gösterilir, çarpıyla kaldırılır.
class EtkinFiltre {
  const EtkinFiltre(this.etiket, this.kaldir, {this.ikon});
  final String etiket;
  final VoidCallback kaldir;
  final IconData? ikon;
}

/// Arama + filtre düğmeleri + etkin filtre çipleri ("Tümünü temizle").
class FiltreCubugu extends StatelessWidget {
  const FiltreCubugu({super.key, this.arama, this.filtreler = const [], this.etkinler = const [], this.sag});

  /// Genelde [AramaAlani].
  final Widget? arama;

  /// Filtre seçim düğmeleri / çipleri.
  final List<Widget> filtreler;
  final List<EtkinFiltre> etkinler;

  /// Sağda ek içerik (sayaç, görünüm düğmesi).
  final Widget? sag;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return LayoutBuilder(
      builder: (context, k) {
        final genis = k.maxWidth >= 720;
        final ust = genis
            ? Row(
                children: [
                  if (arama != null) SizedBox(width: (k.maxWidth * .38).clamp(240, 420), child: arama),
                  if (filtreler.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _aralikli(filtreler))),
                    ),
                  ] else
                    const Spacer(),
                  ?sag,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (arama != null)
                    Row(
                      children: [
                        Expanded(child: arama!),
                        ?sag,
                      ],
                    ),
                  if (filtreler.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _aralikli(filtreler))),
                  ],
                ],
              );
        return Padding(
          padding: EdgeInsets.fromLTRB(genis ? 16 : 12, 4, genis ? 16 : 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ust,
              if (etkinler.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.filter_alt_rounded, size: 16, color: r.vurgu),
                    for (final f in etkinler)
                      InputChip(
                        avatar: f.ikon == null ? null : Icon(f.ikon, size: 15),
                        label: Text(f.etiket),
                        labelStyle: TextStyle(fontSize: 12.5, color: r.metin, fontWeight: FontWeight.w600),
                        backgroundColor: r.vurguYumusak,
                        side: BorderSide(color: r.vurgu.withValues(alpha: .35)),
                        visualDensity: VisualDensity.compact,
                        deleteIcon: const Icon(Icons.close_rounded, size: 15),
                        deleteButtonTooltipMessage: 'Filtreyi kaldır',
                        onDeleted: f.kaldir,
                      ),
                    if (etkinler.length > 1)
                      TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () {
                          for (final f in [...etkinler]) {
                            f.kaldir();
                          }
                        },
                        child: const Text('Tümünü temizle'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _aralikli(List<Widget> l) => [
    for (final (i, w) in l.indexed) ...[if (i > 0) const SizedBox(width: 6), w],
  ];
}

/// Açılır filtre düğmesi: seçili değeri gösterir, dokununca seçenek menüsü açar.
class FiltreDugmesi<T> extends StatelessWidget {
  const FiltreDugmesi({super.key, required this.etiket, required this.secenekler, required this.secili, required this.secildi, this.ikon});
  final String etiket;
  final List<(T, String)> secenekler;
  final T secili;
  final ValueChanged<T> secildi;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ilk = secenekler.isEmpty ? null : secenekler.first.$1;
    final aktif = secili != ilk;
    final secEtiket = secenekler.where((s) => s.$1 == secili).map((s) => s.$2).firstOrNull ?? '';
    return PopupMenuButton<T>(
      tooltip: etiket,
      position: PopupMenuPosition.under,
      color: r.kart,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: r.kenar)),
      onSelected: secildi,
      itemBuilder: (_) => [
        for (final (d, e) in secenekler)
          PopupMenuItem<T>(
            value: d,
            height: 40,
            child: Row(
              children: [
                SizedBox(width: 22, child: d == secili ? Icon(Icons.check_rounded, size: 18, color: r.vurgu) : null),
                const SizedBox(width: 6),
                Text(e, style: const TextStyle(fontSize: 13.5)),
              ],
            ),
          ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: aktif ? r.vurguYumusak : r.kart,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: aktif ? r.vurgu.withValues(alpha: .45) : r.kenar),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ikon != null) ...[Icon(ikon, size: 16, color: aktif ? r.vurgu : r.soluk), const SizedBox(width: 6)],
            Text(aktif ? '$etiket: $secEtiket' : etiket, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: r.metin)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 18, color: r.soluk),
          ],
        ),
      ),
    );
  }
}

/// Türkçe büyük harf (i → İ, ı → I).
String trBuyuk(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
