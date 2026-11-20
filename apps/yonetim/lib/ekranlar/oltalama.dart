import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/dosya.dart' show dosyaIndir;
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'tehdit_oltalama_diger.dart';
import 'tehdit_oltalama_model.dart';
import 'tehdit_ortak.dart';

/// Oltalama Simülasyonu (web: admin/phishing): kampanyalar, raporlar, şablonlar ve bildirilen iletiler.
/// Müşteri yöneticisi kendi müşterisini görür; ortak yöneticiler müşteri seçer. Yetki: phishing.manage.
class OltalamaEkrani extends StatefulWidget {
  const OltalamaEkrani({super.key});
  @override
  State<OltalamaEkrani> createState() => _OltalamaEkraniState();
}

class _OltalamaEkraniState extends State<OltalamaEkrani> {
  String? _orgId = Uyg.musteri ? kendiMusterim() : null;
  String? _orgAdi;
  Map<String, dynamic>? _ozet;
  String? _hata;
  int _nesil = 0;
  final _kampanyaAnahtari = GlobalKey<_KampanyalarState>();

  @override
  void initState() {
    super.initState();
    _ozetYukle();
  }

  Future<void> _ozetYukle() async {
    final org = _orgId;
    if (org == null || !Uyg.yetki('phishing.manage')) return;
    try {
      final v = harita(await Uyg.api.get('/api/v1/phishing/overview', q: {'org': org}));
      if (mounted && org == _orgId) {
        setState(() {
          _ozet = v;
          _hata = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _musteriSec() async {
    final o = await musteriSec(context);
    if (o == null) return;
    setState(() {
      _orgId = o.id;
      _orgAdi = o.ad;
      _ozet = null;
      _hata = null;
      _nesil++;
    });
    _ozetYukle();
  }

  @override
  Widget build(BuildContext context) {
    const baslik = 'Oltalama Simülasyonu';
    if (!Uyg.yetki('phishing.manage')) {
      return const Iskelet(baslik: baslik, govde: Kapali('Bu sayfa için phishing.manage yetkisi gerekiyor.'));
    }
    final org = _orgId;
    final secici = Uyg.musteri
        ? <Widget>[]
        : [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                avatar: const Icon(Icons.business_rounded, size: 17),
                label: Text(_orgAdi ?? 'Müşteri seçin', overflow: TextOverflow.ellipsis),
                onPressed: _musteriSec,
              ),
            ),
          ];
    if (org == null) {
      return Iskelet(
        baslik: baslik,
        eylemler: secici,
        govde: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Kapali('Tatbikat düzenlemek ya da raporları görmek için bir müşteri seçin.', ikon: Icons.phishing_rounded),
              FilledButton.icon(onPressed: _musteriSec, icon: const Icon(Icons.business_rounded), label: const Text('Müşteri seçin')),
            ],
          ),
        ),
      );
    }
    final o = _ozet;
    if (o == null) {
      return Iskelet(
        baslik: baslik,
        eylemler: secici,
        govde: _hata != null ? Durum.hata(_hata!, tekrar: _ozetYukle) : const Durum.yukleniyor(),
      );
    }
    final acik = mantik(harita(o['organization'])['feature_enabled']);
    final yeni = tamsayi(o['new_user_reports']);
    return DefaultTabController(
      length: 4,
      child: Iskelet(
        baslik: baslik,
        alt: [metin(harita(o['organization'])['name']), '${tamsayi(o['active_mailboxes'])} etkin kutu', '${tamsayi(o['active_campaigns'])} etkin kampanya'].join(' · '),
        eylemler: secici,
        yenile: () {
          _ozetYukle();
          setState(() => _nesil++);
        },
        birincil: acik ? BirincilEylem(Icons.add_rounded, 'Yeni kampanya', () => _kampanyaAnahtari.currentState?.olustur()) : null,
        sekmeler: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: 'Kampanyalar'),
            const Tab(text: 'Raporlar'),
            const Tab(text: 'Şablonlar'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bildirilen iletiler'),
                  if (yeni > 0) ...[const SizedBox(width: 6), Badge(label: Text('$yeni'))],
                ],
              ),
            ),
          ],
        ),
        govde: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!acik)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Bant(
                  'Oltalama simülasyonu bu müşterinin paketinde bulunmuyor. Geçmiş raporlar ve çalışanların bildirdiği iletiler yine de görüntülenebilir.',
                  renk: Marka.kehribar,
                  ikon: Icons.lock_outline_rounded,
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _Kampanyalar(key: _kampanyaAnahtari, orgId: org, acik: acik, nesil: _nesil, degisti: _ozetYukle),
                  OltaRaporlari(key: ValueKey('r$org$_nesil'), orgId: org),
                  OltaSablonlari(key: ValueKey('s$org$_nesil'), orgId: org, acik: acik, yerTutucular: haritalar(o['placeholders'])),
                  OltaBildirimleri(key: ValueKey('b$org$_nesil'), orgId: org, degisti: _ozetYukle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- kampanyalar --------------------------------------------------------------------------------------------

Widget kampanyaRozeti(String d) => Rozet(kampanyaDurumEtiketi[d] ?? d, renk: kampanyaDurumRengi(d));

class _Kampanyalar extends StatefulWidget {
  const _Kampanyalar({super.key, required this.orgId, required this.acik, required this.nesil, required this.degisti});
  final String orgId;
  final bool acik;
  final int nesil;
  final VoidCallback degisti;
  @override
  State<_Kampanyalar> createState() => _KampanyalarState();
}

class _KampanyalarState extends State<_Kampanyalar> {
  late final _y = SayfaYukleyici.yerel<OltaKampanya>(
    () async => haritalar(harita(await Uyg.api.get('/api/v1/phishing/campaigns', q: {'org': widget.orgId}))['items']).map(OltaKampanya.coz).toList(),
    sayfaBoyu: 25,
  )..yenile();

  @override
  void didUpdateWidget(_Kampanyalar eski) {
    super.didUpdateWidget(eski);
    if (eski.orgId != widget.orgId || eski.nesil != widget.nesil) _y.yenile();
  }

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> olustur() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _KampanyaDialog(orgId: widget.orgId));
    if (ok == true) {
      _y.yenile();
      widget.degisti();
    }
  }

  Future<void> _iptal(OltaKampanya k) async {
    if (!await onayla(
      context,
      'Kampanya iptal edilsin mi?',
      mesaj: 'Teslim edilmiş iletiler kutularda kalır ve izlenmeye devam eder; bekleyenler gönderilmez.',
      evet: 'İptal et',
      tehlikeli: true,
    )) {
      return;
    }
    if (await islem(() => Uyg.api.post('/api/v1/phishing/campaigns/${k.id}/cancel'), tamam: 'Kampanya iptal edildi; bekleyen iletiler gönderilmeyecek') != null) {
      _y.yenile();
      widget.degisti();
    }
  }

  Future<void> _csv(OltaKampanya k) =>
      dosyaIndir('/api/v1/phishing/campaigns/${k.id}/export.csv', 'oltalama-${k.id}.csv', baslik: 'CSV indiriliyor', tur: 'text/csv');

  void _ac(OltaKampanya k) {
    final w = _KampanyaDetay(id: k.id);
    if (MediaQuery.sizeOf(context).width < 600) {
      sayfaAc(context, k.ad, w);
    } else {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(k.ad, style: gosterim(18, agirlik: FontWeight.w700), overflow: TextOverflow.ellipsis),
          content: SizedBox(width: 760, child: w),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        ),
      );
    }
  }

  List<SatirEylemi> _eylemler(OltaKampanya k) => [
    SatirEylemi(Icons.insights_rounded, 'Sonuçlar', () => _ac(k)),
    SatirEylemi(Icons.table_view_outlined, 'Sonuçları CSV olarak indir', () => _csv(k)),
    if (k.etkin) SatirEylemi(Icons.block_rounded, 'Kampanyayı iptal et', () => _iptal(k), tehlikeli: true),
  ];

  String _alt(OltaKampanya k) => '${k.sablonAdi} · ${k.huni.hedef} alıcı · ${k.acilis == 'login' ? 'sahte giriş formu' : 'yalnızca tıklama'}';

  @override
  Widget build(BuildContext context) => VeriTablosu<OltaKampanya>(
    yukleyici: _y,
    bosMetin: 'Henüz kampanya yok. İlk tatbikatı başlatmak için hazır bir senaryo seçin.',
    bosIkon: Icons.phishing_rounded,
    onTap: _ac,
    eylemler: _eylemler,
    ust: const Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Aciklama('Her alıcıya özel bağlantı gönderilir; tıklama, form gönderimi ve bildirim kişi bazında izlenir.'),
    ),
    sutunlar: [
      Sutun('Kampanya', esnek: 5, hucre: (c, k) => IkiSatir(k.ad, alt: _alt(k))),
      Sutun('Durum', genislik: 120, hucre: (c, k) => Align(alignment: Alignment.centerLeft, child: kampanyaRozeti(k.durum))),
      Sutun('Başlangıç', genislik: 130, hucre: (c, k) => SolukMetin(kisaZaman(k.baslangic))),
      Sutun('Tıklama', genislik: 100, sagaYasla: true, hucre: (c, k) => Text('${k.huni.tiklayan} (%${k.huni.yuzde(k.huni.tiklayan)})')),
      Sutun('Form', genislik: 70, sagaYasla: true, hucre: (c, k) => Text('${k.huni.formGonderen}')),
      Sutun('Bildirim', genislik: 80, sagaYasla: true, hucre: (c, k) => Text('${k.huni.bildiren}')),
    ],
    kart: (c, k) => VeriKarti(
      baslik: k.ad,
      alt: _alt(k),
      onTap: () => _ac(k),
      eylemler: _eylemler(k),
      rozetler: [kampanyaRozeti(k.durum)],
      alanlar: [
        ('Başlangıç', kisaZaman(k.baslangic)),
        ('Tıklama', '%${k.huni.yuzde(k.huni.tiklayan)}'),
        ('Bildirim', '%${k.huni.yuzde(k.huni.bildiren)}'),
      ],
    ),
  );
}

