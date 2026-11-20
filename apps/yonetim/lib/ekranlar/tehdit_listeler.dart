import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import '../veri/tehdit_modeller.dart';
import 'tehdit_ortak.dart';

// Tehdit Koruması: tıklama engel listesi, korunan kişiler (VIP) + müşteri ayarları, bağlantı listesi, IP/ASN itibarı.

/// Liste kaydı ekleme penceresi (bağlantı listesi ve tıklama engel listesi): sunucu hatası alanın altında gösterilir.
class _ListeEkleDialog extends StatefulWidget {
  const _ListeEkleDialog({required this.baslik, required this.kaydet, this.turSec = false, this.notAlani = false, this.aciklama});
  final String baslik;
  final String? aciklama;

  /// Engel / izin seçimi gösterilsin mi (izin yalnızca ortak yöneticiler için).
  final bool turSec;
  final bool notAlani;

  /// (tür, değer, not, müşteri) ile POST eder.
  final Future<void> Function(String tur, String deger, String not, String? orgId) kaydet;

  @override
  State<_ListeEkleDialog> createState() => _ListeEkleDialogState();
}

class _ListeEkleDialogState extends State<_ListeEkleDialog> {
  final _deger = TextEditingController(), _not = TextEditingController();
  String _tur = 'block';
  String? _orgId, _orgAdi, _hata, _kapsamHata;
  bool _mesgul = false;

  @override
  void dispose() {
    _deger.dispose();
    _not.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    final v = _deger.text.trim();
    if (v.isEmpty) {
      setState(() => _hata = 'Alan adı veya adres girin');
      return;
    }
    if (!Uyg.musteri && !Uyg.platformYoneticisi && _orgId == null) {
      setState(() => _kapsamHata = 'Müşteri seçin');
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = _kapsamHata = null;
    });
    try {
      await widget.kaydet(_tur, v, _not.text.trim(), _orgId);
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      setState(() => _hata = e.durum == 409 ? 'Bu kayıt zaten var.' : e.mesaj);
    } catch (e) {
      setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.baslik, style: gosterim(19, agirlik: FontWeight.w700)),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.aciklama != null) ...[Aciklama(widget.aciklama!), const SizedBox(height: 14)],
            if (widget.turSec) ...[
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'block', icon: Icon(Icons.gpp_bad_outlined, size: 18), label: Text('Engel')),
                  if (Uyg.ortak) const ButtonSegment(value: 'allow', icon: Icon(Icons.verified_outlined, size: 18), label: Text('İzin')),
                ],
                selected: {_tur},
                onSelectionChanged: (s) => setState(() => _tur = s.first),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _deger,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Alan adı veya adres', hintText: 'kotu-site.com veya https://ornek.com/giris', errorText: _hata),
              onSubmitted: (_) => _gonder(),
            ),
            if (widget.notAlani) ...[
              const SizedBox(height: 12),
              TextField(controller: _not, maxLength: 200, decoration: const InputDecoration(labelText: 'Not', hintText: 'İsteğe bağlı')),
            ],
            const SizedBox(height: 12),
            KapsamSecici(
              orgId: _orgId,
              orgAdi: _orgAdi,
              hata: _kapsamHata,
              degisti: (id, ad) => setState(() {
                _orgId = id;
                _orgAdi = ad;
                _kapsamHata = null;
              }),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(onPressed: _mesgul ? null : _gonder, child: const Text('Ekle')),
    ],
  );
}

Widget _ekleDugmesi(String etiket, VoidCallback fn) => FilledButton.tonalIcon(onPressed: fn, icon: const Icon(Icons.add_rounded, size: 18), label: Text(etiket));

// ---- tıklama engel listesi ----------------------------------------------------------------------------------

/// Tıklama engel listesi (GET/POST/DELETE /clicks/blocklist).
class TiklamaEngelListesi extends StatefulWidget {
  const TiklamaEngelListesi({super.key});
  @override
  State<TiklamaEngelListesi> createState() => _TiklamaEngelListesiState();
}

