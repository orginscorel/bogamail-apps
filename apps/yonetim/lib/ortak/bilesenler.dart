import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../veri/bicim.dart';
import 'simgeler.dart';

/// Ekran genişliği iki sütunlu (liste + ayrıntı) düzen için yeterli mi.
bool bolunmus(BuildContext c) => MediaQuery.sizeOf(c).width >= 1050;

Color durumRengi(String durum) => switch (durum) {
  'active' || 'ok' || 'released' || 'resolved' || 'accepted' => Marka.zumrut,
  'pending' || 'warn' || 'deferred' || 'held' || 'repeat' || 'warning' => Marka.kehribar,
  'suspended' || 'fail' || 'failed' || 'deleted' || 'down' || 'critical' || 'firing' || 'invalid_user' => Marka.gul,
  _ => Marka.mavi,
};

class DurumRozeti extends StatelessWidget {
  const DurumRozeti(this.durum, {super.key, this.etiket});
  final String durum;
  final String? etiket;
  @override
  Widget build(BuildContext context) => Rozet(etiket ?? durumEtiketi(durum), renk: durumRengi(durum));
}

/// Kota / disk kullanım çubuğu. [toplam] sınırsızsa yalnızca kullanılan yazılır.
class KullanimCubugu extends StatelessWidget {
  const KullanimCubugu({super.key, required this.kullanilan, required this.toplam, this.yazi = true, this.kalinlik = 8});
  final int kullanilan, toplam;
  final bool yazi;
  final double kalinlik;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final oran = kullanimOrani(kullanilan, toplam);
    final renk = oran == null ? r.birincil : (oran >= .9 ? Marka.gul : (oran >= .75 ? Marka.kehribar : r.birincil));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(kalinlik),
          child: LinearProgressIndicator(value: oran ?? 0, minHeight: kalinlik, backgroundColor: r.ic, color: renk),
        ),
        if (yazi) ...[
          const SizedBox(height: 5),
          Text(
            oran == null
                ? '${boyutYaz(kullanilan)} kullanılıyor · ${sinirsizMi(toplam) ? 'sınırsız kota' : 'kota yok'}'
                : '${boyutYaz(kullanilan)} / ${boyutYaz(toplam)} · ${yuzdeYaz(oran * 100, basamak: 0)}',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Etiket–değer satırı (ayrıntı ekranları).
class BilgiSatiri extends StatelessWidget {
  const BilgiSatiri(this.etiket, this.deger, {super.key, this.kopyalanabilir = false, this.mono = false, this.sag});
  final String etiket, deger;
  final bool kopyalanabilir, mono;
  final Widget? sag;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(etiket, style: TextStyle(color: r.silik, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(
              deger.isEmpty ? '—' : deger,
              style: TextStyle(fontSize: 13.5, fontFamily: mono ? 'monospace' : null, fontWeight: FontWeight.w500),
            ),
          ),
          if (kopyalanabilir && deger.isNotEmpty)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Kopyala',
              icon: const Icon(Simgeler.copy, size: 17),
              onPressed: () => kopyala(deger),
            ),
          ?sag,
        ],
      ),
    );
  }
}

/// Monospace kopyalanabilir değer kutusu (DNS kayıtları, şifreler).
class KopyaKutusu extends StatelessWidget {
  const KopyaKutusu(this.deger, {super.key, this.etiket, this.mesaj = 'Kopyalandı'});
  final String deger;
  final String? etiket;
  final String mesaj;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (etiket != null)
            SizedBox(
              width: 64,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(etiket!, style: TextStyle(color: r.silik, fontSize: 12)),
              ),
            ),
          Expanded(
            child: SelectableText(deger, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.35)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Kopyala',
            icon: const Icon(Simgeler.copy, size: 17),
            onPressed: () => kopyala(deger, mesaj: mesaj),
          ),
        ],
      ),
    );
  }
}

/// Başlıklı kart bölümü.
class BolumKarti extends StatelessWidget {
  const BolumKarti({super.key, required this.baslik, required this.child, this.sag, this.ikon, this.altBaslik, this.padding = const EdgeInsets.all(16)});
  final String baslik;
  final String? altBaslik;
  final IconData? ikon;
  final Widget child;
  final Widget? sag;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Kutu(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (ikon != null) ...[Icon(ikon, size: 19, color: r.birincil), const SizedBox(width: 8)],
              Expanded(
                child: Text(baslik, style: gosterim(16, agirlik: FontWeight.w600)),
              ),
              ?sag,
            ],
          ),
          if (altBaslik != null) ...[const SizedBox(height: 4), Text(altBaslik!, style: TextStyle(color: r.silik, fontSize: 12.5))],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Özet kutusu: ikon, etiket, büyük değer, alt satır. Dokununca [onTap].