/// Kampanya sonuçları (GET /phishing/campaigns/{id}): huni, medyan süreler ve alıcılar.
class _KampanyaDetay extends StatefulWidget {
  const _KampanyaDetay({required this.id});
  final String id;
  @override
  State<_KampanyaDetay> createState() => _KampanyaDetayState();
}

class _KampanyaDetayState extends State<_KampanyaDetay> {
  Map<String, dynamic>? _v;
  String? _hata;
  String _q = '';

  @override
  void initState() {
    super.initState();
    Uyg.api.get('/api/v1/phishing/campaigns/${widget.id}').then(
      (v) => mounted ? setState(() => _v = harita(v)) : null,
      onError: (Object e) => mounted ? setState(() => _hata = hataMetni(e)) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final v = _v;
    if (v == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _hata != null ? Text(_hata!, style: const TextStyle(color: Marka.gul)) : const CircularProgressIndicator()),
      );
    }
    final k = OltaKampanya.coz(harita(v['campaign']));
    final sure = harita(v['timings']);
    final s = _q.trim().toLowerCase();
    final hedefler = haritalar(v['targets']).map(OltaHedef.coz).where((t) => s.isEmpty || t.adres.contains(s) || t.ad.toLowerCase().contains(s)).toList();
    Widget istat(String e, String d) => Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(10), border: Border.all(color: r.kenar)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e, style: TextStyle(color: r.silik, fontSize: 11.5)),
          Text(d, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: MediaQuery.sizeOf(context).width < 600 ? const EdgeInsets.all(16) : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${metin(harita(v['template'])['name'])} · ${k.acilis == 'login' ? 'sahte giriş formu → eğitim' : 'tıklama → eğitim'} · ${tamZaman(k.baslangic)}',
            style: TextStyle(color: r.silik, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              kampanyaRozeti(k.durum),
              Text('${k.huni.hedef} alıcı · ${k.huni.bekleyen} bekliyor · ${k.huni.atlanan} atlandı/iptal', style: TextStyle(color: r.soluk, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          HuniCubuklari(k.huni),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              istat('Tıklamaya kadar (medyan)', dakikaYaz(ondalikYa(sure['median_minutes_to_click']))),
              istat('Form gönderimine kadar', dakikaYaz(ondalikYa(sure['median_minutes_to_submit']))),
              istat('Bildirime kadar', dakikaYaz(ondalikYa(sure['median_minutes_to_report']))),
            ],
          ),
          if (k.acilmaIzle)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Açılma sayısı yaklaşıktır: webmail uzak resimleri varsayılan olarak engeller; tıklayan herkes açmış sayılır.',
                style: TextStyle(color: r.silik, fontSize: 12),
              ),
            ),
          const SizedBox(height: 14),
          AramaAlani(ipucu: 'Alıcı ara', degisti: (q) => setState(() => _q = q)),
          const SizedBox(height: 6),
          for (final t in hedefler.take(300))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t.ad.isEmpty ? t.adres : t.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                [
                  if (t.ad.isNotEmpty) t.adres,
                  hedefDurumEtiketi[t.durum] ?? t.durum,
                  if (t.tiklama != null) 'tıkladı ${kisaZaman(t.tiklama)}${t.tiklamaSayisi > 1 ? ' (${t.tiklamaSayisi}×)' : ''}',
                  if (t.sonHata != null) t.sonHata!,
                ].join(' · '),
                style: TextStyle(color: r.silik, fontSize: 12),
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  if (t.formGonderdi) const Rozet('Form', renk: Marka.gul),
                  if (t.bildirim != null) const Rozet('Bildirdi', renk: Marka.zumrut),
                ],
              ),
            ),
          if (hedefler.length > 300) Text('İlk 300 alıcı gösteriliyor; aramayı daraltın.', style: TextStyle(color: r.silik, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Yeni kampanya (POST /phishing/campaigns).
class _KampanyaDialog extends StatefulWidget {
  const _KampanyaDialog({required this.orgId});
  final String orgId;
  @override
  State<_KampanyaDialog> createState() => _KampanyaDialogState();
}

class _KampanyaDialogState extends State<_KampanyaDialog> {
  final _ad = TextEditingController();
  final _yay = TextEditingController(text: '0');
  List<OltaSablon>? _sablonlar;
  List<AlanAdi> _alanlar = [];
  String _sablon = 'sifre';
  String _acilis = 'login';
  String _hedef = 'all';
  final Map<String, String> _kutular = {};
  final Set<String> _alanIdleri = {};
  bool _hemen = true;
  DateTime _baslangic = DateTime.now().add(const Duration(hours: 1));
  bool _acilmaIzle = false;
  bool _mesgul = false;
  String? _hata, _hataAlan;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final t = harita(await Uyg.api.get('/api/v1/phishing/templates', q: {'org': widget.orgId}));
      final d = Sayfa.coz(await Uyg.api.get('/api/v1/domains', q: {'organization_id': widget.orgId, 'page_size': '100'}), AlanAdi.coz).ogeler;
      if (!mounted) return;
      setState(() {
        _sablonlar = [...haritalar(t['builtin']), ...haritalar(t['custom'])].map(OltaSablon.coz).toList();
        _alanlar = d;
        if (_sablonlar!.isNotEmpty && !_sablonlar!.any((s) => s.anahtar == _sablon)) _sablon = _sablonlar!.first.anahtar;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  @override
  void dispose() {
    _ad.dispose();
    _yay.dispose();
    super.dispose();
  }

  Future<void> _tarihSec() async {
    final g = await showDatePicker(
      context: context,
      initialDate: _baslangic,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (g == null || !mounted) return;
    final s = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_baslangic));
    if (s == null) return;
    setState(() => _baslangic = DateTime(g.year, g.month, g.day, s.hour, s.minute));
  }

  Future<void> _kutuSec() async {
    final k = await araVeSec<PostaKutusu>(
      context,
      baslik: 'Posta kutusu ekle',
      ipucu: 'Kutu ara…',
      yukle: (q) async => Sayfa.coz(
        await Uyg.api.get('/api/v1/mailboxes', q: {'organization_id': widget.orgId, 'page_size': '100', 'page': '1', if (q.isNotEmpty) 'q': q}),
        PostaKutusu.coz,
      ).ogeler.where((m) => m.aktif).toList(),
      ad: (m) => m.adres,
      alt: (m) => m.gorunenAd.isEmpty ? null : m.gorunenAd,
    );
    if (k != null) setState(() => _kutular[k.id] = k.adres);
  }

  bool get _gecerli =>
      _ad.text.trim().isNotEmpty && _sablon.isNotEmpty && !(_hedef == 'mailboxes' && _kutular.isEmpty) && !(_hedef == 'domains' && _alanIdleri.isEmpty);

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = _hataAlan = null;
    });
    try {
      await Uyg.api.post('/api/v1/phishing/campaigns', {
        'organization_id': widget.orgId,
        'name': _ad.text.trim(),
        'template_key': _sablon,
        'landing': _acilis,
        'track_opens': _acilmaIzle,
        'target_mode': _hedef,
        'mailbox_ids': _hedef == 'mailboxes' ? _kutular.keys.toList() : <String>[],
        'domain_ids': _hedef == 'domains' ? _alanIdleri.toList() : <String>[],
        if (!_hemen) 'start_at': _baslangic.toUtc().toIso8601String(),
        'spread_hours': int.tryParse(_yay.text.trim()) ?? 0,
      });
      bildir('Kampanya planlandı', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      setState(() {
        _hata = e.mesaj;
        _hataAlan = e.alan;
      });
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  String? _alanHatasi(List<String> l) => l.contains(_hataAlan) ? _hata : null;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final sablonlar = _sablonlar;
    final secili = sablonlar?.where((s) => s.anahtar == _sablon).firstOrNull;
    const bilinen = ['name', 'template_key', 'target_mode', 'mailbox_ids', 'domain_ids', 'start_at', 'spread_hours'];
    return AlertDialog(
      title: Text('Yeni oltalama kampanyası', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 620,
        child: sablonlar == null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: _hata != null ? Text(_hata!, style: const TextStyle(color: Marka.gul)) : const CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Aciklama(
                      'İletiler yalnızca bu müşterinin posta kutularına, doğrudan Gelen Kutusu\'na bırakılır. Hiçbir şifre veya form içeriği kaydedilmez.',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _ad,
                      maxLength: 120,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Kampanya adı',
                        hintText: 'ör. Kasım 2026 farkındalık tatbikatı',
                        errorText: _alanHatasi(['name']),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: sablonlar.any((s) => s.anahtar == _sablon) ? _sablon : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Senaryo (şablon)', errorText: _alanHatasi(['template_key'])),
                      items: [
                        for (final s in sablonlar)
                          DropdownMenuItem(value: s.anahtar, child: Text(s.hazir ? s.ad : '${s.ad} (özel)', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _sablon = v ?? _sablon),
                    ),
                    if (secili != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${secili.gonderen} — ${secili.konu}', style: TextStyle(color: r.silik, fontSize: 12)),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _acilis,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Açılış sayfası',
                        helperText: 'Sahte formun alanları hiçbir veri göndermez; yalnızca "form gönderildi" bilgisi kaydedilir.',
                        helperMaxLines: 2,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'login', child: Text('Sahte giriş formu → eğitim sayfası')),
                        DropdownMenuItem(value: 'click', child: Text('Yalnızca tıklama → eğitim sayfası')),
                      ],
                      onChanged: (v) => setState(() => _acilis = v ?? _acilis),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _hedef,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Hedef', errorText: _alanHatasi(['target_mode', 'mailbox_ids', 'domain_ids'])),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Tüm etkin posta kutuları')),
                        DropdownMenuItem(value: 'mailboxes', child: Text('Seçili posta kutuları')),
                        DropdownMenuItem(value: 'domains', child: Text('Alan adına göre')),
                      ],
                      onChanged: (v) => setState(() => _hedef = v ?? _hedef),
                    ),
                    if (_hedef == 'mailboxes')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final e in _kutular.entries) InputChip(label: Text(e.value), onDeleted: () => setState(() => _kutular.remove(e.key))),
                            ActionChip(avatar: const Icon(Icons.add_rounded, size: 17), label: const Text('Kutu ekle'), onPressed: _kutuSec),
                            Text('${_kutular.length} kutu seçildi', style: TextStyle(color: r.silik, fontSize: 12)),
                          ],
                        ),
                      ),
                    if (_hedef == 'domains')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _alanlar.isEmpty
                            ? Text('Alan adı yok', style: TextStyle(color: r.silik))
                            : Column(
                                children: [
                                  for (final d in _alanlar)
                                    CheckboxListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity: ListTileControlAffinity.leading,
                                      value: _alanIdleri.contains(d.id),
                                      onChanged: (b) => setState(() => b == true ? _alanIdleri.add(d.id) : _alanIdleri.remove(d.id)),
                                      title: Text(d.gorunenAd),
                                      secondary: Text('${d.kutuSayisi} kutu', style: TextStyle(color: r.silik, fontSize: 12)),
                                    ),
                                ],
                              ),
                      ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _hemen,
                      onChanged: (v) => setState(() => _hemen = v),
                      title: const Text('Hemen başlat'),
                      subtitle: _hemen ? null : Text('Başlangıç: ${tamZaman(_baslangic)}'),
                      secondary: _hemen ? null : IconButton(tooltip: 'Tarih seç', onPressed: _tarihSec, icon: const Icon(Icons.event_rounded)),
                    ),
                    if (_alanHatasi(['start_at']) != null) Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 12)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _yay,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Gönderimi yay (saat)',
                        helperText: '0 = hepsi birden. İletiler bu süreye rastgele dağıtılır (en fazla 168).',
                        helperMaxLines: 2,
                        errorText: _alanHatasi(['spread_hours']),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _acilmaIzle,
                      onChanged: (b) => setState(() => _acilmaIzle = b ?? false),
                      title: const Text('Açılma izleme pikseli ekle'),
                      subtitle: const Text('Yaklaşık: webmail uzak resimleri varsayılan olarak engeller.'),
                    ),
                    if (_hata != null && !bilinen.contains(_hataAlan)) Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 12.5)),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul || !_gecerli || sablonlar == null ? null : _kaydet, child: const Text('Kampanyayı planla')),
      ],
    );
  }
}
