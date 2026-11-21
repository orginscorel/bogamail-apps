// "Tüm hesaplar" birleşik gelen kutusu: liste (hesap renkli etiket, klasör ve hesap süzgeçleri) ve hesap
// değiştirmeden okuma. Yanıtla/ilet önce o hesaba geçer, sonra yazma penceresini açar.

import 'dart:async';
import 'dart:math';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/ek_listesi.dart';
import '../ortak/esitleme.dart';
import '../ortak/html_govde.dart';
import '../veri/birlesik.dart';
import '../veri/durum.dart';
import '../veri/modeller.dart';
import '../veri/onbellek.dart';
import '../veri/posta_servisi.dart';
import '../veri/tercihler.dart';
import '../veri/yazma_hazirla.dart';
import 'ileti_satiri.dart';
import 'okuyucu.dart';
import 'yazma.dart';

/// Telefonda birleşik iletiyi tam sayfa açar.
Future<void> birlesikOkuyucuAc(BuildContext context, BirlesikOge o, {BirlesikHesap? hesap}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (c) => BirlesikOkuyucu(oge: o, hesap: hesap, sayfa: true, kaldirildi: () => Navigator.of(c).maybePop()),
  ),
);

/// Yanıtla / tümünü yanıtla / ilet: ileti oturumdaki hesaba aitse hemen; değilse önce o hesaba geçilir, yeni
/// kabuk açılınca yazma penceresi açılır (gönderen o hesap olur).
Future<void> birlesikYaz(BuildContext context, BirlesikOge o, String tur) async {
  final simdiki = '${Uyg.kutu.value?['mailbox_id'] ?? ''}';
  if (o.kutuId == simdiki) {
    await bekleyenYazmayiAc(context, o.ozet.id, tur);
    return;
  }
  Uyg.bekleyenYazma = (o.ozet.id, tur);
  final ok = await Uyg.hesabaGec(id: o.kutuId);
  if (!ok) Uyg.bekleyenYazma = null;
}

