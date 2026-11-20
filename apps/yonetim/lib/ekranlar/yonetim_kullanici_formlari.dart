import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../ortak/secimler.dart';
import '../oturum.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';

/// Panel kullanıcısı (GET /users → items; internal/api/admin.go User).
class PanelKullanicisi {
  const PanelKullanicisi({
    required this.id,
    required this.eposta,
    required this.ad,
    required this.rol,
    required this.bayiId,
    required this.orgId,
    required this.orgAdi,
    required this.durum,
    required this.mfa,
    required this.sonGiris,
    required this.eklenme,
    required this.telefon,
    required this.unvan,
    required this.not,
    required this.izinler,
  });
  final String id, eposta, ad, rol, durum, telefon, unvan, not;
  final String? bayiId, orgId, orgAdi;
  final bool mfa;
  final DateTime? sonGiris, eklenme;

  /// null = rolün tüm yetkileri.
  final List<String>? izinler;

  bool get aktif => durum == 'active';
  String get gorunenAd => ad.isEmpty ? eposta : ad;

  factory PanelKullanicisi.coz(Map<String, dynamic> m) => PanelKullanicisi(
    id: metin(m['id']),
    eposta: metin(m['email']),
    ad: metin(m['display_name']),
    rol: metin(m['role']),
    bayiId: metinYa(m['reseller_id']),
    orgId: metinYa(m['organization_id']),
    orgAdi: metinYa(m['organization_name']),
    durum: metin(m['status'], 'active'),
    mfa: mantik(m['mfa_enabled']),
    sonGiris: tarihOku(m['last_login_at']),
    eklenme: tarihOku(m['created_at']),
    telefon: metin(m['phone']),
    unvan: metin(m['title']),
    not: metin(m['note']),
    izinler: m['permissions'] is List ? metinler(m['permissions']) : null,
  );
}

/// GET /catalog: yetki kataloğu ve rol şablonları.
class YetkiKatalogu {
  const YetkiKatalogu(this.yetkiler, this.sablonlar);
  final List<(String, String)> yetkiler;

  /// Şablon → yetkiler (null = tam yetki).
  final Map<String, List<String>?> sablonlar;

  factory YetkiKatalogu.coz(Map<String, dynamic> m) {
    final s = harita(m['role_templates']);
    return YetkiKatalogu(
      [for (final p in haritalar(m['permissions'])) (metin(p['key']), metin(p['name']))],
      {for (final e in s.entries) e.key: e.value is List ? metinler(e.value) : null},
    );
  }

  static const bos = YetkiKatalogu([], {'full': null});
}

const sablonEtiketleri = {'full': 'Tam yetki', 'support': 'Destek', 'readonly': 'Salt okunur', 'security': 'Güvenlik'};

/// Yetki listesinin uyduğu şablon ("custom" = hiçbiri). null → full.
String sablonBul(List<String>? izinler, YetkiKatalogu? k) {
  if (izinler == null) return 'full';
  if (k == null) return 'custom';
  final a = ([...izinler]..sort()).join(',');
  for (final e in k.sablonlar.entries) {
    final v = e.value;
    if (v != null && ([...v]..sort()).join(',') == a) return e.key;
  }
  return 'custom';
}

String sablonEtiketi(String s) => sablonEtiketleri[s] ?? (s == 'custom' ? 'Özel yetkiler' : s);

/// Oturumdaki kullanıcının yetkileri (null = rolün tamamı).
List<String>? get benimYetkilerim {
  final p = Uyg.ben.value?['permissions'];
  return p is List ? metinler(p) : null;
}

/// Yetki seçici: rol şablonu + özel yetki kutuları. Yalnızca sahip olunan yetkiler verilebilir (sunucu: checkGrant).
class YetkiSecici extends StatelessWidget {
  const YetkiSecici({super.key, required this.katalog, required this.deger, required this.degisti, required this.benim});
  final YetkiKatalogu katalog;
  final List<String>? deger;
  final ValueChanged<List<String>?> degisti;
  final List<String>? benim;

