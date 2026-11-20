import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'trafik_ortak.dart';
import '../ortak/simgeler.dart';

const _olayFiltreleri = <(String, String)>[
  ('', 'Tümü'),
  ('accepted', 'Kabul'),
  ('delivered', 'Teslim'),
  ('rejected', 'Ret'),
  ('deferred', 'Ertelendi'),
  ('failed', 'Başarısız'),
  ('quarantined', 'Karantina'),
];

const _yonFiltreleri = <(String, String)>[('', 'Her yön'), ('inbound', 'Gelen'), ('outbound', 'Giden')];

/// Mesaj Takibi: her SMTP kararı ve teslim sonucu (GET /mail-events), aşama gecikmeleri (GET /mail-events/latency)
/// ve kuyruk kimliğine dokununca ileti yolculuğu ([IletiYolculugu]).
class MesajTakibiEkrani extends StatefulWidget {
  const MesajTakibiEkrani({super.key, this.olay = '', this.yon = ''});

  /// Başlangıç filtreleri (ör. özet ekranından "Reddedilenler").
  final String olay, yon;
  @override
  State<MesajTakibiEkrani> createState() => _MesajTakibiEkraniState();
}

class _MesajTakibiEkraniState extends State<MesajTakibiEkrani> {
  String _q = '';
  late String _olay = widget.olay;
  late String _yon = widget.yon;
  bool _artan = false;
  final _gecikmeAnahtari = GlobalKey<_GecikmeSeridiState>();

