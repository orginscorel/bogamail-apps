import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/esitleme.dart';
import '../ortak/simgeler.dart';
import '../ortak/surukle.dart';
import '../ortak/uyarlanir.dart';
import '../veri/birlesik.dart';
import '../veri/durum.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/yardimci.dart';
import 'ayarlar.dart';
import 'hesap/posta_yonetimi.dart';
import 'hesaplar.dart';

/// Kenar menüsü: hesap başlığı + kota, klasörler (okunmamış sayılarıyla), görünümler, kullanıcı klasörleri, etiketler.
/// Geniş ekranda kenar çubuğu; telefonda "Klasörler" sekmesinin sayfası ([sayfa]).
class YanMenu extends StatefulWidget {
  const YanMenu({super.key, required this.sec, this.yeniIleti, this.cekmecede = false, this.sayfa = false});
  final ValueChanged<Konum> sec;
  final VoidCallback? yeniIleti;
  final bool cekmecede;

  /// Telefon sekmesi: başlık çubuğu var, seçili konum vurgulanmaz, Ayarlar alt sekmede olduğundan gösterilmez.
  final bool sayfa;

  @override
  State<YanMenu> createState() => _YanMenuState();
}

/// Web ile aynı: "Klasör ara" kutusu kullanıcı klasörü 8'den fazlaysa görünür.
const klasorAramaEsigi = 8;

class _YanMenuState extends State<YanMenu> {
  ValueChanged<Konum> get sec => widget.sec;
  VoidCallback? get yeniIleti => widget.yeniIleti;
  bool get cekmecede => widget.cekmecede;
  bool get sayfa => widget.sayfa;

  final _klasorAra = TextEditingController();

