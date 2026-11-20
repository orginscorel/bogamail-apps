import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/operasyon.dart';

/// Karantina (GET /quarantine): virüs / engellenen ek / spam nedeniyle tutulan iletiler.
class KarantinaEkrani extends StatefulWidget {
  const KarantinaEkrani({super.key});
  @override
  State<KarantinaEkrani> createState() => _KarantinaEkraniState();
}

class _KarantinaEkraniState extends State<KarantinaEkrani> {
  String _durum = 'held', _neden = '', _q = '';
  List<KarantinaOgesi>? _liste;
  Map<String, dynamic> _ozet = {}, _tarayici = {};
  String? _hata;
  KarantinaOgesi? _secili;
  int _nesil = 0;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final n = ++_nesil;
    try {
      final v = harita(await Uyg.api.get('/api/v1/quarantine', q: {'status': _durum, if (_neden.isNotEmpty) 'reason': _neden, if (_q.isNotEmpty) 'q': _q}));
      if (!mounted || n != _nesil) return;
      setState(() {
        _liste = haritalar(v['items']).map(KarantinaOgesi.coz).toList();
        _ozet = harita(v['summary']);
        _tarayici = harita(v['scanner']);
        _hata = null;
      });
    } catch (e) {
      if (mounted && n == _nesil) setState(() => _hata = hataMetni(e));
    }
  }

  void _filtre(void Function() f) {
    setState(() {
      f();
      _liste = null;
    });
    _yukle();
  }

  void _ac(KarantinaOgesi k) {
    if (bolunmus(context)) {
      setState(() => _secili = k);
    } else {
      sayfaAc(context, 'Karantina', KarantinaDetay(oge: k, degisti: _degisti, tamSayfa: true));
    }
  }

  void _degisti() {
    setState(() => _secili = null);
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = _liste;
    final tarayiciKapali = _tarayici.isNotEmpty && !mantik(_tarayici['configured'], true);
    final ust = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tarayiciKapali)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Bant('Virüs tarayıcısı yapılandırılmamış; yalnızca ek ve spam kuralları uygulanıyor.', renk: Marka.kehribar),
          ),
        if (_ozet.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Rozet('${tamsayi(_ozet['held'])} bekliyor', renk: Marka.mor),
                Rozet('Son 7 gün: ${tamsayi(_ozet['virus_7d'])} virüs', renk: tamsayi(_ozet['virus_7d']) > 0 ? Marka.gul : r.silik),
                Rozet('${tamsayi(_ozet['blocked_7d'])} engellenen ek', renk: r.silik),
              ],
            ),
          ),
        AramaAlani(ipucu: 'Konu, gönderen veya alıcı…', degisti: (v) => _filtre(() => _q = v)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (d, e) in const [('held', 'Bekleyen'), ('released', 'Serbest bırakılan'), ('deleted', 'Silinen'), ('all', 'Tümü')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(e), selected: _durum == d, showCheckmark: false, onSelected: (_) => _filtre(() => _durum = d)),
                ),
              const SizedBox(width: 8),
              for (final (d, e) in [('', 'Tüm nedenler'), ...karantinaNedenleri.entries.map((x) => (x.key, x.value))])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(e), selected: _neden == d, showCheckmark: false, onSelected: (_) => _filtre(() => _neden = d)),
                ),
            ],
          ),
        ),
      ],
    );
    Widget govde;
    if (_hata != null && l == null) {
      govde = ListView(
        children: [SizedBox(height: 320, child: Durum.hata(_hata!, tekrar: _yukle))],
      );
    } else if (l == null) {
      govde = const Durum.yukleniyor();
    } else if (l.isEmpty) {
      govde = ListView(
        children: [SizedBox(height: 320, child: Durum.bos(_durum == 'held' ? 'Karantinada bekleyen ileti yok.' : 'Kayıt yok.', ikon: Icons.shield_outlined))],
      );
    } else {
      govde = ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: l.length,
        itemBuilder: (c, i) {
          final k = l[i];
          return ListeSatiri(
            secili: _secili?.id == k.id && bolunmus(c),
            onTap: () => _ac(k),
            sol: KarantinaIkonu(k.neden),
            baslik: k.konu.isEmpty ? '(konu yok)' : k.konu,
            alt: k.kimden.isNotEmpty ? k.kimden : k.zarfGonderen,
            alt2: [
              karantinaNedenleri[k.neden] ?? k.neden,
              if (k.bulgular.isNotEmpty) k.bulgular.first.ad,
              if (!Uyg.musteri && k.orgAdi != null) k.orgAdi!,
            ].join(' · '),
            sag: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (k.durum != 'held') Rozet(karantinaDurumlari[k.durum] ?? k.durum, renk: k.durum == 'released' ? Marka.zumrut : r.silik),
                Text(goreliZaman(k.olusturma), style: TextStyle(color: r.silik, fontSize: 11.5)),
              ],
            ),
          );
        },
      );
    }
    final liste = Column(
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 6), child: ust),
        Expanded(
          child: RefreshIndicator.adaptive(onRefresh: _yukle, child: govde),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Karantina'),
        actions: [IconButton(tooltip: 'Yenile', onPressed: _yukle, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: AnaDetay(
        liste: liste,
        detay: _secili == null ? null : KarantinaDetay(key: ValueKey(_secili!.id), oge: _secili!, degisti: _degisti),
        bosMetin: 'İçerik ve bulgular için bir ileti seçin',
      ),
    );
  }
}