  late final _y = SayfaYukleyici<PostaOlayi>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/mail-events',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': 'at',
          'order': _artan ? 'asc' : 'desc',
          if (_q.isNotEmpty) 'q': _q,
          if (_olay.isNotEmpty) 'event': _olay,
          if (_yon.isNotEmpty) 'direction': _yon,
        },
      ),
      PostaOlayi.coz,
    ),
    sayfaBoyu: 50,
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _ac(PostaOlayi e) {
    if (e.kuyrukId.isEmpty) {
      _olayDetayi(e);
      return;
    }
    iletiYolculugunuAc(context, e.kuyrukId);
  }

  void _olayDetayi(PostaOlayi e) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Bağlantı olayı', style: gosterim(19, agirlik: FontWeight.w600)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AciklamaRozeti(e.aciklama),
              const SizedBox(height: 8),
              AciklamaMetni(e.aciklama),
              const SizedBox(height: 8),
              BilgiSatiri('Zaman', tamZaman(e.zaman)),
              BilgiSatiri('Gönderen', e.gonderen.isEmpty ? '<>' : e.gonderen),
              BilgiSatiri('Alıcı', e.alici),
              BilgiSatiri('Kaynak IP', e.uzakIp ?? '', mono: true),
              if (e.smtpKodu != null) BilgiSatiri('SMTP', '${e.smtpKodu} ${e.genisKod}', mono: true),
              if (e.neden.isNotEmpty) BilgiSatiri('Neden', e.neden),
              if (e.kurum != null) BilgiSatiri('Müşteri', e.kurum!),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
    ),
  );

  void _yenile() {
    _y.yenile();
    _gecikmeAnahtari.currentState?.yukle();
  }

  void _yonSec(String v) {
    setState(() => _yon = v);
    _y.yenile();
    _gecikmeAnahtari.currentState?.yukle(v);
  }

  List<Widget> _rozetler(PostaOlayi e) => [
    if (e.giden) const Rozet('giden', renk: Marka.lavanta),
    AciklamaRozeti(e.aciklama),
    if (e.toplu) const Rozet('toplu', renk: Marka.gok),
    if (e.spamli) Rozet('spam ${e.spamPuani?.toStringAsFixed(1) ?? ''}'.trim(), renk: Marka.kehribar),
  ];

  @override
  Widget build(BuildContext context) {
    final etkinler = [
      if (_olay.isNotEmpty)
        EtkinFiltre('Olay: ${_olayFiltreleri.firstWhere((f) => f.$1 == _olay, orElse: () => (_olay, _olay)).$2}', () {
          setState(() => _olay = '');
          _y.yenile();
        }),
      if (_yon.isNotEmpty) EtkinFiltre('Yön: ${_yonFiltreleri.firstWhere((f) => f.$1 == _yon, orElse: () => (_yon, _yon)).$2}', () => _yonSec('')),
    ];
    return Iskelet(
      baslik: 'Mesaj Takibi',
      alt: 'SMTP kararları ve teslim sonuçları · kayıtlar 30 gün saklanır',
      yenile: _yenile,
      govde: VeriTablosu<PostaOlayi>(
        yukleyici: _y,
        bosMetin: 'Kayıt yok. Sunucuya SMTP ile ileti geldiğinde burada görünür.',
        bosIkon: Simgeler.manageSearch,
        onTap: _ac,
        siralama: 'at',
        artan: _artan,
        siralamaDegisti: (_, a) {
          setState(() => _artan = a);
          _y.yenile();
        },
        ust: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GecikmeSeridi(key: _gecikmeAnahtari, yon: _yon),
            FiltreCubugu(
              arama: AramaAlani(
                ipucu: 'Kuyruk kimliği, gönderen, alıcı veya IP ara…',
                degisti: (v) {
                  _q = v;
                  _y.yenile();
                },
              ),
              filtreler: [
                FiltreDugmesi<String>(
                  etiket: 'Olay',
                  ikon: Simgeler.filterList,
                  secenekler: _olayFiltreleri,
                  secili: _olay,
                  secildi: (v) {
                    setState(() => _olay = v);
                    _y.yenile();
                  },
                ),
                FiltreDugmesi<String>(etiket: 'Yön', ikon: Simgeler.swapHoriz, secenekler: _yonFiltreleri, secili: _yon, secildi: _yonSec),
              ],
              etkinler: etkinler,
            ),
          ],
        ),
        sutunlar: [
          Sutun('Zaman', genislik: 150, siralama: 'at', hucre: (_, e) => SolukMetin(tamZaman(e.zaman))),
          Sutun(
            'Durum',
            esnek: 2,
            hucre: (_, e) => Wrap(spacing: 4, runSpacing: 4, children: _rozetler(e)),
          ),
          Sutun('Gönderen', esnek: 3, hucre: (_, e) => IkiSatir(e.gonderen.isEmpty ? '<>' : e.gonderen, alt: e.kurum, kalin: false)),
          Sutun('Alıcı', esnek: 3, hucre: (_, e) => SolukMetin(e.alici)),
          Sutun(
            'Açıklama',
            esnek: 4,
            hucre: (c, e) => Tooltip(
              message: [e.aciklama.ozet, if (e.aciklama.oneri.isNotEmpty) 'Öneri: ${e.aciklama.oneri}'].join('\n'),
              child: Text(e.aciklama.ozet, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            ),
          ),
          Sutun('Kaynak IP', genislik: 130, hucre: (_, e) => SolukMetin(e.uzakIp ?? '', mono: true)),
          Sutun('Kuyruk', genislik: 130, hucre: (c, e) => _KuyrukHucresi(e)),
        ],
        kart: (c, e) => VeriKarti(
          baslik: e.gonderen.isEmpty ? '<>' : e.gonderen,
          alt: '→ ${e.alici.isEmpty ? '—' : e.alici}',
          rozetler: _rozetler(e),
          onTap: () => _ac(e),
          alanlar: [
            ('Zaman', tamZaman(e.zaman)),
            if (e.uzakIp != null) ('IP', e.uzakIp!),
            ('Kuyruk', e.kuyrukId.isEmpty ? 'bağlantıda' : e.kuyrukId),
          ],
          ek: e.aciklama.ozet.isEmpty
              ? null
              : Text(e.aciklama.ozet, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.r.soluk, fontSize: 12.5)),
        ),
      ),
    );
  }
}

