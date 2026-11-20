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
    });
    _yukle();
  }

  /// İşlem: iyimser (satır hemen güncellenir/çıkar), hata olursa geri alınır.
  Future<void> _eylem(BirlesikOge o, String eylem) async {
    final kaldir = const {'archive', 'trash', 'spam'}.contains(eylem);
    final onceki = List<BirlesikOge>.from(_ogeler);
    final eskiOkundu = o.ozet.okundu, eskiYildiz = o.ozet.yildizli;
    setState(() {
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
      if (kaldir) _ogeler.removeWhere((x) => x.anahtar == o.anahtar);
    });
    if (kaldir) widget.kaldirildi?.call({o.anahtar});
    try {
      await Birlesik.eylem([o], eylem);
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
        o.ozet.okundu = eskiOkundu;
        o.ozet.yildizli = eskiYildiz;
      });
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  void _ac(BirlesikOge o) {
    if (!o.ozet.okundu) unawaited(_eylem(o, 'seen'));
    widget.ac(o, hesap(o.kutuId));
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
                icon: Badge(
                  isLabelVisible: widget.klasorRozeti > 0,
                  label: Text(widget.klasorRozeti > 999 ? '999+' : '${widget.klasorRozeti}'),
                  child: const Icon(Icons.menu_rounded),
                ),
              ),
        titleSpacing: widget.klasorler != null ? 0 : 16,
        title: ListenableBuilder(
          listenable: b,
          builder: (_, _) => Row(
            children: [
              const Flexible(child: Text('Tüm hesaplar', maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (b.toplamOkunmamis > 0) ...[
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('birlesik-okunmamis'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: r.vurgu, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    b.toplamOkunmamis > 9999 ? '9999+' : '${b.toplamOkunmamis}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('bu-hesap'),
            onPressed: () {
              final g = PostaDurum.ben.rolu('inbox');
              if (g != null) PostaDurum.ben.git(Konum.klasor(g.id));
            },
            icon: const Icon(Icons.inbox_outlined, size: 19),
            label: const Text('Bu hesap'),
          ),
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _yukle(sessiz: _ogeler.isNotEmpty),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!context.genis) const EsitlemeDurumu(serit: true),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              children: [
                for (final (id, ad, ikon) in birlesikKlasorler)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: ValueKey('birlesik-klasor-$id'),
                      avatar: Icon(ikon, size: 16),
                      label: Text(ad),
                      selected: _klasor == id,
                      showCheckmark: false,
                      onSelected: (_) => _klasorSec(id),
                    ),
                  ),
              ],
            ),
          ),
          if (_hesaplar.length > 1)
            SizedBox(
              height: 44,
              child: ListenableBuilder(
                listenable: b,
                builder: (_, _) => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        key: const ValueKey('birlesik-hesap-hepsi'),
                        label: const Text('Hepsi'),
                        selected: _hesapSuzgeci == null,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _hesapSuzgeci = null),
                      ),
                    ),
                    for (final h in _hesaplar)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Tooltip(
                          message: h.adres,
                          child: FilterChip(
                            key: ValueKey('birlesik-hesap-${h.id}'),
                            avatar: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: h.renk, shape: BoxShape.circle),
                            ),
                            label: Text((b.hesapOkunmamis[h.id] ?? 0) > 0 ? '${h.kisa} · ${b.hesapOkunmamis[h.id]}' : h.kisa),
                            selected: _hesapSuzgeci == h.id,
                            showCheckmark: false,
                            selectedColor: h.renk.withValues(alpha: .16),
                            onSelected: (s) => setState(() => _hesapSuzgeci = s ? h.id : null),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _yukleniyor && _ogeler.isEmpty
                ? const Durum.yukleniyor()
                : _hata != null && _ogeler.isEmpty
                ? Durum.hata(_hata!, tekrar: _yukle)
                : l.isEmpty
                ? const Durum.bos('Burada ileti yok', ikon: Icons.layers_outlined)
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
                            secili: false,
                            acik: widget.seciliAnahtar == o.anahtar,
                            secimModu: false,
                            copte: false,
                            arsivde: false,
                            dokun: () => _ac(o),
                            sec: () {},
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
      if (_d == null) setState(() => _hata = e is ApiHata && e.durum == 404 ? 'İleti bulunamadı; silinmiş veya taşınmış olabilir.' : hataMetni(e));
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
        icon: Icon(o.ozet.yildizli ? Icons.star_rounded : Icons.star_border_rounded, color: o.ozet.yildizli ? const Color(0xFFEAB308) : null),
        onPressed: () => _eylem(o.ozet.yildizli ? 'unflag' : 'flag', o.ozet.yildizli ? 'Yıldız kaldırıldı' : 'Yıldızlandı'),
      ),
      IconButton(
        key: const ValueKey('birlesik-arsiv'),
        tooltip: 'Arşivle',
        icon: const Icon(Icons.archive_outlined),
        onPressed: () => _eylem('archive', 'Arşivlendi'),
      ),
      IconButton(
        key: const ValueKey('birlesik-cop'),
        tooltip: 'Çöp Kutusu\'na taşı',
        icon: const Icon(Icons.delete_outline_rounded),
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
            child: ListTile(leading: Icon(Icons.mark_email_unread_outlined), title: Text('Okunmadı yap')),
          ),
          PopupMenuItem(
            value: 'spam',
            child: ListTile(
              leading: Icon(Icons.gpp_maybe_outlined, color: Color(0xFFF97316)),
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
              style: TextStyle(color: renk, fontWeight: FontWeight.w700, fontSize: 12.5),
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
            SelectableText(v.konu.trim().isEmpty ? '(konu yok)' : v.konu, style: gosterim(20, agirlik: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                Avatar(kimden?.gorunen ?? '?', boyut: 40, tohum: kimden?.eposta ?? ''),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kimden?.gorunen ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
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
                icon: const Icon(Icons.reply_rounded),
                label: const Text('Yanıtla'),
              ),
              OutlinedButton.icon(
                onPressed: () => birlesikYaz(context, o, 'tumu'),
                icon: const Icon(Icons.reply_all_rounded),
                label: const Text('Tümünü yanıtla'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('birlesik-ilet'),
                onPressed: () => birlesikYaz(context, o, 'ilet'),
                icon: const Icon(Icons.forward_rounded),
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