class _TiklamaEngelListesiState extends State<TiklamaEngelListesi> {
  late final _y = SayfaYukleyici.yerel<ListeKaydi>(
    () async => haritalar(harita(await Uyg.api.get('/api/v1/clicks/blocklist'))['items']).map(ListeKaydi.coz).toList(),
  )..yenile();

  bool get _yonetir => Uyg.yetki('spam.manage');

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _ekle() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ListeEkleDialog(
        baslik: 'Tıklama engeli ekle',
        notAlani: true,
        aciklama: 'Alan adı (alt alan adlarını da kapsar) veya http(s):// ile başlayan adres öneki. Listedeki bir bağlantıya tıklandığında, '
            'ileti teslim edildikten sonra eklenmiş olsa bile sayfa açılmaz.',
        kaydet: (_, deger, not, org) => Uyg.api.post('/api/v1/clicks/blocklist', {'value': deger, 'note': not, 'organization_id': ?org}),
      ),
    );
    if (ok == true) {
      bildir('Engel listesine eklendi', tur: MesajTur.basari);
      _y.yenile();
    }
  }

  Future<void> _sil(ListeKaydi k) async {
    if (!await onayla(context, 'Engel kaldırılsın mı?', mesaj: 'Bu kayıt engel listesinden çıkarılacak: ${k.deger}', evet: 'Kaldır', tehlikeli: true)) return;
    if (await islem(() => Uyg.api.delete('/api/v1/clicks/blocklist/${k.id}'), tamam: 'Kaldırıldı') != null) _y.degistir((x) => x.id == k.id, null);
  }

  List<SatirEylemi> _eylemler(ListeKaydi k) => [
    if (_yonetir && (Uyg.platformYoneticisi || k.orgId != null)) SatirEylemi(Icons.delete_outline_rounded, 'Kaldır', () => _sil(k), tehlikeli: true),
  ];

  @override
  Widget build(BuildContext context) => VeriTablosu<ListeKaydi>(
    yukleyici: _y,
    bosMetin: 'Tıklama engel listesi boş.',
    bosIkon: Icons.block_rounded,
    eylemler: _eylemler,
    ust: FiltreCubugu(
      arama: const Aciklama('Listedeki bir bağlantıya tıklandığında, ileti teslim edildikten sonra eklenmiş olsa bile sayfa açılmaz.'),
      sag: _yonetir ? Padding(padding: const EdgeInsets.only(left: 8), child: _ekleDugmesi('Engel ekle', _ekle)) : null,
    ),
    sutunlar: [
      Sutun('Alan adı / adres', esnek: 4, hucre: (c, k) => IkiSatir(k.deger, alt: k.not.isEmpty ? null : k.not, mono: true)),
      Sutun('Kapsam', esnek: 2, hucre: (c, k) => SolukMetin(k.orgAdi ?? 'Tüm platform')),
      Sutun('Ekleyen', esnek: 2, hucre: (c, k) => IkiSatir(k.ekleyen, alt: kisaZaman(k.eklenme), kalin: false)),
    ],
    kart: (c, k) => VeriKarti(
      baslik: k.deger,
      alt: k.not,
      eylemler: _eylemler(k),
      alanlar: [('Kapsam', k.orgAdi ?? 'Tüm platform'), ('Eklenme', kisaZaman(k.eklenme))],
    ),
  );
}

// ---- korunan kişiler + müşteri ayarları ---------------------------------------------------------------------

const dmarcKipleri = <String, String>{
  'platform': 'Platform ayarı',
  'enforce': 'Uygula (reject → ret, quarantine → Önemsiz)',
  'quarantine': 'Yumuşak (reject ve quarantine → Önemsiz)',
  'monitor': 'Yalnızca izle (puanla, işlem yapma)',
};

/// Korunan kişiler sekmesi: müşteri seçimi, müşterinin tehdit ayarları ve VIP listesi.
class TehditKorunanKisiler extends StatefulWidget {
  const TehditKorunanKisiler({super.key});
  @override
  State<TehditKorunanKisiler> createState() => _TehditKorunanKisilerState();
}

