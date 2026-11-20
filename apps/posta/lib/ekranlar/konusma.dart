// Konuşma görünümü (Gmail benzeri yığın): konu bir kez üstte (kaydırınca küçülüp yapışır); iletiler eskiden yeniye.
// Kapalı iletiler tek sıkı satır (avatar 28, gönderen, tek satır özet, ek sayısı, tarih); yalnız son ileti ve
// okunmamışlar açık gelir. Ortada 4'ten çok kapalı ileti varsa "N ileti daha" ayırıcısının arkasına toplanır.
// Açık ileti: sıkı başlık (gönderen, tek satır alıcı özeti — dokununca ayrıntı, tarih, yanıtla + taşma menüsü),
// gövde içerik yüksekliğinde (iç içe kaydırma yok), alıntılanan geçmiş ve tekrarlanan imza "•••" arkasında,
// ekler gövdenin altında tek satırlık sıkı şerit. Açılışta ilk okunmamış (yoksa son) iletiye kaydırılır.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../oturum.dart';
import '../ortak/ek_listesi.dart';
import '../ortak/html_govde.dart';
import '../ortak/simgeler.dart';
import '../veri/durum.dart';
import '../veri/html_temizle.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/tercihler.dart';
import '../veri/yardimci.dart';
import '../veri/yazma_hazirla.dart';
import 'okuyucu.dart';
import 'okuyucu_parcalari.dart';
import 'takvim/davet_karti.dart';
import 'yazma.dart';

/// Ortada bundan çok kapalı ileti varsa "N ileti daha" ile toplanır.
const _toplamaEsigi = 4;

class KonusmaGorunumu extends StatefulWidget {
  const KonusmaGorunumu({super.key, required this.acilan, required this.ogeler, this.yenile});

  /// Okuyucuda açılan ileti (ayrıntısı hazır).
  final IletiDetay acilan;

  /// Konuşmadaki iletiler (eskiden yeniye; açılan da içinde).
  final List<IletiOzet> ogeler;

  final Future<void> Function()? yenile;

  @override
  State<KonusmaGorunumu> createState() => KonusmaGorunumuState();
}

class KonusmaGorunumuState extends State<KonusmaGorunumu> {
  final _kaydirma = ScrollController();
  final _anahtarlar = <String, GlobalKey>{};
  final _detaylar = <String, IletiDetay>{};
  late Set<String> _acik;
  bool _ortaAcik = false;
  bool _kullaniciEtkilesti = false;
  late String _hedef;

  List<IletiOzet> get _l => widget.ogeler;

  @override
  void initState() {
    super.initState();
    _detaylar[widget.acilan.ozet.id] = widget.acilan;
    _baslangic();
  }

