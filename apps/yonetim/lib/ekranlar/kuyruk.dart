import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/sayfali.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/operasyon.dart';
import 'bekletilenler.dart';
import 'kuyruk_detay.dart';

/// Kuyruk yönetimi (GET /queue/manager): kabul edilmiş ama henüz teslim edilmemiş iletiler; bekletilen giden iletiler
/// ayrı sekmede (GET /outbound-holds).
class KuyrukEkrani extends StatelessWidget {
  const KuyrukEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    final bekletme = Uyg.yetki('quarantine.view');
    if (!bekletme) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kuyruk')),
        body: const KuyrukListesi(),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kuyruk'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Teslim kuyruğu'),
              Tab(text: 'Bekletilenler'),
            ],
          ),
        ),
        body: const TabBarView(children: [KuyrukListesi(), BekletilenlerListesi()]),
      ),
    );
  }
}

class KuyrukListesi extends StatefulWidget {
  const KuyrukListesi({super.key});
  @override
  State<KuyrukListesi> createState() => _KuyrukListesiState();
}

class _KuyrukListesiState extends State<KuyrukListesi> with AutomaticKeepAliveClientMixin {
  String _q = '', _yon = '', _durum = '', _hataSinifi = '';
  KuyrukYaniti? _son;
  KuyrukOgesi? _secili;

  late final _y = SayfaYukleyici<KuyrukOgesi>((s, b) async {
    final v = await Uyg.api.get(
      '/api/v1/queue/manager',
      q: {
        'page': '$s',
        'page_size': '$b',
        if (_q.isNotEmpty) 'q': _q,
        if (_yon.isNotEmpty) 'direction': _yon,
        if (_durum.isNotEmpty) 'status': _durum,
        if (_hataSinifi.isNotEmpty) 'error_class': _hataSinifi,
      },
    );
    final y = KuyrukYaniti(harita(v));
    if (mounted) setState(() => _son = y);
    return Sayfa(y.ogeler, y.eslesen);
  })..yenile();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _filtre(void Function() f) {
    setState(f);
    _y.yenile();
  }