  @override
  void dispose() {
    _klasorAra.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return ListenableBuilder(
      listenable: PostaDurum.ben,
      builder: (context, _) {
        final d = PostaDurum.ben;
        final govde = Material(
          color: r.kart,
          child: SafeArea(
            right: false,
            top: !sayfa,
            child: Column(
              children: [
                const _HesapBasligi(),
                if (yeniIleti != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(onPressed: yeniIleti, icon: const Icon(Icons.edit_rounded, size: 19), label: const Text('Yeni ileti')),
                    ),
                  ),
                Expanded(
                  child: !d.yuklendi && d.hata == null
                      ? const Center(child: CircularProgressIndicator.adaptive())
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          children: [
                            if (d.hata != null)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(d.hata!, style: const TextStyle(color: Marka.gul)),
                              ),
                            // Birden çok hesap: klasörlerin üstünde "Tüm hesaplar" (toplam okunmamış).
                            ListenableBuilder(
                              listenable: BirlesikDurum.ben,
                              builder: (context, _) => BirlesikDurum.ben.kullanilabilir
                                  ? KeyedSubtree(
                                      key: const ValueKey('yan-tum-hesaplar'),
                                      child: _oge(
                                        context,
                                        gorunumSimgesi('unified'),
                                        'Tüm hesaplar',
                                        const Konum.birlesik(),
                                        sayi: BirlesikDurum.ben.toplamOkunmamis,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            const _Bolum(baslik: 'Posta kutusu'),
                            for (final k in d.sistemKlasorleri) _klasorOgesi(context, k),
                            const _Bolum(baslik: 'Görünümler'),
                            for (final (id, ad) in const [
                              ('unread', 'Okunmamışlar'),
                              ('starred', 'Yıldızlı'),
                              ('important', 'Önemli'),
                              ('attachments', 'Ekli iletiler'),
                              ('followup', 'Takip edilenler'),
                              ('all', 'Tüm postalar'),
                            ])
                              _oge(context, gorunumSimgesi(id), ad, Konum.gorunum(id), renk: gorunumRengi(id)),
                            _Bolum(
                              baslik: 'Klasörlerim',
                              eylem: IconButton(
                                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                                tooltip: 'Klasör oluştur',
                                onPressed: () => _klasorOlustur(context),
                              ),
                            ),
                            if (d.kullaniciKlasorleri.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                                child: Text('Henüz klasör yok.', style: TextStyle(color: r.silik, fontSize: 13)),
                              ),
                            if (d.kullaniciKlasorleri.length > klasorAramaEsigi)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                                child: SizedBox(
                                  height: 38,
                                  child: TextField(
                                    key: const ValueKey('klasor-ara'),
                                    controller: _klasorAra,
                                    onChanged: (_) => setState(() {}),
                                    style: const TextStyle(fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: 'Klasör ara',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                      prefixIcon: Icon(Icons.search_rounded, size: 18, color: r.silik),
                                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                                      suffixIcon: _klasorAra.text.isEmpty
                                          ? null
                                          : IconButton(
                                              tooltip: 'Aramayı temizle',
                                              icon: const Icon(Icons.close_rounded, size: 16),
                                              onPressed: () => setState(_klasorAra.clear),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            for (final k in _suzulmus(d.kullaniciKlasorleri)) _klasorOgesi(context, k, menu: true),
                            if (_klasorAra.text.trim().isNotEmpty && _suzulmus(d.kullaniciKlasorleri).isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                                child: Text('Eşleşen klasör yok.', style: TextStyle(color: r.silik, fontSize: 13)),
                              ),
                            _Bolum(
                              baslik: 'Etiketler',
                              eylem: IconButton(
                                icon: const Icon(Icons.new_label_outlined, size: 20),
                                tooltip: 'Etiket oluştur',
                                onPressed: () => _etiketOlustur(context),
                              ),
                            ),
                            if (d.etiketler.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                                child: Text('Henüz etiket yok.', style: TextStyle(color: r.silik, fontSize: 13)),
                              ),
                            for (final e in d.etiketler)
                              _oge(context, Icons.label_rounded, e.ad, Konum.etiket(e.id), sayi: e.okunmamis, renk: etiketRengi(e.renk), birakilir: true),
                            // Web kenar menüsündeki araçlar: Kişiler, Planlanan, Karantina, Gönderim durumu.
                            const _Bolum(baslik: 'Araçlar'),
                            _arac(context, Icons.contacts_outlined, 'Kişiler', KisilerEkrani.new),
                            _arac(context, Icons.schedule_send_outlined, 'Planlanan', PlanlananlarEkrani.new),
                            _arac(context, Icons.gpp_maybe_outlined, 'Karantina', KarantinaEkrani.new),
                            _arac(context, Icons.monitor_heart_outlined, 'Gönderim durumu', GonderimDurumuEkrani.new),
                          ],
                        ),
                ),
                const Divider(),
                if (!sayfa && !cekmecede)
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Ayarlar'),
                    onTap: () {
                      final nav = Navigator.of(context);
                      if (cekmecede) nav.pop();
                      nav.push(MaterialPageRoute<void>(builder: (_) => const AyarlarEkrani()));
                    },
                  ),
                // Eşitleme durumu: Canlı / Bağlanıyor… / Bağlantı yok — N sn (geri sayım), son eşitleme, Şimdi eşitle.
                const Padding(padding: EdgeInsets.fromLTRB(18, 2, 6, 0), child: EsitlemeDurumu()),
                const Padding(padding: EdgeInsets.fromLTRB(20, 0, 16, 10), child: SurumEtiketi()),
              ],
            ),
          ),
        );
        if (!sayfa) return govde;
        return Scaffold(
          appBar: AppBar(title: const Text('Klasörler')),
          body: govde,
        );
      },
    );
  }

  /// Klasör ara süzgeci (Türkçe küçük harf, web toLocaleLowerCase("tr-TR") gibi).
  List<Klasor> _suzulmus(List<Klasor> l) {
    final q = trKucukHarf(_klasorAra.text.trim());
    if (q.isEmpty || l.length <= klasorAramaEsigi) return l;
    return l.where((k) => trKucukHarf(k.gorunenAd).contains(q)).toList();
  }

  Widget _arac(BuildContext context, IconData ikon, String ad, Widget Function() sayfa) {
    final r = context.r;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: 12, right: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(ikon, size: 21, color: r.soluk),
      title: Text(ad, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
      onTap: () {
        final nav = Navigator.of(context);
        if (cekmecede) nav.pop();
        uyarlanirAc<void>(nav.context, (_) => sayfa());
      },
    );
  }

  Widget _klasorOgesi(BuildContext context, Klasor k, {bool menu = false}) {
    // Web ile aynı: taslak/şablon/ertelenen için toplam, gönderilen/çöp için sayı yok.
    final sayi = switch (k.rol) {
      'drafts' || 'templates' || 'snoozed' => k.toplam,
      'sent' || 'trash' => 0,
      _ => k.okunmamis,
    };
    final soluk = k.rol == 'drafts' || k.rol == 'templates' || k.rol == 'snoozed' || k.rol == 'junk';
    // Web ile aynı: taslak, şablon, ertelenen ve gönderilmiş klasörlerine bırakılamaz.
    final birakilir = !const {'drafts', 'templates', 'snoozed', 'sent'}.contains(k.rol);
    return _oge(
      birakilir: birakilir,
      context,
      klasorSimgesi(k.rol),
      k.gorunenAd,
      Konum.klasor(k.id),
      sayi: sayi,
      solukSayi: soluk,
      renk: klasorRengi(k.rol),
      menu: menu ? _KlasorMenusu(klasor: k) : null,
    );
  }

  Widget _oge(
    BuildContext context,
    IconData ikon,
    String ad,
    Konum konum, {
    int sayi = 0,
    bool solukSayi = false,
    Color? renk,
    Widget? menu,
    bool birakilir = false,
  }) {
    if (!birakilir || sayfa || cekmecede) return _ogeGovdesi(context, ikon, ad, konum, sayi: sayi, solukSayi: solukSayi, renk: renk, menu: menu);
    // Masaüstü: iletiler (tek ya da seçim) klasöre taşınmak / etiketlenmek üzere bırakılabilir.
    return DragTarget<IletiSurukleme>(
      key: ValueKey('birak-${konum.tur.name}-${konum.id}'),
      onWillAcceptWithDetails: (a) => a.data.kaynak != konum,
      onAcceptWithDetails: (a) => a.data.birak(konum),
      builder: (context, aday, _) => _ogeGovdesi(context, ikon, ad, konum, sayi: sayi, solukSayi: solukSayi, renk: renk, menu: menu, uzerinde: aday.isNotEmpty),
    );
  }

  Widget _ogeGovdesi(
    BuildContext context,
    IconData ikon,
    String ad,
    Konum konum, {
    int sayi = 0,
    bool solukSayi = false,
    Color? renk,
    Widget? menu,
    bool uzerinde = false,
  }) {
    final r = context.r;
    final aktif = !sayfa && PostaDurum.ben.konum == konum;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: aktif || uzerinde ? r.vurguYumusak : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: uzerinde ? BorderSide(color: r.vurgu, width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (cekmecede) Navigator.of(context).pop();
            sec(konum);
          },
          child: Semantics(
            selected: aktif,
            label: sayi > 0 ? (solukSayi ? '$ad, $sayi ileti' : '$ad, $sayi okunmamış') : ad,
            excludeSemantics: true,
            button: true,
            child: SizedBox(
              height: sayfa ? 50 : 44,
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 3,
                    height: 22,
                    decoration: BoxDecoration(color: aktif ? r.vurgu : Colors.transparent, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 9),
                  Icon(ikon, size: 21, color: renk ?? (aktif ? r.vurgu : r.soluk)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: aktif || (sayi > 0 && !solukSayi) ? FontWeight.w700 : FontWeight.w500,
                        color: aktif ? r.vurgu : r.metin,
                      ),
                    ),
                  ),
                  if (sayi > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: solukSayi ? r.ic : r.vurgu, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        sayi > 999 ? '999+' : '$sayi',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: solukSayi ? r.soluk : Colors.white),
                      ),
                    ),
                  menu ?? const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _klasorOlustur(BuildContext context) async {
    final ad = await metinSor(context, 'Yeni klasör', ipucu: 'Klasör adı', tamam: 'Oluştur');
    if (ad == null || ad.trim().isEmpty) return;
    await islem(() => Posta.klasorOlustur(ad.trim()), tamam: 'Klasör oluşturuldu');
    PostaDurum.ben.sayilariYenile(listeler: false);
  }

  Future<void> _etiketOlustur(BuildContext context) async {
    final ad = TextEditingController();
    var renk = 'blue';
    final v = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => AlertDialog(
          title: Text('Yeni etiket', style: gosterim(19, agirlik: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ad,
                autofocus: true,
                maxLength: 60,
                decoration: const InputDecoration(hintText: 'Etiket adı'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in etiketRenkleri.entries)
                    Tooltip(
                      message: etiketRenkAdlari[e.key] ?? e.key,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => yenile(() => renk = e.key),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: renk == e.key ? Border.all(color: c.r.metin, width: 2.5) : null,
                          ),
                          child: renk == e.key ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oluştur')),
          ],
        ),
      ),
    );
    final metin = ad.text.trim();
    ad.dispose();
    if (v != true || metin.isEmpty) return;
    await islem(() => Posta.etiketOlustur(metin, renk), tamam: 'Etiket oluşturuldu');
    PostaDurum.ben.sayilariYenile(listeler: false);
  }
}

class _Bolum extends StatelessWidget {
  const _Bolum({required this.baslik, this.eylem});
  final String baslik;
  final Widget? eylem;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 14, 0, 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            baslik.toUpperCase(),
            style: TextStyle(color: context.r.silik, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
        ),
        ?eylem,
      ],
    ),
  );
}