class IstatistikKarti extends StatelessWidget {
  const IstatistikKarti({super.key, required this.ikon, required this.etiket, required this.deger, this.alt, this.onTap, this.renk, this.ek});
  final IconData ikon;
  final String etiket, deger;
  final String? alt;
  final VoidCallback? onTap;
  final Color? renk;
  final Widget? ek;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Kutu(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(ikon, size: 16, color: renk ?? r.silik),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  etiket,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: r.soluk, fontSize: 12.5),
                ),
              ),
              if (onTap != null) Icon(SimgelerKalin.chevronRight, size: 16, color: r.silik),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            deger,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: gosterim(22, agirlik: FontWeight.w600, renk: renk),
          ),
          if (ek != null) ...[const SizedBox(height: 8), ek!],
          if (alt != null)
            Text(
              alt!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: r.silik, fontSize: 11.5),
            ),
        ],
      ),
    );
  }
}

/// Gecikmeli arama alanı.
class AramaAlani extends StatefulWidget {
  const AramaAlani({super.key, required this.ipucu, required this.degisti, this.ilk = ''});
  final String ipucu, ilk;
  final ValueChanged<String> degisti;
  @override
  State<AramaAlani> createState() => _AramaAlaniState();
}

class _AramaAlaniState extends State<AramaAlani> {
  late final _k = TextEditingController(text: widget.ilk);
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    _k.dispose();
    super.dispose();
  }

  void _degis(String v) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 350), () => widget.degisti(v.trim()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _k,
    onChanged: _degis,
    textInputAction: TextInputAction.search,
    onSubmitted: (v) {
      _t?.cancel();
      widget.degisti(v.trim());
    },
    decoration: InputDecoration(
      hintText: widget.ipucu,
      isDense: true,
      prefixIcon: const Icon(Simgeler.search, size: 20),
      suffixIcon: _k.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Aramayı temizle',
              icon: const Icon(Simgeler.close, size: 18),
              onPressed: () {
                _k.clear();
                _degis('');
              },
            ),
    ),
  );
}

/// Yatay kaydırılabilir seçim çipleri.
class SecimCipleri<T> extends StatelessWidget {
  const SecimCipleri({super.key, required this.secenekler, required this.secili, required this.secildi});
  final List<(T, String)> secenekler;
  final T secili;
  final ValueChanged<T> secildi;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (d, e) in secenekler)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text(e), selected: d == secili, onSelected: (_) => secildi(d), showCheckmark: false),
          ),
      ],
    ),
  );
}

/// Ayrıntı ekranlarındaki eylem satırı.
class EylemSatiri extends StatelessWidget {
  const EylemSatiri({super.key, required this.ikon, required this.baslik, this.ipucu, required this.onTap, this.tehlikeli = false});
  final IconData ikon;
  final String baslik;
  final String? ipucu;
  final VoidCallback? onTap;
  final bool tehlikeli;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final renk = tehlikeli ? Marka.gul : r.birincil;
    return Kutu(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
            child: Icon(ikon, size: 19, color: renk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  baslik,
                  style: TextStyle(fontWeight: FontWeight.w500, color: tehlikeli ? Marka.gul : null),
                ),
                if (ipucu != null) Text(ipucu!, style: TextStyle(color: r.silik, fontSize: 12)),
              ],
            ),
          ),
          Icon(Simgeler.chevronRight, color: r.silik),
        ],
      ),
    );
  }
}

/// Bilgi / uyarı bandı.
class Bant extends StatelessWidget {
  const Bant(this.metin, {super.key, this.renk = Marka.mavi, this.ikon = Simgeler.infoOutline, this.eylem});
  final String metin;
  final Color renk;
  final IconData ikon;
  final Widget? eylem;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: renk.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: renk.withValues(alpha: .3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ikon, size: 20, color: renk),
        const SizedBox(width: 8),
        Expanded(child: Text(metin, style: const TextStyle(fontSize: 13.5, height: 1.35))),
        if (eylem != null) ...[const SizedBox(width: 8), eylem!],
      ],
    ),
  );
}

/// İki sütunlu düzende ayrıntı seçilmemişken gösterilen yer tutucu.
class BosDetay extends StatelessWidget {
  const BosDetay(this.metin, {super.key, this.ikon = Simgeler.touchApp});
  final String metin;
  final IconData ikon;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ikon, size: 44, color: context.r.silik.withValues(alpha: .6)),
        const SizedBox(height: 8),
        Text(metin, style: TextStyle(color: context.r.silik)),
      ],
    ),
  );
}

/// Liste + ayrıntı düzeni: geniş ekranda yan yana, dar ekranda yalnızca liste.
class AnaDetay extends StatelessWidget {
  const AnaDetay({super.key, required this.liste, required this.detay, this.bosMetin = 'Ayrıntı için listeden bir kayıt seçin', this.listeGenisligi = 420});
  final Widget liste;
  final Widget? detay;
  final String bosMetin;
  final double listeGenisligi;