  void _ac(KuyrukOgesi o) {
    final etiketler = _son?.hataSiniflari ?? const {};
    final yonetir = _son?.yonetebilir ?? false;
    if (bolunmus(context)) {
      setState(() => _secili = o);
    } else {
      sayfaAc(context, 'Kuyruk kaydı', KuyrukDetay(oge: o, hataEtiketleri: etiketler, yonetebilir: yonetir, degisti: _y.yenile, tamSayfa: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = context.r;
    final y = _son;
    final st = y?.istatistik ?? const <String, dynamic>{};
    final ust = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (y != null && !y.etkin)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Bant('Kuyruk devre dışı: SMTP dinleyicisi yapılandırılmamış.', renk: Marka.kehribar),
          ),
        if (y != null && y.kapsamli)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Bant(
              'Yalnızca alan adlarınıza ait kuyruk kayıtları gösterilir.${Uyg.musteri ? ' İletilerinizi yeniden deneyebilirsiniz; bekletme ve silme platform yöneticisindedir.' : ''}',
            ),
          ),
        if (y != null && y.istatistikVar)
          SizedBox(
            height: 78,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              children: [
                _Kucuk('Kuyrukta', sayiYaz(tamsayi(st['total'])), alt: boyutYaz(tamsayi(st['bytes']))),
                _Kucuk('Bekliyor', sayiYaz(tamsayi(st['pending']))),
                _Kucuk('Ertelendi', sayiYaz(tamsayi(st['deferred'])), renk: tamsayi(st['deferred']) > 0 ? Marka.kehribar : null),
                _Kucuk('Bekletiliyor', sayiYaz(tamsayi(st['held']))),
                _Kucuk('En eski', yasYaz(tamsayiYa(st['oldest_age_seconds'])), renk: tamsayi(st['oldest_age_seconds']) > 6 * 3600 ? Marka.gul : null),
                _Kucuk('Giden / gelen', '${tamsayi(st['outbound'])} / ${tamsayi(st['inbound'])}'),
              ],
            ),
          ),
        if (y != null && y.hataSayilari.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Erteleme nedenleri',
                  style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (k, e, n) in y.hataSayilari)
                      FilterChip(
                        label: Text('$e  $n'),
                        selected: _hataSinifi == k,
                        showCheckmark: false,
                        onSelected: (_) => _filtre(() => _hataSinifi = _hataSinifi == k ? '' : k),
                      ),
                  ],
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(
            children: [
              AramaAlani(ipucu: 'Kuyruk kimliği, gönderen veya alıcı…', degisti: (v) => _filtre(() => _q = v)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (d, e) in const [('', 'Tüm yönler'), ('outbound', 'Giden'), ('inbound', 'Gelen')])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(label: Text(e), selected: _yon == d, showCheckmark: false, onSelected: (_) => _filtre(() => _yon = d)),
                      ),
                    const SizedBox(width: 8),
                    for (final (d, e) in const [('', 'Tüm durumlar'), ('pending', 'Bekliyor'), ('deferred', 'Ertelendi'), ('held', 'Bekletiliyor')])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(label: Text(e), selected: _durum == d, showCheckmark: false, onSelected: (_) => _filtre(() => _durum = d)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final liste = SayfaliListe<KuyrukOgesi>(
      yukleyici: _y,
      ust: ust,
      ayrac: false,
      bosIkon: Icons.done_all_rounded,
      bosMetin: (_q + _yon + _durum + _hataSinifi).isEmpty
          ? 'Kuyruk boş: tüm kabul edilen iletiler teslim edildi.'
          : 'Eşleşen ileti yok. Filtreleri değiştirin.',
      oge: (c, o) => ListeSatiri(
        secili: _secili?.kimlik == o.kimlik && _secili?.yon == o.yon && bolunmus(c),
        onTap: () => _ac(o),
        sol: Icon(o.giden ? Icons.north_east_rounded : Icons.south_west_rounded, color: o.giden ? Marka.mavi : Marka.zumrut),
        baslik: o.gonderen.isEmpty ? '<>' : o.gonderen,
        alt: '→ ${o.alicilar.isEmpty ? '—' : o.alicilar.first}${o.alicilar.length > 1 ? ' +${o.alicilar.length - 1}' : ''}',
        alt2: o.frenNedeni.isNotEmpty
            ? 'Güvenlik freni: ${o.frenNedeni}'
            : (o.sonHata.isNotEmpty
                  ? '${_son?.hataSiniflari[o.hataSinifi] ?? o.hataSinifi}: ${o.sonHata}'
                  : [o.orgAdi, '${o.deneme} deneme', boyutYaz(o.boyut)].where((s) => s.isNotEmpty).join(' · ')),
        sag: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            KuyrukDurumu(o),
            const SizedBox(height: 4),
            Text(yasYaz(o.yasSn), style: TextStyle(color: r.silik, fontSize: 11.5)),
          ],
        ),
      ),
    );
    return AnaDetay(
      liste: liste,
      detay: _secili == null
          ? null
          : KuyrukDetay(
              key: ValueKey('${_secili!.yon}${_secili!.kimlik}'),
              oge: _secili!,
              hataEtiketleri: _son?.hataSiniflari ?? const {},
              yonetebilir: _son?.yonetebilir ?? false,
              degisti: () {
                setState(() => _secili = null);
                _y.yenile();
              },
            ),
      bosMetin: 'Ayrıntı ve başlıklar için bir ileti seçin',
    );
  }
}

class _Kucuk extends StatelessWidget {
  const _Kucuk(this.etiket, this.deger, {this.alt, this.renk});
  final String etiket, deger;
  final String? alt;
  final Color? renk;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: r.kart,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: r.kenar),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(etiket, style: TextStyle(color: r.silik, fontSize: 11)),
          Text(deger, style: gosterim(16, renk: renk)),
          if (alt != null) Text(alt!, style: TextStyle(color: r.silik, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class KuyrukDurumu extends StatelessWidget {
  const KuyrukDurumu(this.o, {super.key});
  final KuyrukOgesi o;
  @override
  Widget build(BuildContext context) {
    if (o.durum == 'held' && o.frenNedeni.isNotEmpty) return const Rozet('Frende', renk: Marka.gul);
    if (o.durum == 'held') return const Rozet('Bekletiliyor', renk: Marka.mor);
    if (o.durum == 'deferred') {
      return Rozet(o.sonrakiDeneme == null ? 'Ertelendi' : 'Ertelendi · ${kisaZaman(o.sonrakiDeneme)}', renk: Marka.kehribar);
    }
    return Rozet('Bekliyor', renk: context.r.silik);
  }
}