  bool _verilebilir(String k) => benim == null || benim!.contains(k);

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final sablon = sablonBul(deger, katalog);
    final anahtarlar = katalog.sablonlar.keys.isEmpty ? const ['full'] : katalog.sablonlar.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(sablon),
          initialValue: sablon,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Rol şablonu', helperText: 'Yalnızca sahip olduğunuz yetkileri verebilirsiniz.'),
          items: [
            for (final k in anahtarlar)
              DropdownMenuItem(value: k, enabled: !(k == 'full' && benim != null), child: Text(sablonEtiketi(k))),
            const DropdownMenuItem(value: 'custom', child: Text('Özel')),
          ],
          onChanged: (v) {
            if (v == null) return;
            if (v == 'custom') {
              degisti(deger ?? <String>[]);
            } else {
              final l = katalog.sablonlar[v];
              degisti(l == null ? null : [...l]);
            }
          },
        ),
        if (deger != null) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(border: Border.all(color: r.kenar), borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (k, ad) in katalog.yetkiler)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: deger!.contains(k),
                    title: Text(ad, style: TextStyle(color: _verilebilir(k) ? null : r.silik)),
                    onChanged: !_verilebilir(k)
                        ? null
                        : (v) => degisti(v == true ? [...deger!, k] : deger!.where((x) => x != k).toList()),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

Widget _hataSatiri(String? h) => h == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(h, style: const TextStyle(color: Marka.gul, fontSize: 13)),
      );

Widget _dugmeIkonu(bool mesgul, IconData ikon) =>
    mesgul ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(ikon);

/// Şifre alanı + "Üret" düğmesi.
class _SifreAlani extends StatelessWidget {
  const _SifreAlani({required this.kontrol, required this.etiket, this.hata, this.degisti});
  final TextEditingController kontrol;
  final String etiket;
  final String? hata;
  final VoidCallback? degisti;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextField(
          controller: kontrol,
          onChanged: (_) => degisti?.call(),
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(labelText: etiket, errorText: hata, helperText: 'En az 12 karakter'),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: OutlinedButton(
          onPressed: () {
            kontrol.text = sifreUret(uzunluk: 16);
            degisti?.call();
          },
          child: const Text('Üret'),
        ),
      ),
    ],
  );
}

// ---- yeni kullanıcı --------------------------------------------------------------------------------------------

/// POST /users {email, display_name, title, password, role, permissions, reseller_id?, organization_id?}.
/// Rol seçenekleri oturum rolüne göre (kimse kendi kapsamının üstünde kullanıcı açamaz). Başarıda true döner.
class KullaniciOlusturDialog extends StatefulWidget {
  const KullaniciOlusturDialog({super.key, required this.katalog});
  final YetkiKatalogu katalog;

  @override
  State<KullaniciOlusturDialog> createState() => _KullaniciOlusturDialogState();
}

class _KullaniciOlusturDialogState extends State<KullaniciOlusturDialog> {
  late final List<String> _roller = switch (Uyg.rol) {
    'super_admin' => const ['super_admin', 'reseller_admin', 'org_admin'],
    'reseller_admin' => const ['reseller_admin', 'org_admin'],
    _ => const ['org_admin'],
  };
  late String _rol = Uyg.musteri ? 'org_admin' : _roller.first;
  final _eposta = TextEditingController();
  final _ad = TextEditingController();
  final _unvan = TextEditingController();
  final _sifre = TextEditingController(text: sifreUret(uzunluk: 16));
  late List<String>? _izinler = benimYetkilerim == null ? null : <String>[];
  String? _bayiId, _bayiAdi;
  Organizasyon? _org;
  List<Bayi>? _bayiler;
  String? _hata, _hataAlani;
  bool _mesgul = false;

  @override
  void dispose() {
    _eposta.dispose();
    _ad.dispose();
    _unvan.dispose();
    _sifre.dispose();
    super.dispose();
  }

