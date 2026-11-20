import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/dosya.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'mesaj_takibi.dart';

const _geriDonusSiniri = 0.05;
const _sikayetSiniri = 0.001;

const _sekmeler = <(String, String)>[
  ('active', 'Etkin'),
  ('pending_approval', 'Onay bekleyenler'),
  ('sending', 'Gönderiliyor'),
  ('paused', 'Duraklatıldı'),
  ('completed', 'Tamamlandı'),
  ('cancelled', 'İptal / red'),
  ('all', 'Tümü'),
];

const _durumEtiketleri = {
  'draft': 'Taslak',
  'pending_approval': 'Onay bekliyor',
  'scheduled': 'Planlandı',
  'sending': 'Gönderiliyor',
  'paused': 'Duraklatıldı',
  'completed': 'Tamamlandı',
  'cancelled': 'İptal',
  'rejected': 'Reddedildi',
};

Color _durumRengi(String d) => switch (d) {
  'pending_approval' || 'paused' => Marka.kehribar,
  'scheduled' => Marka.mavi,
  'sending' => Marka.mor,
  'completed' => Marka.zumrut,
  'cancelled' || 'rejected' => Marka.gul,
  _ => const Color(0xFF94A3B8),
};

class _KampanyaDurumu extends StatelessWidget {
  const _KampanyaDurumu(this.durum);
  final String durum;
  @override
  Widget build(BuildContext context) => Rozet(_durumEtiketleri[durum] ?? durum, renk: _durumRengi(durum));
}

String _yuzde(int n, int d) {
  if (d == 0) return '0';
  final v = n * 100 / d;
  return (v < 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(0)).replaceAll('.', ',');
}

String _oranYaz(double v, int basamak) => (v * 100).toStringAsFixed(basamak).replaceAll('.', ',');

/// Yönetici kampanya satırı (campaigns_admin.go campAdminRow).
class _Kampanya {
  const _Kampanya(this.m);
  final Map<String, dynamic> m;
  factory _Kampanya.coz(Map<String, dynamic> m) => _Kampanya(m);

  String get id => metin(m['id']);
  String get ad => metin(m['name']);
  String get musteri => metin(m['organization_name']);
  String get gonderen => metin(m['from_address']);
  String get durum => metin(m['status']);
  String get tur => metin(m['kind']);
  String get gerekce => metinYa(m['status_reason']) ?? metin(m['wait_reason']);
  int get alici => tamsayi(m['total_recipients']);
  int get hiz => tamsayi(m['speed_per_hour']);
  DateTime? get gonderilme => tarihOku(m['submitted_at']);
  Map<String, dynamic> get istatistik => harita(m['stats']);
  bool get istatistikVar => m['stats'] is Map;
  double get geriDonus => ondalik(harita(m['rates'])['bounce']);
  double get sikayet => ondalik(harita(m['rates'])['complaint']);
  bool get riskli => geriDonus > _geriDonusSiniri || sikayet > _sikayetSiniri;
}

/// Toplu Gönderim İzleme (ortaklar): müşterilerin kampanyaları, onay kuyruğu, onayla / reddet / duraklat / devam / iptal
/// (GET/POST /admin/campaigns...), onay politikası (GET/PUT /admin/campaigns/policy, değiştirmek yalnızca süper yönetici).
class KampanyaIzlemeEkrani extends StatefulWidget {
  const KampanyaIzlemeEkrani({super.key});
  @override
  State<KampanyaIzlemeEkrani> createState() => _KampanyaIzlemeEkraniState();
}

class _KampanyaIzlemeEkraniState extends State<KampanyaIzlemeEkrani> {
  String _durum = 'active';
  String _q = '';
  int _onayBekleyen = 0;
  Timer? _zamanlayici;

