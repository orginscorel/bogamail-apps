// Eşitleme durumu göstergesi: "Canlı" (yeşil, SSE bağlı) / "Bağlanıyor…" / "Bağlantı yok — N sn sonra yeniden
// denenecek" (canlı geri sayım), son eşitleme zamanı ve "Şimdi eşitle". Kenar menüsü altında tam, telefonda liste
// başlığının altında yalnız bağlantı yokken ince bir şerit olarak.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../veri/birlesik.dart';
import '../veri/canli.dart';
import '../veri/durum.dart';

/// Kullanıcı "Şimdi eşitle"ye bastı: akış hemen yeniden bağlanır, sayılar ve açık liste tazelenir.
void simdiEsitle() {
  Canli.ben.simdiBaglan();
  PostaDurum.ben.sayilariYenile();
  unawaited(BirlesikDurum.ben.sayilariYenile());
}

String esitlemeMetni(CanliDurumu d, DateTime simdi) => switch (d.tur) {
  CanliTur.bagli => 'Canlı',
  CanliTur.baglaniyor => 'Bağlanıyor…',
  CanliTur.kapali => 'Eşitleme durdu',
  CanliTur.yok => () {
    final kalan = d.sonrakiDeneme == null ? 0 : d.sonrakiDeneme!.difference(simdi).inSeconds + 1;
    return kalan > 0 ? 'Bağlantı yok — $kalan sn sonra yeniden denenecek' : 'Bağlantı yok — yeniden deneniyor';
  }(),
};

String sonEsitlemeMetni(DateTime? t, DateTime simdi) {
  if (t == null) return 'Henüz eşitlenmedi';
  final s = simdi.difference(t).inSeconds;
  if (s < 5) return 'Son eşitleme: az önce';
  if (s < 60) return 'Son eşitleme: $s sn önce';
  if (s < 3600) return 'Son eşitleme: ${s ~/ 60} dk önce';
  final h = t.toLocal();
  return 'Son eşitleme: ${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
}

class EsitlemeDurumu extends StatefulWidget {
  const EsitlemeDurumu({super.key, this.serit = false});

  /// true: telefonda liste üstü ince şerit (yalnız bağlı değilken görünür).
  final bool serit;

  @override
  State<EsitlemeDurumu> createState() => _EsitlemeDurumuState();
}

class _EsitlemeDurumuState extends State<EsitlemeDurumu> {
  Timer? _saat;

  @override
  void initState() {
    super.initState();
    Canli.ben.durum.addListener(_degisti);
    Canli.ben.sonOlay.addListener(_degisti);
    _saatiKur();
  }

  @override
  void dispose() {
    Canli.ben.durum.removeListener(_degisti);
    Canli.ben.sonOlay.removeListener(_degisti);
    _saat?.cancel();
    super.dispose();
  }

  void _degisti() {
    _saatiKur();
    if (mounted) setState(() {});
  }

  /// Geri sayım ve "N sn önce" için saniyelik tazeleme; bağlıyken şeritte gerekmez.
  void _saatiKur() {
    final gerek = !widget.serit || Canli.ben.durum.value.tur != CanliTur.bagli;
    if (gerek && _saat == null) {
      _saat = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!gerek) {
      _saat?.cancel();
      _saat = null;
    }
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
    final metin = esitlemeMetni(d, simdi);
    if (widget.serit) {
      if (d.tur == CanliTur.bagli || d.tur == CanliTur.kapali) return const SizedBox.shrink();
      return Material(
        key: const ValueKey('esitleme-serit'),
        color: renk.withValues(alpha: .1),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          child: Row(
            children: [
              Icon(d.tur == CanliTur.yok ? Icons.cloud_off_rounded : Icons.sync_rounded, size: 16, color: renk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metin,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: r.metin),
                ),
              ),
              TextButton(onPressed: simdiEsitle, child: const Text('Şimdi eşitle')),
            ],
          ),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      label: '$metin. ${sonEsitlemeMetni(Canli.ben.sonOlay.value, simdi)}',
      child: Row(
        key: const ValueKey('esitleme-durumu'),
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  metin,
                  maxLines: 2,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: d.tur == CanliTur.bagli ? Marka.zumrut : r.metin),
                ),
                Text(sonEsitlemeMetni(Canli.ben.sonOlay.value, simdi), style: TextStyle(fontSize: 11, color: r.silik)),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('simdi-esitle'),
            tooltip: 'Şimdi eşitle',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.sync_rounded, size: 19, color: r.soluk),
            onPressed: simdiEsitle,
          ),
        ],
      ),
    );
  }
}
