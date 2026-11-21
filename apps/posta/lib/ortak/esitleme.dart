// Eşitleme durumu göstergesi: "Canlı" (yeşil, SSE bağlı) / "Bağlanıyor…" / "Bağlantı yok — N sn sonra yeniden
// denenecek" (canlı geri sayım), son eşitleme zamanı ve "Şimdi eşitle". Kenar menüsü altında tam, telefonda liste
// başlığının altında yalnız bağlantı yokken ince bir şerit olarak.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../ekranlar/giden_kutusu.dart';
import '../veri/baglanti.dart';
import '../veri/birlesik.dart';
import '../veri/canli.dart';
import '../veri/durum.dart';
import '../veri/esitleyici.dart';
import '../veri/kuyruk.dart';
import 'uyarlanir.dart';

/// Kullanıcı "Şimdi eşitle"ye bastı: akış hemen yeniden bağlanır, bekleyen değişiklikler / Giden Kutusu
/// gönderilir, sayılar ve açık liste tazelenir.
void simdiEsitle() {
  Canli.ben.simdiBaglan();
  unawaited(IslemKuyrugu.ben.oynat());
  unawaited(GidenKutusu.ben.gonder());
  PostaDurum.ben.sayilariYenile();
  unawaited(BirlesikDurum.ben.sayilariYenile());
  Esitleyici.ben.tetikle(hemen: true);
}

/// Sunucuya ulaşılamıyor (son istek ya da canlı akış).
bool get cevrimdisiMi => Baglanti.ben.cevrimdisi.value || Canli.ben.durum.value.tur == CanliTur.yok;

/// "Çevrimdışı — son eşitleme 14:32" (bugün değilse tarihle).
String cevrimdisiMetni(DateTime? son, DateTime simdi) {
  if (son == null) return 'Çevrimdışı — henüz eşitlenmedi';
  final t = son.toLocal();
  final bugun = t.year == simdi.year && t.month == simdi.month && t.day == simdi.day;
  return 'Çevrimdışı — son eşitleme ${DateFormat(bugun ? 'HH:mm' : 'd MMM HH:mm', 'tr_TR').format(t)}';
}

/// "2 ileti gönderilmeyi bekliyor · 3 değişiklik eşitlenmeyi bekliyor" (yoksa null).
String? bekleyenMetni() {
  final g = GidenKutusu.ben.ogeler.value.length;
  final k = IslemKuyrugu.ben.ogeler.value.length;
  final p = [if (g > 0) '$g ileti gönderilmeyi bekliyor', if (k > 0) '$k değişiklik eşitlenmeyi bekliyor'];
  return p.isEmpty ? null : p.join(' · ');
}

/// Eşitleme göstergesinin dinlediği her şey.
Listenable get esitlemeDinleyicisi =>
    Listenable.merge([Canli.ben.durum, Canli.ben.sonOlay, Baglanti.ben.cevrimdisi, Baglanti.ben.sonEsitleme, GidenKutusu.ben.ogeler, IslemKuyrugu.ben.ogeler]);

/// Bekleyen değişiklikler ve Giden Kutusu özeti (eşitleme göstergesine dokununca).
Future<void> bekleyenleriGoster(BuildContext context) => showDialog<void>(context: context, builder: (c) => const _BekleyenlerPenceresi());