class _TehditKorunanKisilerState extends State<TehditKorunanKisiler> {
  String? _orgId = Uyg.musteri ? kendiMusterim() : null;
  String? _orgAdi;

  late final _y = SayfaYukleyici.yerel<KorunanKisi>(
    () async => haritalar(
      harita(await Uyg.api.get('/api/v1/threat/people', q: {'organization_id': ?_orgId}))['items'],
    ).map(KorunanKisi.coz).toList(),
    sayfaBoyu: 25,
  )..yenile();

  bool get _yonetir => Uyg.yetki('spam.manage');

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _ekle() async {
    final org = _orgId;
    if (org == null) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => _KisiEkleDialog(orgId: org));
    if (ok == true) _y.yenile();
  }

  Future<void> _sil(KorunanKisi k) async {
    if (!await onayla(context, 'Kişi listeden çıkarılsın mı?', mesaj: '${k.ad} artık korunmayacak.', evet: 'Çıkar', tehlikeli: true)) return;
    if (await islem(() => Uyg.api.delete('/api/v1/threat/people/${k.id}'), tamam: 'Kişi çıkarıldı') != null) _y.degistir((x) => x.id == k.id, null);
  }

  List<SatirEylemi> _eylemler(KorunanKisi k) => [
    if (_yonetir) SatirEylemi(Icons.person_remove_outlined, 'Listeden çıkar', () => _sil(k), tehlikeli: true),
  ];

  @override
  Widget build(BuildContext context) {
    final orgGoster = !Uyg.musteri;
    return VeriTablosu<KorunanKisi>(
      yukleyici: _y,
      bosMetin: 'Korunan kişi listesi boş.',
      bosIkon: Icons.badge_outlined,
      eylemler: _eylemler,
      ust: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Aciklama(
              'Dışarıdan gelen bir iletinin görünen adı bu kişilerle eşleşirse (büyük/küçük harf, Türkçe karakter, benzer görünen harfler ve '
              'boşluklar yok sayılır) ileti puanlanır ve alıcıya "… gibi görünüyor ama dışarıdan geldi" uyarısı gösterilir. Kişinin gerçekten '
              'kullandığı dış adresler istisna olarak eklenebilir.',
            ),
          ),
          FiltreCubugu(
            filtreler: [
              if (orgGoster)
                MusteriFiltresi(
                  ad: _orgAdi,
                  degisti: (id, ad) {
                    setState(() {
                      _orgId = id;
                      _orgAdi = ad;
                    });
                    _y.yenile();
                  },
                ),
              if (_orgId != null)
                ActionChip(
                  avatar: const Icon(Icons.tune_rounded, size: 17),
                  label: const Text('Müşteri ayarları'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showDialog<void>(context: context, builder: (_) => MusteriTehditAyarlari(orgId: _orgId!)),
                ),
              if (_yonetir && _orgId != null) _ekleDugmesi('Kişi ekle', _ekle),
              if (_orgId == null) Text('Kişi eklemek için müşteri seçin.', style: TextStyle(color: context.r.silik, fontSize: 12.5)),
            ],
          ),
        ],
      ),
      sutunlar: [
        Sutun('Kişi', esnek: 3, hucre: (c, k) => IkiSatir(k.ad, alt: k.unvan.isEmpty ? '—' : k.unvan)),
        Sutun('İstisna adresler', esnek: 4, hucre: (c, k) => SolukMetin(k.adresler.join(', '))),
        if (orgGoster) Sutun('Müşteri', esnek: 2, hucre: (c, k) => SolukMetin(k.orgAdi)),
      ],
      kart: (c, k) => VeriKarti(
        baslik: k.ad,
        alt: k.unvan,
        sol: Avatar(k.ad, boyut: 36),
        eylemler: _eylemler(k),
        alanlar: [('İstisna adresler', k.adresler.join(', ')), if (orgGoster) ('Müşteri', k.orgAdi)],
      ),
    );
  }
}

class _KisiEkleDialog extends StatefulWidget {
  const _KisiEkleDialog({required this.orgId});
  final String orgId;
  @override
  State<_KisiEkleDialog> createState() => _KisiEkleDialogState();
}