  void _baslangic() {
    final l = _l;
    final okunmamis = l.where((m) => !m.okundu).map((m) => m.id);
    _acik = {if (l.isNotEmpty) l.last.id, ...okunmamis};
    // Açılan ileti son değilse (listeden eski bir yanıt seçildi) o da açık gelir.
    if (l.any((m) => m.id == widget.acilan.ozet.id) && l.isNotEmpty && l.last.id != widget.acilan.ozet.id && !l.last.okundu) {
      _acik.add(widget.acilan.ozet.id);
    }
    _hedef = l.where((m) => !m.okundu).firstOrNull?.id ?? (l.isEmpty ? widget.acilan.ozet.id : l.last.id);
    _ortaAcik = false;
    _kullaniciEtkilesti = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _hedefeKaydir());
  }

  @override
  void didUpdateWidget(KonusmaGorunumu oldWidget) {
    final eski = oldWidget;
    super.didUpdateWidget(eski);
    _detaylar[widget.acilan.ozet.id] = widget.acilan;
    if (eski.acilan.ozet.id != widget.acilan.ozet.id) {
      _baslangic();
    } else if (eski.ogeler.length != widget.ogeler.length) {
      // Yeni yanıt geldi: son ileti açılır.
      if (widget.ogeler.isNotEmpty) _acik.add(widget.ogeler.last.id);
    }
  }

  @override
  void dispose() {
    _kaydirma.dispose();
    super.dispose();
  }

  GlobalKey _anahtar(String id) => _anahtarlar.putIfAbsent(id, GlobalKey.new);

  /// Hedef iletiyi (ilk okunmamış ya da son) yapışkan başlığın hemen altına getirir (görünüm penceresi sabit
  /// başlığı hesaba katar).
  void _hedefeKaydir() {
    if (!mounted || _kullaniciEtkilesti || !_kaydirma.hasClients) return;
    final ro = _anahtarlar[_hedef]?.currentContext?.findRenderObject();
    if (ro == null) return;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return;
    final p = _kaydirma.position;
    final y = viewport.getOffsetToReveal(ro, 0).offset.clamp(p.minScrollExtent, p.maxScrollExtent);
    if ((p.pixels - y).abs() > 1) _kaydirma.jumpTo(y);
  }

  void _yuklendi(IletiDetay d) {
    final ilk = !_detaylar.containsKey(d.ozet.id);
    _detaylar[d.ozet.id] = d;
    if (ilk && mounted) {
      setState(() {});
      // Gövdeler yerleştikçe yükseklik değişir: kullanıcı kaydırmadıysa hedef yerinde tutulur.
      WidgetsBinding.instance.addPostFrameCallback((_) => _hedefeKaydir());
    }
  }

  void _degistir(String id) {
    _kullaniciEtkilesti = true;
    setState(() => _acik.contains(id) ? _acik.remove(id) : _acik.add(id));
  }

  /// Görünen sıra: ileti, ya da toplanmış ara ("N ileti daha").
  List<Object> _sira() {
    final l = _l;
    final out = <Object>[];
    var i = 0;
    while (i < l.length) {
      final m = l[i];
      // İlk ve son ileti hiç toplanmaz.
      if (!_ortaAcik && i > 0 && i < l.length - 1 && !_acik.contains(m.id)) {
        var j = i;
        while (j < l.length - 1 && !_acik.contains(l[j].id)) {
          j++;
        }
        final grup = l.sublist(i, j);
        if (grup.length > _toplamaEsigi) {
          out.add(grup.length);
          i = j;
          continue;
        }
      }
      out.add(m);
      i++;
    }
    return out;
  }

  IletiDetay? get _sonDetay => _l.isEmpty ? widget.acilan : (_detaylar[_l.last.id] ?? widget.acilan);

  void _yanitla(IletiDetay d, {bool tumu = false}) => yazmaAc(context, yanitHazirla(d, ben: Uyg.adres, tumu: tumu));

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = widget.acilan;
    final konu = KonusmaSeridi.yalinKonu(d.gorunum.konu).isEmpty ? '(konu yok)' : d.gorunum.konu;
    final etiketler = {for (final m in _l) ...m.etiketler, ...d.ozet.etiketler}.map(PostaDurum.ben.etiket).whereType<Etiket>().toList();
    final kisiler = {for (final m in _l) adresCoz(m.kimden).eposta.toLowerCase()};
    final onceGorulen = <String>{};
    final govde = NotificationListener<ScrollStartNotification>(
      onNotification: (n) {
        if (n.dragDetails != null) _kullaniciEtkilesti = true;
        return false;
      },
      child: CustomScrollView(
        key: const ValueKey('konusma'),
        controller: _kaydirma,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _KonuBasligi(konu: konu, sayi: _l.length, kisi: kisiler.length, etiketler: etiketler, onemli: d.ozet.onemli, renkler: r),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 16),
            sliver: SliverList.list(
              children: [
                for (final o in _sira())
                  if (o is int)
                    _DahaAyirici(
                      key: const ValueKey('konusma-daha'),
                      sayi: o,
                      ac: () => setState(() {
                        _ortaAcik = true;
                        _kullaniciEtkilesti = true;
                      }),
                    )
                  else if (o is IletiOzet)
                    Builder(
                      builder: (_) {
                        final gonderen = adresCoz(o.kimden).eposta.toLowerCase();
                        // Aynı gönderenin daha önce iletisi varsa imzası tekrardır: "•••" arkasına katlanır.
                        final imzaTekrar = !onceGorulen.add(gonderen);
                        return KeyedSubtree(
                          key: _anahtar(o.id),
                          child: _acik.contains(o.id)
                              ? KonusmaIletisi(
                                  key: ValueKey('konusma-ileti-${o.id}'),
                                  ozet: o,
                                  detay: _detaylar[o.id],
                                  imzayiKatla: imzaTekrar,
                                  yuklendi: _yuklendi,
                                  kapat: () => _degistir(o.id),
                                  yanitla: _yanitla,
                                )
                              : _KapaliIleti(key: ValueKey('konusma-kapali-${o.id}'), ozet: o, detay: _detaylar[o.id], ac: () => _degistir(o.id)),
                        );
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
    final son = _sonDetay;
    return Column(
      children: [
        Expanded(
          child: widget.yenile == null ? govde : RefreshIndicator(onRefresh: widget.yenile!, notificationPredicate: (n) => n.depth == 0, child: govde),
        ),
        if (son != null)
          _HizliYanit(d: son, yanitla: () => _yanitla(son), tumunu: () => _yanitla(son, tumu: true), ilet: () => yazmaAc(context, iletHazirla(son))),
      ],
    );
  }
}

/// Yapışkan konu başlığı: açıkken iki satır konu + etiketler; kaydırınca tek satıra küçülür.
class _KonuBasligi extends SliverPersistentHeaderDelegate {
  _KonuBasligi({required this.konu, required this.sayi, required this.kisi, required this.etiketler, required this.onemli, required this.renkler});
  final String konu;
  final int sayi;
  final int kisi;
  final List<Etiket> etiketler;
  final bool onemli;
  final Renkler renkler;

  static const kucuk = 46.0;
  static const buyuk = 84.0;

  @override
  double get minExtent => kucuk;
  @override
  double get maxExtent => buyuk;

  @override
  Widget build(BuildContext context, double kaydirma, bool ustuKapali) {
    final r = renkler;
    final t = (kaydirma / (buyuk - kucuk)).clamp(0.0, 1.0);
    final dar = t > .6;
    return Material(
      key: const ValueKey('konusma-baslik'),
      color: r.kart,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: r.kenar.withValues(alpha: t > 0 ? .8 : 0)),
          ),
        ),
        padding: EdgeInsets.fromLTRB(16, dar ? 0 : 10, 12, dar ? 0 : 6),
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              konu,
              maxLines: dar ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dar ? 15 : 17, fontWeight: FontWeight.w600, height: 1.25, color: r.metin),
            ),
            if (!dar)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Opacity(
                  opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                  child: SizedBox(
                    height: 20,
                    child: Row(
                      children: [
                        Text('$sayi ileti · $kisi kişi', style: TextStyle(fontSize: 12, color: r.soluk)),
                        if (onemli) ...[const SizedBox(width: 8), const Icon(Simge.onemliDolu, size: 14, color: Marka.kehribar)],
                        for (final e in etiketler.take(3)) ...[const SizedBox(width: 6), _EtiketHapi(e)],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_KonuBasligi eski) =>
      eski.konu != konu ||
      eski.sayi != sayi ||
      eski.kisi != kisi ||
      eski.etiketler.length != etiketler.length ||
      eski.renkler != renkler ||
      eski.onemli != onemli;
}

class _EtiketHapi extends StatelessWidget {
  const _EtiketHapi(this.e);
  final Etiket e;
  @override
  Widget build(BuildContext context) {
    final renk = etiketRengi(e.renk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
      child: Text(
        e.ad,
        style: TextStyle(fontSize: 11.5, color: renk, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// "N ileti daha": toplanmış ara iletileri açar.
class _DahaAyirici extends StatelessWidget {
  const _DahaAyirici({super.key, required this.sayi, required this.ac});
  final int sayi;
  final VoidCallback ac;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return InkWell(
      onTap: ac,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Expanded(child: Divider(color: r.kenar, height: 1)),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: r.kart,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: r.kenar),
              ),
              child: Text(
                '$sayi ileti daha',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: r.vurgu),
              ),
            ),
            Expanded(child: Divider(color: r.kenar, height: 1)),
          ],
        ),
      ),
    );
  }
}

