import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import 'kutu_formlari.dart';
import 'musteri_model.dart';
import '../ortak/simgeler.dart';

/// Müşteri kartı: oluşturma (POST /organizations) ve düzenleme (PATCH /organizations/{id}).
/// Web customer-form.tsx ile aynı alanlar: firma, yetkili, teknik irtibat, fatura/vergi, adres, paket, (ortaklar) dahili notlar.
/// Oluştururken isteğe bağlı olarak müşterinin ilk panel yöneticisi açılır (POST /users, role org_admin).
Future<Musteri?> musteriFormuAc(BuildContext context, {Musteri? musteri}) => showDialog<Musteri>(
  context: context,
  barrierDismissible: false,
  builder: (_) => MusteriFormu(musteri: musteri),
);

class MusteriFormu extends StatefulWidget {
  const MusteriFormu({super.key, this.musteri});
  final Musteri? musteri;
  @override
  State<MusteriFormu> createState() => _MusteriFormuState();
}

/// Profilde serbest metin olarak tutulan alanlar.
const _metinAlanlari = [
  'legal_name', 'website', 'contact_name', 'contact_title', 'contact_email', 'contact_phone', 'contact_mobile', //
  'tech_name', 'tech_email', 'tech_phone', 'billing_email', 'tax_office', 'tax_number', 'mersis_no', //
  'address', 'district', 'city', 'postal_code', 'country', 'source', 'notes',
];

const _faturaAlanlari = {'legal_name', 'tax_office', 'tax_number', 'mersis_no', 'billing_email', 'address', 'district', 'city', 'postal_code', 'country'};
const _digerAlanlar = {'company_size', 'website', 'contact_title', 'contact_mobile', 'tech_name', 'tech_email', 'tech_phone', 'source', 'notes'};

class _MusteriFormuState extends State<MusteriFormu> with SingleTickerProviderStateMixin {
  late final Musteri? _m = widget.musteri;
  late final bool _yeni = _m == null;
  final bool _ortak = Uyg.ortak;
  final bool _super = Uyg.platformYoneticisi;
  late final _sekme = TabController(length: 3, vsync: this);

  late final _ad = TextEditingController(text: _m?.ad ?? '');
  late final Map<String, TextEditingController> _k = {
    for (final a in _metinAlanlari) a: TextEditingController(text: metin(_m?.profil[a], a == 'country' ? 'TR' : '')),
  };
  late String _tur = metin(_m?.profil['customer_type'], 'corporate');
  late String? _sektor = metinYa(_m?.profil['sector']);
  late String? _calisan = metinYa(_m?.profil['company_size']);
  late String? _paket = _m?.paketId ?? (_super ? '' : null); // '' = paketsiz (yalnızca süper, oluştururken)
  String _bayi = '';
  late String _durum = _m?.durum ?? 'active';
  late bool _teknikAyni = (_m?.p('tech_name') ?? '').isEmpty && (_m?.p('tech_email') ?? '').isEmpty;
  late bool _yoneticiAc = _yeni && _ortak && Uyg.yetki('users.manage');
  final _yoneticiEposta = TextEditingController();
  final _yoneticiSifre = TextEditingController(text: sifreUret());

  List<Map<String, dynamic>>? _paketler;
  List<Map<String, dynamic>>? _bayiler;
  bool _mesgul = false;
  String? _hata, _alan;

  @override
  void initState() {
    super.initState();
    if (_ortak) _paketleriYukle();
    if (_super && _yeni) _bayileriYukle();
  }

  Future<void> _paketleriYukle() async {
    try {
      final v = await Uyg.api.get('/api/v1/plans');
      if (mounted) setState(() => _paketler = haritalar(harita(v)['items']));
    } catch (_) {
      if (mounted) setState(() => _paketler = const []);
    }
  }

  Future<void> _bayileriYukle() async {
    try {
      final v = await Uyg.api.get('/api/v1/resellers');
      if (mounted) setState(() => _bayiler = haritalar(harita(v)['items']));
    } catch (_) {
      if (mounted) setState(() => _bayiler = const []);
    }
  }