class _KisiEkleDialogState extends State<_KisiEkleDialog> {
  final _ad = TextEditingController(), _unvan = TextEditingController(), _adresler = TextEditingController();
  String? _hata;
  bool _mesgul = false;

  @override
  void dispose() {
    _ad.dispose();
    _unvan.dispose();
    _adresler.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final ad = _ad.text.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).join(' ');
    if (ad.length < 4 || ad.length > 120 || !ad.contains(' ')) {
      setState(() => _hata = 'Ad ve soyad girin (4–120 karakter)');
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.post('/api/v1/threat/people', {
        'organization_id': widget.orgId,
        'name': ad,
        'title': _unvan.text.trim(),
        'emails': _adresler.text.split(RegExp(r'[,\s]+')).where((x) => x.isNotEmpty).toList(),
      });
      bildir('Korunan kişi eklendi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      setState(() => _hata = e.durum == 409 ? 'Bu kişi zaten listede.' : e.mesaj);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Korunan kişi ekle', style: gosterim(19, agirlik: FontWeight.w700)),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _ad, autofocus: true, decoration: const InputDecoration(labelText: 'Ad soyad', hintText: 'Ayşe Demir')),
            const SizedBox(height: 12),
            TextField(controller: _unvan, decoration: const InputDecoration(labelText: 'Unvan', hintText: 'Finans Müdürü')),
            const SizedBox(height: 12),
            TextField(
              controller: _adresler,
              decoration: const InputDecoration(
                labelText: 'İstisna dış adresler (isteğe bağlı)',
                hintText: 'ayse.demir@gmail.com',
                helperText: 'Virgül veya boşlukla ayırın (en fazla 10).',
              ),
            ),
            if (_hata != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 12.5))),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Ekle')),
    ],
  );
}

/// Müşterinin tehdit ayarları (GET/PUT /threat/orgs/{id}). Müşteri yöneticisi için salt okunur (platform politikası).
class MusteriTehditAyarlari extends StatefulWidget {
  const MusteriTehditAyarlari({super.key, required this.orgId});
  final String orgId;
  @override
  State<MusteriTehditAyarlari> createState() => _MusteriTehditAyarlariState();
}

class _MusteriTehditAyarlariState extends State<MusteriTehditAyarlari> {
  Map<String, dynamic>? _v;
  String? _hata;
  bool _mesgul = false;