String _ozetMetni(IletiOzet o, IletiDetay? d) {
  if (o.onizleme.trim().isNotEmpty) return o.onizleme.trim();
  final v = d?.gorunum;
  if (v == null) return '';
  final m = v.metin.trim().isNotEmpty ? v.metin : htmlMetne(v.html);
  return alintiAyir(m).ana.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Kapalı ileti: tek sıkı satır.
class _KapaliIleti extends StatelessWidget {
  const _KapaliIleti({super.key, required this.ozet, required this.detay, required this.ac});
  final IletiOzet ozet;
  final IletiDetay? detay;
  final VoidCallback ac;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final g = adresCoz(ozet.kimden);
    final ekSayisi = detay?.gorunum.dosyaEkleri.length ?? 0;
    return Material(
      color: r.kart,
      child: InkWell(
        onTap: ac,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: r.kenar.withValues(alpha: .6))),
          ),
          padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
          child: Row(
            children: [
              Avatar(g.gorunen, boyut: 28, tohum: g.eposta),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  g.gorunen,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: ozet.okundu ? FontWeight.w500 : FontWeight.w600, color: r.metin),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _ozetMetni(ozet, detay),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: r.soluk),
                ),
              ),
              if (ozet.ekVar || ekSayisi > 0) ...[
                const SizedBox(width: 6),
                Icon(Simge.ek, size: 15, color: r.silik, semanticLabel: 'Ekli'),
                if (ekSayisi > 1) Text('$ekSayisi', style: TextStyle(fontSize: 11.5, color: r.silik)),
              ],
              const SizedBox(width: 8),
              Text(kisaZaman(ozet.tarih), style: TextStyle(fontSize: 12, color: r.silik)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Açık ileti kartı.
class KonusmaIletisi extends StatefulWidget {
  const KonusmaIletisi({
    super.key,
    required this.ozet,
    required this.detay,
    required this.yuklendi,
    required this.kapat,
    required this.yanitla,
    this.imzayiKatla = false,
  });
  final IletiOzet ozet;
  final IletiDetay? detay;
  final ValueChanged<IletiDetay> yuklendi;
  final VoidCallback kapat;
  final void Function(IletiDetay d, {bool tumu}) yanitla;
  final bool imzayiKatla;

  @override
  State<KonusmaIletisi> createState() => _KonusmaIletisiState();
}

class _KonusmaIletisiState extends State<KonusmaIletisi> {
  IletiDetay? _d;
  String? _hata;
  bool _ayrinti = false;
  bool _alinti = false;
  bool _duzMetin = false;

  @override
  void initState() {
    super.initState();
    _d = widget.detay ?? Posta.iletiHemen(widget.ozet.id);
    if (_d != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hazir(_d!));
    } else {
      unawaited(_yukle());
    }
  }

  Future<void> _yukle() async {
    final id = widget.ozet.id;
    // Önbellek ve ağ birlikte: önbellek hızlı gelirse hemen gösterilir, ağ yanıtı gelince yenilenir.
    final ag = Posta.iletiHam(id);
    unawaited(
      Posta.iletiOnbellek(id).then((o) {
        if (o != null && mounted && _d == null) {
          setState(() => _d = o);
          _hazir(o);
        }
      }, onError: (_) {}),
    );
    try {
      final v = IletiDetay.json(await ag);
      if (!mounted) return;
      setState(() => _d = v);
      _hazir(v);
    } catch (e) {
      if (mounted && _d == null) setState(() => _hata = hataMetni(e));
    }
  }

  void _hazir(IletiDetay d) {
    if (!mounted) return;
    widget.yuklendi(d);
    // Açılan okunmamış ileti okundu sayılır (iyimser; listeler yerinde güncellenir).
    if (!widget.ozet.okundu) {
      widget.ozet.okundu = true;
      d.ozet.okundu = true;
      PostaDurum.ben.okunduIsaretle(d.ozet.id);
      unawaited(Posta.guncelle(d.ozet.id, {'seen': true}).catchError((_) {}));
    }
  }

  void _menu(String v) {
    final d = _d;
    if (d == null) return;
    switch (v) {
      case 'yanitla':
        widget.yanitla(d);
      case 'tumu':
        widget.yanitla(d, tumu: true);
      case 'ilet':
        yazmaAc(context, iletHazirla(d));
      case 'ekler':
        unawaited(tumEkleriIndir(d.ozet.id, d.gorunum.dosyaEkleri));
      case 'bicim':
        setState(() => _duzMetin = !_duzMetin);
      case 'okunmadi':
        PostaDurum.ben.okunduIsaretle(d.ozet.id, okundu: false);
        unawaited(Posta.guncelle(d.ozet.id, {'seen': false}).catchError((_) {}));
        widget.kapat();
      case 'ayrinti':
        setState(() => _ayrinti = !_ayrinti);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final o = widget.ozet;
    final d = _d;
    final v = d?.gorunum;
    final g = v != null && v.kimden.isNotEmpty ? v.kimden.first : adresCoz(o.kimden);
    final tarih = v?.tarih ?? o.tarih;
    final rol = PostaDurum.ben.klasor(d?.ozet.klasorId)?.rol ?? d?.ozet.klasorRolu;
    final tehlikeli = rol == 'junk' || (d?.tehditler.isNotEmpty ?? false);
    final ekler = v?.dosyaEkleri ?? const <Ek>[];
    final cokAlici = v != null && v.kime.length + v.bilgi.length > 1;
    return Container(
      decoration: BoxDecoration(
        color: r.kart,
        border: Border(top: BorderSide(color: r.kenar.withValues(alpha: .6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sıkı başlık: dokununca ileti kapanır.
          InkWell(
            key: const ValueKey('ileti-basligi'),
            onTap: widget.kapat,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Avatar(g.gorunen, boyut: 32, tohum: g.eposta),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                g.gorunen,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: r.metin),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: tamZaman(tarih),
                              child: Text(kisaZaman(tarih), style: TextStyle(fontSize: 12, color: r.silik)),
                            ),
                          ],
                        ),
                        if (v != null)
                          GestureDetector(
                            key: const ValueKey('alici-ozeti'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _ayrinti = !_ayrinti),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 1, bottom: 2),
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _aliciOzeti(v),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: r.soluk),
                                    ),
                                  ),
                                  Icon(_ayrinti ? Simge.yukari : Simge.asagi, size: 14, color: r.silik),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Yanıtla',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Simge.yanitla, size: 20, color: r.soluk),
                    onPressed: d == null ? null : () => widget.yanitla(d),
                  ),
                  PopupMenuButton<String>(
                    key: const ValueKey('ileti-menu'),
                    tooltip: 'Diğer işlemler',
                    icon: Icon(Simge.dahaFazlaDikey, size: 20, color: r.soluk),
                    enabled: d != null,
                    onSelected: _menu,
                    itemBuilder: (_) => [
                      _oge('yanitla', Simge.yanitla, 'Yanıtla'),
                      if (cokAlici) _oge('tumu', Simge.tumuneYanitla, 'Tümünü yanıtla'),
                      _oge('ilet', Simge.ilet, 'İlet'),
                      if (ekler.isNotEmpty) _oge('ekler', Simge.indir, ekler.length > 1 ? 'Tümünü indir (${ekler.length} ek)' : 'Eki indir'),
                      if (v != null && v.html.trim().isNotEmpty && v.metin.trim().isNotEmpty)
                        _oge('bicim', Simge.duzMetin, _duzMetin ? 'Biçimli göster' : 'Düz metin göster'),
                      _oge('ayrinti', Simge.bilgi, 'Ayrıntılar'),
                      _oge('okunmadi', Simge.okunmadiYap, 'Okunmadı yap'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_ayrinti && v != null) _ayrintiKutusu(v, tarih),
          if (d != null) ...[
            for (final t in d.tehditler) GuvenlikBandi(tur: BantTuru.tehlike, baslik: 'Güvenlik uyarısı', metin: t, ikon: Simge.gereksiz),
            ...sezgiselUyarilar(d),
            if (v!.ekler.any((e) => e.davetiye)) DavetKarti(key: ValueKey('davet-${d.ozet.id}'), iletiId: d.ozet.id),
            _govde(d, tehlikeli),
            if (ekler.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: EkSeridi(iletiId: d.ozet.id, ekler: ekler),
              ),
          ] else if (_hata != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(58, 4, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text('İleti yüklenemedi', style: TextStyle(color: r.soluk, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _hata = null);
                      unawaited(_yukle());
                    },
                    child: const Text('Tekrar dene'),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(58, 4, 16, 14),
              child: Text(
                o.onizleme,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: r.soluk, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _oge(String v, IconData i, String t) => PopupMenuItem(
    value: v,
    height: 40,
    child: Row(
      children: [
        Icon(i, size: 18),
        const SizedBox(width: 12),
        Text(t, style: const TextStyle(fontSize: 13.5)),
      ],
    ),
  );

  String _aliciOzeti(IletiGorunum v) {
    final ben = Uyg.adres.toLowerCase();
    String ad(Adres a) => a.eposta.toLowerCase() == ben ? 'bana' : (a.ad.isNotEmpty ? a.ad.split(' ').first : a.eposta);
    final kime = v.kime.map(ad).toList();
    final bilgi = v.bilgi.map(ad).toList();
    final parca = [...kime, ...bilgi];
    if (parca.isEmpty) return 'alıcı yok';
    final ilk = parca.take(3).join(', ');
    return 'kime: $ilk${parca.length > 3 ? ' +${parca.length - 3}' : ''}';
  }

  Widget _ayrintiKutusu(IletiGorunum v, DateTime? tarih) {
    final r = context.r;
    Widget satir(String e, String d) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(e, style: TextStyle(color: r.silik, fontSize: 12)),
          ),
          Expanded(child: SelectableText(d.isEmpty ? '—' : d, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
    return Container(
      key: const ValueKey('alici-ayrinti'),
      margin: const EdgeInsets.fromLTRB(58, 2, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          satir('Kimden', v.kimden.map(adresYaz).join(', ')),
          satir('Kime', v.kime.map(adresYaz).join(', ')),
          if (v.bilgi.isNotEmpty) satir('Bilgi', v.bilgi.map(adresYaz).join(', ')),
          if (v.yanitAdresi.isNotEmpty) satir('Yanıt', v.yanitAdresi.map(adresYaz).join(', ')),
          satir('Tarih', tamZaman(tarih)),
        ],
      ),
    );
  }

  Widget _govde(IletiDetay d, bool tehlikeli) {
    final r = context.r;
    final v = d.gorunum;
    final html = v.html.trim().isNotEmpty && (!_duzMetin || v.metin.trim().isEmpty);
    if (!html) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
        child: v.metin.trim().isEmpty
            ? Text('(Bu iletinin gövdesi boş.)', style: TextStyle(color: r.silik, fontSize: 13))
            : DuzMetin(
                metin: v.metin,
                baglantilar: d.baglantilar,
                imzayiKatla: widget.imzayiKatla,
                boyut: 14.5,
                eposta: (u) => yazmaAc(context, mailtoBaslangic(u)),
              ),
      );
    }
    final bol = htmlAlintiAyir(v.html, imza: widget.imzayiKatla);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HtmlGovde(
          key: ValueKey('html-${d.ozet.id}-$_alinti'),
          iletiId: d.ozet.id,
          html: _alinti || !bol.katlandi ? v.html : bol.ana,
          ekler: v.ekler,
          baglantilar: d.baglantilar,
          otomatikGorsel: Tercihler.uzakGorseller.value && !tehlikeli,
          otomatikYukseklik: true,
          alintiyiKatla: false,
          epostaBaglantisi: (u) => yazmaAc(context, mailtoBaslangic(u)),
        ),
        if (bol.katlandi)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _UcNokta(acik: _alinti, degistir: () => setState(() => _alinti = !_alinti)),
            ),
          ),
      ],
    );
  }
}