/// Oturumdaki hesabın iletisi için yanıt/iletme penceresi (tur: yanit | tumu | ilet).
Future<void> bekleyenYazmayiAc(BuildContext context, String iletiId, String tur) async {
  try {
    final d = await Posta.ileti(iletiId);
    if (!context.mounted) return;
    await yazmaAc(context, tur == 'ilet' ? iletHazirla(d) : yanitHazirla(d, ben: Uyg.adres, tumu: tur == 'tumu'));
  } catch (e) {
    bildir('İleti açılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
  }
}

class BirlesikListe extends StatefulWidget {
  const BirlesikListe({super.key, required this.ac, this.seciliAnahtar, this.klasorler, this.klasorRozeti = 0, this.fab, this.kaldirildi});

  final void Function(BirlesikOge oge, BirlesikHesap? hesap) ac;
  final String? seciliAnahtar;
  final VoidCallback? klasorler;
  final int klasorRozeti;
  final Widget? fab;

  /// İletiler listeden çıktı (arşiv, çöp, gereksiz).
  final ValueChanged<Set<String>>? kaldirildi;

  @override
  State<BirlesikListe> createState() => BirlesikListeState();
}

class BirlesikListeState extends State<BirlesikListe> {
  final _kaydirma = ScrollController();
  String _klasor = 'inbox';
  String? _hesapSuzgeci;
  List<BirlesikHesap> _hesaplar = [];
  List<BirlesikOge> _ogeler = [];
  String? _sonraki;
  bool _yukleniyor = true;
  bool _dahaYukleniyor = false;
  String? _hata;
  int _istek = 0;
  final _abonelikler = <StreamSubscription<Object?>>[];

  /// Çoklu seçim (satırdaki kutucuk): anahtar = BirlesikOge.anahtar.
  final _secilen = <String>{};

  @override
  void initState() {
    super.initState();
    _kaydirma.addListener(_kaydi);
    _abonelikler
      ..add(BirlesikDurum.ben.yeniPosta.listen((_) => _yukle(sessiz: true)))
      ..add(BirlesikDurum.ben.yerelDegisiklikler.listen((_) => mounted ? setState(() {}) : null));
    PostaDurum.ben.surum.addListener(_canli);
    _yukle();
  }

  @override
  void dispose() {
    for (final a in _abonelikler) {
      a.cancel();
    }
    PostaDurum.ben.surum.removeListener(_canli);
    _kaydirma.dispose();
    super.dispose();
  }

  void _canli() {
    if (!_yukleniyor && !_dahaYukleniyor) _yukle(sessiz: true);
  }

  void _kaydi() {
    if (_kaydirma.position.extentAfter < 1200 && !_dahaYukleniyor && !_yukleniyor && _sonraki != null) _dahaFazla();
  }

  BirlesikHesap? hesap(String kutuId) => _hesaplar.where((h) => h.id == kutuId).firstOrNull;

  List<BirlesikOge> get _gorunen => _hesapSuzgeci == null ? _ogeler : _ogeler.where((o) => o.kutuId == _hesapSuzgeci).toList();

  Future<void> _yukle({bool sessiz = false}) async {
    final no = ++_istek;
    final klasor = _klasor;
    if (!sessiz) {
      setState(() {
        _yukleniyor = true;
        _hata = null;
      });
      final o = await Birlesik.listeOnbellek(klasor).catchError((_) => null);
      if (!mounted || no != _istek) return;
      if (o != null) {
        setState(() {
          _hesaplar = o.hesaplar;
          _ogeler = o.ogeler;
          _sonraki = o.sonraki;
          _yukleniyor = false;
        });
        sessiz = true;
      }
    }
    final sw = Stopwatch()..start();
    try {
      final s = await Birlesik.liste(klasor: klasor);
      if (!mounted || no != _istek) return;
      zamanLogu('birleşik liste (ağ)', sw);
      setState(() {
        _hesaplar = s.hesaplar;
        _ogeler = s.ogeler;
        _sonraki = s.sonraki;
        _yukleniyor = false;
        _hata = null;
        if (_hesapSuzgeci != null && !_hesaplar.any((h) => h.id == _hesapSuzgeci)) _hesapSuzgeci = null;
      });
    } catch (e) {
      if (!mounted || no != _istek) return;
      setState(() {
        _yukleniyor = false;
        if (!sessiz || _ogeler.isEmpty) _hata = hataMetni(e);
      });
    }
  }

  Future<void> _dahaFazla() async {
    final no = _istek;
    setState(() => _dahaYukleniyor = true);
    try {
      final s = await Birlesik.liste(klasor: _klasor, once: _sonraki);
      if (!mounted || no != _istek) return;
      final var_ = _ogeler.map((o) => o.anahtar).toSet();
      setState(() {
        _ogeler = [..._ogeler, ...s.ogeler.where((o) => !var_.contains(o.anahtar))];
        _sonraki = s.sonraki;
      });
    } catch (e) {
      if (mounted) bildir('Daha fazla ileti yüklenemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _dahaYukleniyor = false);
    }
  }

  void _klasorSec(String k) {
    if (k == _klasor) return;
    setState(() {
      _klasor = k;
      _ogeler = [];
      _secilen.clear();
    });
    _yukle();
  }

  /// İşlem: iyimser (satır hemen güncellenir/çıkar), hata olursa geri alınır.
  Future<void> _eylem(BirlesikOge o, String eylem) => _toplu([o], eylem);

  Future<void> _toplu(List<BirlesikOge> os, String eylem) async {
    if (os.isEmpty) return;
    final kaldir = const {'archive', 'trash', 'spam'}.contains(eylem);
    final onceki = List<BirlesikOge>.from(_ogeler);
    final eski = {for (final o in os) o.anahtar: (o.ozet.okundu, o.ozet.yildizli)};
    final anahtarlar = {for (final o in os) o.anahtar};
    setState(() {
      for (final o in os) {
        switch (eylem) {
          case 'seen':
            o.ozet.okundu = true;
          case 'unseen':
            o.ozet.okundu = false;
          case 'flag':
            o.ozet.yildizli = true;
          case 'unflag':
            o.ozet.yildizli = false;
        }
      }
      if (kaldir) {
        _ogeler.removeWhere((x) => anahtarlar.contains(x.anahtar));
        _secilen.removeAll(anahtarlar);
      }
    });
    if (kaldir) widget.kaldirildi?.call(anahtarlar);
    try {
      await Birlesik.eylem(os, eylem);
      unawaited(BirlesikDurum.ben.sayilariYenile());
      if (kaldir) {
        bildir(switch (eylem) {
          'archive' => 'Arşivlendi',
          'trash' => 'Çöp Kutusu\'na taşındı',
          _ => 'Gereksiz olarak işaretlendi',
        }, tur: MesajTur.basari);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ogeler = onceki;
        for (final o in os) {
          final e = eski[o.anahtar];
          if (e != null) {
            o.ozet.okundu = e.$1;
            o.ozet.yildizli = e.$2;
          }
        }
      });
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  void _secDegistir(BirlesikOge o) => setState(() {
    if (!_secilen.remove(o.anahtar)) _secilen.add(o.anahtar);
  });

  /// Seçim varken klasör/hesap sırasının yerine geçen toplu işlem çubuğu (web unified-view ile aynı işlemler).
  Widget _secimCubugu(Renkler r, List<BirlesikOge> gorunen) {
    final secilen = gorunen.where((o) => _secilen.contains(o.anahtar)).toList();
    final hepsi = secilen.length == gorunen.length && gorunen.isNotEmpty;
    final hepsiOkundu = secilen.every((o) => o.ozet.okundu);
    final hepsiYildizli = secilen.every((o) => o.ozet.yildizli);
    Widget d(IconData i, String t, VoidCallback f, {Color? renk}) => IconButton(
      tooltip: t,
      visualDensity: VisualDensity.compact,
      icon: Icon(i, size: 19, color: renk ?? r.metin),
      onPressed: f,
    );
    return Container(
      key: const ValueKey('birlesik-secim'),
      color: r.vurguYumusak,
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
      child: Row(
        children: [
          d(Simge.kapat, 'Seçimi kaldır', () => setState(_secilen.clear)),
          Expanded(
            child: Text(
              '${_secilen.length} seçili',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: r.metin),
            ),
          ),
          d(hepsi ? Simge.secimiKaldir : Simge.tumunuSec, hepsi ? 'Hiçbiri' : 'Tümünü seç', () {
            setState(() {
              if (hepsi) {
                _secilen.clear();
              } else {
                _secilen.addAll(gorunen.map((o) => o.anahtar));
              }
            });
          }),
          d(
            hepsiOkundu ? Simge.okunmadiYap : Simge.okunduYap,
            hepsiOkundu ? 'Okunmadı yap' : 'Okundu yap',
            () => _toplu(secilen, hepsiOkundu ? 'unseen' : 'seen'),
          ),
          d(
            hepsiYildizli ? Simge.yildizDolu : Simge.yildiz,
            hepsiYildizli ? 'Yıldızı kaldır' : 'Yıldızla',
            () => _toplu(secilen, hepsiYildizli ? 'unflag' : 'flag'),
          ),
          if (_klasor != 'archive') d(Simge.arsiv, 'Arşivle', () => _toplu(secilen, 'archive')),
          if (_klasor != 'trash') d(Simge.sil, 'Sil', () => _toplu(secilen, 'trash'), renk: Marka.gul),
        ],
      ),
    );
  }

  void _ac(BirlesikOge o) {
    if (!o.ozet.okundu) unawaited(_eylem(o, 'seen'));
    widget.ac(o, hesap(o.kutuId));
  }

  static const _hap = 32.0;

  /// "Gelen ▾": birleşik klasör seçimi (açılır menü).
  Widget _klasorSecici(Renkler r) {
    final ad = birlesikKlasorler.where((k) => k.$1 == _klasor).firstOrNull?.$2 ?? 'Gelen';
    return PopupMenuButton<String>(
      key: const ValueKey('birlesik-klasor-sec'),
      tooltip: 'Klasör',
      position: PopupMenuPosition.under,
      onSelected: _klasorSec,
      itemBuilder: (_) => [
        for (final (id, ad, ikon) in birlesikKlasorler)
          PopupMenuItem(
            key: ValueKey('birlesik-klasor-$id'),
            value: id,
            height: 40,
            child: Row(
              children: [
                Icon(ikon, size: 18, color: _klasor == id ? r.vurgu : r.soluk),
                const SizedBox(width: 10),
                Text(ad, style: TextStyle(fontSize: 13.5, fontWeight: _klasor == id ? FontWeight.w600 : FontWeight.w400)),
              ],
            ),
          ),
      ],
      child: Container(
        height: _hap,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(color: r.vurguYumusak, borderRadius: BorderRadius.circular(_hap / 2)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ad,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: r.vurgu),
            ),
            const SizedBox(width: 2),
            Icon(Simge.asagi, size: 16, color: r.vurgu),
          ],
        ),
      ),
    );
  }

  /// Hesap süzgeci: "Hepsi" + her hesap için renkli nokta ve kısa ad. Sığmazsa yatay kayar, kenarı solar.
  Widget _hesapSuzgeciSirasi(Renkler r) {
    final b = BirlesikDurum.ben;
    Widget hap({required Key key, required bool secili, required VoidCallback f, Color? renk, required String metin, String? ipucu}) {
      final w = InkWell(
        key: key,
        borderRadius: BorderRadius.circular(_hap / 2),
        onTap: f,
        child: Container(
          height: _hap,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: secili ? (renk ?? r.vurgu).withValues(alpha: .12) : Colors.transparent,
            borderRadius: BorderRadius.circular(_hap / 2),
            border: Border.all(color: secili ? (renk ?? r.vurgu).withValues(alpha: .5) : r.kenar),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (renk != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                metin,
                style: TextStyle(fontSize: 13, fontWeight: secili ? FontWeight.w500 : FontWeight.w400, color: secili ? r.metin : r.soluk),
              ),
            ],
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ipucu == null ? w : Tooltip(message: ipucu, child: w),
      );
    }

    final ogeler = [
      hap(key: const ValueKey('birlesik-hesap-hepsi'), secili: _hesapSuzgeci == null, f: () => setState(() => _hesapSuzgeci = null), metin: 'Hepsi'),
      for (final h in _hesaplar)
        hap(
          key: ValueKey('birlesik-hesap-${h.id}'),
          secili: _hesapSuzgeci == h.id,
          f: () => setState(() => _hesapSuzgeci = _hesapSuzgeci == h.id ? null : h.id),
          renk: h.renk,
          metin: (b.hesapOkunmamis[h.id] ?? 0) > 0 ? '${h.kisa} ${sayiYaz(b.hesapOkunmamis[h.id]!)}' : h.kisa,
          ipucu: h.adres,
        ),
    ];
    return SizedBox(
      height: _hap,
      child: ShaderMask(
        // Sağ kenarda yumuşak solma: taşan hesaplar kesik görünmez.
        shaderCallback: (rect) =>
            LinearGradient(colors: const [Colors.white, Colors.white, Colors.transparent], stops: [0, (rect.width - 24) / rect.width, 1]).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(right: 20), children: ogeler),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final b = BirlesikDurum.ben;
    final l = _gorunen;
    return Scaffold(
      backgroundColor: r.zemin,
      floatingActionButton: widget.fab,
      appBar: AppBar(
        leading: widget.klasorler == null
            ? null
            : IconButton(
                tooltip: 'Klasörler',
                onPressed: widget.klasorler,
                icon: Badge(isLabelVisible: widget.klasorRozeti > 0, smallSize: 7, label: null, child: const Icon(Simge.menu)),
              ),
        titleSpacing: widget.klasorler != null ? 0 : 16,
        // Sade başlık: normal ağırlıkta ad, okunmamış sayısı soluk küçük metin.
        title: ListenableBuilder(
          listenable: b,
          builder: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tüm hesaplar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: r.metin),
              ),
              if (b.toplamOkunmamis > 0)
                Text(
                  '${sayiYaz(b.toplamOkunmamis)} okunmamış',
                  key: const ValueKey('birlesik-okunmamis'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: r.soluk),
                ),
            ],
          ),
        ),
        actions: [
          if (context.genis)
            IconButton(
              tooltip: 'Yenile',
              icon: const Icon(Simge.yenile, size: 20),
              onPressed: () => _yukle(sessiz: _ogeler.isNotEmpty),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!context.genis) const EsitlemeDurumu(serit: true),
          if (_secilen.isNotEmpty)
            _secimCubugu(r, l)
          else
            // Tek sıra: klasör seçici (Gelen ▾) + hesap süzgeci (renkli noktalar). Ekrana sığar; sığmazsa kayar.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  _klasorSecici(r),
                  const SizedBox(width: 8),
                  if (_hesaplar.length > 1)
                    Expanded(
                      child: ListenableBuilder(listenable: b, builder: (_, _) => _hesapSuzgeciSirasi(r)),
                    ),
                ],
              ),
            ),
          Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
          Expanded(
            child: _yukleniyor && _ogeler.isEmpty
                ? const Durum.yukleniyor()
                : _hata != null && _ogeler.isEmpty
                ? Durum.hata(_hata!, tekrar: _yukle)
                : l.isEmpty
                ? const Durum.bos('Burada ileti yok', ikon: Simge.katmanlar)
                : RefreshIndicator(
                    onRefresh: () => _yukle(sessiz: true),
                    child: ListView.builder(
                      controller: _kaydirma,
                      itemCount: l.length + (_dahaYukleniyor ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= l.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator.adaptive()),
                          );
                        }
                        final o = l[i];
                        final h = hesap(o.kutuId);
                        return KeyedSubtree(
                          key: ValueKey('birlesik-${o.anahtar}'),
                          child: IletiSatiri(
                            ileti: o.ozet,
                            secili: _secilen.contains(o.anahtar),
                            acik: widget.seciliAnahtar == o.anahtar,
                            secimModu: _secilen.isNotEmpty,
                            copte: false,
                            arsivde: false,
                            dokun: () => _secilen.isNotEmpty ? _secDegistir(o) : _ac(o),
                            sec: () => _secDegistir(o),
                            okundu: () => _eylem(o, o.ozet.okundu ? 'unseen' : 'seen'),
                            yildiz: () => _eylem(o, o.ozet.yildizli ? 'unflag' : 'flag'),
                            arsivle: () => _eylem(o, 'archive'),
                            sil: () => _eylem(o, 'trash'),
                            hesapRengi: h?.renk ?? BirlesikHesap.renkCoz(''),
                            hesapEtiketi: h?.kisa ?? (o.hesap.contains('@') ? o.hesap.substring(0, o.hesap.indexOf('@')) : o.hesap),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Birleşik ileti okuyucu: içerik hesap değiştirmeden gösterilir.
class BirlesikOkuyucu extends StatefulWidget {
  const BirlesikOkuyucu({super.key, required this.oge, this.hesap, this.sayfa = false, this.kaldirildi});
  final BirlesikOge oge;
  final BirlesikHesap? hesap;
  final bool sayfa;
  final VoidCallback? kaldirildi;

  @override
  State<BirlesikOkuyucu> createState() => _BirlesikOkuyucuState();
}

class _BirlesikOkuyucuState extends State<BirlesikOkuyucu> {
  IletiDetay? _d;
  String? _hata;
  bool _mesgul = false;

  BirlesikOge get o => widget.oge;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void didUpdateWidget(BirlesikOkuyucu eski) {
    super.didUpdateWidget(eski);
    if (eski.oge.anahtar != widget.oge.anahtar) {
      setState(() {
        _d = Birlesik.iletiHemen(o.kutuId, o.ozet.id);
        _hata = null;
      });
      _yukle();
    }
  }

  Future<void> _yukle() async {
    final a = o.anahtar;
    _d ??= Birlesik.iletiHemen(o.kutuId, o.ozet.id);
    try {
      final d = await Birlesik.ileti(o.kutuId, o.ozet.id);
      if (!mounted || a != o.anahtar) return;
      setState(() => _d = d);
    } catch (e) {
      if (!mounted || a != o.anahtar) return;
      if (_d == null) {
        setState(() => _hata = e is ApiHata && e.durum == 404 ? 'İleti bulunamadı; silinmiş veya taşınmış olabilir.' : hataMetni(e));
      }
    }
  }

  Future<void> _eylem(String eylem, String tamam) async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      await Birlesik.eylem([o], eylem);
      switch (eylem) {
        case 'unseen':
          o.ozet.okundu = false;
        case 'flag':
          o.ozet.yildizli = true;
        case 'unflag':
          o.ozet.yildizli = false;
      }
      _d?.ozet.yildizli = o.ozet.yildizli;
      BirlesikDurum.ben.yerelDegisti(o.anahtar);
      unawaited(BirlesikDurum.ben.sayilariYenile());
      bildir(tamam, tur: MesajTur.basari);
      if (const {'archive', 'trash', 'spam', 'unseen'}.contains(eylem)) widget.kaldirildi?.call();
    } catch (e) {
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = _d;
    final h = widget.hesap;
    final renk = h?.renk ?? BirlesikHesap.renkCoz('');
    final eylemler = <Widget>[
      IconButton(
        key: const ValueKey('birlesik-yildiz'),
        tooltip: o.ozet.yildizli ? 'Yıldızı kaldır' : 'Yıldızla',
        icon: Icon(o.ozet.yildizli ? Simge.yildizDolu : Simge.yildiz, color: o.ozet.yildizli ? const Color(0xFFEAB308) : null),
        onPressed: () => _eylem(o.ozet.yildizli ? 'unflag' : 'flag', o.ozet.yildizli ? 'Yıldız kaldırıldı' : 'Yıldızlandı'),
      ),
      IconButton(key: const ValueKey('birlesik-arsiv'), tooltip: 'Arşivle', icon: const Icon(Simge.arsiv), onPressed: () => _eylem('archive', 'Arşivlendi')),
      IconButton(
        key: const ValueKey('birlesik-cop'),
        tooltip: 'Çöp Kutusu\'na taşı',
        icon: const Icon(Simge.sil),
        onPressed: () => _eylem('trash', 'Çöp Kutusu\'na taşındı'),
      ),
      PopupMenuButton<String>(
        tooltip: 'Diğer',
        onSelected: (v) => switch (v) {
          'okunmadi' => _eylem('unseen', 'Okunmadı olarak işaretlendi'),
          'spam' => _eylem('spam', 'Gereksiz olarak işaretlendi'),
          _ => null,
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'okunmadi',
            child: ListTile(leading: Icon(Simge.okunmadiYap), title: Text('Okunmadı yap')),
          ),
          PopupMenuItem(
            value: 'spam',
            child: ListTile(
              leading: Icon(Simge.gereksiz, color: Color(0xFFF97316)),
              title: Text('Gereksiz olarak işaretle'),
            ),
          ),
        ],
      ),
    ];
    final hesapCipi = Container(
      key: const ValueKey('birlesik-hesap-cipi'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: renk.withValues(alpha: .13), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              h?.adres ?? o.hesap,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: renk, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
    Widget govde;
    if (_hata != null && d == null) {
      govde = Durum.hata(_hata!, tekrar: _yukle);
    } else if (d == null) {
      govde = const Durum.yukleniyor();
    } else {
      final v = d.gorunum;
      final kimden = v.kimden.isNotEmpty ? v.kimden.first : null;
      final ust = Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(alignment: Alignment.centerLeft, child: hesapCipi),
            const SizedBox(height: 10),
            SelectableText(v.konu.trim().isEmpty ? '(konu yok)' : v.konu, style: gosterim(20, agirlik: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: [
                Avatar(kimden?.gorunen ?? '?', boyut: 40, tohum: kimden?.eposta ?? ''),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kimden?.gorunen ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        [if (kimden != null) kimden.eposta, if (v.kime.isNotEmpty) 'Kime: ${v.kime.map((a) => a.gorunen).join(', ')}'].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: r.silik, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (v.tarih != null) Text(kisaZaman(v.tarih), style: TextStyle(color: r.silik, fontSize: 12)),
              ],
            ),
            if (v.dosyaEkleri.isNotEmpty) ...[
              const SizedBox(height: 12),
              EkListesi(
                iletiId: '${o.kutuId}_${o.ozet.id}',
                ekler: v.dosyaEkleri,
                indir: (s, {ilerleme}) => Birlesik.ekIndir(o.kutuId, o.ozet.id, s, ilerleme: ilerleme),
              ),
            ],
          ],
        ),
      );
      final yanit = SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('birlesik-yanitla'),
                onPressed: () => birlesikYaz(context, o, 'yanit'),
                icon: const Icon(Simge.yanitla),
                label: const Text('Yanıtla'),
              ),
              OutlinedButton.icon(onPressed: () => birlesikYaz(context, o, 'tumu'), icon: const Icon(Simge.tumuneYanitla), label: const Text('Tümünü yanıtla')),
              OutlinedButton.icon(
                key: const ValueKey('birlesik-ilet'),
                onPressed: () => birlesikYaz(context, o, 'ilet'),
                icon: const Icon(Simge.ilet),
                label: const Text('İlet'),
              ),
            ],
          ),
        ),
      );
      final rol = o.ozet.klasorRolu;
      if (v.html.trim().isNotEmpty) {
        govde = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: max(160, MediaQuery.sizeOf(context).height * .4)),
              child: SingleChildScrollView(child: ust),
            ),
            const Divider(height: 1),
            Expanded(
              child: HtmlGovde(
                key: const ValueKey('birlesik-html'),
                iletiId: '${o.kutuId}_${o.ozet.id}',
                html: v.html,
                ekler: v.ekler,
                baglantilar: d.baglantilar,
                otomatikGorsel: Tercihler.uzakGorseller.value && rol != 'junk' && d.tehditler.isEmpty,
                ekIndir: (s) => Birlesik.ekIndir(o.kutuId, o.ozet.id, s),
                epostaBaglantisi: (u) => yazmaAc(context, mailtoBaslangic(u)),
              ),
            ),
            yanit,
          ],
        );
      } else {
        govde = Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  ust,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: v.metin.trim().isEmpty
                        ? Text('(Bu iletinin gövdesi boş.)', style: TextStyle(color: r.silik))
                        : DuzMetin(metin: v.metin, baglantilar: d.baglantilar, eposta: (u) => yazmaAc(context, mailtoBaslangic(u))),
                  ),
                ],
              ),
            ),
            yanit,
          ],
        );
      }
    }
    if (widget.sayfa) {
      return Scaffold(
        appBar: AppBar(actions: eylemler),
        body: govde,
      );
    }
    return Material(
      color: r.kart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: eylemler),
          ),
          const Divider(height: 1),
          Expanded(child: govde),
        ],
      ),
    );
  }
}