  late final _y = SayfaYukleyici<_Kampanya>((s, b) async {
    final v = harita(
      await Uyg.api.get(
        '/api/v1/admin/campaigns',
        q: {'page': '$s', 'page_size': '$b', if (_durum != 'all') 'status': _durum, if (_q.isNotEmpty) 'q': _q},
      ),
    );
    final bekleyen = tamsayi(v['pending_approval']);
    if (bekleyen != _onayBekleyen && mounted) setState(() => _onayBekleyen = bekleyen);
    return Sayfa.coz(v, _Kampanya.coz);
  })..yenile();

  @override
  void initState() {
    super.initState();
    // Gönderilen ya da onay bekleyen kampanya varken 15 sn'de bir tazele (web ile aynı).
    _zamanlayici = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_y.yukleniyor && _y.ogeler.any((c) => c.durum == 'sending' || c.durum == 'pending_approval')) {
        _y.sayfaGit(_y.sayfa < 1 ? 1 : _y.sayfa);
      }
    });
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _y.dispose();
    super.dispose();
  }

  void _sekme(String v) {
    setState(() => _durum = v);
    _y.yenile();
  }

  Future<void> _basit(_Kampanya c, String eylem) async {
    await islem(
      () => Uyg.api.post('/api/v1/admin/campaigns/${c.id}/$eylem', <String, dynamic>{}),
      tamam: eylem == 'approve' ? 'Kampanya onaylandı' : 'Kampanya devam ediyor',
    );
    _y.yenile();
  }

  Future<void> _gerekceli(_Kampanya c, String eylem) async {
    final tamam = await showDialog<bool>(context: context, builder: (_) => _GerekceDialog(c: c, eylem: eylem));
    if (tamam == true) _y.yenile();
  }

  List<SatirEylemi> _eylemler(_Kampanya c) => [
    SatirEylemi(Icons.visibility_outlined, 'İçeriği önizle', () => _onizle(c)),
    SatirEylemi(Icons.bar_chart_rounded, 'Rapor', () => _rapor(c)),
    SatirEylemi(Icons.table_view_outlined, 'Raporu CSV olarak indir', () => kampanyaCsvIndir(c.id, c.ad)),
    if (c.durum == 'pending_approval') ...[
      SatirEylemi(Icons.check_circle_outline_rounded, 'Onayla', () => _basit(c, 'approve')),
      SatirEylemi(Icons.cancel_outlined, 'Reddet', () => _gerekceli(c, 'reject'), tehlikeli: true),
    ],
    if (c.durum == 'sending' || c.durum == 'scheduled') SatirEylemi(Icons.pause_rounded, 'Duraklat', () => _gerekceli(c, 'pause')),
    if (c.durum == 'paused') SatirEylemi(Icons.play_arrow_rounded, 'Devam ettir', () => _basit(c, 'resume')),
    if (const ['scheduled', 'sending', 'paused'].contains(c.durum)) SatirEylemi(Icons.block_rounded, 'İptal et', () => _gerekceli(c, 'cancel'), tehlikeli: true),
  ];

  void _rapor(_Kampanya c) {
    final govde = _KampanyaRaporu(id: c.id);
    if (context.genis) {
      showDialog<void>(
        context: context,
        builder: (d) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: Text(c.ad, overflow: TextOverflow.ellipsis),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(tooltip: 'CSV indir', onPressed: () => kampanyaCsvIndir(c.id, c.ad), icon: const Icon(Icons.download_rounded)),
                  IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(d), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              body: govde,
            ),
          ),
        ),
      );
    } else {
      sayfaAc(context, c.ad, govde);
    }
  }

  void _onizle(_Kampanya c) => showDialog<void>(context: context, builder: (_) => _OnizlemeDialog(id: c.id));

  Future<void> _politika() => showDialog<void>(context: context, builder: (_) => const _PolitikaDialog());

  Widget _oranlar(BuildContext c, _Kampanya k) {
    final kotuB = k.geriDonus > _geriDonusSiniri, kotuS = k.sikayet > _sikayetSiniri;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'geri dönüş %${_oranYaz(k.geriDonus, 1)}',
            style: TextStyle(color: kotuB ? Marka.gul : null, fontWeight: kotuB ? FontWeight.w700 : null),
          ),
          const TextSpan(text: ' · '),
          TextSpan(
            text: 'şikâyet %${_oranYaz(k.sikayet, 2)}',
            style: TextStyle(color: kotuS ? Marka.gul : null, fontWeight: kotuS ? FontWeight.w700 : null),
          ),
        ],
      ),
      style: TextStyle(fontSize: 12.5, color: c.r.soluk),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Iskelet(
      baslik: 'Toplu Gönderim İzleme',
      alt: 'Geri dönüş %5\'i ya da şikâyet %0,1\'i geçen kampanyalar vurgulanır',
      yenile: _y.yenile,
      eylemler: [
        IconButton(tooltip: 'Onay politikası', onPressed: _politika, icon: const Icon(Icons.policy_outlined)),
      ],
      govde: VeriTablosu<_Kampanya>(
        yukleyici: _y,
        bosMetin: 'Kampanya yok. Bu süzgece uyan toplu gönderim kampanyası bulunmuyor.',
        bosIkon: Icons.cell_tower_rounded,
        vurgulu: (c) => c.riskli,
        onTap: _rapor,
        eylemler: _eylemler,
        ust: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(context.genis ? 16 : 12, 8, 12, 0),
                children: [
                  for (final (d, e) in _sekmeler)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        showCheckmark: false,
                        selected: _durum == d,
                        onSelected: (_) => _sekme(d),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(e),
                            if (d == 'pending_approval' && _onayBekleyen > 0) ...[
                              const SizedBox(width: 6),
                              Rozet('$_onayBekleyen', renk: Marka.kehribar),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            FiltreCubugu(
              arama: AramaAlani(
                ipucu: 'Kampanya, müşteri veya konu ara',
                degisti: (v) {
                  _q = v;
                  _y.yenile();
                },
              ),
            ),
          ],
        ),
        sutunlar: [
          Sutun(
            'Kampanya',
            esnek: 4,
            hucre: (c, k) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                IkiSatir(k.ad, alt: '${k.musteri} · ${k.gonderen.isEmpty ? '—' : k.gonderen}'),
                if (k.gerekce.isNotEmpty)
                  Text(k.gerekce, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Marka.kehribar, fontSize: 12)),
              ],
            ),
          ),
          Sutun(
            'Durum',
            esnek: 2,
            hucre: (c, k) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _KampanyaDurumu(k.durum),
                Text(k.tur == 'commercial' ? 'Ticari' : 'Bilgilendirme', style: TextStyle(color: c.r.silik, fontSize: 11.5)),
              ],
            ),
          ),
          Sutun(
            'Alıcı',
            esnek: 1,
            sagaYasla: true,
            hucre: (c, k) => Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sayiYaz(k.alici), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (k.istatistikVar)
                  Text(
                    'teslim %${_yuzde(tamsayi(k.istatistik['delivered']), tamsayi(k.istatistik['queued']))}',
                    style: TextStyle(color: c.r.silik, fontSize: 11.5),
                  ),
              ],
            ),
          ),
          Sutun('Hız / saat', esnek: 1, sagaYasla: true, hucre: (_, k) => Text(sayiYaz(k.hiz))),
          Sutun(
            'Geri dönüş',
            esnek: 1,
            sagaYasla: true,
            hucre: (_, k) => Text(
              '%${_oranYaz(k.geriDonus, 1)}',
              style: TextStyle(color: k.geriDonus > _geriDonusSiniri ? Marka.gul : null, fontWeight: k.geriDonus > _geriDonusSiniri ? FontWeight.w700 : null),
            ),
          ),
          Sutun(
            'Şikâyet',
            esnek: 1,
            sagaYasla: true,
            hucre: (_, k) => Text(
              '%${_oranYaz(k.sikayet, 2)}',
              style: TextStyle(color: k.sikayet > _sikayetSiniri ? Marka.gul : null, fontWeight: k.sikayet > _sikayetSiniri ? FontWeight.w700 : null),
            ),
          ),
        ],
        kart: (c, k) => VeriKarti(
          baslik: k.ad,
          alt: '${k.musteri} · ${k.gonderen.isEmpty ? '—' : k.gonderen}',
          vurgulu: k.riskli,
          onTap: () => _rapor(k),
          rozetler: [_KampanyaDurumu(k.durum), Rozet(k.tur == 'commercial' ? 'Ticari' : 'Bilgilendirme', renk: Marka.mavi)],
          alanlar: [('Alıcı', sayiYaz(k.alici)), ('Hız / saat', sayiYaz(k.hiz)), if (k.gonderilme != null) ('Gönderilme', tamZaman(k.gonderilme))],
          eylemler: _eylemler(k),
          ek: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _oranlar(c, k),
              if (k.gerekce.isNotEmpty) Text(k.gerekce, style: const TextStyle(color: Marka.kehribar, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

const _gerekceMetinleri = {
  'reject': ('Kampanyayı reddet', 'Reddet', 'Kampanya reddedildi'),
  'pause': ('Kampanyayı duraklat', 'Duraklat', 'Kampanya duraklatıldı'),
  'cancel': ('Kampanyayı iptal et', 'İptal et', 'Kampanya iptal edildi'),
};

/// Gerekçeli işlem (reddet / duraklat / iptal): POST /admin/campaigns/{id}/{eylem} {reason}.
class _GerekceDialog extends StatefulWidget {
  const _GerekceDialog({required this.c, required this.eylem});
  final _Kampanya c;
  final String eylem;
  @override
  State<_GerekceDialog> createState() => _GerekceDialogState();
}

class _GerekceDialogState extends State<_GerekceDialog> {
  final _k = TextEditingController();
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    _k.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    final t = _gerekceMetinleri[widget.eylem]!;
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.post('/api/v1/admin/campaigns/${widget.c.id}/${widget.eylem}', {'reason': _k.text.trim()});
      bildir(t.$3, tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _gerekceMetinleri[widget.eylem]!;
    return AlertDialog(
      title: Text(t.$1, style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.c.ad} · ${widget.c.musteri}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.r.soluk)),
            const SizedBox(height: 12),
            TextField(
              controller: _k,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Gerekçe (müşteriye gösterilir)',
                hintText: 'ör. Geri dönüş oranı çok yüksek; listenizi temizleyin.',
                alignLabelWithHint: true,
              ),
            ),
            if (_hata != null) Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          style: widget.eylem == 'pause' ? null : FilledButton.styleFrom(backgroundColor: Marka.gul),
          onPressed: _mesgul || _k.text.trim().isEmpty ? null : _gonder,
          child: Text(t.$2),
        ),
      ],
    );
  }
}