class _KuyrukHucresi extends StatelessWidget {
  const _KuyrukHucresi(this.e);
  final PostaOlayi e;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (e.kuyrukId.isEmpty) return Text('bağlantıda', style: TextStyle(color: r.silik, fontSize: 12));
    return Text(
      e.kuyrukId,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: r.vurgu, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Aşama gecikmeleri (son 24 saat, p50 / p95)

class _GecikmeSatiri {
  const _GecikmeSatiri(this.anahtar, this.etiket, this.sayi, this.p50, this.p95);
  final String anahtar, etiket;
  final int sayi;
  final double? p50, p95;
  factory _GecikmeSatiri.coz(Map<String, dynamic> m) =>
      _GecikmeSatiri(metin(m['key']), metin(m['label']), tamsayi(m['count']), ondalikYa(m['p50_ms']), ondalikYa(m['p95_ms']));
}

class _GecikmeSeridi extends StatefulWidget {
  const _GecikmeSeridi({super.key, required this.yon});
  final String yon;
  @override
  State<_GecikmeSeridi> createState() => _GecikmeSeridiState();
}

class _GecikmeSeridiState extends State<_GecikmeSeridi> {
  List<_GecikmeSatiri>? _satirlar;
  bool _hata = false;
  bool _acik = true;
  Timer? _zamanlayici;
  late String _yon = widget.yon;

  @override
  void initState() {
    super.initState();
    yukle();
    _zamanlayici = Timer.periodic(const Duration(seconds: 60), (_) => yukle());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  Future<void> yukle([String? yon]) async {
    if (yon != null) _yon = yon;
    try {
      final v = harita(await Uyg.api.get('/api/v1/mail-events/latency', q: {'hours': '24', if (_yon.isNotEmpty) 'direction': _yon}));
      if (!mounted) return;
      setState(() {
        _satirlar = haritalar(v['stages']).map(_GecikmeSatiri.coz).toList();
        _hata = false;
      });
    } catch (_) {
      if (mounted) setState(() => _hata = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _satirlar;
    if (_hata || l == null || l.isEmpty) return const SizedBox.shrink();
    final r = context.r;
    final enFazla = l.fold<double>(1, (a, s) => (s.p95 ?? 0) > a ? s.p95! : a);
    final olcum = l.any((s) => s.sayi > 0);
    final genis = MediaQuery.sizeOf(context).width >= 720;
    return Padding(
      padding: EdgeInsets.fromLTRB(genis ? 16 : 12, 4, genis ? 16 : 12, 4),
      child: Container(
        decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(14), border: Border.all(color: r.kenar)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _acik = !_acik),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(Simgeler.timer, size: 17, color: r.vurgu),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        olcum ? 'Aşama gecikmeleri · son 24 saat (p50 / p95)' : 'Aşama gecikmeleri · henüz ölçülmüş ileti yok',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(_acik ? Simgeler.expandLess : Simgeler.expandMore, size: 20, color: r.soluk),
                  ],
                ),
              ),
            ),
            if (_acik)
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: l.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (c, i) {
                    final s = l[i];
                    return Container(
                      width: 190,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      decoration: BoxDecoration(color: r.ic.withValues(alpha: .6), borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(s.etiket, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 11.5)),
                              ),
                              Text('${s.sayi} ölçüm', style: TextStyle(color: r.silik, fontSize: 10.5)),
                            ],
                          ),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'p50 ${msYaz(s.p50)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                TextSpan(text: '   p95 ${msYaz(s.p95)}'),
                              ],
                            ),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          _OranCubugu(dis: (s.p95 ?? 0) / enFazla, ic: (s.p50 ?? 0) / enFazla),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// p95 (açık) ve p50 (koyu) oran çubuğu.
class _OranCubugu extends StatelessWidget {
  const _OranCubugu({required this.dis, required this.ic});
  final double dis, ic;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 5,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: r.kenar)),
            FractionallySizedBox(widthFactor: dis.clamp(0.0, 1.0), child: ColoredBox(color: r.vurgu.withValues(alpha: .35))),
            FractionallySizedBox(widthFactor: ic.clamp(0.0, 1.0), child: ColoredBox(color: r.vurgu)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// İleti yolculuğu (GET /mail-events/explore/{queue_id}; olmazsa GET /mail-events/trace/{queue_id})

/// İleti yolculuğu ekranını tam sayfa açar (diğer ekranlardan da kullanılır).
Future<void> iletiYolculugunuAc(BuildContext context, String kuyrukId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => IletiYolculugu(queueId: kuyrukId)));

class _Asama {
  const _Asama({
    required this.anahtar,
    required this.etiket,
    this.alici,
    this.baslangic,
    this.bitis,
    this.sureMs,
    this.durum = 'info',
    this.ayrintilar = const [],
    this.aciklama,
    this.enYavas = false,
  });
  final String anahtar, etiket, durum;
  final String? alici;
  final DateTime? baslangic, bitis;
  final int? sureMs;
  final List<(String, String)> ayrintilar;
  final Aciklama? aciklama;
  final bool enYavas;

