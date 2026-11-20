import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import 'hizmet_ortak.dart';
import 'taklit_islemleri.dart';

/// Bayiler: bayi hesapları, limitleri, kullanım, marka varsayılanları, askıya alma ve bayi paneline giriş.
/// Web: admin/resellers. Uç noktalar: GET /resellers/summary, GET /resellers/{id}, POST /resellers (yalnızca süper),
/// PATCH /resellers/{id} (süper + organizations.manage; bayi yalnızca kendi markası, branding.manage),
/// POST /resellers/{id}/impersonate (bayiPanelineGir). API'de bayi silme uç noktası yoktur.
class BayilerEkrani extends StatefulWidget {
  const BayilerEkrani({super.key});
  @override
  State<BayilerEkrani> createState() => _BayilerEkraniState();
}

/// GET /resellers/summary → items.
class BayiOzeti {
  const BayiOzeti(this.ham);
  final Map<String, dynamic> ham;

  String get id => metin(ham['id']);
  String get ad => metin(ham['name']);
  String get durum => metin(ham['status'], 'active');
  int? get enFazlaMusteri => tamsayiYa(ham['max_customers']);
  int? get enFazlaKutu => tamsayiYa(ham['max_mailboxes']);
  int? get enFazlaDepolama => tamsayiYa(ham['max_storage_bytes']);
  String get eposta => metin(ham['contact_email']);
  String get telefon => metin(ham['contact_phone']);
  String get not => metin(ham['note']);
  Map<String, dynamic> get marka => harita(ham['branding']);
  DateTime? get eklenme => tarihOku(ham['created_at']);
  Map<String, dynamic> get _k => harita(ham['usage']);
  int get musteri => tamsayi(_k['customers']);
  int get kutu => tamsayi(_k['mailboxes']);
  int get ayrilan => tamsayi(_k['allocated_bytes']);
  int get kullanilan => tamsayi(_k['used_bytes']);
  int get yoneticiSayisi => tamsayi(ham['admin_count']);
}

const _gib = 1024 * 1024 * 1024;

String _sinir(int kullanilan, int? enFazla, {bool bayt = false}) {
  String y(int n) => bayt ? boyutYaz(n) : sayiYaz(n);
  return '${y(kullanilan)} / ${enFazla == null ? 'Sınırsız' : y(enFazla)}';
}

class _BayilerEkraniState extends State<BayilerEkrani> {
  String _q = '';
  List<BayiOzeti> _hepsi = [];

  late final _y = SayfaYukleyici.yerel<BayiOzeti>(() async {
    final v = await Uyg.api.get('/api/v1/resellers/summary');
    _hepsi = haritalar(harita(v)['items']).map(BayiOzeti.new).toList();
    return _suz();
  })..yenile();

  List<BayiOzeti> _suz() {
    final t = _q.trim().toLowerCase();
    if (t.isEmpty) return _hepsi;
    return _hepsi.where((r) => r.ad.toLowerCase().contains(t) || r.eposta.toLowerCase().contains(t)).toList();
  }

  bool get _super => Uyg.platformYoneticisi;
  bool get _duzenler => _super && Uyg.yetki('organizations.manage') && Uyg.taklit == null;
  bool get _markaDuzenler => Uyg.taklit == null && (Uyg.yetki('branding.manage') || _duzenler);

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _durum(BayiOzeti r, String durum) async {
    if (durum == 'suspended' &&
        !await onayla(
          context,
          '"${r.ad}" askıya alınsın mı?',
          mesaj: 'Bayi yöneticileri giriş yapamaz ve oturumları kapatılır; bayinin müşterilerinin postası çalışmaya devam eder.',
          evet: 'Askıya al',
          tehlikeli: true,
        )) {
      return;
    }
    final ok = await islem(
      () => Uyg.api.patch('/api/v1/resellers/${r.id}', {'status': durum}),
      tamam: durum == 'suspended' ? 'Bayi askıya alındı; bayi yöneticilerinin oturumları kapatıldı' : 'Bayi etkinleştirildi',
    );
    if (ok != null) _y.yenile();
  }

