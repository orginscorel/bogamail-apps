import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import '../ortak/simgeler.dart';

const _nedenler = <(String, String)>[
  ('hard_bounce', 'Kalıcı geri dönüş'),
  ('complaint', 'Spam şikâyeti'),
  ('unsubscribe', 'Abonelikten çıkış'),
  ('manual', 'Elle eklendi'),
];

String _nedenEtiketi(String n) => _nedenler.firstWhere((x) => x.$1 == n, orElse: () => (n, n)).$2;

Color _nedenRengi(String n) => switch (n) {
  'hard_bounce' => Marka.gul,
  'complaint' => Marka.kehribar,
  'unsubscribe' => const Color(0xFF94A3B8),
  _ => Marka.mavi,
};

/// Bastırma kaydı (outbound_scale.go suppressionRow).
class _Bastirma {
  const _Bastirma({
    required this.id,
    this.orgId,
    this.orgAdi = '',
    required this.adres,
    required this.neden,
    this.kaynak = '',
    this.ayrinti = '',
    this.engellenen = 0,
    this.eklenme,
    this.dusme,
  });
  final String id, adres, neden, kaynak, ayrinti, orgAdi;
  final String? orgId;
  final int engellenen;
  final DateTime? eklenme, dusme;

  factory _Bastirma.coz(Map<String, dynamic> m) => _Bastirma(
    id: metin(m['id']),
    orgId: metinYa(m['organization_id']),
    orgAdi: metin(m['organization_name']),
    adres: metin(m['address']),
    neden: metin(m['reason']),
    kaynak: metin(m['source']),
    ayrinti: metin(m['detail']),
    engellenen: tamsayi(m['hits']),
    eklenme: tarihOku(m['created_at']),
    dusme: tarihOku(m['expires_at']),
  );

  String get altSatir => [kaynak.isEmpty ? '—' : kaynak, if (ayrinti.isNotEmpty) ayrinti, if (engellenen > 0) '$engellenen gönderim engellendi'].join(' · ');
}

/// Bastırma Listesi: gönderimi engellenen adresler (GET/POST/DELETE /suppressions) ve FBL şikâyet raporları (GET /fbl/reports).
class BastirmaListesiEkrani extends StatefulWidget {
  const BastirmaListesiEkrani({super.key});
  @override
  State<BastirmaListesiEkrani> createState() => _BastirmaListesiEkraniState();
}

class _BastirmaListesiEkraniState extends State<BastirmaListesiEkrani> {
  String _q = '';
  String _neden = '';
  final _sayilar = ValueNotifier<Map<String, int>?>(null);

  late final _y = SayfaYukleyici<_Bastirma>((s, b) async {
    final v = harita(
      await Uyg.api.get(
        '/api/v1/suppressions',
        q: {'limit': '$b', 'offset': '${(s - 1) * b}', if (_q.isNotEmpty) 'q': _q, if (_neden.isNotEmpty) 'reason': _neden},
      ),
    );
    final c = harita(v['counts']);
    if (mounted) _sayilar.value = {for (final (k, _) in _nedenler) k: tamsayi(c[k])};
    return Sayfa.coz(v, _Bastirma.coz);
  }, sayfaBoyu: 50)..yenile();

  late final _fbl = SayfaYukleyici.yerel<Map<String, dynamic>>(
    () async => haritalar(harita(await Uyg.api.get('/api/v1/fbl/reports'))['items']),
    sayfaBoyu: 25,
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    _fbl.dispose();
    _sayilar.dispose();
    super.dispose();
  }

  /// Çıkarma yalnızca ortaklara açık (paylaşılan IP itibarı); platform geneli kayıtlar yalnızca süper yöneticiye.
  bool _cikarabilir(_Bastirma s) => !Uyg.musteri && (s.orgId != null || Uyg.platformYoneticisi);

  Future<void> _cikar(_Bastirma s) async {
    final ek = switch (s.neden) {
      'complaint' => ' Bu kişi spam şikâyetinde bulundu; çıkarmak IP itibarını riske atar.',
      'hard_bounce' => ' Adres var olmadığı için geri dönmüştü.',
      _ => '',
    };
    final ok = await onayla(
      context,
      'Adres listeden çıkarılsın mı?',
      mesaj: '${s.adres} adresine yeniden gönderim yapılabilir.$ek İşlem denetim kaydına yazılır.',
      evet: 'Çıkar',
      tehlikeli: true,
    );
    if (!ok) return;
    await islem(() => Uyg.api.delete('/api/v1/suppressions/${s.id}'), tamam: 'Listeden çıkarıldı');
    _y.yenile();
  }

  Future<void> _ekle() async {
    final eklendi = await showDialog<bool>(context: context, builder: (_) => const _EkleDialog());
    if (eklendi == true) _y.yenile();
  }

