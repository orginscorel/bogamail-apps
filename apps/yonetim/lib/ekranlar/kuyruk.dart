import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../ortak/tablo.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/operasyon.dart';
import 'bekletilenler.dart';
import 'kuyruk_detay.dart';
import 'liste_ortak.dart';
import '../ortak/simgeler.dart';

/// Kuyruk yönetimi (GET /queue/manager): kabul edilmiş ama henüz teslim edilmemiş iletiler; bekletilen giden iletiler
/// ayrı sekmede (GET /outbound-holds).
class KuyrukEkrani extends StatefulWidget {
  const KuyrukEkrani({super.key});
  @override
  State<KuyrukEkrani> createState() => _KuyrukEkraniState();
}

class _KuyrukEkraniState extends State<KuyrukEkrani> {
  final _liste = GlobalKey<_KuyrukListesiState>();
  final _bekletilenYenile = ValueNotifier<int>(0);
  bool _canli = false;

  @override
  void dispose() {
    _bekletilenYenile.dispose();
    super.dispose();
  }

  void _yenile() {
    _liste.currentState?.yenile();
    _bekletilenYenile.value++;
  }

  @override
  Widget build(BuildContext context) {
    final bekletme = Uyg.yetki('quarantine.view');
    final canli = IconButton(
      tooltip: _canli ? 'Canlı görünümü duraklat' : 'Canlı görünüm (3 sn)',
      isSelected: _canli,
      onPressed: () => setState(() => _canli = !_canli),
      icon: const Icon(Simgeler.playCircleOutline),
      selectedIcon: const Icon(Simgeler.pauseCircleFilled, color: Marka.zumrut),
    );
    final liste = KuyrukListesi(key: _liste, canli: _canli);
    final iskelet = Iskelet(
      baslik: 'Kuyruk Yönetimi',
      alt: 'Kabul edilmiş ama henüz teslim edilmemiş iletiler · yalnızca başlıklar gösterilir',
      eylemler: [canli],
      yenile: _yenile,
      sekmeler: bekletme
          ? const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Teslim kuyruğu'),
                Tab(text: 'Bekletilenler'),
              ],
            )
          : null,
      govde: bekletme ? TabBarView(children: [liste, BekletilenlerListesi(yenileme: _bekletilenYenile)]) : liste,
    );
    return bekletme ? DefaultTabController(length: 2, child: iskelet) : iskelet;
  }
}

class KuyrukListesi extends StatefulWidget {
  const KuyrukListesi({super.key, this.canli = false});

  /// Açıkken liste 3 saniyede bir yenilenir (web panelindeki "Canlı" görünüm).
  final bool canli;
  @override
  State<KuyrukListesi> createState() => _KuyrukListesiState();
}

class _KuyrukListesiState extends State<KuyrukListesi> with AutomaticKeepAliveClientMixin {
  String _q = '', _yon = '', _durum = '', _sinif = '', _hataSinifi = '', _yas = '', _boyut = '', _alan = '', _grup = '';
  String? _orgId, _orgAdi;
  KuyrukYaniti? _son;
  final Set<String> _secim = {};
  Timer? _zamanlayici;

  /// Sunucunun süzgeç nesnesi (toplu "eşleşen tümü" işlemlerinde de gönderilir).
  Map<String, Object> get _suzgec => {
    if (_q.isNotEmpty) 'q': _q,
    if (_yon.isNotEmpty) 'direction': _yon,
    if (_durum.isNotEmpty) 'status': _durum,
    if (_hataSinifi.isNotEmpty) 'error_class': _hataSinifi,
    if (_alan.isNotEmpty) 'domain': _alan.toLowerCase(),
    'org': ?_orgId,
    if (_yas.isNotEmpty) 'min_age_minutes': int.parse(_yas),
    if (_boyut.isNotEmpty) 'min_size': int.parse(_boyut),
    if (_sinif.isNotEmpty) 'class': _sinif,
  };

  late final _y = SayfaYukleyici<KuyrukOgesi>((s, b) async {
    final v = await Uyg.api.get(
      '/api/v1/queue/manager',
      q: {'page': '$s', 'page_size': '$b', for (final e in _suzgec.entries) e.key: '${e.value}', if (_grup.isNotEmpty) 'group_by': _grup},
    );
    final y = KuyrukYaniti(harita(v));
    if (mounted) setState(() => _son = y);
    return Sayfa(y.ogeler, y.eslesen);
  })..yenile();

