import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../ortak/esitleme.dart';
import '../ortak/simgeler.dart';
import '../ortak/surukle.dart';
import '../ortak/uyarlanir.dart';
import '../veri/birlesik.dart';
import '../veri/durum.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/yardimci.dart';
import 'hesap/posta_yonetimi.dart';
import '../veri/bildirim_izni.dart';
import 'hesap_menusu.dart';

/// Kenar menüsü: hesap başlığı + kota, klasörler (okunmamış sayılarıyla), görünümler, kullanıcı klasörleri, etiketler.
/// Geniş ekranda kenar çubuğu; telefonda "Klasörler" sekmesinin sayfası ([sayfa]).
class YanMenu extends StatefulWidget {
  const YanMenu({
    super.key,
    required this.sec,
    this.yeniIleti,
    this.cekmecede = false,
    this.sayfa = false,
    this.dar = false,
    this.daraltildi = false,
    this.daraltDegistir,
  });
  final ValueChanged<Konum> sec;
  final VoidCallback? yeniIleti;
  final bool cekmecede;

  /// Web: daraltılmış klasör sütunu (64 px, yalnız simgeler; ipucu = ad (sayı); okunmamışta 8 px nokta).
  final bool dar;

  /// Kullanıcı tercihi daraltılmış mı (düğme "sabitle" / "daralt" der).
  final bool daraltildi;