  factory _Asama.coz(Map<String, dynamic> m) => _Asama(
    anahtar: metin(m['key']),
    etiket: metin(m['label']),
    alici: metinYa(m['rcpt']),
    baslangic: tarihOku(m['start']),
    bitis: tarihOku(m['end']),
    sureMs: tamsayiYa(m['duration_ms']),
    durum: metin(m['status'], 'info'),
    ayrintilar: [for (final d in haritalar(m['details'])) (metin(d['k']), metin(d['v']))],
    aciklama: m['explain'] is Map ? Aciklama.coz(m['explain']) : null,
    enYavas: mantik(m['slowest']),
  );
}

class _Yolculuk {
  const _Yolculuk({
    required this.yon,
    this.gateway = false,
    this.baslangic,
    this.toplamMs,
    this.asamalar = const [],
    this.hatalar = 0,
    this.alicilar = const [],
    this.ozet = const Aciklama(),
    this.eksik = const [],
    this.yavasNotu = '',
    this.olaylar = const [],
    this.yalnizKayit = false,
  });
  final String yon;
  final bool gateway;
  final DateTime? baslangic;
  final int? toplamMs;
  final List<_Asama> asamalar;
  final int hatalar;
  final List<(String, Aciklama)> alicilar;
  final Aciklama ozet;
  final List<String> eksik;
  final String yavasNotu;
  final List<PostaOlayi> olaylar;

  /// Yalnızca ham kayıtlar alınabildi (trace yedeği).
  final bool yalnizKayit;

  factory _Yolculuk.coz(Map<String, dynamic> v) {
    final t = harita(v['timeline']);
    return _Yolculuk(
      yon: metin(t['direction']),
      gateway: mantik(t['gateway']),
      baslangic: tarihOku(t['start']),
      toplamMs: tamsayiYa(t['total_ms']),
      asamalar: haritalar(t['stages']).map(_Asama.coz).toList(),
      hatalar: tamsayi(t['failures']),
      alicilar: [for (final a in haritalar(t['recipients'])) (metin(a['rcpt']), Aciklama.coz(a['explain']))],
      ozet: Aciklama.coz(t['summary']),
      eksik: metinler(t['missing']),
      yavasNotu: metin(v['slow_note']),
      olaylar: haritalar(v['events']).map(PostaOlayi.coz).toList(),
    );
  }
}

const _eksikEtiketleri = {
  'connect': 'bağlantı zamanı',
  'smtp': 'SMTP süresi',
  'scan': 'tarama süresi',
  'delivery': 'kutuya yazma süresi',
  'attempt': 'uzak sunucu denemesi süresi',
};

String _saat(DateTime? d) {
  if (d == null) return '';
  String iki(int n) => n.toString().padLeft(2, '0');
  return '${iki(d.hour)}:${iki(d.minute)}:${iki(d.second)}';
}

/// Bir iletinin SMTP bağlantısından posta kutusuna (ya da alıcı sunucuya) kadar her aşaması, zamanları ve gecikmeleri.
class IletiYolculugu extends StatefulWidget {
  const IletiYolculugu({super.key, required this.queueId, this.tamSayfa = true});
  final String queueId;

  /// false ise yalnızca gövde çizilir (başka bir ekranın içine gömmek için).
  final bool tamSayfa;
  @override
  State<IletiYolculugu> createState() => _IletiYolculuguState();
}

class _IletiYolculuguState extends State<IletiYolculugu> {
  final _anahtar = GlobalKey<TekYuklemeState<_Yolculuk>>();
  Timer? _zamanlayici;
  bool _ham = false;

