// Kenar menüsünün altındaki sade hesap bloğu ve ondan açılan hesap menüsü (masaüstü: yukarı açılan ~300 px açılır
// pencere; telefon: alt sayfa). Kayıtlı hesaplar (okunmamış, etkin olanda onay), Tüm hesaplar, Hesap ekle,
// Hesapları yönet, Bu hesaptan çık. Geçiş beklemesizdir (Uyg.hesabaGec: önbellekle anında açılış).

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../veri/birlesik.dart';
import '../veri/durum.dart';
import 'ayarlar.dart';
import 'hesaplar.dart';

/// Son bilinen kayıtlı hesaplar: menü ağ beklemeden açılır, Ctrl/Cmd+1…9 kısayolları bunu kullanır.
List<KayitliHesap> sonHesaplar = const [];

Future<List<KayitliHesap>> hesaplariTazele() async {
  try {
    sonHesaplar = await Uyg.hesaplar();
  } catch (_) {}
  return sonHesaplar;
}

/// Ctrl/Cmd+[sira] (1'den başlar): o sıradaki kayıtlı hesaba geçer.
Future<void> siradakiHesabaGec(int sira) async {
  var l = sonHesaplar;
  if (l.isEmpty) l = await hesaplariTazele();
  final acik = l.where((h) => !h.cikisYapti).toList();
  if (sira < 1 || sira > acik.length) return;
  final h = acik[sira - 1];
  if (h.etkin) return;
  await Uyg.hesabaGec(hesap: h);
}

/// Kenar menüsünün altındaki hesap bloğu: 32 px avatar, ad, adres, tek ok.
class HesapBlogu extends StatelessWidget {
  const HesapBlogu({super.key, this.cekmecede = false});
  final bool cekmecede;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: Uyg.kutu,
      builder: (context, _, _) {
        // Hiçbir zaman boş çizilmez: ad yoksa adres, o da yoksa (kutu bilgisi henüz gelmediyse) "Hesabım".
        final adres = Uyg.adres.trim();
        final ad = Uyg.ad.trim().isNotEmpty ? Uyg.ad.trim() : '';
        final gorunen = ad.isNotEmpty ? ad : (adres.isNotEmpty ? adres : 'Hesabım');
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const ValueKey('hesap-blogu'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => hesapMenusuAc(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Avatar(ad.isNotEmpty ? ad : (adres.isNotEmpty ? adres.split('@').first : gorunen), boyut: 32, tohum: adres.isEmpty ? gorunen : adres),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            gorunen,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: r.metin),
                          ),
                          if (ad.isNotEmpty && adres.isNotEmpty)
                            Text(
                              adres,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: r.soluk),
                            ),
                        ],
                      ),
                    ),
                    Icon(Simge.acKapa, size: 18, color: r.soluk, semanticLabel: 'Hesap değiştir'),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Hesap menüsünü açar: geniş ekranda bloğun üstüne açılan açılır pencere, telefonda alt sayfa.
Future<void> hesapMenusuAc(BuildContext context) async {
  unawaited(hesaplariTazele());
  if (!context.genis) {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const HesapMenusu());
    return;
  }
  final kutu = context.findRenderObject() as RenderBox?;
  final ust = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (kutu == null || ust == null) return;
  final sol = kutu.localToGlobal(Offset.zero, ancestor: ust);
  final altKenar = ust.size.height - sol.dy + 6;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (c, _, _) => Stack(
      children: [
        Positioned(
          left: sol.dx + 8,
          bottom: altKenar,
          width: 300,
          child: Material(
            color: c.r.kart,
            elevation: 3,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: c.r.kenar),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: (sol.dy - 24).clamp(240, 640).toDouble()),
              child: const HesapMenusu(acilir: true),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (_, a, _, child) => FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .02), end: Offset.zero).animate(a),
        child: child,
      ),
    ),
  );
}

class HesapMenusu extends StatefulWidget {
  const HesapMenusu({super.key, this.acilir = false});

  /// Masaüstü açılır pencere (alt sayfa değil).
  final bool acilir;

  @override
  State<HesapMenusu> createState() => _HesapMenusuState();
}