  /// Daralt / genişlet düğmesi (yalnız geniş ekran).
  final VoidCallback? daraltDegistir;

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
  bool _klasorlerAcik = true, _etiketlerAcik = true;

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
        if (widget.dar) return _dar(context, d);
        final gelen = d.sistemKlasorleri.where((k) => k.rol == 'inbox');
        final digerSistem = d.sistemKlasorleri.where((k) => k.rol != 'inbox');
        final govde = Material(
          // Web: kenar çubuğu bg-muted/20.
          color: sayfa ? r.kart : r.zemin,
          child: SafeArea(
            right: false,
            top: !sayfa,
            child: Column(
              children: [
                const BildirimIzniBandi(kenar: EdgeInsets.fromLTRB(12, 12, 12, 0)),
                if (yeniIleti != null)
                  // Web: h-11, rounded-xl, sola yaslı "Yeni E-posta".
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: FilledButton.icon(
                              key: const ValueKey('yeni-eposta'),
                              style: FilledButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                elevation: 1,
                                textStyle: TextStyle(fontFamily: govdeYaziTipi, fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                              onPressed: yeniIleti,
                              icon: const Icon(Simge.duzenle, size: 20),
                              label: const Text('Yeni E-posta'),
                            ),
                          ),
                        ),
                        if (widget.daraltDegistir != null) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: IconButton(
                              key: const ValueKey('kenar-daralt'),
                              padding: EdgeInsets.zero,
                              iconSize: 17,
                              tooltip: widget.daraltildi ? 'Klasörleri sabitle' : 'Klasörleri daralt',
                              onPressed: widget.daraltDegistir,
                              icon: Icon(Simge.kenarCubugu, color: r.metin),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                Expanded(
                  child: !d.yuklendi && d.hata == null
                      ? const Center(child: CircularProgressIndicator.adaptive())
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                          children: [
                            if (d.hata != null && d.klasorler.isEmpty)
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
                            // Web sırası: Gelen, Yıldızlı, Önemli, Okunmamışlar, Takip, diğer sistem klasörleri, Planlanan,
                            // Karantina, Gönderim durumu (+ Kişiler; web'de ayrı uygulama).
                            for (final k in gelen) _klasorOgesi(context, k),
                            // 1.4'teki "Ekli iletiler" ve "Tüm postalar" görünümleri de korunur.
                            for (final (id, ad) in const [
                              ('starred', 'Yıldızlı'),
                              ('important', 'Önemli'),
                              ('unread', 'Okunmamışlar'),
                              ('followup', 'Takip'),
                              ('attachments', 'Ekli iletiler'),
                              ('all', 'Tüm postalar'),
                            ])
                              _oge(context, gorunumSimgesi(id), ad, Konum.gorunum(id), renk: gorunumRengi(id)),
                            for (final k in digerSistem) _klasorOgesi(context, k),
                            _arac(context, Simge.planliGonder, 'Planlanan', PlanlananlarEkrani.new),
                            _arac(context, Simge.gereksiz, 'Karantina', KarantinaEkrani.new),
                            _arac(context, Simge.gonderimDurumu, 'Gönderim durumu', GonderimDurumuEkrani.new),
                            _arac(context, Simge.kisiler, 'Kişiler', KisilerEkrani.new),
                            _Bolum(
                              baslik: 'Klasörlerim',
                              acik: _klasorlerAcik,
                              degistir: () => setState(() => _klasorlerAcik = !_klasorlerAcik),
                              eylem: _BolumEylemi(ikon: Simge.klasorEkle, ipucu: 'Klasör oluştur', dokun: () => _klasorOlustur(context)),
                            ),
                            if (_klasorlerAcik) ...[
                              if (d.kullaniciKlasorleri.isEmpty)
                                _ogeGovdesi(context, Simge.ekle, 'Klasör oluştur', null, soluk: true, dokun: () => _klasorOlustur(context)),
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
                                        prefixIcon: Icon(Simge.ara, size: 18, color: r.silik),
                                        prefixIconConstraints: const BoxConstraints(minWidth: 36),
                                        suffixIcon: _klasorAra.text.isEmpty
                                            ? null
                                            : IconButton(
                                                tooltip: 'Aramayı temizle',
                                                icon: const Icon(Simge.kapat, size: 16),
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
                            ],
                            _Bolum(
                              baslik: 'Etiketler',
                              acik: _etiketlerAcik,
                              degistir: () => setState(() => _etiketlerAcik = !_etiketlerAcik),
                              eylem: _BolumEylemi(ikon: Simge.ekle, ipucu: 'Etiket ekle', dokun: () => _etiketOlustur(context)),
                            ),
                            if (_etiketlerAcik) ...[
                              if (d.etiketler.isEmpty)
                                _ogeGovdesi(context, Simge.etiket, 'Etiket ekle', null, soluk: true, dokun: () => _etiketOlustur(context)),
                              for (final e in d.etiketler)
                                _oge(
                                  context,
                                  Simge.etiket,
                                  e.ad,
                                  Konum.etiket(e.id),
                                  sayi: e.okunmamis,
                                  solukSayi: true,
                                  renk: etiketRengi(e.renk),
                                  nokta: true,
                                  birakilir: true,
                                ),
                            ],
                          ],
                        ),
                ),
                // Telefonda (çekmece / klasörler sayfası) altta hesap bloğu, eşitleme durumu ve sürüm. Geniş ekranda
                // bunların hepsi sol rayın altındadır; klasör çubuğunun altı boş kalır.
                if (sayfa || cekmecede) ...[
                  Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
                  HesapBlogu(cekmecede: cekmecede),
                  // Canlı / Bağlanıyor… / Bağlantı yok — N sn (geri sayım), son eşitleme, Şimdi eşitle.
                  const Padding(padding: EdgeInsets.fromLTRB(18, 2, 6, 0), child: EsitlemeDurumu()),
                  const Padding(padding: EdgeInsets.fromLTRB(20, 0, 16, 10), child: SurumEtiketi()),
                ],
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

  /// Daraltılmış sütun (web compact): genişlet düğmesi, 40 px yeni ileti, 40×40 simge düğmeleri.
  Widget _dar(BuildContext context, PostaDurum d) {
    final r = context.r;
    Widget simge(String anahtar, IconData ikon, String ad, Konum? konum, {int sayi = 0, Color? renk, VoidCallback? dokun}) {
      final aktif = konum != null && d.konum == konum;
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Tooltip(
          message: sayi > 0 ? '$ad ($sayi)' : ad,
          waitDuration: const Duration(milliseconds: 300),
          child: Semantics(
            label: sayi > 0 ? '$ad, $sayi okunmamış' : ad,
            selected: aktif,
            button: true,
            excludeSemantics: true,
            child: Material(
              color: aktif ? r.birincil.withValues(alpha: .1) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: ValueKey('dar-$anahtar'),
                borderRadius: BorderRadius.circular(10),
                hoverColor: r.ic,
                onTap: dokun ?? () => sec(konum!),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    children: [
                      Center(child: Icon(ikon, size: 18, color: aktif ? r.birincil : (renk ?? r.metin))),
                      if (sayi > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: r.birincil,
                              shape: BoxShape.circle,
                              border: Border.all(color: r.zemin, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final gelen = d.sistemKlasorleri.where((k) => k.rol == 'inbox');
    final digerSistem = d.sistemKlasorleri.where((k) => k.rol != 'inbox');
    return Material(
      color: r.zemin,
      child: Column(
        children: [
          const SizedBox(height: 12),
          if (widget.daraltDegistir != null)
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                key: const ValueKey('kenar-genislet'),
                padding: EdgeInsets.zero,
                iconSize: 17,
                tooltip: 'Klasörleri genişlet',
                onPressed: widget.daraltDegistir,
                icon: Icon(Simge.kenarCubugu, color: r.metin),
              ),
            ),
          if (yeniIleti != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Tooltip(
                message: 'Yeni E-posta',
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: FilledButton(
                    key: const ValueKey('dar-yeni'),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 40),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: yeniIleti,
                    child: const Icon(Simge.duzenle, size: 20),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                if (BirlesikDurum.ben.kullanilabilir)
                  simge('birlesik', gorunumSimgesi('unified'), 'Tüm hesaplar', const Konum.birlesik(), sayi: BirlesikDurum.ben.toplamOkunmamis),
                for (final k in gelen) simge(k.id, klasorSimgesi(k.rol), k.gorunenAd, Konum.klasor(k.id), sayi: k.okunmamis),
                simge('starred', gorunumSimgesi('starred'), 'Yıldızlı', const Konum.gorunum('starred'), renk: gorunumRengi('starred')),
                simge('unread', gorunumSimgesi('unread'), 'Okunmamışlar', const Konum.gorunum('unread')),
                simge('important', gorunumSimgesi('important'), 'Önemli', const Konum.gorunum('important'), renk: gorunumRengi('important')),
                simge('followup', gorunumSimgesi('followup'), 'Takip', const Konum.gorunum('followup'), renk: gorunumRengi('followup')),
                simge('attachments', gorunumSimgesi('attachments'), 'Ekli iletiler', const Konum.gorunum('attachments')),
                simge('all', gorunumSimgesi('all'), 'Tüm postalar', const Konum.gorunum('all')),
                for (final k in digerSistem)
                  simge(
                    k.id,
                    klasorSimgesi(k.rol),
                    k.gorunenAd,
                    Konum.klasor(k.id),
                    sayi: const {'sent', 'trash', 'drafts', 'templates', 'snoozed'}.contains(k.rol) ? 0 : k.okunmamis,
                    renk: klasorRengi(k.rol),
                  ),
                simge('planlanan', Simge.planliGonder, 'Planlanan', null, dokun: () => uyarlanirAc<void>(context, (_) => const PlanlananlarEkrani())),
                simge('karantina', Simge.gereksiz, 'Karantina', null, dokun: () => uyarlanirAc<void>(context, (_) => const KarantinaEkrani())),
                simge('gonderim', Simge.gonderimDurumu, 'Gönderim durumu', null, dokun: () => uyarlanirAc<void>(context, (_) => const GonderimDurumuEkrani())),
                simge('kisiler', Simge.kisiler, 'Kişiler', null, dokun: () => uyarlanirAc<void>(context, (_) => const KisilerEkrani())),
                for (final k in d.kullaniciKlasorleri) simge(k.id, klasorSimgesi(k.rol), k.gorunenAd, Konum.klasor(k.id), sayi: k.okunmamis),
                for (final e in d.etiketler) simge('e-${e.id}', Simge.etiket, e.ad, Konum.etiket(e.id), sayi: e.okunmamis, renk: etiketRengi(e.renk)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Klasör ara süzgeci (Türkçe küçük harf, web toLocaleLowerCase("tr-TR") gibi).
  List<Klasor> _suzulmus(List<Klasor> l) {
    final q = trKucukHarf(_klasorAra.text.trim());
    if (q.isEmpty || l.length <= klasorAramaEsigi) return l;
    return l.where((k) => trKucukHarf(k.gorunenAd).contains(q)).toList();
  }

  Widget _arac(BuildContext context, IconData ikon, String ad, Widget Function() sayfa) => _ogeGovdesi(
    context,
    ikon,
    ad,
    null,
    dokun: () {
      final nav = Navigator.of(context);
      if (cekmecede) nav.pop();
      uyarlanirAc<void>(nav.context, (_) => sayfa());
    },
  );

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
    bool nokta = false,
  }) {
    if (!birakilir || sayfa || cekmecede) return _ogeGovdesi(context, ikon, ad, konum, sayi: sayi, solukSayi: solukSayi, renk: renk, menu: menu, nokta: nokta);
    // Masaüstü: iletiler (tek ya da seçim) klasöre taşınmak / etiketlenmek üzere bırakılabilir.
    return DragTarget<IletiSurukleme>(
      key: ValueKey('birak-${konum.tur.name}-${konum.id}'),
      onWillAcceptWithDetails: (a) => a.data.kaynak != konum,
      onAcceptWithDetails: (a) => a.data.birak(konum),
      builder: (context, aday, _) =>
          _ogeGovdesi(context, ikon, ad, konum, sayi: sayi, solukSayi: solukSayi, renk: renk, menu: menu, nokta: nokta, uzerinde: aday.isNotEmpty),
    );
  }

  /// Web NavItem: h-9 (telefonda 44), rounded-lg, px-2.5, 16 px simge, text-sm; etkin: primary/10 zemin, birincil
  /// renkli orta kalın yazı. Sayı rozeti: birincil (okunmamış) ya da soluk (toplam). [nokta]: etiket rengi noktası.
  Widget _ogeGovdesi(
    BuildContext context,
    IconData ikon,
    String ad,
    Konum? konum, {
    int sayi = 0,
    bool solukSayi = false,
    Color? renk,
    Widget? menu,
    bool uzerinde = false,
    bool nokta = false,
    bool soluk = false,
    VoidCallback? dokun,
  }) {
    final r = context.r;
    final aktif = konum != null && !sayfa && PostaDurum.ben.konum == konum;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: uzerinde ? r.birincil.withValues(alpha: .2) : (aktif ? r.birincil.withValues(alpha: .1) : Colors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: uzerinde ? BorderSide(color: r.birincil.withValues(alpha: .4), width: 2) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: aktif ? r.birincil.withValues(alpha: .05) : r.ic,
          onTap:
              dokun ??
              () {
                if (cekmecede) Navigator.of(context).pop();
                sec(konum!);
              },
          child: Semantics(
            selected: aktif,
            label: sayi > 0 ? (solukSayi ? '$ad, $sayi ileti' : '$ad, $sayi okunmamış') : ad,
            excludeSemantics: true,
            button: true,
            child: SizedBox(
              height: sayfa ? 44 : 36,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  if (nokta)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 2),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: renk ?? r.silik, shape: BoxShape.circle),
                      ),
                    )
                  else
                    Icon(ikon, size: 16, color: aktif ? r.birincil : (renk ?? (soluk ? r.silik : r.metin))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: aktif ? FontWeight.w500 : FontWeight.w400,
                        color: aktif ? r.birincil : (soluk ? r.silik : r.metin),
                      ),
                    ),
                  ),
                  if (sayi > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 24),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: solukSayi ? r.ic : r.birincil, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        sayi > 999 ? '999+' : '$sayi',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          color: solukSayi ? r.silik : Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  menu ?? const SizedBox(width: 10),
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
          title: Text('Yeni etiket', style: gosterim(19, agirlik: FontWeight.w600)),
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
                          child: renk == e.key ? const Icon(Simge.onay, color: Colors.white, size: 18) : null,
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

/// Web Section: mt-4, açılır kapanır başlık (chevron + BÜYÜK HARF text-xs font-semibold soluk), sağda küçük eylem.
class _Bolum extends StatelessWidget {
  const _Bolum({required this.baslik, this.eylem, this.acik = true, this.degistir});
  final String baslik;
  final Widget? eylem;
  final bool acik;
  final VoidCallback? degistir;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: degistir,
              borderRadius: BorderRadius.circular(6),
              child: Semantics(
                expanded: acik,
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: acik ? 0 : -.25,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(Simge.asagi, size: 14, color: r.silik),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trBuyukHarf(baslik),
                      style: TextStyle(color: r.silik, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: .3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ?eylem,
        ],
      ),
    );
  }
}

class _BolumEylemi extends StatelessWidget {
  const _BolumEylemi({required this.ikon, required this.ipucu, required this.dokun});
  final IconData ikon;
  final String ipucu;
  final VoidCallback dokun;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: IconButton(
      padding: EdgeInsets.zero,
      iconSize: 14,
      tooltip: ipucu,
      onPressed: dokun,
      icon: Icon(ikon, color: context.r.silik),
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
      icon: Icon(Simge.dahaFazla, size: 16, color: context.r.silik),
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
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
          child: ListTile(leading: Icon(Simge.yenidenAdlandir), title: Text('Yeniden adlandır')),
        ),
        PopupMenuItem(
          value: 'okundu',
          child: ListTile(leading: Icon(Simge.hepsiOkundu), title: Text('Tümünü okundu işaretle')),
        ),
        PopupMenuItem(
          value: 'sil',
          child: ListTile(
            leading: Icon(Simge.sil, color: Marka.gul),
            title: Text('Klasörü sil'),
          ),
        ),
      ],
    );
  }
}