  Future<void> _limitler(BayiOzeti? r) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _LimitDialog(bayi: r));
    if (ok == true) _y.yenile();
  }

  Future<void> _marka(BayiOzeti r) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _MarkaDialog(bayi: r));
    if (ok == true) _y.yenile();
  }

  void _ayrinti(BayiOzeti r) {
    final govde = _BayiAyrinti(bayi: r);
    if (context.genis) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(r.ad, style: gosterim(19, agirlik: FontWeight.w700)),
          content: SizedBox(width: 560, child: govde),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        ),
      );
    } else {
      sayfaAc(context, r.ad, SingleChildScrollView(padding: const EdgeInsets.all(16), child: govde));
    }
  }

  List<SatirEylemi> _eylemler(BayiOzeti r) => [
    if (_super && Uyg.taklit == null && r.durum == 'active') SatirEylemi(Icons.login_rounded, 'Bayi paneline gir', () => bayiPanelineGir(context, id: r.id, ad: r.ad)),
    SatirEylemi(Icons.apartment_rounded, 'Ayrıntılar', () => _ayrinti(r)),
    if (_duzenler) SatirEylemi(Icons.speed_rounded, 'Limitler ve iletişim', () => _limitler(r)),
    if (_markaDuzenler) SatirEylemi(Icons.palette_outlined, 'Marka', () => _marka(r)),
    if (_duzenler)
      r.durum == 'active'
          ? SatirEylemi(Icons.block_rounded, 'Askıya al', () => _durum(r, 'suspended'), tehlikeli: true)
          : SatirEylemi(Icons.check_circle_outline_rounded, 'Etkinleştir', () => _durum(r, 'active')),
  ];

  Widget _limitHucresi(BuildContext c, int kullanilan, int? enFazla, {bool bayt = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(_sinir(kullanilan, enFazla, bayt: bayt), style: const TextStyle(fontSize: 13)),
      if (enFazla != null) ...[
        const SizedBox(height: 4),
        KullanimCubugu(kullanilan: kullanilan, toplam: enFazla, yazi: false, kalinlik: 5),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Iskelet(
      baslik: 'Bayiler',
      alt: _super ? 'Bayi hesapları, kota ve müşteri limitleri, marka ve bayi yöneticileri' : 'Bayi hesabınız: limitler, kullanım ve marka',
      yenile: _y.yenile,
      birincil: _duzenler ? BirincilEylem(Icons.add_rounded, 'Yeni bayi', () => _limitler(null)) : null,
      govde: VeriTablosu<BayiOzeti>(
        yukleyici: _y,
        bosMetin: _q.isEmpty ? 'Henüz bayi yok. Bayi ekleyip limitlerini belirleyin; bayi kendi müşterilerini ve paketlerini yönetir.' : 'Eşleşen bayi yok.',
        bosIkon: Icons.handshake_outlined,
        onTap: _ayrinti,
        eylemler: _eylemler,
        ust: _super
            ? FiltreCubugu(
                arama: AramaAlani(
                  ipucu: 'Bayi adı veya e-posta ara…',
                  degisti: (v) {
                    _q = v;
                    _y.yenile();
                  },
                ),
              )
            : null,
        sutunlar: [
          Sutun(
            'Bayi',
            esnek: 4,
            hucre: (c, r) => IkiSatir(r.ad, alt: '${r.eposta.isEmpty ? 'İletişim e-postası yok' : r.eposta} · ${r.yoneticiSayisi} yönetici'),
          ),
          Sutun('Müşteri', esnek: 2, hucre: (c, r) => _limitHucresi(c, r.musteri, r.enFazlaMusteri)),
          Sutun('Posta kutusu', esnek: 2, hucre: (c, r) => _limitHucresi(c, r.kutu, r.enFazlaKutu)),
          Sutun('Depolama (ayrılan)', esnek: 2, hucre: (c, r) => _limitHucresi(c, r.ayrilan, r.enFazlaDepolama, bayt: true)),
          Sutun('Durum', esnek: 1, hucre: (c, r) => DurumRozeti(r.durum)),
        ],
        kart: (c, r) => VeriKarti(
          baslik: r.ad,
          alt: '${r.eposta.isEmpty ? 'İletişim e-postası yok' : r.eposta} · ${r.yoneticiSayisi} yönetici',
          sol: Avatar(r.ad, tohum: r.id),
          rozetler: [DurumRozeti(r.durum)],
          alanlar: [
            ('Müşteri', _sinir(r.musteri, r.enFazlaMusteri)),
            ('Posta kutusu', _sinir(r.kutu, r.enFazlaKutu)),
            ('Depolama', _sinir(r.ayrilan, r.enFazlaDepolama, bayt: true)),
          ],
          eylemler: _eylemler(r),
          onTap: () => _ayrinti(r),
        ),
      ),
    );
  }
}

/// Bayi ayrıntısı (GET /resellers/{id}): limitler, paket kataloğu, bayi yöneticileri.
class _BayiAyrinti extends StatelessWidget {
  const _BayiAyrinti({required this.bayi});
  final BayiOzeti bayi;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return FutureBuilder<dynamic>(
      future: Uyg.api.get('/api/v1/resellers/${bayi.id}'),
      builder: (c, s) {
        if (s.hasError) return Bant(hataMetni(s.error!), renk: Marka.gul, ikon: Icons.error_outline_rounded);
        if (!s.hasData) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        final v = harita(s.data);
        final b = BayiOzeti(harita(v['reseller']));
        final paketler = haritalar(v['plans']);
        final yoneticiler = haritalar(v['admins']);
        final iletisim = [b.eposta, b.telefon].where((x) => x.isNotEmpty).join(' · ');
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(iletisim.isEmpty ? 'İletişim bilgisi yok' : iletisim, style: TextStyle(color: r.soluk, fontSize: 13)),
            if (b.not.isNotEmpty) Text(b.not, style: TextStyle(color: r.silik, fontSize: 12.5)),
            const SizedBox(height: 12),
            Izgara(
              enAz: 160,
              children: [
                KullanimSayaci(etiket: 'Müşteri', kullanilan: b.musteri, sinir: b.enFazlaMusteri),
                KullanimSayaci(etiket: 'Posta kutusu', kullanilan: b.kutu, sinir: b.enFazlaKutu),
                KullanimSayaci(etiket: 'Depolama', kullanilan: b.ayrilan, sinir: b.enFazlaDepolama, bayt: true, not: 'Kullanılan ${boyutYaz(b.kullanilan)}'),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Paket kataloğu', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (paketler.isEmpty)
              Text('Bayinin kendi paketi yok; Paketler bölümünden oluşturulabilir.', style: TextStyle(color: r.silik, fontSize: 13))
            else
              for (final p in paketler)
                ListeSatiri(
                  baslik: metin(p['name']),
                  alt: '${tamsayi(p['organization_count'])} müşteri',
                  sag: DurumRozeti(metin(p['status'])),
                ),
            const SizedBox(height: 16),
            const Text('Bayi yöneticileri', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (yoneticiler.isEmpty)
              Text('Yönetici yok; Yöneticiler bölümünden "${rolEtiketi('reseller_admin')}" rolüyle ekleyin.', style: TextStyle(color: r.silik, fontSize: 13))
            else
              for (final u in yoneticiler)
                ListeSatiri(
                  sol: Avatar(metin(u['display_name'], metin(u['email'])), tohum: metin(u['id'])),
                  baslik: metinYa(u['display_name']) ?? metin(u['email']),
                  alt: 'Son giriş ${u['last_login_at'] == null ? 'hiç' : goreliZaman(tarihOku(u['last_login_at']))}${mantik(u['mfa_enabled']) ? ' · 2FA açık' : ''}',
                  sag: DurumRozeti(metin(u['status'])),
                ),
          ],
        );
      },
    );
  }
}

/// Yeni bayi (bayi null) ya da limitler ve iletişim düzenleme. Yeni: POST /resellers {name} → PATCH /resellers/{id}.
class _LimitDialog extends StatefulWidget {
  const _LimitDialog({this.bayi});
  final BayiOzeti? bayi;
  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  final _form = GlobalKey<FormState>();
  late final BayiOzeti? b = widget.bayi;
  late final _ad = TextEditingController(text: b?.ad ?? '');
  late final _eposta = TextEditingController(text: b?.eposta ?? '');
  late final _tel = TextEditingController(text: b?.telefon ?? '');
  late final _not = TextEditingController(text: b?.not ?? '');
  late final _musteri = TextEditingController(text: b?.enFazlaMusteri?.toString() ?? '');
  late final _kutu = TextEditingController(text: b?.enFazlaKutu?.toString() ?? '');
  late final _depolama = TextEditingController(text: b?.enFazlaDepolama == null ? '' : _gbYaz(b!.enFazlaDepolama!));
  bool _mesgul = false;
  String? _hata;

  static String _gbYaz(int bayt) {
    final v = (bayt / _gib * 100).round() / 100;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  @override
  void dispose() {
    for (final k in [_ad, _eposta, _tel, _not, _musteri, _kutu, _depolama]) {
      k.dispose();
    }
    super.dispose();
  }

  int? _sayi(TextEditingController k, [int carpan = 1]) {
    final s = k.text.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return (num.parse(s) * carpan).round();
  }

  Future<void> _kaydet() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    final govde = {
      'name': _ad.text.trim(),
      'contact_email': _eposta.text.trim(),
      'contact_phone': _tel.text.trim(),
      'note': _not.text.trim(),
      'max_customers': _sayi(_musteri),
      'max_mailboxes': _sayi(_kutu),
      'max_storage_bytes': _sayi(_depolama, _gib),
    };
    try {
      var id = b?.id;
      if (id == null) {
        final y = harita(await Uyg.api.post('/api/v1/resellers', {'name': govde['name']}));
        id = metin(y['id']);
      }
      await Uyg.api.patch('/api/v1/resellers/$id', govde);
      bildir(b == null ? 'Bayi oluşturuldu' : 'Bayi kaydedildi', mesaj: b == null ? 'Bayi yöneticisini Yöneticiler bölümünden ekleyin.' : null, tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _hata = hataMetni(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String? sayiKontrol(String? v) => sayiDogrula(v);
    Widget alan(TextEditingController k, String etiket, {TextInputType? tur, String? Function(String?)? dogrula, int satir = 1}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: k,
        keyboardType: tur,
        maxLines: satir,
        validator: dogrula,
        decoration: InputDecoration(labelText: etiket),
      ),
    );
    final mevcut = b;
    return AlertDialog(
      title: Text(mevcut == null ? 'Yeni bayi' : 'Limitler ve iletişim', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  mevcut == null
                      ? 'Limitler bayinin tüm müşterileri için toplamdır; aşılırsa yeni müşteri / posta kutusu oluşturulamaz.'
                      : 'Şu an: ${mevcut.musteri} müşteri, ${mevcut.kutu} posta kutusu, ${boyutYaz(mevcut.ayrilan)} ayrılmış (${boyutYaz(mevcut.kullanilan)} kullanılan). '
                            'Mevcut kullanımın altına inen limit yalnızca yeni eklemeleri engeller.',
                  style: TextStyle(color: context.r.soluk, fontSize: 13),
                ),
                const SizedBox(height: 14),
                alan(
                  _ad,
                  'Bayi adı',
                  dogrula: (v) => (v ?? '').trim().isEmpty ? 'Zorunlu' : ((v ?? '').trim().length > 200 ? 'En fazla 200 karakter' : null),
                ),
                alan(
                  _eposta,
                  'İletişim e-postası',
                  tur: TextInputType.emailAddress,
                  dogrula: (v) => (v ?? '').trim().isNotEmpty && !(v ?? '').contains('@') ? 'Geçersiz e-posta' : null,
                ),
                alan(_tel, 'Telefon', tur: TextInputType.phone, dogrula: (v) => (v ?? '').trim().length > 40 ? 'Geçersiz telefon' : null),
                alan(_musteri, 'En çok müşteri (boş = sınırsız)', tur: TextInputType.number, dogrula: sayiKontrol),
                alan(_kutu, 'En çok posta kutusu (boş = sınırsız)', tur: TextInputType.number, dogrula: sayiKontrol),
                alan(_depolama, 'Toplam depolama, GB (boş = sınırsız)', tur: const TextInputType.numberWithOptions(decimal: true), dogrula: sayiKontrol),
                alan(_not, 'Not', satir: 2, dogrula: (v) => (v ?? '').length > 2000 ? 'En fazla 2000 karakter' : null),
                if (_hata != null) Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul ? null : _kaydet, child: Text(mevcut == null ? 'Oluştur' : 'Kaydet')),
      ],
    );
  }
}

/// Bayi markası (PATCH /resellers/{id} {branding}).
class _MarkaDialog extends StatefulWidget {
  const _MarkaDialog({required this.bayi});
  final BayiOzeti bayi;
  @override
  State<_MarkaDialog> createState() => _MarkaDialogState();
}

class _MarkaDialogState extends State<_MarkaDialog> {
  final _form = GlobalKey<FormState>();
  static const _alanlar = [
    ('product_name', 'Ürün adı (panel ve webmail başlığı)'),
    ('primary_color', 'Ana renk (#RRGGBB)'),
    ('support_email', 'Destek e-postası'),
    ('support_url', 'Destek adresi (https://…)'),
    ('footer_text', 'Alt bilgi metni'),
  ];
  late final _k = {for (final (a, _) in _alanlar) a: TextEditingController(text: metin(widget.bayi.marka[a]))};
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    for (final k in _k.values) {
      k.dispose();
    }
    super.dispose();
  }

  String? _dogrula(String a, String? v) {
    final s = (v ?? '').trim();
    return switch (a) {
      'product_name' when s.length > 40 => 'En fazla 40 karakter',
      'primary_color' when s.isNotEmpty && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s) => 'Renk #RRGGBB biçiminde olmalı',
      'support_email' when s.isNotEmpty && !s.contains('@') => 'Geçersiz destek e-postası',
      'support_url' when s.isNotEmpty && !s.startsWith('https://') => 'Destek adresi https:// ile başlamalı',
      'footer_text' when s.length > 200 => 'En fazla 200 karakter',
      _ => null,
    };
  }

  Future<void> _kaydet() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.patch('/api/v1/resellers/${widget.bayi.id}', {
        'branding': {for (final e in _k.entries) e.key: e.value.text.trim()},
      });
      bildir('Bayi markası kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _hata = hataMetni(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final renk = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(_k['primary_color']!.text.trim())
        ? Color(int.parse('FF${_k['primary_color']!.text.trim().substring(1)}', radix: 16))
        : null;
    return AlertDialog(
      title: Text('Bayi markası', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Kendi markasını ayarlamamış müşteriler bu adı, rengi ve destek bilgilerini görür. Logo müşteri bazında Marka bölümünden yüklenir.',
                  style: TextStyle(color: context.r.soluk, fontSize: 13),
                ),
                const SizedBox(height: 14),
                for (final (a, e) in _alanlar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: _k[a],
                      validator: (v) => _dogrula(a, v),
                      onChanged: a == 'primary_color' ? (_) => setState(() {}) : null,
                      keyboardType: a == 'support_email' ? TextInputType.emailAddress : (a == 'support_url' ? TextInputType.url : null),
                      decoration: InputDecoration(
                        labelText: e,
                        suffixIcon: a == 'primary_color' && renk != null
                            ? Padding(
                                padding: const EdgeInsets.all(10),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(6), border: Border.all(color: context.r.kenar)),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                if (_hata != null) Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}