  @override
  void initState() {
    super.initState();
    _zamanlayici = Timer.periodic(const Duration(seconds: 15), (_) => _anahtar.currentState?.yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  Future<_Yolculuk> _getir() async {
    final id = Uri.encodeComponent(widget.queueId);
    try {
      return _Yolculuk.coz(harita(await Uyg.api.get('/api/v1/mail-events/explore/$id')));
    } on ApiHata catch (e) {
      if (e.durum == 404 || e.durum == 403 || e.durum == 401) rethrow;
      // Gezgin hesaplanamadıysa ham kayıtları göster.
      final v = harita(await Uyg.api.get('/api/v1/mail-events/trace/$id'));
      final olaylar = haritalar(v['events']).map(PostaOlayi.coz).toList();
      return _Yolculuk(
        yon: olaylar.isEmpty ? '' : olaylar.first.yon,
        olaylar: olaylar,
        ozet: olaylar.isEmpty ? const Aciklama() : olaylar.last.aciklama,
        yalnizKayit: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final govde = TekYukleme<_Yolculuk>(key: _anahtar, getir: _getir, icerik: (c, v, yenile) => _icerik(c, v));
    if (!widget.tamSayfa) return govde;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('İleti Yolculuğu'),
            Text(widget.queueId, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: context.r.silik)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Kuyruk kimliğini kopyala', onPressed: () => kopyala(widget.queueId), icon: const Icon(Simgeler.copy)),
          IconButton(tooltip: 'Yenile', onPressed: () => _anahtar.currentState?.yenile(), icon: const Icon(Simgeler.refresh)),
          const SizedBox(width: 4),
        ],
      ),
      body: govde,
    );
  }

  Widget _icerik(BuildContext context, _Yolculuk v) {
    final r = context.r;
    final gelen = v.yon == 'inbound';
    return IcerikListesi(
      enFazla: 1000,
      children: [
        const SizedBox(height: 8),
        if (v.yalnizKayit)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Bant('Aşama ayrıntıları alınamadı; iletinin ham takip kayıtları gösteriliyor.', renk: Marka.kehribar, ikon: Simgeler.warningAmber),
          ),
        BolumKarti(
          baslik: 'Özet',
          ikon: Simgeler.route,
          sag: v.toplamMs == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(SimgelerKalin.schedule, size: 15, color: r.soluk),
                    const SizedBox(width: 4),
                    Text('toplam ${msYaz(v.toplamMs)}', style: TextStyle(color: r.soluk, fontSize: 12.5)),
                  ],
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AciklamaRozeti(v.ozet),
                  if (v.yon.isNotEmpty) Rozet(gelen ? (v.gateway ? 'gelen · gateway' : 'gelen') : 'giden', renk: gelen ? Marka.mavi : Marka.lavanta),
                  if (v.hatalar > 0) Rozet('${v.hatalar} hata', renk: Marka.gul, ikon: Simgeler.errorOutline),
                ],
              ),
              const SizedBox(height: 8),
              AciklamaMetni(v.ozet),
              if (v.yavasNotu.isNotEmpty) ...[
                const SizedBox(height: 8),
                Bant(v.yavasNotu, renk: Marka.kehribar, ikon: Simgeler.speed),
              ],
              if (v.asamalar.isNotEmpty) ...[const SizedBox(height: 12), _Akis(v.asamalar)],
              if (v.alicilar.length > 1) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(border: Border.all(color: r.kenar), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: [
                      for (final (i, (alici, a)) in v.alicilar.indexed) ...[
                        if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(child: Text(alici, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                              AciklamaRozeti(a),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (v.eksik.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Bu ileti için şu süreler kaydedilmemiş (gecikme ölçümü eklenmeden önceki kayıt olabilir): '
                  '${v.eksik.map((m) => _eksikEtiketleri[m] ?? m).join(', ')}.',
                  style: TextStyle(color: r.silik, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        if (v.asamalar.isNotEmpty) ...[
          AltBaslik('Aşamalar', alt: 'Çubuklar aşamanın toplam yolculuk içindeki yerini ve süresini gösterir (${v.baslangic == null ? '—' : tamZaman(v.baslangic)} başlangıç).'),
          for (final (i, s) in v.asamalar.indexed) _AsamaKarti(s: s, v: v, son: i == v.asamalar.length - 1),
        ],
        if (gelen) ...[_DogrulamaKarti(widget.queueId), _EkAnaliziKarti(widget.queueId)],
        const SizedBox(height: 12),
        if (!v.yalnizKayit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _ham = !_ham),
              icon: Icon(_ham ? Simgeler.expandLess : Simgeler.expandMore),
              label: Text(_ham ? 'Ham kayıtları gizle' : 'Ham kayıtlar (${v.olaylar.length})'),
            ),
          ),
        if (_ham || v.yalnizKayit)
          BolumKarti(
            baslik: 'Mesaj takibi kayıtları',
            altBaslik: 'Zarf bilgileri ve SMTP kararları; içerik yok.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, e) in v.olaylar.indexed) ...[
                  if (i > 0) Divider(height: 16, color: r.kenar),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AciklamaRozeti(e.aciklama),
                      Text(tamZaman(e.zaman), style: TextStyle(color: r.silik, fontSize: 12)),
                      Rozet(e.asama.isEmpty ? '—' : e.asama, renk: Marka.mavi),
                      if (e.giden) const Rozet('giden', renk: Marka.lavanta),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    '${e.gonderen.isEmpty ? '<>' : e.gonderen} → ${e.alici}${e.boyut != null && e.boyut! > 0 ? ' · ${boyutYaz(e.boyut)}' : ''}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  SelectableText(
                    [
                      '${e.smtpKodu != null ? '${e.smtpKodu} ${e.genisKod} ' : ''}${e.neden}',
                      ?e.uzakIp,
                      ?e.mxSunucu,
                    ].where((s) => s.trim().isNotEmpty).join(' · '),
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: r.soluk),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Akış şeması: her aşama için bir çip.
class _Akis extends StatelessWidget {
  const _Akis(this.asamalar);
  final List<_Asama> asamalar;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Wrap(
      spacing: 4,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, s) in asamalar.indexed) ...[
          if (i > 0) Icon(SimgelerKalin.chevronRight, size: 16, color: r.silik),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: s.durum == 'bad' || s.durum == 'warn' ? tonRengi(s.durum).withValues(alpha: .1) : null,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: s.enYavas ? Marka.kehribar : (s.durum == 'bad' || s.durum == 'warn' ? tonRengi(s.durum).withValues(alpha: .4) : r.kenar),
                width: s.enYavas ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DurumNoktasi(tonRengi(s.durum), boyut: 7),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(s.etiket, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ),
                if (s.sureMs != null) ...[const SizedBox(width: 8), Text(msYaz(s.sureMs), style: TextStyle(fontSize: 12, color: r.silik))],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AsamaKarti extends StatelessWidget {
  const _AsamaKarti({required this.s, required this.v, required this.son});
  final _Asama s;
  final _Yolculuk v;
  final bool son;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final renk = tonRengi(s.durum);
    final kenar = s.enYavas ? Marka.kehribar.withValues(alpha: .6) : (s.durum == 'bad' ? Marka.gul.withValues(alpha: .4) : r.kenar);
    final zemin = s.enYavas ? Marka.kehribar.withValues(alpha: .05) : (s.durum == 'bad' ? Marka.gul.withValues(alpha: .05) : r.kart);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: renk, shape: BoxShape.circle, border: Border.all(color: r.zemin, width: 2)),
                ),
                if (!son) Expanded(child: Container(width: 1, color: r.kenar)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: zemin, borderRadius: BorderRadius.circular(12), border: Border.all(color: kenar)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(s.etiket, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            if (s.enYavas) const Rozet('en yavaş', renk: Marka.kehribar, ikon: Simgeler.speed),
                            if (s.durum == 'bad') const Rozet('hata', renk: Marka.gul, ikon: Simgeler.warningAmber),
                            if (s.alici != null) Text('→ ${s.alici}', style: TextStyle(color: r.silik, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text(msYaz(s.sureMs), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(s.baslangic != null ? '${_saat(s.baslangic)} → ${_saat(s.bitis)}' : _saat(s.bitis), style: TextStyle(color: r.silik, fontSize: 12)),
                  _GecikmeCubugu(s: s, v: v),
                  if (s.ayrintilar.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final (k, d) in s.ayrintilar)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 120, child: Text(k, style: TextStyle(color: r.silik, fontSize: 12))),
                            Expanded(child: SelectableText(d, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                          ],
                        ),
                      ),
                  ],
                  if (s.aciklama != null && (s.durum == 'bad' || s.durum == 'warn' || s.anahtar == 'dsn')) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: r.ic.withValues(alpha: .6), borderRadius: BorderRadius.circular(8)),
                      child: AciklamaMetni(s.aciklama!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gantt tarzı çubuk: aşamanın iletinin tüm yolculuğu içindeki yeri.
class _GecikmeCubugu extends StatelessWidget {
  const _GecikmeCubugu({required this.s, required this.v});
  final _Asama s;
  final _Yolculuk v;
  @override
  Widget build(BuildContext context) {
    final t0 = v.baslangic, toplam = v.toplamMs;
    final bas = s.baslangic ?? s.bitis;
    if (t0 == null || toplam == null || toplam <= 0 || bas == null) return const SizedBox.shrink();
    final r = context.r;
    final sol = (bas.difference(t0).inMilliseconds / toplam).clamp(0.0, 1.0);
    final kalan = (1.0 - sol).clamp(0.008, 1.0);
    final gen = s.sureMs != null && s.sureMs! > 0 ? (s.sureMs! / toplam).clamp(0.008, kalan) : 0.0;
    final renk = s.enYavas ? Marka.kehribar : tonRengi(s.durum);
    // Oranlar binde paya çevrilir (Row + Expanded; IntrinsicHeight içinde LayoutBuilder kullanılamaz).
    final solPay = (sol * 1000).round(), genPay = (gen * 1000).round();
    final kalanPay = (1000 - solPay - genPay).clamp(0, 1000);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 7,
          color: r.ic,
          child: Row(
            children: [
              if (solPay > 0) Spacer(flex: solPay),
              if (genPay > 0)
                Expanded(
                  flex: genPay,
                  child: DecoratedBox(decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(4))),
                )
              else
                SizedBox(width: 4, child: ColoredBox(color: renk)),
              if (kalanPay > 0) Spacer(flex: kalanPay),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gelen ileti için SPF/DKIM/DMARC/ARC sonucu ve tehdit bulguları (GET /threat/auth/{queue_id}); kayıt yoksa gizli.
class _DogrulamaKarti extends StatefulWidget {
  const _DogrulamaKarti(this.kuyrukId);
  final String kuyrukId;
  @override
  State<_DogrulamaKarti> createState() => _DogrulamaKartiState();
}

class _DogrulamaKartiState extends State<_DogrulamaKarti> {
  Map<String, dynamic>? _v;
  bool _baslik = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/threat/auth/${Uri.encodeComponent(widget.kuyrukId)}'));
      if (mounted) setState(() => _v = v);
    } catch (_) {}
  }

  Color _ton(String v) => switch (v) {
    'pass' => Marka.zumrut,
    'fail' || 'softfail' || 'permerror' => Marka.gul,
    _ => const Color(0xFF94A3B8),
  };

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null || v['auth'] is! Map) return const SizedBox.shrink();
    final a = harita(v['auth']);
    final r = context.r;
    final arc = metin(a['arc']);
    final dmarcPol = metin(a['dmarc_policy']);
    final tespitler = haritalar(v['detections']);
    final asn = tamsayi(a['asn']);
    final dkimAlanlari = metinler(a['dkim_domains']);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: BolumKarti(
        baslik: 'Gönderen doğrulaması',
        ikon: Simgeler.verifiedUser,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Rozet('SPF ${metin(a['spf'])}', renk: _ton(metin(a['spf']))),
                Rozet('DKIM ${metin(a['dkim'])}', renk: _ton(metin(a['dkim']))),
                Rozet(
                  'DMARC ${metin(a['dmarc'])}${dmarcPol.isNotEmpty ? ' (p=$dmarcPol, uygulanan ${metin(a['disposition'])})' : ''}',
                  renk: _ton(metin(a['dmarc'])),
                ),
                if (arc == 'not_checked')
                  const Rozet('ARC denetlenmedi', renk: Color(0xFF94A3B8))
                else
                  Rozet('ARC $arc${mantik(a['arc_override']) ? ' · DMARC geçersiz kılındı (güvenilir iletici)' : ''}', renk: _ton(arc)),
                if (asn > 0) Rozet('AS$asn ${metin(a['as_name'])}', renk: Marka.mavi),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'From: ${metinYa(a['header_from']) ?? '—'} · Zarf/HELO: ${metinYa(a['spf_domain']) ?? '—'}'
              '${dkimAlanlari.isEmpty ? '' : ' · DKIM: ${dkimAlanlari.join(', ')}'}',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
            if (metin(a['arc_sealer']).isNotEmpty || metin(a['arc_detail']).isNotEmpty)
              Text(
                [if (metin(a['arc_sealer']).isNotEmpty) 'Son mühürleyen: ${metin(a['arc_sealer'])}', metin(a['arc_detail'])].where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(color: r.silik, fontSize: 12),
              ),
            if (tespitler.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final d in tespitler)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: metin(d['rule']), style: const TextStyle(fontFamily: 'monospace')),
                        TextSpan(text: ' (+${ondalik(d['score']).toStringAsFixed(1)}): ${metin(d['detail'])}'),
                      ],
                    ),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
            if (metin(a['header']).isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _baslik = !_baslik),
                  child: Text(_baslik ? 'Authentication-Results başlığını gizle' : 'Authentication-Results başlığı'),
                ),
              ),
              if (_baslik) KopyaKutusu(metin(a['header'])),
            ],
          ],
        ),
      ),
    );
  }
}