  bool get _salt => !Uyg.ortak || !Uyg.yetki('spam.manage');

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/threat/orgs/${widget.orgId}'));
      if (mounted) setState(() => _v = v);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _kaydet(Map<String, dynamic> degisen) async {
    final v = _v!;
    setState(() => _mesgul = true);
    final y = await islem(
      () => Uyg.api.put('/api/v1/threat/orgs/${widget.orgId}', {
        'dmarc_mode': metin(v['dmarc_mode'], 'platform'),
        'mailbox_names': mantik(v['mailbox_names']),
        'banner': mantik(v['banner']),
        ...degisen,
      }),
      tamam: 'Kaydedildi',
    );
    if (!mounted) return;
    setState(() {
      _mesgul = false;
      if (y != null) _v = harita(y);
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final r = context.r;
    Widget govde;
    if (v == null) {
      govde = _hata != null ? Text(_hata!, style: const TextStyle(color: Marka.gul)) : const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    } else {
      final kip = metin(v['dmarc_mode'], 'platform');
      final kapali = _salt || _mesgul;
      govde = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: mantik(v['feature_enabled'])
                ? const Rozet('Kimlik taklidi koruması pakette açık', renk: Marka.zumrut, ikon: Icons.check_rounded)
                : const Rozet('Kimlik taklidi koruması pakette yok', renk: Marka.kehribar),
          ),
          const SizedBox(height: 10),
          const Aciklama(
            'DKIM/DMARC doğrulaması, kendi alan adınızı taklit eden iletiler ve bağlantı denetimi tüm paketlerde çalışır. Görünen ad (VIP) ve '
            'benzer alan adı denetimi "Kimlik taklidi ve benzer alan adı koruması" paket özelliğiyle açılır.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: dmarcKipleri.containsKey(kip) ? kip : 'platform',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'DMARC politikası uygulaması'),
            items: [for (final e in dmarcKipleri.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: kapali ? null : (k) => k == null ? null : _kaydet({'dmarc_mode': k}),
          ),
          const SizedBox(height: 4),
          Text(
            'Platform ayarı şu an: ${mantik(v['platform_dmarc_enforce']) ? 'uygula' : 'yalnızca izle'}. Birden çok müşteriye giden iletide en yumuşak ayar geçerlidir.',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
          const SizedBox(height: 8),
          AyarAnahtari(
            baslik: 'Tüm posta kutusu adlarını da koru',
            ipucu: 'Ad ve soyadı olan posta kutuları; düşük puan ve uyarı (aynı adlı gerçek dış kişiler uyarı görebilir).',
            deger: mantik(v['mailbox_names']),
            degisti: kapali ? null : (b) => _kaydet({'mailbox_names': b}),
          ),
          AyarAnahtari(
            baslik: 'Alıcıya uyarı göster',
            ipucu: 'Webmail\'de uyarı şeridi, IMAP istemcileri için X-BogaMail-Warning başlığı.',
            deger: mantik(v['banner']),
            degisti: kapali ? null : (b) => _kaydet({'banner': b}),
          ),
          if (_salt) ...[
            const SizedBox(height: 8),
            const Bant('Bu ayarlar platform politikasıdır; yalnızca platform ya da bayi yöneticisi değiştirebilir.', ikon: Icons.policy_outlined),
          ],
        ],
      );
    }
    return AlertDialog(
      title: Text('Müşteri tehdit ayarları', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: govde)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}

// ---- bağlantı listesi ---------------------------------------------------------------------------------------

/// Bağlantı engel/izin listesi: spam listelerinin "link" türündeki kayıtları (GET/POST/DELETE /spam/lists).
class TehditBaglantiListesi extends StatefulWidget {
  const TehditBaglantiListesi({super.key});
  @override
  State<TehditBaglantiListesi> createState() => _TehditBaglantiListesiState();
}

class _TehditBaglantiListesiState extends State<TehditBaglantiListesi> {
  late final _y = SayfaYukleyici.yerel<ListeKaydi>(
    () async => haritalar(harita(await Uyg.api.get('/api/v1/spam/lists'))['items']).map(ListeKaydi.coz).where((l) => l.tip == 'link').toList(),
  )..yenile();

  bool get _yonetir => Uyg.yetki('spam.manage');

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _ekle() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ListeEkleDialog(
        baslik: 'Bağlantı listesine ekle',
        turSec: true,
        aciklama: 'İleti gövdesindeki bağlantılar için alan adı (alt alan adlarını da kapsar) veya https:// ile başlayan adres öneki. '
            'Engel: +8 puan. İzin: o bağlantıya hiçbir bağlantı kuralı uygulanmaz.',
        kaydet: (tur, deger, _, org) => Uyg.api.post('/api/v1/spam/lists', {'kind': tur, 'type': 'link', 'value': deger, 'organization_id': ?org}),
      ),
    );
    if (ok == true) {
      bildir('Listeye eklendi', tur: MesajTur.basari);
      _y.yenile();
    }
  }

  Future<void> _sil(ListeKaydi k) async {
    if (!await onayla(context, 'Kayıt silinsin mi?', mesaj: '${k.deger} listeden çıkarılacak.', evet: 'Sil', tehlikeli: true)) return;
    if (await islem(() => Uyg.api.delete('/api/v1/spam/lists/${k.id}'), tamam: 'Kayıt silindi') != null) _y.degistir((x) => x.id == k.id, null);
  }

  List<SatirEylemi> _eylemler(ListeKaydi k) => [
    if (_yonetir && (Uyg.platformYoneticisi || k.orgId != null)) SatirEylemi(Icons.delete_outline_rounded, 'Sil', () => _sil(k), tehlikeli: true),
  ];

  Widget _turRozeti(ListeKaydi k) => k.tur == 'allow'
      ? const Rozet('İzin', renk: Marka.zumrut, ikon: Icons.verified_outlined)
      : const Rozet('Engel', renk: Marka.gul, ikon: Icons.gpp_bad_outlined);

  @override
  Widget build(BuildContext context) => VeriTablosu<ListeKaydi>(
    yukleyici: _y,
    bosMetin: 'Bağlantı listesi boş.',
    bosIkon: Icons.link_rounded,
    eylemler: _eylemler,
    ust: FiltreCubugu(
      arama: const Aciklama('Engel: +8 puan. İzin: o bağlantıya hiçbir bağlantı kuralı uygulanmaz (ör. bülten servisinizin yönlendirme alan adı).'),
      sag: _yonetir ? Padding(padding: const EdgeInsets.only(left: 8), child: _ekleDugmesi('Ekle', _ekle)) : null,
    ),
    sutunlar: [
      Sutun('Liste', genislik: 110, hucre: (c, k) => Align(alignment: Alignment.centerLeft, child: _turRozeti(k))),
      Sutun('Alan adı / adres', esnek: 4, hucre: (c, k) => IkiSatir(k.deger, alt: k.not.isEmpty ? null : k.not, mono: true)),
      Sutun('Kapsam', esnek: 2, hucre: (c, k) => SolukMetin(k.orgAdi ?? 'Tüm platform')),
      Sutun('Eklenme', esnek: 2, hucre: (c, k) => IkiSatir(kisaZaman(k.eklenme), alt: k.ekleyen, kalin: false)),
    ],
    kart: (c, k) => VeriKarti(
      baslik: k.deger,
      alt: k.not,
      rozetler: [_turRozeti(k)],
      eylemler: _eylemler(k),
      alanlar: [('Kapsam', k.orgAdi ?? 'Tüm platform'), ('Eklenme', kisaZaman(k.eklenme))],
    ),
  );
}

// ---- IP / ASN itibarı (süper yönetici) ----------------------------------------------------------------------

/// IP / ASN itibarı: ASN istatistikleri (engel/izin listesi yönetimi) ve IP itibarı (GET /threat/asn, /threat/ips).
class TehditItibar extends StatefulWidget {
  const TehditItibar({super.key});
  @override
  State<TehditItibar> createState() => _TehditItibarState();
}

class _TehditItibarState extends State<TehditItibar> {
  int _gorunum = 0;
  String _asnQ = '', _ipQ = '';
  String _asnSira = 'messages', _ipSira = 'last_seen';
  bool _asnArtan = false, _ipArtan = false;

  late final _asn = SayfaYukleyici<AsnIstatistigi>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/threat/asn',
        q: {'page': '$s', 'page_size': '$b', 'sort': _asnSira, 'order': _asnArtan ? 'asc' : 'desc', if (_asnQ.isNotEmpty) 'q': _asnQ},
      ),
      AsnIstatistigi.coz,
    ),
    sayfaBoyu: 20,
  )..yenile();

  late final _ip = SayfaYukleyici<IpItibari>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/threat/ips',
        q: {'page': '$s', 'page_size': '$b', 'sort': _ipSira, 'order': _ipArtan ? 'asc' : 'desc', if (_ipQ.isNotEmpty) 'q': _ipQ},
      ),
      IpItibari.coz,
    ),
    sayfaBoyu: 20,
  )..yenile();

  @override
  void dispose() {
    _asn.dispose();
    _ip.dispose();
    super.dispose();
  }

  /// ASN'yi platform engel/izin listesine alır ya da listeden çıkarır (web: setList).
  Future<void> _listele(AsnIstatistigi a, String? tur) async {
    final ok = await islem(() async {
      final kayitlar = haritalar(harita(await Uyg.api.get('/api/v1/spam/lists'))['items']).map(ListeKaydi.coz);
      for (final e in kayitlar.where((e) => e.tip == 'asn' && e.orgId == null && e.deger.toUpperCase() == 'AS${a.asn}')) {
        await Uyg.api.delete('/api/v1/spam/lists/${e.id}');
      }
      if (tur != null) {
        await Uyg.api.post('/api/v1/spam/lists', {
          'kind': tur,
          'type': 'asn',
          'value': 'AS${a.asn}',
          'note': a.ad.length > 200 ? a.ad.substring(0, 200) : a.ad,
        });
      }
      return true;
    }, tamam: tur == 'block' ? 'ASN engel listesine eklendi' : (tur == 'allow' ? 'ASN izin listesine eklendi' : 'ASN listeden çıkarıldı'));
    if (ok != null) _asn.sayfaGit(_asn.sayfa < 1 ? 1 : _asn.sayfa);
  }

  void _yonet(AsnIstatistigi a) {
    void sec(String? tur) {
      Navigator.pop(context);
      _listele(a, tur);
    }

    ayrintiGoster(
      context,
      baslik: 'AS${a.asn}',
      alt: '${a.ad} · ${a.ulke} · ${sayiYaz(a.ileti)} ileti, spam/ret ${oranYaz(a.kotuOran)}',
      icerik: [
        if (a.liste != 'block')
          EylemSatiri(
            ikon: Icons.block_rounded,
            baslik: 'Engel listesine ekle',
            ipucu: 'Bu AS\'den gelen her ileti +10 puan alır (platform geneli).',
            tehlikeli: true,
            onTap: () => sec('block'),
          ),
        if (a.liste != 'allow') ...[
          const SizedBox(height: 8),
          EylemSatiri(
            ikon: Icons.how_to_reg_outlined,
            baslik: 'İzin listesine ekle',
            ipucu: '−3 puan; DMARC ve diğer denetimler yine uygulanır.',
            onTap: () => sec('allow'),
          ),
        ],
        if (a.liste != null) ...[
          const SizedBox(height: 8),
          EylemSatiri(ikon: Icons.delete_outline_rounded, baslik: 'Listeden çıkar', ipucu: 'ASN için özel puan uygulanmaz.', onTap: () => sec(null)),
        ],
      ],
    );
  }

  Widget? _listeRozeti(AsnIstatistigi a) => switch (a.liste) {
    'block' => const Rozet('Engel', renk: Marka.gul),
    'allow' => const Rozet('İzin', renk: Marka.zumrut),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final secici = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, icon: Icon(Icons.hub_outlined, size: 18), label: Text('ASN itibarı')),
            ButtonSegment(value: 1, icon: Icon(Icons.dns_outlined, size: 18), label: Text('IP itibarı')),
          ],
          selected: {_gorunum},
          onSelectionChanged: (s) => setState(() => _gorunum = s.first),
        ),
      ),
    );
    if (_gorunum == 0) {
      return VeriTablosu<AsnIstatistigi>(
        key: const ValueKey('asn'),
        yukleyici: _asn,
        bosMetin: 'Veri yok. İlk iletiler geldikçe dolar.',
        bosIkon: Icons.hub_outlined,
        siralama: _asnSira,
        artan: _asnArtan,
        siralamaDegisti: (a, b) {
          setState(() {
            _asnSira = a;
            _asnArtan = b;
          });
          _asn.yenile();
        },
        onTap: _yonet,
        eylemler: (a) => [SatirEylemi(Icons.tune_rounded, 'Listeyi yönet', () => _yonet(a))],
        ust: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            secici,
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Aciklama(
                'İstemci IP\'sinin AS numarası Team Cymru DNS servisiyle bulunur ve 24 saat önbelleğe alınır. Oranlar yalnızca bizim sunucumuza '
                'gelen iletilerden hesaplanır. Engel listesi +10 puan (tek başına Önemsiz), izin listesi −3 puan.',
              ),
            ),
            FiltreCubugu(
              arama: AramaAlani(
                ipucu: 'AS numarası, ad veya ülke…',
                degisti: (v) {
                  _asnQ = v;
                  _asn.yenile();
                },
              ),
            ),
          ],
        ),
        sutunlar: [
          Sutun(
            'AS',
            esnek: 4,
            hucre: (c, a) => Row(
              children: [
                Text('AS${a.asn}', style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600)),
                if (_listeRozeti(a) != null) ...[const SizedBox(width: 6), _listeRozeti(a)!],
                const SizedBox(width: 8),
                Expanded(child: SolukMetin(a.ad)),
              ],
            ),
          ),
          Sutun('Ülke', genislik: 70, hucre: (c, a) => SolukMetin(a.ulke)),
          Sutun('İleti', genislik: 90, siralama: 'messages', sagaYasla: true, hucre: (c, a) => Text(sayiYaz(a.ileti))),
          Sutun(
            'Spam/ret',
            genislik: 100,
            siralama: 'bad',
            sagaYasla: true,
            hucre: (c, a) => Text(oranYaz(a.kotuOran), style: TextStyle(color: a.kotuOran >= .7 ? Marka.gul : null, fontWeight: FontWeight.w600)),
          ),
          Sutun('Son', genislik: 120, siralama: 'last_seen', hucre: (c, a) => SolukMetin(kisaZaman(a.son))),
        ],
        kart: (c, a) => VeriKarti(
          baslik: 'AS${a.asn}',
          alt: a.ad,
          onTap: () => _yonet(a),
          rozetler: [?_listeRozeti(a)],
          alanlar: [('İleti', sayiYaz(a.ileti)), ('Spam/ret', oranYaz(a.kotuOran)), ('Ülke', a.ulke), ('Son', kisaZaman(a.son))],
        ),
      );
    }
    return VeriTablosu<IpItibari>(
      key: const ValueKey('ip'),
      yukleyici: _ip,
      bosMetin: 'Veri yok.',
      bosIkon: Icons.dns_outlined,
      siralama: _ipSira,
      artan: _ipArtan,
      siralamaDegisti: (a, b) {
        setState(() {
          _ipSira = a;
          _ipArtan = b;
        });
        _ip.yenile();
      },
      ust: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          secici,
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Aciklama(
              'Puan = spam veya ret oranı (%). En az 10 iletisi olan IP\'lerde %80 ve üzeri +2, %50 ve üzeri +1 puan; 20+ temiz iletide −0,5 puan. '
              'IP engellemek için Spam Güvenliği listelerini kullanın.',
            ),
          ),
          FiltreCubugu(
            arama: AramaAlani(
              ipucu: 'IP, AS numarası veya adı…',
              degisti: (v) {
                _ipQ = v;
                _ip.yenile();
              },
            ),
          ),
        ],
      ),
      sutunlar: [
        Sutun('IP', esnek: 4, hucre: (c, i) => IkiSatir(i.ip, mono: true, alt: i.asn != null ? 'AS${i.asn} ${i.asAdi ?? ''}' : 'AS bilinmiyor')),
        Sutun('İleti', genislik: 90, siralama: 'messages', sagaYasla: true, hucre: (c, i) => Text(sayiYaz(i.ileti))),
        Sutun('Spam / ret', genislik: 110, sagaYasla: true, hucre: (c, i) => SolukMetin('${sayiYaz(i.spam)} / ${sayiYaz(i.ret)}')),
        Sutun('Son', genislik: 120, siralama: 'last_seen', hucre: (c, i) => SolukMetin(kisaZaman(i.son))),
        Sutun(
          'Puan',
          genislik: 80,
          siralama: 'score',
          sagaYasla: true,
          hucre: (c, i) => Text(i.puan.toStringAsFixed(0), style: TextStyle(fontWeight: FontWeight.w700, color: i.puan >= 50 ? Marka.gul : null)),
        ),
      ],
      kart: (c, i) => VeriKarti(
        baslik: i.ip,
        alt: i.asn != null ? 'AS${i.asn} ${i.asAdi ?? ''}' : 'AS bilinmiyor',
        rozetler: [Rozet('Puan ${i.puan.toStringAsFixed(0)}', renk: i.puan >= 50 ? Marka.gul : Colors.blueGrey)],
        alanlar: [('İleti', sayiYaz(i.ileti)), ('Spam', sayiYaz(i.spam)), ('Ret', sayiYaz(i.ret)), ('Son', kisaZaman(i.son))],
      ),
    );
  }
}
