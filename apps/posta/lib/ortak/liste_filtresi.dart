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
class FiltreCubugu extends StatelessWidget {
  const FiltreCubugu({super.key, required this.secili, required this.degisti, this.sayilar = const {}});
  final ListeFiltresi secili;
  final ValueChanged<ListeFiltresi> degisti;

  /// Bilinen sayılar (ör. okunmamış). Olmayanlar sayısız gösterilir.
  final Map<ListeFiltresi, int> sayilar;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: r.ic,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: r.kenar),
      ),
      child: Row(
        children: [
          for (final f in ListeFiltresi.values)
            // Genişlik etiket (ve sayı) uzunluğuyla orantılı: dar bölmede de hiçbir etiket kesilmez.
            Expanded(
              flex: 30 + f.ad.length * 9 + ((sayilar[f] ?? 0) > 0 ? 30 : 0),
              child: _Bolum(filtre: f, secili: f == secili, sayi: sayilar[f], dokun: () => degisti(f)),
            ),
        ],
      ),
    );
  }
}

class _Bolum extends StatelessWidget {
  const _Bolum({required this.filtre, required this.secili, required this.sayi, required this.dokun});
  final ListeFiltresi filtre;
  final bool secili;
  final int? sayi;
  final VoidCallback dokun;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final sayiVar = sayi != null && sayi! > 0;
    return Semantics(
      button: true,
      selected: secili,
      label: '${filtre.ad}${sayiVar ? ', $sayi' : ''}${secili ? ', seçili' : ''}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: secili ? r.vurgu : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: secili ? r.hafifGolge : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('filtre-${filtre.name}'),
            borderRadius: BorderRadius.circular(9),
            onTap: dokun,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      filtre.ad,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(fontSize: 13, fontWeight: secili ? FontWeight.w600 : FontWeight.w500, color: secili ? Colors.white : r.metin),
                    ),
                  ),
                  if (sayiVar) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: secili ? Colors.white.withValues(alpha: .25) : r.vurgu, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        sayi! > 999 ? '999+' : '$sayi',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Süzgeç etkinken listenin üstünde ince bilgi şeridi: "Yalnızca okunmamış iletiler gösteriliyor · Temizle".
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