class _KlasorMenusu extends StatelessWidget {
  const _KlasorMenusu({required this.klasor});
  final Klasor klasor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '${klasor.ad} seçenekleri',
      icon: Icon(Icons.more_horiz_rounded, size: 19, color: context.r.silik),
      onSelected: (v) async {
        final d = PostaDurum.ben;
        switch (v) {
          case 'ad':
            final ad = await metinSor(context, 'Klasörü yeniden adlandır', ilk: klasor.ad, ipucu: 'Klasör adı');
            if (ad == null || ad.trim().isEmpty || ad.trim() == klasor.ad) return;
            await islem(() => Posta.klasorAdlandir(klasor.id, ad.trim()), tamam: 'Klasör yeniden adlandırıldı');
            d.sayilariYenile(listeler: false);
          case 'okundu':
            await islem(() => Posta.klasorOkundu(klasor.id), tamam: 'Tümü okundu işaretlendi');
            d.sayilariYenile();
          case 'sil':
            if (!await onayla(
              context,
              '"${klasor.ad}" silinsin mi?',
              mesaj: klasor.toplam > 0 ? 'Klasördeki ${klasor.toplam} ileti Çöp Kutusu\'na taşınır.' : null,
              evet: 'Sil',
              tehlikeli: true,
            )) {
              return;
            }
            await islem(() => Posta.klasorSil(klasor.id), tamam: 'Klasör silindi');
            if (d.konum == Konum.klasor(klasor.id)) {
              final gelen = d.rolu('inbox');
              if (gelen != null) d.git(Konum.klasor(gelen.id));
            }
            d.sayilariYenile();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'ad',
          child: ListTile(leading: Icon(Icons.drive_file_rename_outline), title: Text('Yeniden adlandır')),
        ),
        PopupMenuItem(
          value: 'okundu',
          child: ListTile(leading: Icon(Icons.done_all_rounded), title: Text('Tümünü okundu işaretle')),
        ),
        PopupMenuItem(
          value: 'sil',
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Marka.gul),
            title: Text('Klasörü sil'),
          ),
        ),
      ],
    );
  }
}