  @override
  Widget build(BuildContext context) {
    if (!bolunmus(context)) return liste;
    return Row(
      children: [
        SizedBox(width: listeGenisligi, child: liste),
        const VerticalDivider(width: 1),
        Expanded(child: detay ?? BosDetay(bosMetin)),
      ],
    );
  }
}

/// Ayrıntı ekranını tam sayfa açar (dar ekran).
Future<T?> sayfaAc<T>(BuildContext context, String baslik, Widget govde, {List<Widget>? eylemler}) => Navigator.of(context).push<T>(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(
        title: Text(baslik, overflow: TextOverflow.ellipsis),
        actions: eylemler,
      ),
      body: govde,
    ),
  ),
);

/// Kullanıcının bir metni aynen yazmasını isteyerek onay alır (geri alınamaz silmeler).
Future<bool> yazarakOnayla(BuildContext context, {required String baslik, required String mesaj, required String beklenen, String evet = 'Sil'}) async {
  final k = TextEditingController();
  final v = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, yenile) {
        final tamam = k.text.trim().toLowerCase() == beklenen.trim().toLowerCase();
        return AlertDialog(
          title: Text(baslik, style: gosterim(19, agirlik: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mesaj),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Onaylamak için '),
                    TextSpan(
                      text: beklenen,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                    ),
                    const TextSpan(text: ' yazın'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: k, autofocus: true, autocorrect: false, onChanged: (_) => yenile(() {})),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Marka.gul),
              onPressed: tamam ? () => Navigator.pop(c, true) : null,
              child: Text(evet),
            ),
          ],
        );
      },
    ),
  );
  return v ?? false;
}

/// Yeni şifreyi bir kez gösterir (kopyalama düğmesiyle).
Future<void> sifreGoster(BuildContext context, {required String adres, required String sifre, String? not}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (c) => AlertDialog(
    title: Text('Yeni şifre', style: gosterim(19, agirlik: FontWeight.w600)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(adres, style: const TextStyle(fontWeight: FontWeight.w600)),
        KopyaKutusu(sifre, mesaj: 'Şifre kopyalandı'),
        const SizedBox(height: 12),
        Bant(
          not ?? 'Bu şifre yalnızca şimdi gösterilir; sunucuda düz metin olarak saklanmaz. Kullanıcıya güvenli bir kanaldan iletin.',
          renk: Marka.kehribar,
          ikon: Simgeler.key,
        ),
      ],
    ),
    actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
  ),
);

/// Basit seçim listesi (alt sayfa).
Future<T?> secimYap<T>(BuildContext context, {required String baslik, required List<(T, String, String?)> secenekler, T? secili}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  builder: (c) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(baslik, style: gosterim(17, agirlik: FontWeight.w600)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (d, e, alt) in secenekler)
                  ListTile(
                    title: Text(e),
                    subtitle: alt == null ? null : Text(alt),
                    trailing: d == secili ? Icon(Simgeler.check, color: context.r.birincil) : null,
                    onTap: () => Navigator.pop(c, d),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

/// Liste satırı: başlık, alt satırlar, sağda rozet. Seçiliyse vurgulanır.
class ListeSatiri extends StatelessWidget {
  const ListeSatiri({super.key, required this.baslik, this.alt, this.alt2, this.sol, this.sag, this.onTap, this.secili = false, this.vurgulu = false});
  final String baslik;
  final String? alt, alt2;
  final Widget? sol, sag;
  final VoidCallback? onTap;
  final bool secili, vurgulu;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Material(
      color: secili ? r.birincilYumusak : (vurgulu ? Marka.kehribar.withValues(alpha: .14) : Colors.transparent),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              if (sol != null) ...[sol!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      baslik,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5),
                    ),
                    if (alt != null && alt!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          alt!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: r.soluk, fontSize: 12.5),
                        ),
                      ),
                    if (alt2 != null && alt2!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          alt2!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: r.silik, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              if (sag != null) ...[const SizedBox(width: 8), sag!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ayrıntı panelinin üst başlığı (geniş ekranda; dar ekranda AppBar zaten başlığı gösterir).
class DetayBasligi extends StatelessWidget {
  const DetayBasligi({super.key, required this.baslik, this.alt, this.sag});
  final String baslik;
  final String? alt;
  final Widget? sag;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(baslik, style: gosterim(21, agirlik: FontWeight.w600)),
              if (alt != null && alt!.isNotEmpty) Text(alt!, style: TextStyle(color: context.r.silik, fontSize: 13)),
            ],
          ),
        ),
        ?sag,
      ],
    ),
  );
}