  Future<void> _bayiSec() async {
    try {
      _bayiler ??= haritalar(harita(await Uyg.api.get('/api/v1/resellers'))['items']).map(Bayi.coz).toList();
    } catch (e) {
      bildir('Bayiler yüklenemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
      return;
    }
    if (!mounted) return;
    final b = await araVeSec<Bayi>(
      context,
      baslik: 'Bayi seçin',
      ipucu: 'Bayi ara…',
      yukle: (q) async => _bayiler!.where((x) => x.ad.toLowerCase().contains(q.toLowerCase())).toList(),
      ad: (x) => x.ad,
      alt: (x) => '${x.musteriSayisi} müşteri',
    );
    if (b != null) {
      setState(() {
        _bayiId = b.id;
        _bayiAdi = b.ad;
      });
    }
  }

  Future<void> _orgSec() async {
    final o = await musteriSec(context);
    if (o != null) setState(() => _org = o);
  }

  bool get _hazir => _eposta.text.trim().isNotEmpty && _sifre.text.length >= 12;

  Future<void> _olustur() async {
    setState(() {
      _mesgul = true;
      _hata = _hataAlani = null;
    });
    try {
      await Uyg.api.post('/api/v1/users', {
        'email': _eposta.text.trim(),
        'display_name': _ad.text.trim(),
        'title': _unvan.text.trim(),
        'password': _sifre.text,
        'role': _rol,
        'permissions': _izinler,
        if (_rol == 'reseller_admin' && Uyg.platformYoneticisi) 'reseller_id': _bayiId,
        if (_rol == 'org_admin' && !Uyg.musteri) 'organization_id': _org?.id,
      });
      bildir('Kullanıcı oluşturuldu', mesaj: 'Şifreyi kullanıcıya güvenli bir kanaldan iletin.', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _hata = e.mesaj;
          _hataAlani = e.alan;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  String? _alanHatasi(String a) => _hataAlani == a ? _hata : null;

  @override
  Widget build(BuildContext context) {
    final alanli = const {'email', 'password', 'reseller_id', 'organization_id'}.contains(_hataAlani);
    return AlertDialog(
      title: const Text('Yeni yönetici'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "E-posta ile davet gönderilmez: şifreyi kullanıcıya siz iletirsiniz. Kullanıcı ilk girişte kendi şifresini ve 2FA'yı ayarlayabilir.",
                style: TextStyle(color: context.r.silik, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (_roller.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: _rol,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: [
                    for (final r in _roller)
                      DropdownMenuItem(value: r, child: Text(r == 'super_admin' ? 'Platform ekibi (süper yönetici)' : rolEtiketi(r))),
                  ],
                  onChanged: (v) => setState(() => _rol = v ?? _rol),
                ),
                const SizedBox(height: 12),
              ],
              if (_rol == 'reseller_admin' && Uyg.platformYoneticisi) ...[
                SecimAlani(etiket: 'Bayi', deger: _bayiAdi, onTap: _bayiSec, hata: _alanHatasi('reseller_id')),
                const SizedBox(height: 12),
              ],
              if (_rol == 'org_admin' && !Uyg.musteri) ...[
                SecimAlani(etiket: 'Müşteri', deger: _org?.ad, onTap: _orgSec, hata: _alanHatasi('organization_id')),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _eposta,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'E-posta', errorText: _alanHatasi('email')),
              ),
              const SizedBox(height: 12),
              TextField(controller: _ad, decoration: const InputDecoration(labelText: 'Ad soyad')),
              const SizedBox(height: 12),
              TextField(controller: _unvan, decoration: const InputDecoration(labelText: 'Unvan')),
              const SizedBox(height: 12),
              _SifreAlani(kontrol: _sifre, etiket: 'Başlangıç şifresi', hata: _alanHatasi('password'), degisti: () => setState(() {})),
              const SizedBox(height: 16),
              YetkiSecici(katalog: widget.katalog, deger: _izinler, benim: benimYetkilerim, degisti: (v) => setState(() => _izinler = v)),
              if (!alanli) _hataSatiri(_hata),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton.icon(
          onPressed: _mesgul || !_hazir ? null : _olustur,
          icon: _dugmeIkonu(_mesgul, Icons.person_add_alt_rounded),
          label: const Text('Oluştur'),
        ),
      ],
    );
  }
}

// ---- profil ----------------------------------------------------------------------------------------------------

/// PATCH /users/{id} {display_name, title, phone, note}. Başarıda true.
class ProfilDuzenleDialog extends StatefulWidget {
  const ProfilDuzenleDialog({super.key, required this.kullanici});
  final PanelKullanicisi kullanici;

  @override
  State<ProfilDuzenleDialog> createState() => _ProfilDuzenleDialogState();
}

class _ProfilDuzenleDialogState extends State<ProfilDuzenleDialog> {
  late final _ad = TextEditingController(text: widget.kullanici.ad);
  late final _unvan = TextEditingController(text: widget.kullanici.unvan);
  late final _telefon = TextEditingController(text: widget.kullanici.telefon);
  late final _not = TextEditingController(text: widget.kullanici.not);
  String? _hata;
  bool _mesgul = false;

  @override
  void dispose() {
    for (final k in [_ad, _unvan, _telefon, _not]) {
      k.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.patch('/api/v1/users/${widget.kullanici.id}', {
        'display_name': _ad.text,
        'title': _unvan.text,
        'phone': _telefon.text,
        'note': _not.text,
      });
      bildir('Profil kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Profili düzenle'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.kullanici.eposta, style: TextStyle(color: context.r.silik)),
            const SizedBox(height: 12),
            TextField(controller: _ad, maxLength: 200, decoration: const InputDecoration(labelText: 'Ad soyad')),
            TextField(controller: _unvan, maxLength: 120, decoration: const InputDecoration(labelText: 'Unvan')),
            TextField(controller: _telefon, maxLength: 40, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon')),
            TextField(controller: _not, maxLength: 2000, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Not')),
            _hataSatiri(_hata),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
      FilledButton.icon(onPressed: _mesgul ? null : _kaydet, icon: _dugmeIkonu(_mesgul, Icons.save_rounded), label: const Text('Kaydet')),
    ],
  );
}

// ---- yetkiler ---------------------------------------------------------------------------------------------------

/// PATCH /users/{id} {permissions}. Kullanıcının oturumları kapanır. Başarıda true.
class YetkilerDialog extends StatefulWidget {
  const YetkilerDialog({super.key, required this.kullanici, required this.katalog});
  final PanelKullanicisi kullanici;
  final YetkiKatalogu katalog;

  @override
  State<YetkilerDialog> createState() => _YetkilerDialogState();
}

class _YetkilerDialogState extends State<YetkilerDialog> {
  late List<String>? _izinler = widget.kullanici.izinler == null ? null : [...widget.kullanici.izinler!];
  String? _hata;
  bool _mesgul = false;

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.patch('/api/v1/users/${widget.kullanici.id}', {'permissions': _izinler});
      bildir('Yetkiler kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Yetkiler'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.kullanici.eposta} · ${rolEtiketi(widget.kullanici.rol)}. Değişiklik kullanıcının oturumlarını kapatır (hemen geçerli olur).',
              style: TextStyle(color: context.r.silik, fontSize: 13),
            ),
            const SizedBox(height: 14),
            YetkiSecici(katalog: widget.katalog, deger: _izinler, benim: benimYetkilerim, degisti: (v) => setState(() => _izinler = v)),
            _hataSatiri(_hata),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
      FilledButton.icon(onPressed: _mesgul ? null : _kaydet, icon: _dugmeIkonu(_mesgul, Icons.save_rounded), label: const Text('Kaydet')),
    ],
  );
}

// ---- şifre ----------------------------------------------------------------------------------------------------

/// PATCH /users/{id} {password}: kullanıcının tüm oturumları kapanır.
class SifreSifirlaDialog extends StatefulWidget {
  const SifreSifirlaDialog({super.key, required this.kullanici});
  final PanelKullanicisi kullanici;

  @override
  State<SifreSifirlaDialog> createState() => _SifreSifirlaDialogState();
}

class _SifreSifirlaDialogState extends State<SifreSifirlaDialog> {
  final _sifre = TextEditingController(text: sifreUret(uzunluk: 16));
  String? _hata;
  bool _mesgul = false;

  @override
  void dispose() {
    _sifre.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.patch('/api/v1/users/${widget.kullanici.id}', {'password': _sifre.text});
      bildir('Şifre değiştirildi', mesaj: 'Şifreyi kullanıcıya güvenli bir kanaldan iletin.', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Şifre sıfırla'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.kullanici.eposta} için yeni şifre. Kullanıcının tüm oturumları kapatılır; şifreyi güvenli bir kanaldan iletin.',
            style: TextStyle(color: context.r.silik, fontSize: 13),
          ),
          const SizedBox(height: 14),
          _SifreAlani(kontrol: _sifre, etiket: 'Yeni şifre', degisti: () => setState(() {})),
          _hataSatiri(_hata),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
      FilledButton.icon(
        onPressed: _mesgul || _sifre.text.length < 12 ? null : _kaydet,
        icon: _dugmeIkonu(_mesgul, Icons.key_rounded),
        label: const Text('Şifreyi kaydet'),
      ),
    ],
  );
}

// ---- oturumlar --------------------------------------------------------------------------------------------------

/// GET /users/{id}/sessions; "Tümünü kapat" DELETE /users/{id}/sessions (users.manage, kendisi değil).
class KullaniciOturumlariDialog extends StatefulWidget {
  const KullaniciOturumlariDialog({super.key, required this.kullanici, required this.kapatabilir});
  final PanelKullanicisi kullanici;
  final bool kapatabilir;