/// Onay politikası: ilk N kampanya onaya düşer (GET/PUT /admin/campaigns/policy {approval_first_n}); değiştirmek süper yöneticiye.
class _PolitikaDialog extends StatefulWidget {
  const _PolitikaDialog();
  @override
  State<_PolitikaDialog> createState() => _PolitikaDialogState();
}

class _PolitikaDialogState extends State<_PolitikaDialog> {
  final _k = TextEditingController();
  bool _yuklendi = false, _mesgul = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/admin/campaigns/policy'));
      if (!mounted) return;
      setState(() {
        _k.text = '${tamsayi(v['approval_first_n'])}';
        _yuklendi = true;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  @override
  void dispose() {
    _k.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final n = int.tryParse(_k.text.trim());
    if (n == null || n < 0 || n > 100) {
      setState(() => _hata = '0–100 arasında olmalı (0 = onay istenmez)');
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.put('/api/v1/admin/campaigns/policy', {'approval_first_n': n});
      bildir('Politika kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duzenler = Uyg.platformYoneticisi;
    return AlertDialog(
      title: Text('Onay politikası', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Her müşterinin ilk N kampanyası gönderilmeden önce onaya düşer (0 = onay yok). '
              'Müşteri bazında "Müşteriler → Yönet → Toplu gönderim" ile değiştirilebilir.',
              style: TextStyle(color: context.r.soluk, fontSize: 13),
            ),
            const SizedBox(height: 14),
            if (!_yuklendi && _hata == null)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else if (_yuklendi)
              TextField(
                controller: _k,
                enabled: duzenler,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'İlk kaç kampanya onaylı', helperText: duzenler ? null : 'Yalnızca platform yöneticisi değiştirebilir'),
              ),
            if (_hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(duzenler ? 'Vazgeç' : 'Kapat')),
        if (duzenler) FilledButton(onPressed: _mesgul || !_yuklendi ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}

/// Kampanya raporunu (alıcı bazında) CSV olarak indirir: GET /campaigns/c/{id}/export.csv.
Future<void> kampanyaCsvIndir(String id, String ad) {
  final kok = ad.trim().isEmpty ? 'kampanya' : ad.trim();
  return dosyaIndir('/api/v1/campaigns/c/$id/export.csv', '${kok.length > 60 ? kok.substring(0, 60) : kok}-rapor.csv',
      baslik: 'Rapor indiriliyor', tur: 'text/csv');
}

/// Kampanya önizlemesi (GET /campaigns/c/{id}/preview): HTML sürümü güvenli önizlemede (betik ve uzak içerik yok),
/// ayrıca düz metin sürümü.
class _OnizlemeDialog extends StatelessWidget {
  const _OnizlemeDialog({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
      child: TekYukleme<Map<String, dynamic>>(
        getir: () async => harita(await Uyg.api.get('/api/v1/campaigns/c/$id/preview')),
        icerik: (c, v, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(child: Text(metinYa(v['subject']) ?? 'Önizleme', style: gosterim(18, agirlik: FontWeight.w700))),
                IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            Text('Örnek alıcı verisiyle oluşturulan görünüm. Betikler çalışmaz, uzak görseller yüklenmez.', style: TextStyle(color: c.r.silik, fontSize: 12.5)),
            const SizedBox(height: 12),
            if (metin(v['html']).trim().isNotEmpty) ...[
              HtmlOnizleme(html: metin(v['html']), yukseklik: 460),
              const SizedBox(height: 12),
              Text('Düz metin sürümü', style: TextStyle(color: c.r.soluk, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.r.ic, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(
                metinYa(v['text']) ?? _htmlden(metin(v['html'])),
                style: const TextStyle(fontSize: 13.5, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static String _htmlden(String h) => h
      .replaceAll(RegExp(r'<(style|script)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</h\d>|</li>|</tr>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

const _aliciFiltreleri = <(String, String)>[
  ('all', 'Tüm alıcılar'),
  ('pending', 'Sırada'),
  ('queued', 'Kuyruğa alındı'),
  ('delivered', 'Teslim edildi'),
  ('deferred', 'Ertelendi'),
  ('bounced', 'Geri döndü'),
  ('unsubscribed', 'Abonelikten çıktı'),
  ('skipped', 'Atlandı'),
  ('failed', 'Gönderilemedi'),
  ('cancelled', 'İptal'),
];

const _aliciDurumlari = {
  'pending': 'Sırada',
  'sending': 'Gönderiliyor',
  'queued': 'Kuyruğa alındı',
  'skipped': 'Atlandı',
  'failed': 'Gönderilemedi',
  'held': 'Bekletildi',
  'cancelled': 'İptal',
};

const _teslimEtiketleri = {'delivered': 'Teslim edildi', 'deferred': 'Ertelendi', 'bounced': 'Geri döndü'};

/// Kampanya raporu: canlı sayılar (GET /campaigns/c/{id}) ve alıcı bazında durum (GET /campaigns/c/{id}/recipients).
class _KampanyaRaporu extends StatefulWidget {
  const _KampanyaRaporu({required this.id});
  final String id;
  @override
  State<_KampanyaRaporu> createState() => _KampanyaRaporuState();
}

class _KampanyaRaporuState extends State<_KampanyaRaporu> {
  Map<String, dynamic>? _c;
  String? _hata;
  String _q = '';
  String _durum = 'all';
  Timer? _zamanlayici;

  late final _y = SayfaYukleyici<Map<String, dynamic>>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/campaigns/c/${widget.id}/recipients',
        q: {'page': '$s', 'page_size': '$b', if (_q.isNotEmpty) 'q': _q, if (_durum != 'all') 'status': _durum},
      ),
      (m) => m,
    ),
  )..yenile();

  @override
  void initState() {
    super.initState();
    _yukle();
    _zamanlayici = Timer.periodic(const Duration(seconds: 15), (_) {
      final d = metin(_c?['status']);
      if (const ['scheduled', 'sending', 'pending_approval'].contains(d)) {
        _yukle();
        if (d == 'sending' && !_y.yukleniyor) _y.sayfaGit(_y.sayfa < 1 ? 1 : _y.sayfa);
      }
    });
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _y.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/campaigns/c/${widget.id}'));
      if (mounted) setState(() => _c = v);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Widget _ozet(BuildContext context) {
    final c = _c;
    if (c == null) {
      return _hata != null
          ? Padding(padding: const EdgeInsets.all(16), child: Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded))
          : const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
    }
    final r = context.r;
    final s = c['stats'] is Map ? harita(c['stats']) : null;
    int n(String k) => tamsayi(s?[k]);
    final q = n('queued');
    Widget kutu(String e, int d, {String? alt, bool kotu = false}) => Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kotu ? Marka.gul.withValues(alpha: .08) : r.kart,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kotu ? Marka.gul.withValues(alpha: .4) : r.kenar),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 11.5)),
          Text(sayiYaz(d), style: gosterim(18, agirlik: FontWeight.w700, renk: kotu ? Marka.gul : r.metin)),
          if (alt != null) Text(alt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 11)),
        ],
      ),
    );
    final gerekce = metin(c['status_reason']), bekleme = metin(c['wait_reason']);
    return Padding(
      padding: EdgeInsets.fromLTRB(context.genis ? 16 : 12, 8, context.genis ? 16 : 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              _durumEtiketleri[metin(c['status'])] ?? metin(c['status']),
              metinYa(c['from_address']) ?? '—',
              '${sayiYaz(tamsayi(c['total_recipients']))} alıcı',
              if (tarihOku(c['started_at']) != null) 'başladı ${tamZaman(tarihOku(c['started_at']))}',
            ].join(' · '),
            style: TextStyle(color: r.soluk, fontSize: 12.5),
          ),
          if (gerekce.isNotEmpty || bekleme.isNotEmpty) ...[
            const SizedBox(height: 8),
            Bant([if (gerekce.isNotEmpty) gerekce, if (bekleme.isNotEmpty) 'Bekleme: $bekleme'].join('\n'), renk: Marka.kehribar, ikon: Icons.info_outline_rounded),
          ],
          const SizedBox(height: 8),
          if (s == null)
            Text('Taslak kampanyanın raporu yok.', style: TextStyle(color: r.silik))
          else
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final w in [
                    kutu('Sırada', n('pending')),
                    kutu('Kuyruğa alındı', q, alt: 'son 1 saat: ${n('queued_last_hour')}'),
                    kutu('Teslim edildi', n('delivered'), alt: '%${_yuzde(n('delivered'), q)}'),
                    kutu('Ertelendi', n('deferred')),
                    kutu('Kalıcı geri dönüş', n('bounced_hard'), alt: '%${_yuzde(n('bounced_hard'), q)}', kotu: q > 0 && n('bounced_hard') / q > _geriDonusSiniri),
                    kutu('Geçici hata (süre doldu)', n('bounced_soft')),
                    kutu('Şikâyet', n('complained'), alt: '%${_yuzde(n('complained'), q)}', kotu: q > 0 && n('complained') / q > _sikayetSiniri),
                    kutu('Abonelikten çıktı', n('unsubscribed'), alt: '%${_yuzde(n('unsubscribed'), q)}'),
                    kutu('Atlandı', n('skipped'), alt: 'çıkmış / bastırılmış'),
                    kutu('Gönderilemedi', n('failed') + n('held')),
                  ])
                    Padding(padding: const EdgeInsets.only(right: 8), child: w),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Açılma/tıklama takibi kapalı (gizlilik). Teslim bilgisi alıcı sunucuların yanıtlarından, şikâyetler geri bildirim döngüsü (FBL) raporlarından gelir.',
            style: TextStyle(color: r.silik, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  String _teslim(Map<String, dynamic> x) => [
    _aliciDurumlari[metin(x['status'])] ?? metin(x['status']),
    if (metin(x['delivery']).isNotEmpty) _teslimEtiketleri[metin(x['delivery'])] ?? metin(x['delivery']),
    if (tarihOku(x['unsubscribed_at']) != null) 'çıktı',
    if (mantik(x['complained'])) 'şikâyet',
  ].join(' · ');

  void _ac(Map<String, dynamic> x) {
    final q = metin(x['queue_id']);
    if (q.isNotEmpty) iletiYolculugunuAc(context, q);
  }

  @override
  Widget build(BuildContext context) => VeriTablosu<Map<String, dynamic>>(
    yukleyici: _y,
    bosMetin: 'Kayıt yok.',
    bosIkon: Icons.people_outline_rounded,
    tabloEnAz: 640,
    onTap: _ac,
    ust: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ozet(context),
        FiltreCubugu(
          arama: AramaAlani(
            ipucu: 'Alıcı ara',
            degisti: (v) {
              _q = v;
              _y.yenile();
            },
          ),
          filtreler: [
            FiltreDugmesi<String>(
              etiket: 'Durum',
              secenekler: _aliciFiltreleri,
              secili: _durum,
              secildi: (v) {
                setState(() => _durum = v);
                _y.yenile();
              },
            ),
          ],
        ),
      ],
    ),
    sutunlar: [
      Sutun('Alıcı', esnek: 3, hucre: (_, x) => IkiSatir(metin(x['email']), alt: metinYa(x['name']))),
      Sutun('Durum', esnek: 2, hucre: (_, x) => IkiSatir(_aliciDurumlari[metin(x['status'])] ?? metin(x['status']), alt: metinYa(x['reason']), kalin: false)),
      Sutun(
        'Teslim',
        esnek: 3,
        hucre: (_, x) => IkiSatir(
          [
            metin(x['delivery']).isEmpty ? '—' : (_teslimEtiketleri[metin(x['delivery'])] ?? metin(x['delivery'])),
            if (tarihOku(x['unsubscribed_at']) != null) 'çıktı',
            if (mantik(x['complained'])) 'şikâyet',
          ].join(' · '),
          alt: '${metin(x['delivery_code'])} ${metin(x['delivery_detail'])}'.trim(),
          kalin: false,
        ),
      ),
      Sutun('Zaman', genislik: 140, hucre: (_, x) => SolukMetin(tamZaman(tarihOku(x['delivery_at']) ?? tarihOku(x['queued_at'])))),
    ],
    kart: (c, x) => VeriKarti(
      baslik: metin(x['email']),
      alt: metinYa(x['name']),
      onTap: metin(x['queue_id']).isEmpty ? null : () => _ac(x),
      alanlar: [
        ('Durum', _teslim(x)),
        ('Zaman', tamZaman(tarihOku(x['delivery_at']) ?? tarihOku(x['queued_at']))),
        if (metin(x['delivery_detail']).isNotEmpty) ('Yanıt', '${metin(x['delivery_code'])} ${metin(x['delivery_detail'])}'.trim()),
      ],
    ),
  );
}