  void _nedenSec(String v) {
    setState(() => _neden = v);
    _y.yenile();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Iskelet(
          baslik: 'Bastırma Listesi',
          alt: 'Bu adreslere gönderim engellenir',
          yenile: () {
            _y.yenile();
            _fbl.yenile();
          },
          birincil: BirincilEylem(Simgeler.add, 'Adres ekle', _ekle),
          sekmeler: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Adresler'), Tab(text: 'Şikâyet raporları')],
          ),
          govde: TabBarView(children: [_adresler(context), _raporlar(context)]),
        ),
      ),
    );
  }

  Widget _adresler(BuildContext context) => VeriTablosu<_Bastirma>(
    yukleyici: _y,
    bosMetin: 'Kayıt yok. Geri dönen, şikâyet eden veya elle eklenen adresler burada görünür.',
    bosIkon: Simgeler.block,
    ust: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(context.genis ? 16 : 12, 8, context.genis ? 16 : 12, 2),
          child: Text(
            'Kalıcı geri dönüşler 30 gün sonra kendiliğinden düşer; spam şikâyeti ve abonelikten çıkış yalnızca toplu gönderimi '
            'engeller, elle eklenenler ve kalıcı geri dönüşler her postayı engeller.',
            style: TextStyle(color: context.r.silik, fontSize: 12.5),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _sayilar,
          builder: (c, s, _) => s == null
              ? const SizedBox.shrink()
              : SizedBox(
                  height: 72,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.fromLTRB(context.genis ? 16 : 12, 8, 12, 0),
                    children: [
                      for (final (k, e) in _nedenler)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _SayacKutusu(etiket: e, deger: s[k] ?? 0, renk: _nedenRengi(k), secili: _neden == k, onTap: () => _nedenSec(_neden == k ? '' : k)),
                        ),
                    ],
                  ),
                ),
        ),
        FiltreCubugu(
          arama: AramaAlani(
            ipucu: 'Adres ara…',
            degisti: (v) {
              _q = v;
              _y.yenile();
            },
          ),
          filtreler: [
            FiltreDugmesi<String>(etiket: 'Neden', ikon: Simgeler.filterList, secenekler: [('', 'Tüm nedenler'), ..._nedenler], secili: _neden, secildi: _nedenSec),
          ],
          etkinler: [if (_neden.isNotEmpty) EtkinFiltre('Neden: ${_nedenEtiketi(_neden)}', () => _nedenSec(''))],
        ),
      ],
    ),
    eylemler: (s) => [if (_cikarabilir(s)) SatirEylemi(Simgeler.deleteOutline, 'Listeden çıkar', () => _cikar(s), tehlikeli: true)],
    sutunlar: [
      Sutun('Adres', esnek: 4, hucre: (_, s) => IkiSatir(s.adres, alt: s.altSatir, mono: true)),
      Sutun(
        'Neden',
        esnek: 2,
        hucre: (c, s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Rozet(_nedenEtiketi(s.neden), renk: _nedenRengi(s.neden)),
            if (s.dusme != null) Text('${tamZaman(s.dusme)} düşer', style: TextStyle(color: c.r.silik, fontSize: 11.5)),
          ],
        ),
      ),
      Sutun('Müşteri', esnek: 2, hucre: (_, s) => s.orgId == null ? const Rozet('Platform geneli', renk: Marka.mor) : SolukMetin(s.orgAdi)),
      Sutun('Eklenme', genislik: 150, hucre: (_, s) => SolukMetin(tamZaman(s.eklenme))),
    ],
    kart: (c, s) => VeriKarti(
      baslik: s.adres,
      alt: s.altSatir,
      rozetler: [Rozet(_nedenEtiketi(s.neden), renk: _nedenRengi(s.neden)), if (s.orgId == null) const Rozet('Platform geneli', renk: Marka.mor)],
      alanlar: [
        if (s.orgId != null) ('Müşteri', s.orgAdi),
        ('Eklenme', tamZaman(s.eklenme)),
        if (s.dusme != null) ('Düşme', tamZaman(s.dusme)),
      ],
      eylemler: [if (_cikarabilir(s)) SatirEylemi(Simgeler.deleteOutline, 'Listeden çıkar', () => _cikar(s), tehlikeli: true)],
    ),
  );

  Widget _raporlar(BuildContext context) => VeriTablosu<Map<String, dynamic>>(
    yukleyici: _fbl,
    bosMetin: 'Şikâyet raporu yok. Posta sağlayıcılarından gelen spam şikâyetleri (ARF) burada listelenir.',
    bosIkon: Simgeler.reportGmailerrorred,
    sutunlar: [
      Sutun(
        'Şikâyet eden alıcı',
        esnek: 4,
        hucre: (_, r) => IkiSatir(
          metinYa(r['recipient']) ?? (mantik(r['parsed']) ? '—' : 'Okunamayan bildirim'),
          alt: [metinYa(r['reporter']) ?? metinYa(r['subject']) ?? '—', ?metinYa(r['organization_name'])].join(' · '),
          mono: true,
        ),
      ),
      Sutun(
        'Tür',
        esnek: 1,
        hucre: (_, r) => mantik(r['parsed']) ? Rozet(metin(r['feedback_type'], '—'), renk: Marka.kehribar) : const Rozet('okunamadı', renk: Color(0xFF94A3B8)),
      ),
      Sutun('Gönderen alan adı', esnek: 2, hucre: (_, r) => SolukMetin(metin(r['sender_domain']))),
      Sutun('Tarih', genislik: 150, hucre: (_, r) => SolukMetin(tamZaman(tarihOku(r['received_at'])))),
    ],
    kart: (c, r) => VeriKarti(
      baslik: metinYa(r['recipient']) ?? (mantik(r['parsed']) ? '—' : 'Okunamayan bildirim'),
      alt: [metinYa(r['reporter']) ?? metinYa(r['subject']) ?? '—', ?metinYa(r['organization_name'])].join(' · '),
      rozetler: [mantik(r['parsed']) ? Rozet(metin(r['feedback_type'], '—'), renk: Marka.kehribar) : const Rozet('okunamadı', renk: Color(0xFF94A3B8))],
      alanlar: [('Gönderen alan adı', metin(r['sender_domain'])), ('Tarih', tamZaman(tarihOku(r['received_at'])))],
    ),
  );
}

