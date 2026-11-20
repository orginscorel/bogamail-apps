import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import 'bolumler.dart';
import 'trafik_ortak.dart';

const _sira = {'fail': 0, 'warn': 1, 'unknown': 2, 'unchecked': 3, 'info': 4, 'ok': 5};

bool _sorun(String d) => d == 'fail' || d == 'warn' || d == 'unknown';

/// Monitor denetimi (types.ts MonCheck).
class _Denetim {
  const _Denetim(this.m);
  final Map<String, dynamic> m;
  String get id => metin(m['id']);
  String get etiket => metin(m['label']);
  String get durum => metin(m['status'], 'unknown');
  String get ayrinti => metin(m['detail']);
  String get neden => metin(m['cause']);
  String get cozum => metin(m['fix']);
  DateTime? get denetlenme => tarihOku(m['checked_at']);
  DateTime? get degisme => tarihOku(m['changed_at']);
}

class _Alan {
  const _Alan(this.m);
  final Map<String, dynamic> m;
  String get id => metin(m['id']);
  String get ad => metin(m['name']);
  String get kip => metin(m['mode']);
  String get durum => metin(m['status']);
  String get musteri => metin(m['organization_name']);
  String get enKotu => metin(m['worst'], 'unchecked');
  int get sorunlar => tamsayi(m['problems']);
  DateTime? get denetlenme => tarihOku(m['checked_at']);
  List<_Denetim> get denetimler => haritalar(m['checks']).map(_Denetim.new).toList()..sort((a, b) => (_sira[a.durum] ?? 9) - (_sira[b.durum] ?? 9));
}

/// Teslimat Sorunları: alan adlarının MX/SPF/DKIM/DMARC/gateway/kara liste denetimleri, nedeni ve çözümü
/// (GET /monitor/issues; POST /monitor/domains/{id}/run; GET /monitor/domains/{id}/history; süper yönetici: POST /monitor/run,
/// GET/PUT /monitor/settings).
class TeslimatSorunlariEkrani extends StatefulWidget {
  const TeslimatSorunlariEkrani({super.key});
  @override
  State<TeslimatSorunlariEkrani> createState() => _TeslimatSorunlariEkraniState();
}

class _TeslimatSorunlariEkraniState extends State<TeslimatSorunlariEkrani> {
  final _anahtar = GlobalKey<TekYuklemeState<Map<String, dynamic>>>();
  Timer? _zamanlayici;
  String _q = '';
  bool _tumu = false;
  int _gosterilen = 20;
  bool _basliyor = false;