class _BekleyenlerPenceresi extends StatelessWidget {
  const _BekleyenlerPenceresi();

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return ListenableBuilder(
      listenable: esitlemeDinleyicisi,
      builder: (context, _) {
        final simdi = DateTime.now();
        final islemler = IslemKuyrugu.ben.ogeler.value;
        final giden = GidenKutusu.ben.ogeler.value;
        final son = Baglanti.ben.sonEsitleme.value ?? Canli.ben.sonOlay.value;
        return AlertDialog(
          key: const ValueKey('bekleyenler'),
          title: Text(cevrimdisiMi ? cevrimdisiMetni(son, simdi) : 'Eşitleme', style: gosterim(18, agirlik: FontWeight.w600)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!cevrimdisiMi) Text(sonEsitlemeMetni(son, simdi), style: TextStyle(color: r.soluk, fontSize: 13)),
                  if (islemler.isEmpty && giden.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Tüm değişiklikler eşitlendi.', style: TextStyle(color: r.soluk)),
                    ),
                  if (giden.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('${giden.length} ileti gönderilmeyi bekliyor', style: const TextStyle(fontWeight: FontWeight.w600)),
                    for (final o in giden.take(5))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• ${o.konu.trim().isEmpty ? '(konu yok)' : o.konu}${o.durum == GidenDurum.hata ? ' — hata' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: o.durum == GidenDurum.hata ? Marka.gul : r.metin),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const ValueKey('bekleyen-giden-ac'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          final ctx = kokGezgin.currentContext;
                          if (ctx != null) uyarlanirAc<void>(ctx, (_) => const GidenKutusuEkrani());
                        },
                        child: const Text('Giden Kutusu\'nu aç'),
                      ),
                    ),
                  ],
                  if (islemler.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('${islemler.length} değişiklik eşitlenmeyi bekliyor', style: const TextStyle(fontWeight: FontWeight.w600)),
                    for (final i in islemler.take(12))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• ${i.aciklama} · ${DateFormat('HH:mm', 'tr_TR').format(i.zaman)}', style: TextStyle(fontSize: 13, color: r.metin)),
                      ),
                    if (islemler.length > 12) Text('… ve ${islemler.length - 12} değişiklik daha', style: TextStyle(fontSize: 13, color: r.silik)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Kapat')),
            FilledButton(onPressed: simdiEsitle, child: const Text('Şimdi eşitle')),
          ],
        );
      },
    );
  }
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
    esitlemeDinleyicisi.addListener(_degisti);
    _saatiKur();
  }

  @override
  void dispose() {
    esitlemeDinleyicisi.removeListener(_degisti);
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
    final cd = cevrimdisiMi;
    final son = Baglanti.ben.sonEsitleme.value ?? Canli.ben.sonOlay.value;
    final bekleyen = bekleyenMetni();
    // Çevrimdışı: "Çevrimdışı — son eşitleme 14:32"; altında yeniden deneme geri sayımı.
    final metin = cd ? cevrimdisiMetni(son, simdi) : esitlemeMetni(d, simdi);
    final renk2 = cd ? Marka.gul : renk;
    if (widget.serit) {
      if (!cd && bekleyen == null && (d.tur == CanliTur.bagli || d.tur == CanliTur.kapali)) return const SizedBox.shrink();
      final serit = [metin, if (d.tur == CanliTur.yok) esitlemeMetni(d, simdi).replaceFirst('Bağlantı yok — ', ''), ?bekleyen].join(' · ');
      return Material(
        key: const ValueKey('esitleme-serit'),
        color: renk2.withValues(alpha: .06),
        child: InkWell(
          onTap: () => bekleyenleriGoster(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(
              children: [
                Icon(cd ? Simge.cevrimdisi : Simge.esitle, size: 16, color: renk2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    serit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: r.metin),
                  ),
                ),
                TextButton(onPressed: simdiEsitle, child: const Text('Şimdi eşitle')),
              ],
            ),
          ),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      label: '$metin. ${cd ? '' : sonEsitlemeMetni(son, simdi)}${bekleyen == null ? '' : '. $bekleyen'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => bekleyenleriGoster(context),
        child: Row(
          key: const ValueKey('esitleme-durumu'),
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: renk2, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    metin,
                    key: const ValueKey('esitleme-metni'),
                    maxLines: 2,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: !cd && d.tur == CanliTur.bagli ? Marka.zumrut : r.metin),
                  ),
                  Text(
                    cd
                        ? (d.tur == CanliTur.yok ? esitlemeMetni(d, simdi).replaceFirst('Bağlantı yok — ', '') : 'Yeniden bağlanılacak')
                        : sonEsitlemeMetni(son, simdi),
                    style: TextStyle(fontSize: 11, color: r.silik),
                  ),
                  if (bekleyen != null)
                    Text(
                      bekleyen,
                      key: const ValueKey('esitleme-bekleyen'),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Marka.kehribar),
                    ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('simdi-esitle'),
              tooltip: 'Şimdi eşitle',
              visualDensity: VisualDensity.compact,
              icon: Icon(Simge.esitle, size: 19, color: r.soluk),
              onPressed: simdiEsitle,
            ),
          ],
        ),
      ),
    );
  }
}