class _SayacKutusu extends StatelessWidget {
  const _SayacKutusu({required this.etiket, required this.deger, required this.renk, required this.secili, required this.onTap});
  final String etiket;
  final int deger;
  final Color renk;
  final bool secili;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Material(
      color: secili ? r.vurguYumusak : r.kart,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: secili ? r.vurgu : r.kenar)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 170,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  DurumNoktasi(renk, boyut: 7),
                  const SizedBox(width: 8),
                  Expanded(child: Text(etiket, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 12))),
                ],
              ),
              Text(sayiYaz(deger), style: gosterim(18, agirlik: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Elle adres ekleme (POST /suppressions {address, note, organization_id?}).
class _EkleDialog extends StatefulWidget {
  const _EkleDialog();
  @override
  State<_EkleDialog> createState() => _EkleDialogState();
}

class _EkleDialogState extends State<_EkleDialog> {
  final _adres = TextEditingController();
  final _not = TextEditingController();
  final _form = GlobalKey<FormState>();

  /// Müşteri seçimi: null = seçilmedi; ('', 'Platform geneli') yalnızca süper yönetici için.
  (String, String)? _org = Uyg.platformYoneticisi ? ('', 'Platform geneli (tüm müşteriler)') : null;
  String? _hata;
  bool _mesgul = false;

  bool get _musteriGerekli => !Uyg.musteri;

  @override
  void dispose() {
    _adres.dispose();
    _not.dispose();
    super.dispose();
  }

  Future<void> _musteriSec() async {
    if (Uyg.platformYoneticisi) {
      final secim = await secimYap<String>(
        context,
        baslik: 'Kapsam',
        secenekler: const [('', 'Platform geneli', 'Tüm müşteriler için engellenir'), ('musteri', 'Bir müşteri', 'Yalnızca seçilen müşteri için')],
        secili: _org?.$1 == '' ? '' : 'musteri',
      );
      if (secim == null || !mounted) return;
      if (secim == '') {
        setState(() => _org = ('', 'Platform geneli (tüm müşteriler)'));
        return;
      }
    }
    final o = await musteriSec(context);
    if (o != null && mounted) setState(() => _org = (o.id, o.ad));
  }

  Future<void> _kaydet() async {
    if (!_form.currentState!.validate()) return;
    if (_musteriGerekli && _org == null) {
      setState(() => _hata = 'Müşteri seçin');
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.post('/api/v1/suppressions', {
        'address': _adres.text.trim(),
        'note': _not.text.trim(),
        if (_musteriGerekli && _org != null && _org!.$1.isNotEmpty) 'organization_id': _org!.$1,
      });
      bildir('Adres eklendi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Adres ekle', style: gosterim(19, agirlik: FontWeight.w600)),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Elle eklenen adreslere hiçbir posta gönderilmez (kişisel posta dahil).', style: TextStyle(color: context.r.soluk, fontSize: 13)),
            const SizedBox(height: 16),
            if (_musteriGerekli) ...[SecimAlani(etiket: 'Müşteri', deger: _org?.$2, onTap: _musteriSec), const SizedBox(height: 12)],
            TextFormField(
              controller: _adres,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-posta adresi'),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Adres girin';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'Geçerli bir e-posta adresi girin';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _not,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)'),
            ),
            if (_hata != null) Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(onPressed: _mesgul ? null : _kaydet, child: Text(_mesgul ? 'Ekleniyor…' : 'Ekle')),
    ],
  );
}