  @override
  State<KullaniciOturumlariDialog> createState() => _KullaniciOturumlariDialogState();
}

class _KullaniciOturumlariDialogState extends State<KullaniciOturumlariDialog> {
  List<PanelOturumu>? _liste;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/users/${widget.kullanici.id}/sessions'));
      if (mounted) {
        setState(() {
          _liste = haritalar(v['items']).map(PanelOturumu.coz).toList();
          _hata = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _hepsiniKapat() async {
    final ok = await onayla(context, 'Tüm oturumlar kapatılsın mı?', mesaj: '${widget.kullanici.eposta} her yerden çıkış yapar.', evet: 'Tümünü kapat', tehlikeli: true);
    if (!ok) return;
    final v = await islem(() => Uyg.api.delete('/api/v1/users/${widget.kullanici.id}/sessions'));
    if (v == null) return;
    bildir('${tamsayi(harita(v)['revoked'])} oturum kapatıldı', tur: MesajTur.basari);
    await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = _liste;
    Widget govde;
    if (_hata != null) {
      govde = Text(_hata!, style: const TextStyle(color: Marka.gul));
    } else if (l == null) {
      govde = const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    } else if (l.isEmpty) {
      govde = Text('Açık oturum yok.', style: TextStyle(color: r.silik));
    } else {
      govde = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in l)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(o.tarayici.contains('BogaMail') ? Icons.phone_iphone_rounded : Icons.laptop_rounded, color: r.soluk),
              title: Text(
                [cihazAdi(o.tarayici), if (o.musteriGorunumu != null) 'müşteri görünümü: ${o.musteriGorunumu}'].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${o.ip ?? 'IP yok'} · ${goreliZaman(o.sonGorulme ?? o.olusturma)}'),
              trailing: o.gecerli ? const Rozet('Bu oturum', renk: Marka.zumrut) : null,
            ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Oturumlar'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.kullanici.eposta, style: TextStyle(color: r.silik)),
              const SizedBox(height: 10),
              govde,
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
        if (widget.kapatabilir)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Marka.gul),
            onPressed: (l?.isNotEmpty ?? false) ? _hepsiniKapat : null,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Tümünü kapat'),
          ),
      ],
    );
  }
}