  Future<void> yenile() => _y.sayfaGit(_y.sayfa < 1 ? 1 : _y.sayfa);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _zamanlayiciKur();
  }

  @override
  void didUpdateWidget(KuyrukListesi eski) {
    super.didUpdateWidget(eski);
    if (eski.canli != widget.canli) _zamanlayiciKur();
  }

  void _zamanlayiciKur() {
    _zamanlayici?.cancel();
    _zamanlayici = widget.canli
        ? Timer.periodic(const Duration(seconds: 3), (_) {
            if (!_y.yukleniyor) yenile();
          })
        : null;
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _y.dispose();
    super.dispose();
  }

  void _filtre(void Function() f) {
    setState(() {
      f();
      _secim.clear();
    });
    _y.yenile();
  }

  bool get _yonetir => (_son?.yonetebilir ?? false) && Uyg.taklit == null;
  bool get _yazabilir => Uyg.taklit == null;

  void _ac(KuyrukOgesi o) => ayrintiAc(
    context,
    'Kuyruk kaydı',
    KuyrukDetay(oge: o, hataEtiketleri: _son?.hataSiniflari ?? const {}, yonetebilir: _yonetir, degisti: yenile, tamSayfa: true),
  );

  Future<void> _toplu(String eylem, {List<String>? kimlikler, bool tumu = false}) async {
    if (eylem == 'delete') {
      final s = await showDialog<(String, String)>(
        context: context,
        builder: (_) => KuyrukSilDialog(giden: true, adet: tumu ? (_son?.eslesen ?? 0) : kimlikler!.length),
      );
      if (s == null) return;
      final v = await islem(
        () => Uyg.api.post('/api/v1/queue/bulk', {
          'action': 'delete',
          'mode': s.$1,
          'confirm': 'SİL',
          if (s.$2.isNotEmpty) 'reason': s.$2,
          if (tumu) ...{'all_matching': true, 'filter': _suzgec} else 'ids': kimlikler,
        }),
      );
      _sonuc(v, 'silindi');
      return;
    }
    final v = await islem(
      () => Uyg.api.post('/api/v1/queue/bulk', {
        'action': eylem,
        if (tumu) ...{'all_matching': true, 'filter': _suzgec} else 'ids': kimlikler,
      }),
    );
    _sonuc(v, const {'retry': 'yeniden denemeye alındı', 'hold': 'bekletmeye alındı', 'release': 'serbest bırakıldı'}[eylem] ?? 'işlendi');
  }

  void _sonuc(Object? v, String fiil) {
    if (v == null) return;
    final m = harita(v);
    final hatalar = haritalar(m['failed']);
    final n = tamsayi(m['done']);
    if (hatalar.isNotEmpty) {
      bildir('$n ileti $fiil; ${hatalar.length} başarısız', mesaj: metin(hatalar.first['error']), tur: MesajTur.uyari);
    } else {
      bildir('$n ileti $fiil', tur: MesajTur.basari);
    }
    setState(_secim.clear);
    yenile();
  }

  List<SatirEylemi> _eylemler(KuyrukOgesi o) => [
    SatirEylemi(Simgeler.description, 'Ayrıntılar ve başlıklar', () => _ac(o)),
    if (_yazabilir) SatirEylemi(Simgeler.replay, 'Şimdi yeniden dene', () => _toplu('retry', kimlikler: [o.kimlik])),
    if (_yonetir && o.giden)
      o.durum == 'held'
          ? SatirEylemi(Simgeler.playArrow, 'Serbest bırak', () => _toplu('release', kimlikler: [o.kimlik]))
          : SatirEylemi(Simgeler.pause, 'Beklet', () => _toplu('hold', kimlikler: [o.kimlik])),
    if (_yonetir) SatirEylemi(Simgeler.deleteOutline, 'Kuyruktan sil', () => _toplu('delete', kimlikler: [o.kimlik]), tehlikeli: true),
  ];

  Widget _ozet(BuildContext context) {
    final y = _son;
    if (y == null || !y.istatistikVar) return const SizedBox.shrink();
    final st = y.istatistik;
    final yas = tamsayiYa(st['oldest_age_seconds']);
    return Izgara(
      enAz: 150,
      bosluk: 8,
      children: [
        OzetKutusu('Kuyrukta', sayiYaz(tamsayi(st['total'])), alt: boyutYaz(tamsayi(st['bytes'])), ikon: Simgeler.inbox),
        OzetKutusu('Bekliyor', sayiYaz(tamsayi(st['pending'])), ikon: Simgeler.schedule),
        OzetKutusu('Ertelendi', sayiYaz(tamsayi(st['deferred'])), ikon: Simgeler.update, renk: tamsayi(st['deferred']) > 0 ? Marka.kehribar : null),
        OzetKutusu('Bekletiliyor', sayiYaz(tamsayi(st['held'])), ikon: Simgeler.pauseCircleOutline),
        OzetKutusu(
          'En eski',
          yasYaz(yas),
          alt: tamZaman(tarihOku(st['oldest'])),
          ikon: Simgeler.hourglassBottom,
          renk: (yas ?? 0) > 6 * 3600 ? Marka.gul : null,
        ),
        OzetKutusu('Giden / gelen', '${tamsayi(st['outbound'])} / ${tamsayi(st['inbound'])}', ikon: Simgeler.swapVert),
      ],
    );
  }

  Widget _ust(BuildContext context) {
    final r = context.r;
    final y = _son;
    final yatay = context.genis ? 16.0 : 12.0;
    final hataEt = y?.hataSiniflari ?? const <String, String>{};
    const yonler = {'outbound': 'Giden', 'inbound': 'Gelen'};
    const durumlar = {'pending': 'Bekliyor', 'deferred': 'Ertelendi', 'held': 'Bekletiliyor'};
    const siniflar = {'normal': 'Normal', 'bulk': 'Toplu', 'brake': 'Güvenlik freninde'};
    const yaslar = {'15': "15 dk'dan eski", '60': '1 saatten eski', '360': '6 saatten eski', '1440': '1 günden eski'};
    const boyutlar = {'1048576': "1 MB'tan büyük", '10485760': "10 MB'tan büyük"};
    const gruplar = {'domain': 'Hedef alan adı', 'customer': 'Müşteri', 'status': 'Durum'};
    FiltreDugmesi<String> dugme(String etiket, Map<String, String> m, String secili, void Function(String) ata, {IconData? ikon, String tumu = 'Tümü'}) =>
        FiltreDugmesi<String>(
          etiket: etiket,
          ikon: ikon,
          secenekler: [('', tumu), for (final e in m.entries) (e.key, e.value)],
          secili: secili,
          secildi: (v) => _filtre(() => ata(v)),
        );
    final gruplarListe = haritalar(y?.m['groups']);
    final secili = _secim.toList();
    final eslesen = y?.eslesen ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (y != null && !y.etkin)
          Padding(
            padding: EdgeInsets.fromLTRB(yatay, 8, yatay, 0),
            child: const Bant('Kuyruk devre dışı: SMTP dinleyicisi yapılandırılmamış.', renk: Marka.kehribar),
          ),
        if (y != null && y.kapsamli)
          Padding(
            padding: EdgeInsets.fromLTRB(yatay, 8, yatay, 0),
            child: Bant(
              'Yalnızca alan adlarınıza ait kuyruk kayıtları gösterilir.${Uyg.musteri ? ' İletilerinizi yeniden deneyebilirsiniz; bekletme ve silme platform yöneticisindedir.' : ''}',
            ),
          ),
        if (y != null && y.istatistikVar) Padding(padding: EdgeInsets.fromLTRB(yatay, 8, yatay, 0), child: _ozet(context)),
        if (y != null && y.hataSayilari.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(yatay, 8, yatay, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Erteleme nedenleri:', style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600)),
                for (final (k, e, n) in y.hataSayilari)
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('$e  $n'),
                    selected: _hataSinifi == k,
                    showCheckmark: false,
                    onSelected: (_) => _filtre(() => _hataSinifi = _hataSinifi == k ? '' : k),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        FiltreCubugu(
          arama: AramaAlani(ipucu: 'Kuyruk kimliği, gönderen veya alıcı…', ilk: _q, degisti: (v) => _filtre(() => _q = v)),
          sag: y == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('${sayiYaz(y.eslesen)} eşleşen', style: TextStyle(color: r.silik, fontSize: 12.5)),
                ),
          filtreler: [
            dugme('Yön', yonler, _yon, (v) => _yon = v, ikon: Simgeler.swapVert),
            dugme('Durum', durumlar, _durum, (v) => _durum = v, ikon: Simgeler.flag),
            dugme('Sınıf', siniflar, _sinif, (v) => _sinif = v, ikon: Simgeler.category),
            if (hataEt.isNotEmpty) dugme('Hata sınıfı', hataEt, _hataSinifi, (v) => _hataSinifi = v, ikon: Simgeler.errorOutline),
            dugme('Yaş', yaslar, _yas, (v) => _yas = v, ikon: Simgeler.hourglassBottom),
            dugme('Boyut', boyutlar, _boyut, (v) => _boyut = v, ikon: Simgeler.straighten),
            if (!Uyg.musteri)
              ActionChip(
                avatar: const Icon(SimgelerKalin.business, size: 16),
                label: Text(_orgId == null ? 'Müşteri' : 'Müşteriyi değiştir'),
                onPressed: () async {
                  final o = await musteriSec(context);
                  if (o != null) {
                    _filtre(() {
                      _orgId = o.id;
                      _orgAdi = o.ad;
                    });
                  }
                },
              ),
            ActionChip(
              avatar: const Icon(SimgelerKalin.language, size: 16),
              label: const Text('Hedef alan adı'),
              onPressed: () async {
                final v = await metinSor(context, 'Hedef alan adı', ilk: _alan, ipucu: 'ornek.com', tamam: 'Süz');
                if (v != null) _filtre(() => _alan = v.trim());
              },
            ),
            dugme('Grupla', gruplar, _grup, (v) => _grup = v, ikon: Simgeler.workspaces, tumu: 'Gruplama yok'),
          ],
          etkinler: [
            if (_yon.isNotEmpty) EtkinFiltre('Yön: ${yonler[_yon]}', () => _filtre(() => _yon = '')),
            if (_durum.isNotEmpty) EtkinFiltre('Durum: ${durumlar[_durum]}', () => _filtre(() => _durum = '')),
            if (_sinif.isNotEmpty) EtkinFiltre('Sınıf: ${siniflar[_sinif]}', () => _filtre(() => _sinif = '')),
            if (_hataSinifi.isNotEmpty) EtkinFiltre('Hata: ${hataEt[_hataSinifi] ?? _hataSinifi}', () => _filtre(() => _hataSinifi = '')),
            if (_yas.isNotEmpty) EtkinFiltre(yaslar[_yas]!, () => _filtre(() => _yas = '')),
            if (_boyut.isNotEmpty) EtkinFiltre(boyutlar[_boyut]!, () => _filtre(() => _boyut = '')),
            if (_orgId != null)
              EtkinFiltre('Müşteri: ${_orgAdi ?? 'seçili'}', () {
                _filtre(() {
                  _orgId = null;
                  _orgAdi = null;
                });
              }),
            if (_alan.isNotEmpty) EtkinFiltre('Alan adı: $_alan', () => _filtre(() => _alan = '')),
            if (_grup.isNotEmpty) EtkinFiltre('Gruplama: ${gruplar[_grup]}', () => _filtre(() => _grup = ''), ikon: Simgeler.workspaces),
          ],
        ),
        if (_grup.isNotEmpty && gruplarListe.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(yatay, 0, yatay, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in gruplarListe.take(30))
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${metin(g['label']).isNotEmpty ? metin(g['label']) : (metin(g['key']).isNotEmpty ? metin(g['key']) : '—')}  ${tamsayi(g['count'])}'),
                    onPressed: () {
                      final k = metin(g['key']);
                      _filtre(() {
                        if (_grup == 'domain') {
                          _alan = k;
                        } else if (_grup == 'customer') {
                          if (k.isNotEmpty) {
                            _orgId = k;
                            _orgAdi = metin(g['label']);
                          }
                        } else {
                          _durum = k;
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
        if (_yazabilir && eslesen > 0)
          Container(
            margin: EdgeInsets.fromLTRB(yatay, 0, yatay, 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: r.ic.withValues(alpha: .6), borderRadius: BorderRadius.circular(12)),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(secili.isEmpty ? 'Seçim yok' : '${secili.length} seçili', style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600)),
                if (secili.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ..._topluDugmeler('Seçilenler', () => (kimlikler: secili, tumu: false)),
                  TextButton(onPressed: () => setState(_secim.clear), child: const Text('Seçimi temizle')),
                ],
                const SizedBox(width: 8),
                ..._topluDugmeler('Eşleşen tümü (${sayiYaz(eslesen)})', () => (kimlikler: const <String>[], tumu: true)),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _topluDugmeler(String etiket, ({List<String> kimlikler, bool tumu}) Function() hedef) {
    Widget d(IconData i, String e, String eylem, {bool tehlikeli = false}) => TextButton.icon(
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: tehlikeli ? Marka.gul : null),
      onPressed: () {
        final h = hedef();
        _toplu(eylem, kimlikler: h.kimlikler, tumu: h.tumu);
      },
      icon: Icon(i, size: 17),
      label: Text(e),
    );
    return [
      Text('$etiket:', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      d(Simgeler.replay, 'Yeniden dene', 'retry'),
      if (_yonetir) ...[
        d(Simgeler.pause, 'Beklet', 'hold'),
        d(Simgeler.playArrow, 'Serbest bırak', 'release'),
        d(Simgeler.deleteOutline, 'Sil', 'delete', tehlikeli: true),
      ],
    ];
  }

  Widget _secimKutusu(KuyrukOgesi o) => Checkbox(
    value: _secim.contains(o.kimlik),
    visualDensity: VisualDensity.compact,
    onChanged: (v) => setState(() => v == true ? _secim.add(o.kimlik) : _secim.remove(o.kimlik)),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = context.r;
    final hataEt = _son?.hataSiniflari ?? const <String, String>{};
    String altSatir(KuyrukOgesi o) => o.frenNedeni.isNotEmpty
        ? 'Güvenlik freni: ${o.frenNedeni}'
        : (o.sonHata.isNotEmpty ? '${hataEt[o.hataSinifi] ?? o.hataSinifi}: ${o.sonHata}' : '→ ${_alicilar(o)}');
    Widget yonIkonu(KuyrukOgesi o) => Icon(o.giden ? Simgeler.northEast : Simgeler.southWest, size: 18, color: o.giden ? Marka.mavi : Marka.zumrut);
    final bos = (_q + _yon + _durum + _hataSinifi + _sinif + _yas + _boyut + _alan + (_orgId ?? '')).isEmpty;
    return VeriTablosu<KuyrukOgesi>(
      yukleyici: _y,
      onTap: _ac,
      eylemler: _eylemler,
      secili: (o) => _secim.contains(o.kimlik),
      vurgulu: (o) => o.frenNedeni.isNotEmpty,
      tabloEnAz: 820,
      bosIkon: Simgeler.doneAll,
      bosMetin: bos ? 'Kuyruk boş: tüm kabul edilen iletiler teslim edildi.' : 'Eşleşen ileti yok. Filtreleri değiştirin.',
      ust: _ust(context),
      sutunlar: [
        if (_yazabilir) Sutun('', genislik: 44, hucre: (c, o) => _secimKutusu(o)),
        Sutun(
          'Gönderen → alıcı',
          esnek: 6,
          hucre: (c, o) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  yonIkonu(o),
                  const SizedBox(width: 8),
                  if (o.sinif == 'bulk') ...[Rozet('Toplu', renk: r.birincil), const SizedBox(width: 8)],
                  Expanded(
                    child: Text(o.gonderen.isEmpty ? '<>' : o.gonderen, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  ),
                ],
              ),
              Text(
                altSatir(o),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: o.frenNedeni.isNotEmpty ? Marka.gul : (o.sonHata.isNotEmpty ? Marka.kehribar : r.silik),
                ),
              ),
            ],
          ),
        ),
        Sutun('Durum', genislik: 150, hucre: (c, o) => Sigdir(KuyrukDurumu(o))),
        if (!Uyg.musteri) Sutun('Müşteri', esnek: 2, hucre: (c, o) => SolukMetin(o.orgAdi)),
        Sutun('Yaş', genislik: 80, hucre: (c, o) => Tooltip(message: tamZaman(o.alinma), child: SolukMetin(yasYaz(o.yasSn)))),
        Sutun('Boyut', genislik: 80, sagaYasla: true, hucre: (c, o) => SolukMetin(boyutYaz(o.boyut))),
        Sutun('Deneme', genislik: 70, sagaYasla: true, hucre: (c, o) => SolukMetin('${o.deneme}')),
      ],
      kart: (c, o) => VeriKarti(
        baslik: o.gonderen.isEmpty ? '<>' : o.gonderen,
        alt: altSatir(o),
        sol: _yazabilir
            ? Column(mainAxisSize: MainAxisSize.min, children: [_secimKutusu(o), yonIkonu(o)])
            : yonIkonu(o),
        secili: _secim.contains(o.kimlik),
        vurgulu: o.frenNedeni.isNotEmpty,
        rozetler: [KuyrukDurumu(o), if (o.sinif == 'bulk') Rozet('Toplu', renk: r.birincil)],
        alanlar: [
          if (o.sonHata.isNotEmpty || o.frenNedeni.isNotEmpty) ('Alıcı', _alicilar(o)),
          ('Yaş', yasYaz(o.yasSn)),
          ('Boyut', boyutYaz(o.boyut)),
          ('Deneme', '${o.deneme}'),
          if (!Uyg.musteri && o.orgAdi.isNotEmpty) ('Müşteri', o.orgAdi),
        ],
        eylemler: _eylemler(o),
        onTap: () => _ac(o),
      ),
    );
  }

  String _alicilar(KuyrukOgesi o) => '${o.alicilar.isEmpty ? '—' : o.alicilar.first}${o.alicilar.length > 1 ? ' +${o.alicilar.length - 1}' : ''}';
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