/// "•••" düğmesi: alıntılanan geçmişi / imzayı gösterir-gizler.
class _UcNokta extends StatelessWidget {
  const _UcNokta({required this.acik, required this.degistir});
  final bool acik;
  final VoidCallback degistir;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Tooltip(
      message: acik ? 'Önceki iletileri gizle' : 'Önceki iletileri göster',
      child: Material(
        color: r.ic,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: const ValueKey('alinti-ac'),
          borderRadius: BorderRadius.circular(6),
          onTap: degistir,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            child: Text(
              '•••',
              style: TextStyle(color: r.silik, fontWeight: FontWeight.w600, letterSpacing: 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alttaki hızlı yanıt: "X'e yanıt yaz…" kutusu (dokununca yanıt penceresi), Tümünü yanıtla ve İlet simgeleri.
class _HizliYanit extends StatelessWidget {
  const _HizliYanit({required this.d, required this.yanitla, required this.tumunu, required this.ilet});
  final IletiDetay d;
  final VoidCallback yanitla;
  final VoidCallback tumunu;
  final VoidCallback ilet;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final v = d.gorunum;
    final g = v.kimden.isNotEmpty ? v.kimden.first : adresCoz(d.ozet.kimden);
    final cok = v.kime.length + v.bilgi.length > 1;
    return Container(
      decoration: BoxDecoration(
        color: r.kart,
        border: Border(top: BorderSide(color: r.kenar.withValues(alpha: .8))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: r.ic,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  key: const ValueKey('hizli-yanit'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: yanitla,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Icon(Simge.yanitla, size: 18, color: r.soluk),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${g.gorunen.split(' ').first} adlı kişiye yanıt yaz…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, color: r.soluk),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (cok)
              IconButton(key: const ValueKey('yanitla-tumu'), tooltip: 'Tümünü yanıtla', icon: const Icon(Simge.tumuneYanitla, size: 20), onPressed: tumunu),
            IconButton(key: const ValueKey('ilet'), tooltip: 'İlet', icon: const Icon(Simge.ilet, size: 20), onPressed: ilet),
          ],
        ),
      ),
    );
  }
}