  @override
  void dispose() {
    _sekme.dispose();
    _ad.dispose();
    for (final c in _k.values) {
      c.dispose();
    }
    _yoneticiEposta.dispose();
    _yoneticiSifre.dispose();
    super.dispose();
  }

  String _v(String a) => _k[a]!.text.trim();
  bool get _bireysel => _tur == 'individual';

  void _hataVer(String alan, String mesaj) {
    setState(() {
      _alan = alan;
      _hata = mesaj;
    });
    final k = alan.replaceFirst('profile.', '');
    _sekme.animateTo(_faturaAlanlari.contains(k) ? 1 : (_digerAlanlar.contains(k) ? 2 : 0));
  }

  String? _hataOf(String alan) => _alan == alan ? _hata : null;

  Future<void> _kaydet() async {
    setState(() => _hata = _alan = null);
    if (_ad.text.trim().isEmpty) return _hataVer('name', 'Müşteri adını girin');
    if (_yeni) {
      if (_sektor == null) return _hataVer('profile.sector', 'Sektör seçin');
      if (_v('contact_name').isEmpty) return _hataVer('profile.contact_name', 'Yetkili adını girin');
      if (_v('contact_phone').isEmpty) return _hataVer('profile.contact_phone', 'Telefon girin');
      if (_v('contact_email').isEmpty) return _hataVer('profile.contact_email', 'E-posta girin');
      if (_ortak && _paket == null) return _hataVer('plan_id', 'Paket seçin');
    }
    // Profil tam olarak değiştirilir: bilinmeyen alanlar korunur.
    final profil = <String, dynamic>{...?_m?.profil};
    for (final a in _metinAlanlari) {
      profil[a] = _v(a);
    }
    profil['customer_type'] = _tur;
    profil['sector'] = _sektor ?? '';
    profil['company_size'] = _bireysel ? '' : (_calisan ?? '');
    if (_teknikAyni) {
      profil['tech_name'] = profil['tech_email'] = profil['tech_phone'] = '';
    }
    if (_bireysel) profil['mersis_no'] = profil['legal_name'] = '';
    if (!_ortak) profil.remove('notes');
    if (!_ortak) profil.remove('source');
    profil.removeWhere((_, v) => v is String && v.isEmpty);

    setState(() => _mesgul = true);
    try {
      final Musteri sonuc;
      if (!_yeni) {
        final m = _m!;
        final govde = <String, dynamic>{'name': _ad.text.trim(), 'profile': profil};
        if (_ortak) {
          if (_paket != null && _paket!.isNotEmpty && _paket != m.paketId) govde['plan_id'] = _paket;
          if (_durum != m.durum) govde['status'] = _durum;
        }
        sonuc = Musteri.coz(harita(await Uyg.api.patch('/api/v1/organizations/${m.id}', govde)));
        bildir('Müşteri güncellendi', tur: MesajTur.basari);
      } else {
        sonuc = Musteri.coz(
          harita(
            await Uyg.api.post('/api/v1/organizations', {
              'name': _ad.text.trim(),
              'profile': profil,
              'plan_id': (_paket ?? '').isEmpty ? null : _paket,
              'reseller_id': _bayi.isEmpty ? null : _bayi,
            }),
          ),
        );
        bildir('Müşteri oluşturuldu', mesaj: sonuc.ad, tur: MesajTur.basari);
        if (_yoneticiAc) await _yoneticiOlustur(sonuc);
      }
      if (mounted) Navigator.pop(context, sonuc);
    } on ApiHata catch (e) {
      if (!mounted) return;
      if (e.alan != null && e.alan!.isNotEmpty) {
        _hataVer(e.alan!, e.mesaj);
      } else {
        setState(() => _hata = e.mesaj);
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _yoneticiOlustur(Musteri m) async {
    final eposta = (_yoneticiEposta.text.trim().isEmpty ? _v('contact_email') : _yoneticiEposta.text.trim()).toLowerCase();
    final sifre = _yoneticiSifre.text;
    try {
      await Uyg.api.post('/api/v1/users', {
        'email': eposta,
        'display_name': _v('contact_name'),
        'phone': _v('contact_mobile').isNotEmpty ? _v('contact_mobile') : _v('contact_phone'),
        'title': _v('contact_title'),
        'password': sifre,
        'role': 'org_admin',
        'organization_id': m.id,
      });
      if (!mounted) return;
      await sifreGoster(
        context,
        adres: eposta,
        sifre: sifre,
        not: 'Müşteri paneli yöneticisi oluşturuldu. Şifreyi müşteriye güvenli bir kanaldan iletin; daha sonra görüntülenemez.',
      );
    } catch (e) {
      bildir('Müşteri oluşturuldu ancak yönetici hesabı açılamadı', mesaj: '${hataMetni(e)} · Kullanıcılar bölümünden ekleyebilirsiniz.', tur: MesajTur.hata);
    }
  }

  Widget _alanKutusu(String a, String etiket, {bool zorunlu = false, String? ipucu, String? yardim, TextInputType? tur, int satir = 1, int? enFazla}) =>
      TextField(
        controller: _k[a],
        keyboardType: tur,
        maxLines: satir,
        minLines: 1,
        maxLength: enFazla,
        autocorrect: false,
        textCapitalization: a == 'country' ? TextCapitalization.characters : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: zorunlu ? '$etiket *' : etiket,
          hintText: ipucu,
          helperText: yardim,
          counterText: '',
          errorText: _hataOf('profile.$a'),
        ),
      );

  Widget _izgara(List<Widget> l, {int sutun = 2}) => LayoutBuilder(
    builder: (c, k) {
      final n = k.maxWidth >= 640 ? sutun : 1;
      final g = (k.maxWidth - (n - 1) * 12) / n;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final w in l) SizedBox(width: g, child: w)],
      );
    },
  );

  Widget _grup(IconData ikon, String baslik, List<Widget> l, {int sutun = 2}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(ikon, size: 16, color: context.r.vurgu),
            const SizedBox(width: 8),
            Text(
              baslik.toUpperCase(),
              style: TextStyle(fontSize: 11.5, letterSpacing: .4, fontWeight: FontWeight.w600, color: context.r.soluk),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _izgara(l, sutun: sutun),
      ],
    ),
  );

  Widget _secim<T>(String etiket, T? deger, List<(T, String)> secenekler, ValueChanged<T?> degisti, {String? hata, bool etkin = true}) =>
      DropdownButtonFormField<T>(
        initialValue: secenekler.any((s) => s.$1 == deger) ? deger : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: etiket, errorText: hata),
        items: [
          for (final (d, e) in secenekler)
            DropdownMenuItem<T>(
              value: d,
              child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: etkin ? degisti : null,
      );

  Widget _temel() {
    final paketler = _paketler;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      children: [
        _izgara([
          TextField(
            controller: _ad,
            autofocus: _yeni,
            maxLength: 200,
            decoration: InputDecoration(labelText: 'Müşteri adı *', counterText: '', errorText: _hataOf('name')),
            onChanged: (_) => setState(() {}),
          ),
          _secim<String>(
            _yeni ? 'Sektör *' : 'Sektör',
            _sektor,
            [for (final e in sektorler.entries) (e.key, e.value)],
            (v) => setState(() => _sektor = v),
            hata: _hataOf('profile.sector'),
          ),
          if (_ortak)
            paketler == null
                ? const InputDecorator(
                    decoration: InputDecoration(labelText: 'Paket'),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                : _secim<String>(
                    _yeni ? 'Paket *' : 'Paket',
                    _paket,
                    [
                      if (_super && _yeni) ('', 'Paketsiz (sınırsız)'),
                      for (final p in paketler)
                        (
                          metin(p['id']),
                          '${metin(p['name'])} · ${sinirYaz(tamsayiYa(p['max_mailboxes']))} kutu · '
                              '${tamsayiYa(p['total_quota_bytes']) == null ? 'sınırsız' : boyutYaz(tamsayi(p['total_quota_bytes']))}',
                        ),
                      // Arşivlenmiş mevcut paket listede olmayabilir.
                      if (_m?.paketId case final pid? when !paketler.any((p) => metin(p['id']) == pid)) (pid, _m?.paketAdi ?? 'Mevcut paket'),
                    ],
                    (v) => setState(() => _paket = v),
                    hata: _hataOf('plan_id'),
                  ),
          if (_super && _yeni)
            _secim<String>(
              'Bayi',
              _bayi,
              [('', 'Doğrudan müşteri (bayisiz)'), for (final b in _bayiler ?? const <Map<String, dynamic>>[]) (metin(b['id']), metin(b['name']))],
              (v) => setState(() => _bayi = v ?? ''),
              hata: _hataOf('reseller_id'),
            ),
          if (_ortak && !_yeni)
            _secim<String>(
              'Durum',
              _durum,
              const [('active', 'Aktif'), ('suspended', 'Askıda')],
              (v) => setState(() => _durum = v ?? _durum),
              hata: _hataOf('status'),
            ),
        ]),
        const SizedBox(height: 16),
        _grup(Simgeler.personOutline, 'Yetkili kişi', [
          _alanKutusu('contact_name', 'Ad soyad', zorunlu: _yeni, enFazla: 120),
          _alanKutusu('contact_phone', 'Telefon', zorunlu: _yeni, ipucu: '0532 555 12 34', tur: TextInputType.phone),
          _alanKutusu('contact_email', 'E-posta', zorunlu: _yeni, tur: TextInputType.emailAddress),
        ], sutun: 3),
        if (_yeni && _ortak && Uyg.yetki('users.manage'))
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.r.ic,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.r.kenar),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _yoneticiAc,
                    onChanged: (v) => setState(() => _yoneticiAc = v ?? false),
                    title: const Text('Müşteri için panel yöneticisi hesabı oluştur', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  if (_yoneticiAc)
                    _izgara([
                      TextField(
                        controller: _yoneticiEposta,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(labelText: 'Giriş e-postası', helperText: 'Boşsa yetkili e-postası kullanılır'),
                      ),
                      SifreAlani(denetleyici: _yoneticiSifre),
                    ]),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _fatura() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    children: [
      _grup(Simgeler.accountBalance, 'Fatura', [
        if (!_bireysel) _alanKutusu('legal_name', 'Ticari unvan', ipucu: 'Örnek Yazılım A.Ş.', enFazla: 300),
        _alanKutusu('tax_office', 'Vergi dairesi', enFazla: 120),
        _alanKutusu(
          'tax_number',
          _bireysel ? 'T.C. kimlik no' : 'Vergi no',
          yardim: _bireysel ? '11 hane' : '10 hane (şahıs şirketi: 11)',
          tur: TextInputType.number,
          enFazla: 11,
        ),
        _alanKutusu('billing_email', 'Fatura e-postası', yardim: 'Boşsa yetkili e-postası', tur: TextInputType.emailAddress),
        if (!_bireysel) _alanKutusu('mersis_no', 'MERSİS no', tur: TextInputType.number, enFazla: 16),
      ]),
      _grup(Simgeler.place, 'Adres', [
        _alanKutusu('address', 'Açık adres', enFazla: 500, satir: 2),
        _alanKutusu('district', 'İlçe', enFazla: 80),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _k['city']!.text),
          optionsBuilder: (v) {
            final q = v.text.trim().toLowerCase();
            if (q.isEmpty) return const Iterable<String>.empty();
            return iller.where((i) => i.toLowerCase().startsWith(q));
          },
          onSelected: (v) => _k['city']!.text = v,
          fieldViewBuilder: (c, ctrl, odak, gonder) => TextField(
            controller: ctrl,
            focusNode: odak,
            maxLength: 80,
            onChanged: (v) => _k['city']!.text = v,
            decoration: InputDecoration(labelText: 'İl', counterText: '', errorText: _hataOf('profile.city')),
          ),
        ),
        _alanKutusu('postal_code', 'Posta kodu', tur: TextInputType.number, enFazla: 12),
        _alanKutusu('country', 'Ülke kodu', ipucu: 'TR', enFazla: 2),
      ]),
    ],
  );

  Widget _diger() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    children: [
      _grup(Simgeler.apartment, 'Firma ve yetkili ayrıntıları', [
        if (!_bireysel)
          _secim<String>(
            'Çalışan sayısı',
            _calisan,
            [for (final s in calisanSayilari) (s, '$s kişi')],
            (v) => setState(() => _calisan = v),
            hata: _hataOf('profile.company_size'),
          ),
        _alanKutusu('website', 'Web sitesi', ipucu: 'firma.com.tr', tur: TextInputType.url),
        _alanKutusu('contact_title', 'Yetkilinin görevi', ipucu: 'Genel Müdür, BT Sorumlusu…', enFazla: 120),
        _alanKutusu('contact_mobile', 'İkinci telefon', tur: TextInputType.phone),
      ]),
      _grup(Simgeler.build, 'Teknik irtibat', [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _teknikAyni,
          onChanged: (v) => setState(() => _teknikAyni = v ?? true),
          title: const Text('Yetkili kişiyle aynı'),
        ),
        if (!_teknikAyni) ...[
          _alanKutusu('tech_name', 'Teknik ad soyad', enFazla: 120),
          _alanKutusu('tech_email', 'Teknik e-posta', tur: TextInputType.emailAddress),
          _alanKutusu('tech_phone', 'Teknik telefon', tur: TextInputType.phone),
        ],
      ]),
      if (_ortak)
        _grup(Simgeler.stickyNote2, 'Dahili (müşteri görmez)', [
          _alanKutusu('source', 'Müşteri kaynağı', ipucu: 'Referans, web sitesi, fuar…', enFazla: 200),
          _alanKutusu('notes', 'Notlar', satir: 3, enFazla: 4000),
        ]),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final genis = context.genis;
    final alanHatasi = _alan != null && (_alan!.startsWith('profile.') || {'name', 'plan_id', 'reseller_id', 'status'}.contains(_alan));
    final icerik = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_yeni ? 'Yeni müşteri' : 'Müşteriyi düzenle', style: gosterim(19, agirlik: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Yalnızca * işaretli alanlar zorunlu; diğer sekmeleri sonra da doldurabilirsiniz.', style: TextStyle(color: r.silik, fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton(tooltip: 'Kapat', onPressed: _mesgul ? null : () => Navigator.pop(context), icon: const Icon(Simgeler.close)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final e in musteriTurleri.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {_tur},
            onSelectionChanged: (s) => setState(() => _tur = s.first),
          ),
        ),
        TabBar(
          controller: _sekme,
          isScrollable: !genis,
          tabs: const [
            Tab(text: 'Temel bilgiler'),
            Tab(text: 'Fatura ve adres'),
            Tab(text: 'Diğer'),
          ],
        ),
        Expanded(
          child: TabBarView(controller: _sekme, children: [_temel(), _fatura(), _diger()]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: r.kenar)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                if (_hata != null && !alanHatasi)
                  Expanded(
                    child: Text(
                      _hata!,
                      style: const TextStyle(color: Marka.gul, fontSize: 13),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _mesgul || _ad.text.trim().isEmpty ? null : _kaydet,
                  child: _mesgul
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_yeni ? 'Oluştur' : 'Kaydet'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    if (!genis) return Dialog.fullscreen(child: SafeArea(child: icerik));
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 860, maxHeight: MediaQuery.sizeOf(context).height * .9),
        child: SizedBox(height: 640, child: icerik),
      ),
    );
  }
}
