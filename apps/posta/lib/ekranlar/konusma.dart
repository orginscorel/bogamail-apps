// Konuşma görünümü (web thread-view.tsx): konu bir kez üstte; iletiler eskiden yeniye. Açılan iletiden önceki
// iletiler tek "▸ N önceki ileti" denetiminin arkasındadır (açılınca tek satırlık sıkı satırlar); varsayılan olarak
// yalnız açılandan hemen önceki ileti ve okunmamışlar görünür. Açılan ileti hafif birincil zeminle, sonrakiler
// (en yeni ve okunmamışlar açık) altında. Kaydırınca konu başlığı 32 px'lik şeride iner: "Ad · bugün 09:12" (o an
// okunan ileti). Açık ileti başlığı: okunmadı noktası / ✓✓ Okundu, zaman, "Bu iletiyi aç". Açılışta ilk okunmamış
// (yoksa açılan) iletiye kaydırılır. Konuşmayı sunucu kurar (thread); istemci konu araması yapmaz.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/ek_listesi.dart';
import '../ortak/html_govde.dart';
import '../ortak/simgeler.dart';
import '../ortak/uyarlanir.dart';
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

/// "bugün 09:12", "dün 14:05", "13 Kas 09:12", "13.11.2025 09:12" (web stripTime).
String seritZamani(DateTime? t) {
  if (t == null) return '';
  final d = t.toLocal();
  final n = DateTime.now();
  final sa = DateFormat('HH:mm', 'tr_TR').format(d);
  bool ayni(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (ayni(d, n)) return 'bugün $sa';
  if (ayni(d, n.subtract(const Duration(days: 1)))) return 'dün $sa';
  if (d.year == n.year) return '${DateFormat('d MMM', 'tr_TR').format(d)} $sa';
  return '${DateFormat('dd.MM.yyyy', 'tr_TR').format(d)} $sa';
}

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

  /// "▸ N önceki ileti" açıldı mı.
  bool _oncekilerAcik = false;

  /// Bir kez görünen önceki ileti görünür kalır (kapatılınca gizli gruba geri kaçmaz; liste zıplamaz).
  final _gorunenler = <String>{};

  /// Yapışkan şerit: o an okunan ileti ("Ad · bugün 09:12").
  final _serit = ValueNotifier<String?>(null);
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
    // Web planThread: açılan, en yeni ve okunmamışlar açık; hedef ilk okunmamış, yoksa açılan.
    _acik = {widget.acilan.ozet.id, if (l.isNotEmpty) l.last.id, ...l.where((m) => !m.okundu).map((m) => m.id)};
    _hedef = l.where((m) => !m.okundu).firstOrNull?.id ?? widget.acilan.ozet.id;
    _oncekilerAcik = false;
    _gorunenler.clear();
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
    _serit.dispose();
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

  /// Şerit: üst %20'lik banttaki (ya da üstündeki) en alttaki ileti; konu başlığı kaymadıysa gizli.
  void _seritiGuncelle() {
    if (!_kaydirma.hasClients) return;
    final kutu = context.findRenderObject() as RenderBox?;
    if (kutu == null || !kutu.hasSize) return;
    if (_kaydirma.offset < _KonuBasligi.buyuk - _KonuBasligi.kucuk - 1) {
      _serit.value = null;
      return;
    }
    final ust = kutu.localToGlobal(Offset.zero).dy;
    final bant = ust + _KonuBasligi.kucuk + kutu.size.height * .2;
    IletiOzet? en;
    for (final m in _l) {
      final ro = _anahtarlar[m.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (ro == null || !ro.attached || !ro.hasSize) continue;
      if (ro.localToGlobal(Offset.zero).dy <= bant) en = m;
    }
    if (en == null) {
      _serit.value = null;
      return;
    }
    final g = adresCoz(en.kimden);
    _serit.value = '${g.gorunen} · ${seritZamani(en.tarih)}';
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

  /// Görünen sıra (web ThreadPart): önceki iletilerden açılandan hemen önceki ve açık olanlar; geri kalanı tek
  /// "▸ N önceki ileti" denetiminin arkasında (int = gizli sayısı, denetimin yeri). Sonrakiler hep görünür.
  List<Object> _sira() {
    final l = _l;
    final c = l.indexWhere((m) => m.id == widget.acilan.ozet.id);
    if (c < 0) return [...l];
    final once = l.sublist(0, c);
    bool gorunur(int i) => i == once.length - 1 || _acik.contains(once[i].id) || _gorunenler.contains(once[i].id);
    for (var i = 0; i < once.length; i++) {
      if (gorunur(i)) _gorunenler.add(once[i].id);
    }
    final gizli = [
      for (var i = 0; i < once.length; i++)
        if (!gorunur(i)) i,
    ].length;
    return [
      if (gizli > 0) gizli,
      for (var i = 0; i < once.length; i++)
        if (_oncekilerAcik || gorunur(i)) once[i],
      ...l.sublist(c),
    ];
  }

  void _baskaAc(String id) => uyarlanirAc<void>(context, (_) => Okuyucu(id: id, sayfa: true));

  IletiDetay? get _sonDetay => _l.isEmpty ? widget.acilan : (_detaylar[_l.last.id] ?? widget.acilan);

  void _yanitla(IletiDetay d, {bool tumu = false}) => yazmaAc(context, yanitHazirla(d, ben: Uyg.adres, tumu: tumu));

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = widget.acilan;
    final konu = KonusmaSeridi.yalinKonu(d.gorunum.konu).isEmpty ? '(konu yok)' : d.gorunum.konu;
    final etiketler = {for (final m in _l) ...m.etiketler, ...d.ozet.etiketler}.map(PostaDurum.ben.etiket).whereType<Etiket>().toList();
    final kisiler = {for (final m in _l) adresCoz(m.kimden).eposta.toLowerCase()};
    // Web planThread.repeatSig: gönderen konuşmada daha önce (gizli olsa da) yazdıysa imzası tekrardır.
    final onceGorulen = <String>{};
    final imzaTekrarlar = {
      for (final m in _l)
        if (!onceGorulen.add(adresCoz(m.kimden).eposta.toLowerCase())) m.id,
    };
    final govde = Listener(
      // Fare tekerleği (masaüstü) de kullanıcı kaydırmasıdır.
      onPointerSignal: (_) => _kullaniciEtkilesti = true,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          // Sürükleme, tekerlek, klavye: kullanıcı kaydırdıysa içerik yüklendikçe hedefe geri atlanmaz.
          if (n is ScrollStartNotification && n.dragDetails != null) _kullaniciEtkilesti = true;
          if (n is UserScrollNotification && n.direction != ScrollDirection.idle) _kullaniciEtkilesti = true;
          if (n.depth == 0) _seritiGuncelle();
          return false;
        },
        child: CustomScrollView(
          key: const ValueKey('konusma'),
          controller: _kaydirma,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _KonuBasligi(konu: konu, sayi: _l.length, kisi: kisiler.length, etiketler: etiketler, onemli: d.ozet.onemli, renkler: r, serit: _serit),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 16),
              sliver: SliverList.list(
                children: [
                  for (final o in _sira())
                    if (o is int)
                      OncekiDenetimi(
                        key: const ValueKey('konusma-daha'),
                        sayi: o,
                        acik: _oncekilerAcik,
                        degistir: () => setState(() {
                          _oncekilerAcik = !_oncekilerAcik;
                          _kullaniciEtkilesti = true;
                        }),
                      )
                    else if (o is IletiOzet)
                      Builder(
                        builder: (_) {
                          // Aynı gönderenin daha önce iletisi varsa imzası tekrardır: "•••" arkasına katlanır.
                          final imzaTekrar = imzaTekrarlar.contains(o.id);
                          final acilan = o.id == d.ozet.id;
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
                                    acilan: acilan,
                                    ayriAc: acilan ? null : () => _baskaAc(o.id),
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
  _KonuBasligi({
    required this.konu,
    required this.sayi,
    required this.kisi,
    required this.etiketler,
    required this.onemli,
    required this.renkler,
    required this.serit,
  });
  final ValueNotifier<String?> serit;
  final String konu;
  final int sayi;
  final int kisi;
  final List<Etiket> etiketler;
  final bool onemli;
  final Renkler renkler;

  static const kucuk = 32.0;
  static const buyuk = 94.0;

  @override
  double get minExtent => kucuk;
  @override
  double get maxExtent => buyuk;

  @override
  Widget build(BuildContext context, double kaydirma, bool ustuKapali) {
    final r = renkler;
    final t = (kaydirma / (buyuk - kucuk)).clamp(0.0, 1.0);
    final dar = t > .6;
    if (t >= 1) {
      // Web ThreadStrip: 32 px şerit, o an okunan ileti.
      return ValueListenableBuilder<String?>(
        valueListenable: serit,
        builder: (context, s, _) => Container(
          key: const ValueKey('konusma-baslik'),
          decoration: BoxDecoration(
            color: r.kart.withValues(alpha: .97),
            border: Border(bottom: BorderSide(color: r.kenar)),
          ),
          padding: EdgeInsets.symmetric(horizontal: context.genis ? 24 : 16),
          alignment: Alignment.centerLeft,
          child: s == null
              ? Text(
                  konu,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: r.metin),
                )
              : Row(
                  key: const ValueKey('konusma-serit'),
                  children: [
                    Flexible(
                      child: Text(
                        s.split(' · ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: r.metin),
                      ),
                    ),
                    Text('  ·  ', style: TextStyle(fontSize: 12, color: r.silik)),
                    Text(s.split(' · ').skip(1).join(' · '), style: TextStyle(fontSize: 12, color: r.silik)),
                  ],
                ),
        ),
      );
    }
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
        padding: EdgeInsets.fromLTRB(context.genis ? 24 : 16, dar ? 0 : 12, 12, dar ? 0 : 6),
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              konu,
              maxLines: dar ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dar ? 14 : 18, fontWeight: FontWeight.w600, height: 1.375, color: r.metin),
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
                        Text('$sayi ileti · $kisi kişi', style: TextStyle(fontSize: 12, color: r.silik)),
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
      eski.onemli != onemli ||
      eski.serit != serit;
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

/// Web: tek "▸ N önceki ileti" denetimi (12 px w500 soluk; açılınca ok 90° döner, "N önceki iletiyi gizle").
class OncekiDenetimi extends StatelessWidget {
  const OncekiDenetimi({super.key, required this.sayi, required this.acik, required this.degistir});
  final int sayi;
  final bool acik;
  final VoidCallback degistir;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Semantics(
      button: true,
      expanded: acik,
      child: Material(
        color: r.kart,
        child: InkWell(
          onTap: degistir,
          hoverColor: r.ic.withValues(alpha: .4),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: r.kenar),
                bottom: BorderSide(color: r.kenar),
              ),
            ),
            padding: EdgeInsets.symmetric(horizontal: context.genis ? 24 : 16, vertical: 8),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: acik ? .25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Simge.ileri, size: 14, color: r.silik),
                ),
                const SizedBox(width: 8),
                Text(
                  acik ? '$sayi önceki iletiyi gizle' : '$sayi önceki ileti',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: r.silik),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Web SeenMark: okunmamışsa "● okunmadı" (11 px birincil), okunduysa ✓✓ (soluk %70).
class OkunduIsareti extends StatelessWidget {
  const OkunduIsareti({super.key, required this.okundu, this.kisa = false});
  final bool okundu;

  /// Dar ekranda yalnız nokta.
  final bool kisa;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (okundu) return Icon(Simge.okunduCift, size: 14, color: r.silik.withValues(alpha: .7), semanticLabel: 'Okundu');
    final nokta = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: r.birincil, shape: BoxShape.circle),
    );
    if (kisa) return Semantics(label: 'okunmadı', child: nokta);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        nokta,
        const SizedBox(width: 4),
        Text(
          'okunmadı',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: r.birincil),
        ),
      ],
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
            border: Border(top: BorderSide(color: r.kenar)),
          ),
          padding: EdgeInsets.symmetric(horizontal: context.genis ? 24 : 16, vertical: 8),
          child: Row(
            children: [
              Avatar(g.gorunen, boyut: 24, tohum: g.eposta),
              const SizedBox(width: 10),
              if (!ozet.okundu) ...[
                Container(
                  key: const ValueKey('konusma-okunmamis'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: r.birincil, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
              ],
              SizedBox(
                width: context.genis ? 160 : 128,
                child: Text(
                  g.gorunen,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: ozet.okundu ? FontWeight.w400 : FontWeight.w600,
                    color: ozet.okundu ? r.metin.withValues(alpha: .8) : r.metin,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _ozetMetni(ozet, detay),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: r.silik),
                ),
              ),
              if (ozet.ekVar || ekSayisi > 0) ...[const SizedBox(width: 8), Icon(Simge.ek, size: 14, color: r.silik, semanticLabel: 'Ekli')],
              const SizedBox(width: 10),
              Text(kisaZaman(ozet.tarih), style: TextStyle(fontSize: 12, color: r.silik)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Masaüstü konuşma satırı (Outlook gibi): avatar, okunmadı noktası, gönderen, tek satır önizleme, ek, zaman;
/// etkin ileti vurgulu (birincil zemin + sol çizgi). Satır yüksekliği sabit (seçim / okundu değişince kaymaz).
class KonusmaSatiri extends StatelessWidget {
  const KonusmaSatiri({super.key, required this.ozet, required this.detay, required this.secili, required this.ac});
  final IletiOzet ozet;
  final IletiDetay? detay;
  final bool secili;
  final VoidCallback ac;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final g = adresCoz(ozet.kimden);
    final ekSayisi = detay?.gorunum.dosyaEkleri.length ?? 0;
    return Semantics(
      selected: secili,
      button: true,
      child: Material(
        color: secili ? r.birincil.withValues(alpha: .08) : r.kart,
        child: InkWell(
          onTap: ac,
          hoverColor: r.ic.withValues(alpha: .5),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: r.kenar),
                left: BorderSide(color: secili ? r.birincil : Colors.transparent, width: 3),
              ),
            ),
            padding: const EdgeInsets.only(left: 21, right: 24),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  child: ozet.okundu
                      ? null
                      : Container(
                          key: const ValueKey('konusma-okunmamis'),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: r.birincil, shape: BoxShape.circle),
                        ),
                ),
                Avatar(g.gorunen, boyut: 22, tohum: g.eposta),
                const SizedBox(width: 10),
                SizedBox(
                  width: 160,
                  child: Text(
                    g.gorunen,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Kalınlık sabit (genişlik değişmesin); okunmamış renkle ayrılır.
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ozet.okundu ? r.metin.withValues(alpha: .75) : r.metin),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _ozetMetni(ozet, detay),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: r.silik),
                  ),
                ),
                if (ozet.ekVar || ekSayisi > 0) ...[const SizedBox(width: 8), Icon(Simge.ek, size: 14, color: r.silik, semanticLabel: 'Ekli')],
                const SizedBox(width: 10),
                Text(
                  seritZamani(ozet.tarih),
                  style: TextStyle(fontSize: 12, color: r.silik, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
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
    this.acilan = false,
    this.ayriAc,
  });

  /// Okuyucuda açılan ileti (web: bg-primary/[0.03]).
  final bool acilan;

  /// "Bu iletiyi aç" (yanıtla, taşı… için tek başına açar); açılan iletide yok.
  final VoidCallback? ayriAc;
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

  /// Açılıştaki okundu durumu (web SeenMark özetten okunur; okuyunca hemen "Okundu"ya dönmez).
  late final bool _ilkOkundu;

  @override
  void initState() {
    super.initState();
    _ilkOkundu = widget.ozet.okundu;
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
    final genis = context.genis;
    return Container(
      decoration: BoxDecoration(
        color: widget.acilan ? Color.alphaBlend(r.birincil.withValues(alpha: .03), r.kart) : r.kart,
        border: Border(top: BorderSide(color: r.kenar)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sıkı başlık: dokununca ileti kapanır.
          InkWell(
            key: const ValueKey('ileti-basligi'),
            onTap: widget.kapat,
            child: Padding(
              padding: EdgeInsets.fromLTRB(genis ? 24 : 16, 12, 4, 4),
              child: Row(
                children: [
                  Avatar(g.gorunen, boyut: 32, tohum: g.eposta),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                g.gorunen,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: r.metin),
                              ),
                            ),
                            if (genis && g.ad.isNotEmpty && g.eposta.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '<${g.eposta}>',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: r.silik),
                                ),
                              ),
                            ],
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
                                      style: TextStyle(fontSize: 12, color: r.silik),
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
                  const SizedBox(width: 8),
                  OkunduIsareti(key: const ValueKey('okundu-isareti'), okundu: _ilkOkundu, kisa: !genis),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: tamZaman(tarih),
                    child: Text(genis ? seritZamani(tarih) : kisaZaman(tarih), style: TextStyle(fontSize: 12, color: r.silik)),
                  ),
                  if (widget.ayriAc != null)
                    IconButton(
                      key: const ValueKey('ileti-ayri-ac'),
                      tooltip: 'Bu iletiyi aç',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Simge.disaAc, size: 16, color: r.soluk),
                      onPressed: widget.ayriAc,
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
            // Ekler gövdeden önce, okuyucudaki gibi kartlar (dokununca açılır / PDF önizlenir; menüden paylaş, kaydet).
            if (ekler.isNotEmpty)
              Padding(
                key: const ValueKey('konusma-ekler'),
                padding: EdgeInsets.fromLTRB(genis ? 24 : 16, 4, 16, 8),
                child: EkListesi(iletiId: d.ozet.id, ekler: ekler),
              ),
            _govde(d, tehlikeli),
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
    if (parca.isEmpty) return 'Kime: —';
    final ilk = parca.take(3).join(', ');
    return 'Kime: $ilk${parca.length > 3 ? ' +${parca.length - 3}' : ''}';
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
        padding: EdgeInsets.fromLTRB(context.genis ? 24 : 16, 2, 16, 12),
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
        // HTML gövde tam genişlik kullanır (çoğu posta kendi ortalanmış tablosunu taşır; girinti sağa kaydırıyordu).
        Padding(
          // Başlık satırıyla aynı hiza (geniş: 24, dar: 16; gövdenin kendi 16 px dolgusu düşülür).
          padding: EdgeInsets.symmetric(horizontal: context.genis ? 8 : 0),
          child: HtmlGovde(
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
        ),
        if (bol.katlandi)
          Padding(
            padding: EdgeInsets.fromLTRB(context.genis ? 24 : 16, 0, 16, 10),
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
