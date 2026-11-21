import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

/// İleti listesinin üstündeki süzgeç. Sunucudaki `filter` sorgu değeriyle eşleşir (webmail.go listFilters).
enum ListeFiltresi {
  tumu('Tümü', null, Simge.tumPosta),
  okunmamis('Okunmamış', 'unread', Simge.okunmadiYap),
  yildizli('Yıldızlı', 'flagged', Simge.yildizDolu),
  ekli('Ekli', 'attachments', Simge.ek);

  const ListeFiltresi(this.ad, this.sunucuDegeri, this.ikon);
  final String ad;
  final String? sunucuDegeri;
  final IconData ikon;

  /// Etkin süzgeç şeridinde gösterilen açıklama.
  String get aciklama => switch (this) {
    ListeFiltresi.tumu => 'Tüm iletiler gösteriliyor',
    ListeFiltresi.okunmamis => 'Yalnızca okunmamış iletiler gösteriliyor',
    ListeFiltresi.yildizli => 'Yalnızca yıldızlı iletiler gösteriliyor',
    ListeFiltresi.ekli => 'Yalnızca ekli iletiler gösteriliyor',
  };

  String get bosMetin => switch (this) {
    ListeFiltresi.tumu => '',
    ListeFiltresi.okunmamis => 'Okunmamış ileti yok. Hepsini okumuşsunuz!',
    ListeFiltresi.yildizli => 'Yıldızlı ileti yok. Önemli iletileri ☆ ile yıldızlayabilirsiniz.',
    ListeFiltresi.ekli => 'Ek içeren ileti yok.',
  };
}

/// "Tümü · Okunmamış (N) · Yıldızlı · Ekli" bölümlü süzgeç çubuğu. Etkin bölüm dolu vurgu rengiyle belirgindir.
/// Web (message-list.tsx) sekmeleri: h-8 yuvarlak düğmeler, seçili olan birincil dolgu + beyaz yazı, diğerleri soluk.
/// [sayilar]: sekmede küçük sayı (ör. okunmamış) ve erişilebilirlik etiketi.
class FiltreCubugu extends StatelessWidget {
  const FiltreCubugu({super.key, required this.secili, required this.degisti, this.sayilar = const {}});
  final ListeFiltresi secili;
  final ValueChanged<ListeFiltresi> degisti;

  final Map<ListeFiltresi, int> sayilar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final f in ListeFiltresi.values) ...[
            _Bolum(filtre: f, secili: f == secili, sayi: sayilar[f], dokun: () => degisti(f)),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _Bolum extends StatefulWidget {
  const _Bolum({required this.filtre, required this.secili, required this.sayi, required this.dokun});
  final ListeFiltresi filtre;
  final bool secili;
  final int? sayi;
  final VoidCallback dokun;

  @override
  State<_Bolum> createState() => _BolumState();
}

class _BolumState extends State<_Bolum> {
  bool _uzerinde = false;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final secili = widget.secili;
    final sayiVar = widget.sayi != null && widget.sayi! > 0;
    return Semantics(
      button: true,
      selected: secili,
      label: '${widget.filtre.ad}${sayiVar ? ', ${widget.sayi}' : ''}${secili ? ', seçili' : ''}',
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _uzerinde = true),
        onExit: (_) => setState(() => _uzerinde = false),
        child: GestureDetector(
          key: ValueKey('filtre-${widget.filtre.name}'),
          onTap: widget.dokun,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: secili ? r.birincil : (_uzerinde ? r.ic : Colors.transparent),
              borderRadius: BorderRadius.circular(16),
              boxShadow: secili ? const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.filtre.ad,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 14, height: 20 / 14, color: secili ? Colors.white : (_uzerinde ? r.metin : r.silik)),
                ),
                // 1.4'teki gibi okunmamış sayısı sekmede (küçük, soluk).
                if (sayiVar) ...[
                  const SizedBox(width: 5),
                  Text(
                    sayiYaz(widget.sayi!),
                    key: ValueKey('filtre-sayi-${widget.filtre.name}'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: secili ? Colors.white.withValues(alpha: .85) : r.birincil,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FiltreBandi extends StatelessWidget {
  const FiltreBandi({super.key, required this.filtre, required this.temizle, this.sonuc});
  final ListeFiltresi filtre;
  final VoidCallback temizle;
  final int? sonuc;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      width: double.infinity,
      color: r.vurguYumusak,
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          Icon(Simge.suzgec, size: 16, color: r.vurgu),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sonuc == null ? filtre.aciklama : '${filtre.aciklama} (${sayiYaz(sonuc)})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: r.metin),
            ),
          ),
          TextButton(
            onPressed: temizle,
            style: TextButton.styleFrom(foregroundColor: r.vurgu, visualDensity: VisualDensity.compact),
            child: const Text('Temizle', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