class KarantinaIkonu extends StatelessWidget {
  const KarantinaIkonu(this.neden, {super.key});
  final String neden;
  @override
  Widget build(BuildContext context) {
    final (ikon, renk) = switch (neden) {
      'virus' => (Icons.coronavirus_rounded, Marka.gul),
      'blocked_attachment' => (Icons.attach_file_rounded, Marka.kehribar),
      _ => (Icons.report_rounded, Marka.mor),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
      child: Icon(ikon, color: renk, size: 20),
    );
  }
}

/// Karantina ayrıntısı (GET /quarantine/{id}: her görüntüleme denetim kaydına yazılır), serbest bırakma ve silme.
class KarantinaDetay extends StatefulWidget {
  const KarantinaDetay({super.key, required this.oge, required this.degisti, this.tamSayfa = false});
  final KarantinaOgesi oge;
  final VoidCallback degisti;
  final bool tamSayfa;
  @override
  State<KarantinaDetay> createState() => _KarantinaDetayState();
}

class _KarantinaDetayState extends State<KarantinaDetay> {
  late KarantinaOgesi _k = widget.oge;
  Map<String, dynamic>? _gorunum;
  String? _hata;
  bool _yukleniyor = false;

  /// İçerik yalnızca istenince açılır: her görüntüleme sunucuda denetim kaydına yazılır.
  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      final v = harita(await Uyg.api.get('/api/v1/quarantine/${_k.id}'));
      if (!mounted) return;
      setState(() {
        if (v['item'] is Map) _k = KarantinaOgesi.coz(harita(v['item']));
        _gorunum = v['view'] is Map ? harita(v['view']) : {};
        _hata = null;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _yenile() async {
    if (_gorunum != null) await _yukle();
  }

  bool get _yetkili => Uyg.yetki('quarantine.release');
  bool get _serbestBirakabilir => _yetkili && (_k.neden != 'virus' || Uyg.platformYoneticisi);

  Future<void> _serbest() async {
    final virus = _k.neden == 'virus';
    if (virus) {
      final ok = await yazarakOnayla(
        context,
        baslik: 'Virüslü ileti teslim edilsin mi?',
        mesaj: 'Bu iletide zararlı yazılım bulundu. Serbest bırakılırsa alıcılara olduğu gibi teslim edilir. Bu karar denetim kaydına yazılır.',
        beklenen: 'TESLİM ET',
        evet: 'Serbest bırak',
      );
      if (!ok) return;
    } else if (!await onayla(context, 'İleti serbest bırakılsın mı?', mesaj: 'İleti alıcılarına teslim edilir.', evet: 'Serbest bırak')) {
      return;
    }
    final v = await islem(() => Uyg.api.post('/api/v1/quarantine/${_k.id}/release').then((_) => true), tamam: 'İleti serbest bırakıldı');
    if (v != null) _bitti();
  }

  Future<void> _sil() async {
    if (!await onayla(context, 'İleti silinsin mi?', mesaj: 'İleti karantinadan kalıcı olarak silinir ve teslim edilmez.', evet: 'Sil', tehlikeli: true)) {
      return;
    }
    final v = await islem(() => Uyg.api.delete('/api/v1/quarantine/${_k.id}').then((_) => true), tamam: 'İleti silindi');
    if (v != null) _bitti();
  }

  void _bitti() {
    widget.degisti();
    if (widget.tamSayfa && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final k = _k;
    final g = _gorunum;
    final metinGovde = g == null ? '' : (metin(g['text']).trim().isNotEmpty ? metin(g['text']) : htmldenMetin(metin(g['html'])));
    final kimden = haritalar(g?['from']).map((f) => metinYa(f['name']) == null ? metin(f['email']) : '${metin(f['name'])} <${metin(f['email'])}>').join(', ');
    final ekler = haritalar(g?['attachments']);
    return RefreshIndicator.adaptive(
      onRefresh: _yenile,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    KarantinaIkonu(k.neden),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(karantinaNedenleri[k.neden] ?? k.neden, style: gosterim(16, agirlik: FontWeight.w700)),
                          Text(karantinaDurumlari[k.durum] ?? k.durum, style: TextStyle(color: r.silik, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                BilgiSatiri('Konu', k.konu.isEmpty ? '(konu yok)' : k.konu),
                BilgiSatiri('Kimden', kimden.isNotEmpty ? kimden : (k.kimden.isEmpty ? '—' : k.kimden)),
                BilgiSatiri('Zarf göndereni', k.zarfGonderen.isEmpty ? '<>' : k.zarfGonderen),
                BilgiSatiri('Alıcılar', k.alicilar.isEmpty ? '—' : k.alicilar.join('\n')),
                if (k.orgAdi != null && !Uyg.musteri) BilgiSatiri('Müşteri', k.orgAdi!),
                BilgiSatiri('Yön', k.yon == 'outbound' ? 'Giden' : 'Gelen'),
                BilgiSatiri('Boyut', boyutYaz(k.boyut)),
                if (k.spamPuani != null) BilgiSatiri('Spam puanı', k.spamPuani!.toStringAsFixed(1).replaceAll('.', ',')),
                BilgiSatiri('Karantinaya alındı', tamZaman(k.olusturma)),
                if (k.durum == 'held' && k.bitis != null) BilgiSatiri('Otomatik silinme', tamZaman(k.bitis)),
                if (k.kararZamani != null) BilgiSatiri('Karar', '${tamZaman(k.kararZamani)}${k.kararVeren != null ? ' · ${k.kararVeren}' : ''}'),
                BilgiSatiri('Kuyruk kimliği', k.kuyrukKimligi, mono: true, kopyalanabilir: true),
              ],
            ),
          ),
          if (k.bulgular.isNotEmpty) ...[
            const Baslik('Bulgular'),
            Kutu(
              child: Column(
                children: [
                  for (final b in k.bulgular)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            k.neden == 'virus' ? Icons.coronavirus_outlined : Icons.warning_amber_rounded,
                            size: 18,
                            color: k.neden == 'virus' ? Marka.gul : Marka.kehribar,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.ad.isEmpty ? b.tur : b.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (b.dosya.isNotEmpty) Text(b.dosya, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                if (b.ayrinti.isNotEmpty) Text(b.ayrinti, style: TextStyle(color: r.silik, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (k.durum == 'held' && _yetkili) ...[
            const Baslik('İşlemler'),
            if (_serbestBirakabilir) ...[
              EylemSatiri(ikon: Icons.mark_email_read_rounded, baslik: 'Serbest bırak', ipucu: 'Alıcılara teslim et', onTap: _serbest),
              const SizedBox(height: 8),
            ] else
              const Padding(padding: EdgeInsets.only(bottom: 8), child: Bant('Virüslü iletiyi yalnızca platform yöneticisi serbest bırakabilir.')),
            EylemSatiri(ikon: Icons.delete_outline_rounded, baslik: 'Sil', ipucu: 'Teslim etmeden kalıcı olarak sil', tehlikeli: true, onTap: _sil),
          ],
          const Baslik('İçerik'),
          if (_hata != null)
            Bant(
              _hata!,
              renk: Marka.gul,
              ikon: Icons.error_outline_rounded,
              eylem: TextButton(onPressed: _yukle, child: const Text('Tekrar dene')),
            )
          else if (g == null)
            Kutu(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'İleti içeriği güvenlik nedeniyle gizli. Açtığınızda görüntüleme denetim kaydına yazılır.',
                    style: TextStyle(color: r.soluk, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _yukleniyor ? null : _yukle,
                      icon: _yukleniyor
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.visibility_rounded, size: 18),
                      label: const Text('İçeriği göster'),
                    ),
                  ),
                ],
              ),
            )
          else
            Kutu(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Görüntüleme denetim kaydına yazılır. Bağlantılara ve eklere güvenmeyin.', style: TextStyle(color: r.silik, fontSize: 12)),
                  const Divider(height: 18),
                  if (metinGovde.trim().isEmpty)
                    Text('İletinin okunabilir metin gövdesi yok.', style: TextStyle(color: r.silik))
                  else
                    SelectableText(metinGovde.trim(), style: const TextStyle(fontSize: 13.5, height: 1.45)),
                  if (mantik(g['truncated']))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('… (kısaltıldı)', style: TextStyle(color: r.silik, fontSize: 12)),
                    ),
                  if (ekler.isNotEmpty) ...[
                    const Divider(height: 22),
                    Text(
                      'Ekler',
                      style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    for (final e in ekler)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Icon(Icons.attach_file_rounded, size: 17, color: r.silik),
                            const SizedBox(width: 6),
                            Expanded(child: Text(metin(e['filename'], '(adsız)'), overflow: TextOverflow.ellipsis)),
                            Text('${metin(e['content_type'])} · ${boyutYaz(tamsayi(e['size']))}', style: TextStyle(color: r.silik, fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