  @override
  void initState() {
    super.initState();
    _zamanlayici = Timer.periodic(const Duration(seconds: 60), (_) => _yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  Future<void> _yenile() async => _anahtar.currentState?.yenile();

  Future<void> _tumunuDenetle() async {
    setState(() => _basliyor = true);
    final r = await islem(() => Uyg.api.post('/api/v1/monitor/run'), tamam: 'Tam tarama başlatıldı; sonuçlar birkaç dakika içinde gelir');
    if (mounted) setState(() => _basliyor = false);
    if (r != null) Timer(const Duration(seconds: 15), () => _anahtar.currentState?.yenile());
  }

  void _gecmis(_Alan d) => showDialog<void>(context: context, builder: (_) => _GecmisDialog(alan: d));

  void _ayarlar() => showDialog<void>(context: context, builder: (_) => const _AyarlarDialog());

  @override
  Widget build(BuildContext context) {
    final suser = Uyg.platformYoneticisi;
    return Iskelet(
      baslik: 'Teslimat Sorunları',
      alt: 'MX, SPF, DKIM, DMARC, gateway hedefi ve kara liste denetimleri',
      yenile: _yenile,
      eylemler: [if (suser) IconButton(tooltip: 'Monitor ayarları', onPressed: _ayarlar, icon: const Icon(Icons.tune_rounded))],
      birincil: suser ? BirincilEylem(Icons.refresh_rounded, _basliyor ? 'Başlatılıyor…' : 'Tümünü denetle', _basliyor ? () {} : _tumunuDenetle) : null,
      govde: TekYukleme<Map<String, dynamic>>(
        key: _anahtar,
        getir: () async => harita(await Uyg.api.get('/api/v1/monitor/issues')),
        icerik: (c, v, yenile) => _icerik(c, v, yenile),
      ),
    );
  }

  Widget _icerik(BuildContext context, Map<String, dynamic> v, Future<void> Function() yenile) {
    final r = context.r;
    final tum = haritalar(v['domains']).map(_Alan.new).toList();
    final platform = haritalar(v['platform']).map(_Denetim.new).toList();
    final ayar = harita(v['settings']);
    final son = harita(v['last_run']);
    final say = {'fail': 0, 'warn': 0, 'unknown': 0, 'ok': 0};
    for (final d in tum) {
      final w = d.enKotu;
      if (w == 'fail' || w == 'warn') {
        say[w] = say[w]! + 1;
      } else if (w == 'unknown' || w == 'unchecked') {
        say['unknown'] = say['unknown']! + 1;
      } else {
        say['ok'] = say['ok']! + 1;
      }
    }
    final q = _q.toLowerCase();
    final liste =
        tum.where((d) => (_tumu || d.sorunlar > 0 || d.enKotu == 'unchecked') && (q.isEmpty || d.ad.contains(q) || d.musteri.toLowerCase().contains(q))).toList()
          ..sort((a, b) {
            final s = (_sira[a.enKotu] ?? 9) - (_sira[b.enKotu] ?? 9);
            return s != 0 ? s : a.ad.compareTo(b.ad);
          });
    final sonBas = tarihOku(son['started_at']);
    final denetler = Uyg.yetki('domains.manage');
    return IcerikListesi(
      children: [
        const SizedBox(height: 4),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final t in [
              'Son tarama: ${sonBas == null ? 'henüz yok' : '${goreliZaman(sonBas)}${son['finished_at'] == null ? ' (sürüyor)' : ''}'}',
              mantik(ayar['enabled']) ? 'her ${tamsayi(ayar['interval_minutes'])} dakikada bir' : 'düzenli denetim kapalı',
              'alan adı kara listesi: ${mantik(ayar['dbl_enabled']) ? 'açık' : 'kapalı'}',
            ])
              Text(t, style: TextStyle(color: r.silik, fontSize: 12.5)),
          ],
        ),
        const SizedBox(height: 12),
        Izgara(
          enAz: 200,
          children: [
            for (final (k, e) in const [('fail', 'Sorunlu'), ('warn', 'Uyarılı'), ('unknown', 'Belirsiz / denetlenmedi'), ('ok', 'Sorunsuz')])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(14), border: Border.all(color: r.kenar)),
                child: Row(
                  children: [
                    DurumNoktasi(izlemeRengi(k), boyut: 10),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 13))),
                    Text('${say[k]}', style: gosterim(22, agirlik: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ),
        if (platform.isNotEmpty) ...[
          const SizedBox(height: 14),
          BolumKarti(
            baslik: 'Platform',
            ikon: Icons.dns_outlined,
            altBaslik: Uyg.platformYoneticisi
                ? 'Kendi TLS sertifikamız, gönderim IP\'lerinin kara liste durumu ve giden 25 numaralı port.'
                : 'Giden 25 numaralı portun durumu (gateway sonuçlarını etkiler).',
            child: Column(
              children: [
                for (final (i, c) in platform.indexed) ...[if (i > 0) Divider(height: 1, color: r.kenar), _DenetimSatiri(c)],
              ],
            ),
          ),
        ],
        AltBaslik('Alan adları'),
        LayoutBuilder(
          builder: (c, k) {
            final dar = k.maxWidth < 600;
            final secim = SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: false, label: Text('Sorunlu')), ButtonSegment(value: true, label: Text('Tümü'))],
              selected: {_tumu},
              onSelectionChanged: (s) => setState(() {
                _tumu = s.first;
                _gosterilen = 20;
              }),
            );
            final arama = AramaAlani(
              ipucu: 'Alan adı veya müşteri ara…',
              ilk: _q,
              degisti: (v) => setState(() {
                _q = v;
                _gosterilen = 20;
              }),
            );
            if (dar) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [secim, const SizedBox(height: 8), arama]);
            return Row(children: [secim, const SizedBox(width: 12), Expanded(child: arama)]);
          },
        ),
        const SizedBox(height: 10),
        if (liste.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Durum.bos(
              tum.isEmpty
                  ? 'Alan adı yok. Alan adı eklendiğinde burada denetlenir.'
                  : 'Sorun bulunmadı. Tüm alan adlarının denetimleri sorunsuz; tümünü görmek için "Tümü"ne basın.',
              ikon: Icons.verified_user_outlined,
            ),
          )
        else ...[
          for (final d in liste.take(_gosterilen))
            _AlanKarti(key: ValueKey(d.id), d: d, ortak: Uyg.ortak, denetler: denetler, denetlendi: yenile, gecmis: () => _gecmis(d)),
          if (liste.length > _gosterilen)
            Center(
              child: TextButton(onPressed: () => setState(() => _gosterilen += 20), child: Text('Daha fazla göster (${liste.length - _gosterilen} kaldı)')),
            ),
        ],
        const SizedBox(height: 14),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text('Alan adı güvenlik puanı ve DMARC raporları için', style: TextStyle(color: r.silik, fontSize: 12.5)),
            TextButton(
              onPressed: () => bolumeGit(Uyg.musteri ? Bolum.itibarMerkezim : Bolum.itibar),
              child: Text(Uyg.musteri ? 'İtibar Merkezim' : 'İtibar'),
            ),
            Text(', geri dönme nedenleri için', style: TextStyle(color: r.silik, fontSize: 12.5)),
            TextButton(onPressed: () => bolumeGit(Bolum.teslimTeshisi), child: const Text('Teslim Teşhisi')),
          ],
        ),
        Text(
          'Durumlar: ${['fail', 'warn', 'unknown', 'ok', 'info'].map(izlemeEtiketi).join(' · ')}. "Belirsiz" ölçülemeyen sonuçlardır (DNS hatası, '
          '25 numaralı port çıkışı engelli olabilir); hiçbir zaman sorunsuz sayılmaz.',
          style: TextStyle(color: r.silik, fontSize: 12),
        ),
      ],
    );
  }
}