const _hukumEtiketleri = {'clean': 'Temiz', 'suspicious': 'Şüpheli', 'malicious': 'Zararlı'};
const _ekEylemleri = {'delivered': 'Teslim edildi', 'quarantined': 'Karantinada', 'rejected': 'Reddedildi'};

Color _hukumRengi(String v) => switch (v) {
  'malicious' => Marka.gul,
  'suspicious' => Marka.kehribar,
  _ => Marka.zumrut,
};

/// Gelen iletinin eklerinin statik analiz raporları (GET /attachment-reports?queue_id=); yoksa gizli.
class _EkAnaliziKarti extends StatefulWidget {
  const _EkAnaliziKarti(this.kuyrukId);
  final String kuyrukId;
  @override
  State<_EkAnaliziKarti> createState() => _EkAnaliziKartiState();
}

class _EkAnaliziKartiState extends State<_EkAnaliziKarti> {
  List<Map<String, dynamic>> _l = const [];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/attachment-reports', q: {'queue_id': widget.kuyrukId, 'page_size': '50'}));
      if (mounted) setState(() => _l = haritalar(v['items']));
    } catch (_) {}
  }

  void _ayrinti(Map<String, dynamic> x) {
    final bulgular = haritalar(x['findings']);
    final qr = metinler(x['qr_urls']);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(metinYa(x['filename']) ?? '(adsız)', style: gosterim(18, agirlik: FontWeight.w600)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    Rozet(_hukumEtiketleri[metin(x['verdict'])] ?? metin(x['verdict']), renk: _hukumRengi(metin(x['verdict']))),
                    Rozet('Puan ${ondalik(x['score']).toStringAsFixed(1)}', renk: Marka.mavi),
                  ],
                ),
                const SizedBox(height: 8),
                BilgiSatiri('Zaman', tamZaman(tarihOku(x['at']))),
                BilgiSatiri('Boyut', boyutYaz(tamsayi(x['size_bytes']))),
                BilgiSatiri('Bildirilen tür', metin(x['declared_type'])),
                BilgiSatiri('Algılanan tür', metin(x['detected_type'])),
                BilgiSatiri('İçerik türü', metin(x['content_type'])),
                BilgiSatiri('SHA-256', metin(x['sha256']), mono: true, kopyalanabilir: true),
                BilgiSatiri('Sonuç', _ekEylemleri[metin(x['action'])] ?? metin(x['action'])),
                if (metin(x['engine']).isNotEmpty) BilgiSatiri('Motor', metin(x['engine'])),
                if (bulgular.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Bulgular', style: TextStyle(fontWeight: FontWeight.w600)),
                  for (final b in bulgular)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${metin(b['rule'])} (+${ondalik(b['score']).toStringAsFixed(1)}): ${metin(b['detail'])}', style: const TextStyle(fontSize: 12.5)),
                    ),
                ],
                if (qr.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('QR bağlantıları', style: TextStyle(fontWeight: FontWeight.w600)),
                  for (final u in qr) SelectableText(u, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_l.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: BolumKarti(
        baslik: 'Ek analizi',
        ikon: Simgeler.findInPage,
        altBaslik: 'Statik derin analiz sonuçları (eklerin hiçbiri çalıştırılmaz).',
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final x in _l)
              ListTile(
                dense: true,
                onTap: () => _ayrinti(x),
                title: Text(metinYa(x['filename']) ?? '(adsız)', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(haritalar(x['findings']).map((b) => metin(b['detail'])).firstOrNull ?? 'Bulgu yok', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Rozet(_hukumEtiketleri[metin(x['verdict'])] ?? metin(x['verdict']), renk: _hukumRengi(metin(x['verdict']))),
              ),
          ],
        ),
      ),
    );
  }
}