class _HesapMenusuState extends State<HesapMenusu> {
  List<KayitliHesap> _l = sonHesaplar;

  @override
  void initState() {
    super.initState();
    hesaplariTazele().then((l) => mounted ? setState(() => _l = l) : null);
  }

  List<KayitliHesap> get _liste {
    final l = _l.where((h) => !h.cikisYapti || h.etkin).toList();
    if (!l.any((h) => h.etkin) && Uyg.adres.isNotEmpty) {
      l.insert(0, KayitliHesap(id: '${Uyg.kutu.value?['mailbox_id'] ?? ''}', adres: Uyg.adres, ad: Uyg.ad, etkin: true));
    }
    return l;
  }

  void _kapat() => Navigator.of(context).pop();

  Future<void> _gec(KayitliHesap h) async {
    final nav = Navigator.of(context);
    _kapat();
    if (h.etkin) return;
    final ok = await Uyg.hesabaGec(hesap: h);
    if (!ok) {
      nav.push(
        MaterialPageRoute<void>(
          builder: (c) => Uyg.girisFormu(ekle: true, adres: h.adres, geri: () => Navigator.pop(c)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final birlesik = BirlesikDurum.ben;
    Widget eylem(String anahtar, IconData ikon, String ad, VoidCallback f, {Color? renk}) => ListTile(
      key: ValueKey(anahtar),
      dense: true,
      visualDensity: VisualDensity.compact,
      minLeadingWidth: 24,
      leading: Icon(ikon, size: 20, color: renk ?? r.soluk),
      title: Text(
        ad,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: renk ?? r.metin),
      ),
      onTap: f,
    );
    final govde = ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final (i, h) in _liste.indexed)
          ListTile(
            key: ValueKey('hesap-${h.id}'),
            dense: true,
            minLeadingWidth: 32,
            leading: Avatar(h.gorunen, boyut: 32, tohum: h.adres),
            title: Text(
              h.gorunen,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: r.metin),
            ),
            subtitle: Text(
              h.cikisYapti ? '${h.adres} · çıkış yapıldı' : h.adres,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: r.soluk),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (h.okunmamis > 0 && !h.etkin)
                  Text(
                    h.okunmamis > 999 ? '999+' : '${h.okunmamis}',
                    style: TextStyle(fontSize: 12, color: r.vurgu, fontWeight: FontWeight.w600),
                  ),
                if (h.etkin) Icon(Simge.onay, size: 18, color: r.vurgu, semanticLabel: 'Etkin hesap'),
                if (context.genis && i < 9 && !h.etkin) ...[
                  const SizedBox(width: 8),
                  Text('${_kisayolOnEki()}${i + 1}', style: TextStyle(fontSize: 11, color: r.silik)),
                ],
              ],
            ),
            onTap: () => _gec(h),
          ),
        if (birlesik.kullanilabilir)
          eylem('menu-tum-hesaplar', Simge.katmanlar, 'Tüm hesaplar', () {
            _kapat();
            PostaDurum.ben.git(const Konum.birlesik());
          }),
        const Divider(height: 12),
        eylem('menu-hesap-ekle', Simge.kisiEkle, 'Hesap ekle', () {
          final nav = Navigator.of(context);
          _kapat();
          hesapEkle(nav);
        }),
        eylem('menu-hesaplari-yonet', Simge.hesapYonet, 'Hesapları yönet', () {
          final nav = Navigator.of(context);
          _kapat();
          nav.push(MaterialPageRoute<void>(builder: (_) => const AyarlarEkrani(kategori: 'hesaplar')));
        }),
        eylem('menu-cikis', Simge.cikis, 'Bu hesaptan çık', () async {
          final c = context;
          _kapat();
          if (await onayla(c, '${Uyg.adres} hesabından çıkılsın mı?', mesaj: 'Hesap bu cihazda kayıtlı kalır.', evet: 'Çık')) {
            await Uyg.cikis();
          }
        }, renk: Marka.gul),
      ],
    );
    if (widget.acilir) return govde;
    return SafeArea(top: false, child: govde);
  }
}

String _kisayolOnEki() => defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl+';