class _DenetimSatiri extends StatelessWidget {
  const _DenetimSatiri(this.c);
  final _Denetim c;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final sorun = _sorun(c.durum);
    final degisti = c.degisme != null && c.denetlenme != null && c.degisme != c.denetlenme && sorun;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 5), child: DurumNoktasi(izlemeRengi(c.durum))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(c.etiket, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    IzlemeRozeti(c.durum),
                    if (degisti) Text('değişti: ${goreliZaman(c.degisme)}', style: TextStyle(color: r.silik, fontSize: 11.5)),
                  ],
                ),
                if (c.ayrinti.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(c.ayrinti, style: TextStyle(color: r.soluk, fontSize: 12.5))),
                if (sorun && c.neden.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.neden, style: const TextStyle(fontSize: 13.5))),
                if (sorun && c.cozum.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lightbulb_outline_rounded, size: 15, color: Marka.kehribar),
                        const SizedBox(width: 6),
                        Expanded(child: Text(c.cozum, style: const TextStyle(fontSize: 12.5))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlanKarti extends StatefulWidget {
  const _AlanKarti({super.key, required this.d, required this.ortak, required this.denetler, required this.denetlendi, required this.gecmis});
  final _Alan d;
  final bool ortak, denetler;
  final Future<void> Function() denetlendi;
  final VoidCallback gecmis;
  @override
  State<_AlanKarti> createState() => _AlanKartiState();
}

class _AlanKartiState extends State<_AlanKarti> {
  late bool _acik = widget.d.enKotu == 'fail' || widget.d.enKotu == 'warn';
  bool _mesgul = false;

  Future<void> _denetle() async {
    setState(() => _mesgul = true);
    final r = await islem(() => Uyg.api.post('/api/v1/monitor/domains/${widget.d.id}/run'), tamam: '${widget.d.ad} denetlendi');
    if (mounted) setState(() => _mesgul = false);
    if (r != null) await widget.denetlendi();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = widget.d;
    final denetimler = d.denetimler;
    final sorunlar = denetimler.where((c) => _sorun(c.durum)).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(14), border: Border.all(color: r.kenar)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _acik = !_acik),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  DurumNoktasi(izlemeRengi(d.enKotu), boyut: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          [
                            d.kip == 'gateway' ? 'Gateway' : 'Barındırma',
                            if (widget.ortak && d.musteri.isNotEmpty) d.musteri,
                            d.denetlenme != null ? '${goreliZaman(d.denetlenme)} denetlendi' : 'henüz denetlenmedi',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: r.silik, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (sorunlar > 0) Rozet('$sorunlar sorun', renk: d.enKotu == 'fail' ? Marka.gul : Marka.kehribar) else IzlemeRozeti(d.enKotu),
                  Icon(_acik ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: r.soluk),
                ],
              ),
            ),
          ),
          if (_acik) ...[
            Divider(height: 1, color: r.kenar),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (denetimler.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Bu alan adı için henüz sonuç yok. Bir sonraki taramada veya "Şimdi denetle" ile denetlenir.',
                        style: TextStyle(color: r.soluk, fontSize: 13),
                      ),
                    )
                  else
                    for (final (i, c) in denetimler.indexed) ...[if (i > 0) Divider(height: 1, color: r.kenar), _DenetimSatiri(c)],
                  Wrap(
                    spacing: 8,
                    children: [
                      if (widget.denetler && d.durum != 'suspended')
                        OutlinedButton.icon(
                          onPressed: _mesgul ? null : _denetle,
                          icon: _mesgul
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Şimdi denetle'),
                        ),
                      TextButton.icon(onPressed: widget.gecmis, icon: const Icon(Icons.history_rounded, size: 18), label: const Text('Geçmiş')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Son 30 günde durumu değişen denetimler (GET /monitor/domains/{id}/history).
class _GecmisDialog extends StatelessWidget {
  const _GecmisDialog({required this.alan});
  final _Alan alan;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(alan.ad, style: gosterim(19, agirlik: FontWeight.w700)),
    contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    content: SizedBox(
      width: 560,
      height: 460,
      child: TekYukleme<List<Map<String, dynamic>>>(
        getir: () async => haritalar(harita(await Uyg.api.get('/api/v1/monitor/domains/${alan.id}/history'))['items']),
        icerik: (c, l, _) {
          final r = c.r;
          if (l.isEmpty) return ListView(children: [Padding(padding: const EdgeInsets.all(16), child: Text('Kayıt yok.', style: TextStyle(color: r.soluk)))]);
          return ListView(
            children: [
              Text('Son 30 günde durumu değişen denetimler (ilk gözlem dahil).', style: TextStyle(color: r.silik, fontSize: 12.5)),
              const SizedBox(height: 8),
              for (final e in l)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(border: Border.all(color: r.kenar), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(metin(e['label']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          if (metinYa(e['prev_status']) != null) IzlemeRozeti(metin(e['prev_status'])) else Text('ilk', style: TextStyle(color: r.silik, fontSize: 12)),
                          Text('→', style: TextStyle(color: r.silik)),
                          IzlemeRozeti(metin(e['status'])),
                          Text(tamZaman(tarihOku(e['at'])), style: TextStyle(color: r.silik, fontSize: 12)),
                        ],
                      ),
                      if (metin(e['detail']).isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text(metin(e['detail']), style: TextStyle(color: r.soluk, fontSize: 12.5))),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
  );
}

/// Monitor ayarları (süper yönetici): GET/PUT /monitor/settings {enabled, interval_minutes, smtp_timeout_seconds, dbl_zones}.
class _AyarlarDialog extends StatefulWidget {
  const _AyarlarDialog();
  @override
  State<_AyarlarDialog> createState() => _AyarlarDialogState();
}

class _AyarlarDialogState extends State<_AyarlarDialog> {
  final _aralik = TextEditingController(), _zaman = TextEditingController(), _bolgeler = TextEditingController();
  bool _acik = true, _yuklendi = false, _mesgul = false;
  String? _hata, _hataAlani;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/monitor/settings'));
      if (!mounted) return;
      setState(() {
        _acik = mantik(v['enabled'], true);
        _aralik.text = '${tamsayi(v['interval_minutes'], 30)}';
        _zaman.text = '${tamsayi(v['smtp_timeout_seconds'], 10)}';
        _bolgeler.text = metinler(v['dbl_zones']).join(', ');
        _yuklendi = true;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  @override
  void dispose() {
    _aralik.dispose();
    _zaman.dispose();
    _bolgeler.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final a = int.tryParse(_aralik.text.trim()), z = int.tryParse(_zaman.text.trim());
    if (a == null || a < 5 || a > 1440) return _hataYaz('interval_minutes', '5–1440 dakika olmalı');
    if (z == null || z < 2 || z > 30) return _hataYaz('smtp_timeout_seconds', '2–30 saniye olmalı');
    setState(() {
      _mesgul = true;
      _hata = _hataAlani = null;
    });
    try {
      final bolgeler = _bolgeler.text.split(RegExp(r'[\s,]+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      await Uyg.api.put('/api/v1/monitor/settings', {'enabled': _acik, 'interval_minutes': a, 'smtp_timeout_seconds': z, 'dbl_zones': bolgeler});
      bildir('Kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context);
    } on ApiHata catch (e) {
      if (mounted) _hataYaz(e.alan, e.mesaj);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  void _hataYaz(String? alan, String mesaj) => setState(() {
    _hataAlani = alan;
    _hata = mesaj;
  });

  String? _alanHatasi(String a) => _hataAlani == a ? _hata : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Monitor ayarları', style: gosterim(19, agirlik: FontWeight.w700)),
    content: SizedBox(
      width: 460,
      child: !_yuklendi
          ? (_hata != null ? Text(_hata!, style: const TextStyle(color: Marka.gul)) : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Denetimler yalnızca bağlanır, EHLO/STARTTLS yapar ve çıkar; asla posta göndermez. Özel/iç ağ adreslerine bağlanılmaz.',
                    style: TextStyle(color: context.r.soluk, fontSize: 13),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Düzenli denetim açık'),
                    value: _acik,
                    onChanged: (v) => setState(() => _acik = v),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _aralik,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: 'Aralık (dakika)', errorText: _alanHatasi('interval_minutes')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _zaman,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: 'SMTP zaman aşımı (sn)', errorText: _alanHatasi('smtp_timeout_seconds')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bolgeler,
                    decoration: InputDecoration(
                      labelText: 'Alan adı kara listeleri (DBL bölgeleri)',
                      hintText: 'ör. dbl.spamhaus.org (boş = kapalı)',
                      helperText: 'Varsayılan kapalı. Bazı listeler ticari kullanım ve genel DNS çözücüler için sorgu kabul etmez.',
                      helperMaxLines: 3,
                      errorText: _alanHatasi('dbl_zones'),
                    ),
                  ),
                  if (_hata != null && _hataAlani == null)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13))),
                ],
              ),
            ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(onPressed: _mesgul || !_yuklendi ? null : _kaydet, child: const Text('Kaydet')),
    ],
  );
}