class _HesapBasligi extends StatelessWidget {
  const _HesapBasligi();

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: Uyg.kutu,
      builder: (_, k, _) {
        final ad = Uyg.ad.trim();
        final adres = Uyg.adres;
        final kota = (k?['quota_bytes'] as num?)?.toInt() ?? 0;
        final kullanilan = (k?['used_bytes'] as num?)?.toInt() ?? 0;
        final sinirsiz = sinirsizKota(kota);
        final oran = sinirsiz ? 0.0 : (kullanilan / kota).clamp(0.0, 1.0);
        final renk = oran >= .9 ? Marka.gul : (oran >= .75 ? Marka.kehribar : r.birincil);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(ad.isEmpty ? adres : ad, boyut: 46, tohum: adres),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ad.isEmpty ? adres : ad,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: gosterim(16, agirlik: FontWeight.w700),
                        ),
                        if (ad.isNotEmpty)
                          Text(
                            adres,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: r.silik, fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('hesap-degistir'),
                    tooltip: 'Hesap değiştir / ekle',
                    icon: const Icon(Icons.unfold_more_rounded),
                    onPressed: () => hesapSeciciAc(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                label: sinirsiz
                    ? 'Kota: ${boyutYaz(kullanilan)} kullanılıyor, sınırsız'
                    : 'Kota: ${boyutYaz(kota)} alanın ${boyutYaz(kullanilan)} kadarı kullanılıyor',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: sinirsiz ? 0 : oran, minHeight: 5, backgroundColor: r.ic, color: renk),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      sinirsiz ? '${boyutYaz(kullanilan)} kullanılıyor · Sınırsız' : '${boyutYaz(kullanilan)} / ${boyutYaz(kota)} (%${(oran * 100).round()})',
                      style: TextStyle(color: r.silik, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
