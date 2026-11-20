// Ayar bölümlerinin ortak parçaları: başlıklı kart (web SectionCard), bilgi notu, iki sütun, seçim çipleri ve sunucu
// ayarlarını yükleyip kaydeden gövde.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/ayar_servisi.dart';
import '../../veri/durum.dart';

/// Başlıklı ayar kartı: simge, başlık, açıklama, sağda rozet; altta isteğe bağlı eylem satırı.
class AyarKarti extends StatelessWidget {
  const AyarKarti({super.key, required this.ikon, required this.baslik, this.aciklama, this.sag, required this.child, this.alt});
  final IconData ikon;
  final String baslik;
  final String? aciklama;
  final Widget? sag;
  final Widget child;
  final Widget? alt;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Kutu(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: r.vurguYumusak, borderRadius: BorderRadius.circular(10)),
                    child: Icon(ikon, size: 19, color: r.vurgu),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(baslik, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                        if (aciklama != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(aciklama!, style: TextStyle(color: r.soluk, fontSize: 13, height: 1.35)),
                          ),
                      ],
                    ),
                  ),
                  if (sag != null) ...[const SizedBox(width: 8), sag!],
                ],
              ),
            ),
            Divider(height: 1, color: r.kenar),
            Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), child: child),
            if (alt != null) ...[
              Divider(height: 1, color: r.kenar),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Align(alignment: Alignment.centerRight, child: alt),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum NotTonu { bilgi, uyari, tehlike, tamam }

/// Kart içi açıklama/uyarı kutusu (web Notice).
class AyarNotu extends StatelessWidget {
  const AyarNotu(this.metin, {super.key, this.ton = NotTonu.bilgi, this.baslik, this.alt});
  final String metin;
  final String? baslik;
  final NotTonu ton;
  final Widget? alt;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final (renk, ikon) = switch (ton) {
      NotTonu.bilgi => (r.vurgu, Icons.info_outline_rounded),
      NotTonu.uyari => (Marka.kehribar, Icons.warning_amber_rounded),
      NotTonu.tehlike => (Marka.gul, Icons.error_outline_rounded),
      NotTonu.tamam => (Marka.zumrut, Icons.check_circle_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: renk.withValues(alpha: .09), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 18, color: renk),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (baslik != null)
                  Text(
                    baslik!,
                    style: TextStyle(fontWeight: FontWeight.w700, color: r.metin, fontSize: 13.5),
                  ),
                Text(metin, style: TextStyle(color: r.metin, fontSize: 13, height: 1.4)),
                ?alt,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Açık/kapalı rozeti.
class DurumRozeti extends StatelessWidget {
  const DurumRozeti(this.metin, {super.key, this.acik = true});
  final String metin;
  final bool acik;
  @override
  Widget build(BuildContext context) => Rozet(metin, renk: acik ? Marka.zumrut : context.r.silik);
}

/// Geniş alanda yan yana, dar alanda alt alta iki (veya daha çok) kart.
class IkiSutun extends StatelessWidget {
  const IkiSutun({super.key, required this.children, this.esik = 680, this.dikeyAralik = 0});
  final List<Widget> children;
  final double esik;

  /// Alt alta dizildiğinde öğeler arası boşluk (kartların kendi alt boşluğu vardır).
  final double dikeyAralik;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, k) => k.maxWidth < esik
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0 && dikeyAralik > 0) SizedBox(height: dikeyAralik), children[i]],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: children[i])],
            ],
          ),
  );
}

/// Tek seçimli çip grubu.
class SecimCipleri<T> extends StatelessWidget {
  const SecimCipleri({super.key, required this.secenekler, required this.deger, required this.degisti, this.etkin = true});
  final Map<T, String> secenekler;
  final T deger;
  final ValueChanged<T> degisti;
  final bool etkin;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final e in secenekler.entries) ChoiceChip(label: Text(e.value), selected: e.key == deger, onSelected: etkin ? (_) => degisti(e.key) : null),
    ],
  );
}

/// Ayar alanı: üstte etiket, altta açıklama.
class AyarAlani extends StatelessWidget {
  const AyarAlani({super.key, required this.etiket, this.ipucu, required this.child});
  final String etiket;
  final String? ipucu;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiket,
            style: TextStyle(fontWeight: FontWeight.w600, color: r.metin, fontSize: 14),
          ),
          const SizedBox(height: 8),
          child,
          if (ipucu != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(ipucu!, style: TextStyle(color: r.silik, fontSize: 12.5, height: 1.35)),
            ),
        ],
      ),
    );
  }
}

/// Ayar bölümü gövdesi: kaydırılabilir, okunabilir genişlikte (en çok 860 px) kart listesi.
class AyarListesi extends StatelessWidget {
  const AyarListesi({super.key, required this.children, this.yenile});
  final List<Widget> children;
  final Future<void> Function()? yenile;
  @override
  Widget build(BuildContext context) {
    Widget l = LayoutBuilder(
      builder: (_, k) {
        final yatay = k.maxWidth >= 600 ? 24.0 : 16.0;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.fromLTRB(yatay, 12, yatay, 40), children: children),
          ),
        );
      },
    );
    if (yenile != null) l = RefreshIndicator(onRefresh: yenile!, child: l);
    return l;
  }
}

/// Sunucu ayarlarını (GET /mail/settings) yükler; [olustur] kaydetme işleviyle birlikte içeriği kurar.
/// Kaydetme kısmi PATCH yapar, ardından ayarları ve uygulama genelindeki kopyayı tazeler.
class SunucuAyarGovdesi extends StatefulWidget {
  const SunucuAyarGovdesi({super.key, required this.olustur});
  final List<Widget> Function(BuildContext context, SunucuAyarlari a, AyarKaydedici kaydet) olustur;
  @override
  State<SunucuAyarGovdesi> createState() => _SunucuAyarGovdesiState();
}

/// Değişen alanları kaydeder; başarıda true döner (hata kullanıcıya bildirilir).
typedef AyarKaydedici = Future<bool> Function(Map<String, dynamic> degisen, {String tamam});

class _SunucuAyarGovdesiState extends State<SunucuAyarGovdesi> {
  SunucuAyarlari? _a;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final a = await Ayar.sunucu();
      if (mounted) {
        setState(() {
          _a = a;
          _hata = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<bool> _kaydet(Map<String, dynamic> d, {String tamam = 'Kaydedildi'}) async {
    try {
      await Ayar.kaydet(d);
      bildir(tamam, tur: MesajTur.basari);
      await _yukle();
      unawaited(PostaDurum.ben.ayarlariYukle());
      return true;
    } catch (e) {
      bildir('Kaydedilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) {
      return _hata != null
          ? Durum.hata(
              _hata!,
              tekrar: () {
                setState(() => _hata = null);
                _yukle();
              },
            )
          : const Durum.yukleniyor();
    }
    return AyarListesi(yenile: _yukle, children: widget.olustur(context, a, _kaydet));
  }
}

/// Kaydet düğmesi (meşgulken dönen gösterge).
class KaydetDugmesi extends StatelessWidget {
  const KaydetDugmesi({super.key, required this.etkin, required this.mesgul, required this.basildi, this.metin = 'Kaydet'});
  final bool etkin;
  final bool mesgul;
  final VoidCallback basildi;
  final String metin;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: etkin && !mesgul ? basildi : null,
    icon: mesgul ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded, size: 18),
    label: Text(metin),
  );
}
