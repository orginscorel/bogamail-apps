import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../ortak/tablo.dart';
import '../oturum.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import 'yonetim_kullanici_formlari.dart';
import '../ortak/simgeler.dart';

/// Yöneticiler (web: /admin/users): panel kullanıcıları (oluştur, profil, yetkiler, şifre, askıya al/etkinleştir,
/// 2FA sıfırla, oturumlar) ve iki adımlı doğrulama politikası. Kapsam sunucudadır (süper: hepsi, bayi: kendi ekibi ve
/// müşterileri, müşteri: kendi firması). Yazma işlemleri users.manage ister; müşteri görünümünde sunucu /users
/// yazmalarını engellediği için gizlenir.
class YoneticilerEkrani extends StatefulWidget {
  const YoneticilerEkrani({super.key});

  @override
  State<YoneticilerEkrani> createState() => _YoneticilerEkraniState();
}

class _YoneticilerEkraniState extends State<YoneticilerEkrani> {
  String _q = '';
  String _rol = '';
  List<PanelKullanicisi>? _hepsi;
  bool _tazele = true;
  YetkiKatalogu? _katalog;

  late final _y = SayfaYukleyici.yerel<PanelKullanicisi>(() async {
    if (_tazele || _hepsi == null) {
      _hepsi = haritalar(harita(await Uyg.api.get('/api/v1/users'))['items']).map(PanelKullanicisi.coz).toList();
    }
    _tazele = true;
    final t = _q.trim().toLowerCase();
    return _hepsi!
        .where(
          (u) =>
              (_rol.isEmpty || u.rol == _rol) &&
              (t.isEmpty || [u.eposta, u.ad, u.orgAdi ?? '', u.unvan].any((x) => x.toLowerCase().contains(t))),
        )
        .toList();
  });

  bool get _yonetir => Uyg.yetki('users.manage') && Uyg.taklit == null;
  String get _benimId => '${Uyg.ben.value?['id'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _y.yenile();
    _katalogYukle();
  }

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _katalogYukle() async {
    try {
      final k = YetkiKatalogu.coz(harita(await Uyg.api.get('/api/v1/catalog')));
      if (mounted) setState(() => _katalog = k);
    } catch (_) {
      // Katalog yüklenemezse şablon etiketi "Özel yetkiler" görünür; formlar boş katalogla açılır.
    }
  }

  /// Filtre değişti: listeyi sunucuya gitmeden yeniden süz.
  void _suz() {
    _tazele = false;
    _y.yenile();
  }

  Future<void> _yeni() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => KullaniciOlusturDialog(katalog: _katalog ?? YetkiKatalogu.bos),
    );
    if (ok == true) _y.yenile();
  }

  Future<void> _dialog(Widget d) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => d);
    if (ok == true) _y.yenile();
  }

  Future<void> _durum(PanelKullanicisi u) async {
    final askiya = u.aktif;
    if (askiya) {
      final ok = await onayla(
        context,
        'Kullanıcı askıya alınsın mı?',
        mesaj: '${u.eposta} panele giriş yapamaz ve açık oturumları kapatılır.',
        evet: 'Askıya al',
        tehlikeli: true,
      );
      if (!ok) return;
    }
    final v = await islem(
      () => Uyg.api.patch('/api/v1/users/${u.id}', {'status': askiya ? 'suspended' : 'active'}),
      tamam: askiya ? 'Kullanıcı askıya alındı' : 'Kullanıcı etkinleştirildi',
    );
    if (v != null) _y.yenile();
  }

  Future<void> _mfaSifirla(PanelKullanicisi u) async {
    final ok = await onayla(
      context,
      'İki adımlı doğrulama sıfırlansın mı?',
      mesaj: 'Telefonunu kaybeden kullanıcı için. ${u.eposta} bir sonraki girişte yeniden kurar; işlem denetim kaydına geçer.',
      evet: '2FA sıfırla',
      tehlikeli: true,
    );
    if (!ok) return;
    final v = await islem(
      () => Uyg.api.post('/api/v1/users/${u.id}/mfa/reset').then((_) => true),
      tamam: 'İki adımlı doğrulama sıfırlandı',
    );
    if (v == true) _y.yenile();
  }

  /// Kullanıcıyı kalıcı olarak siler (DELETE /users/{id}): oturumları, mobil bildirim cihazları ve API anahtarları
  /// da silinir. Sunucu kendini silmeyi (cannot_delete_self) ve son süper yöneticiyi silmeyi (last_super_admin) reddeder.
  Future<void> _sil(PanelKullanicisi u) async {
    final ok = await onayla(
      context,
      'Kullanıcı silinsin mi?',
      mesaj: '${u.eposta} kalıcı olarak silinir; açık oturumları kapatılır, mobil bildirim cihazları ve API anahtarları da silinir. '
          'Bu işlem geri alınamaz ve denetim kaydına yazılır. Geçici olarak engellemek için "Askıya al"ı kullanın.',
      evet: 'Kalıcı olarak sil',
      tehlikeli: true,
    );
    if (!ok) return;
    try {
      await Uyg.api.delete('/api/v1/users/${u.id}');
      bildir('Kullanıcı silindi', mesaj: u.eposta, tur: MesajTur.basari);
      _y.yenile();
    } on ApiHata catch (e) {
      final mesaj = switch (e.kod) {
        'cannot_delete_self' => 'Kendi hesabınızı silemezsiniz. Başka bir yöneticiden silmesini isteyin.',
        'last_super_admin' => 'Bu, platformdaki son süper yönetici. Silmeden önce başka bir kullanıcıya süper yönetici rolü verin.',
        'not_found' => 'Kullanıcı bulunamadı ya da yetki alanınızın dışında.',
        _ => hataMetni(e),
      };
      bildir('Kullanıcı silinemedi', mesaj: mesaj, tur: MesajTur.hata);
    } catch (e) {
      bildir('Kullanıcı silinemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  void _oturumlar(PanelKullanicisi u) => showDialog<void>(
    context: context,
    builder: (_) => KullaniciOturumlariDialog(kullanici: u, kapatabilir: _yonetir && u.id != _benimId),
  );

  /// Web'deki "yönet" menüsü (ManageAction listesi) ile aynı eylemler.
  List<(IconData, String, String, VoidCallback, bool)> _eylemListesi(PanelKullanicisi u) {
    final ben = u.id == _benimId;
    return [
      if (_yonetir) ...[
        (Simgeler.edit, 'Profili düzenle', 'Ad, unvan, telefon, not', () => _dialog(ProfilDuzenleDialog(kullanici: u)), false),
        if (!ben) ...[
          (
            Simgeler.manageAccounts,
            'Yetkiler',
            'Rol şablonu veya özel yetkiler',
            () => _dialog(YetkilerDialog(kullanici: u, katalog: _katalog ?? YetkiKatalogu.bos)),
            false,
          ),
          (Simgeler.key, 'Şifre sıfırla', 'Yeni şifre ver, oturumları kapat', () => _dialog(SifreSifirlaDialog(kullanici: u)), false),
          if (u.aktif)
            (Simgeler.block, 'Askıya al', 'Girişi engelle, oturumları kapat', () => _durum(u), true)
          else
            (Simgeler.checkCircleOutline, 'Etkinleştir', 'Girişe yeniden izin ver', () => _durum(u), false),
          if (u.mfa) (Simgeler.gppBad, '2FA sıfırla', 'Telefonu kaybeden kullanıcı için; kayda geçer', () => _mfaSifirla(u), true),
        ],
      ],
      (Simgeler.devices, 'Oturumlar', 'Açık oturumları gör${_yonetir && !ben ? ', kapat' : ''}', () => _oturumlar(u), false),
      if (_yonetir && !ben) (Simgeler.deleteOutline, 'Sil', 'Hesabı kalıcı olarak sil; oturumlar ve anahtarlar silinir', () => _sil(u), true),
    ];
  }

  List<SatirEylemi> _satirEylemleri(PanelKullanicisi u) => [
    for (final (i, b, _, f, t) in _eylemListesi(u)) SatirEylemi(i, b, f, tehlikeli: t),
  ];

  Future<void> _yonet(PanelKullanicisi u) async {
    final r = context.r;
    final secilen = await showModalBottomSheet<VoidCallback>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Avatar(u.gorunenAd, tohum: u.eposta, boyut: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u.gorunenAd, maxLines: 1, overflow: TextOverflow.ellipsis, style: gosterim(17, agirlik: FontWeight.w600)),
                          Text(
                            [u.eposta, rolEtiketi(u.rol), ?u.orgAdi].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: r.silik, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _ozet(c, u.sonGiris == null ? 'Hiç' : goreliZaman(u.sonGiris), 'son giriş')),
                    const SizedBox(width: 8),
                    Expanded(child: _ozet(c, u.mfa ? 'Açık' : 'Kapalı', '2FA')),
                    const SizedBox(width: 8),
                    Expanded(child: _ozet(c, durumEtiketi(u.durum), 'durum', renk: durumRengi(u.durum))),
                  ],
                ),
                const SizedBox(height: 8),
                BilgiSatiri('Yetki', '${rolEtiketi(u.rol)} · ${sablonEtiketi(sablonBul(u.izinler, _katalog))}'),
                if (u.unvan.isNotEmpty) BilgiSatiri('Unvan', u.unvan),
                if (u.telefon.isNotEmpty) BilgiSatiri('Telefon', u.telefon),
                if (u.not.isNotEmpty) BilgiSatiri('Not', u.not),
                if (u.eklenme != null) BilgiSatiri('Eklenme', tamZaman(u.eklenme)),
                const SizedBox(height: 8),
                if (!Uyg.yetki('users.manage'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Kullanıcıları yönetme yetkiniz yok (users.manage).', style: TextStyle(color: r.silik)),
                  )
                else if (Uyg.taklit != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Bant('Müşteri görünümündeyken panel kullanıcıları değiştirilemez.', renk: Marka.kehribar, ikon: Simgeler.visibility),
                  ),
                for (final (i, b, ipucu, f, t) in _eylemListesi(u))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: EylemSatiri(ikon: i, baslik: b, ipucu: ipucu, tehlikeli: t, onTap: () => Navigator.pop(c, f)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    secilen?.call();
  }

  Widget _ozet(BuildContext c, String deger, String etiket, {Color? renk}) {
    final r = c.r;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(deger, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: renk)),
          Text(etiket, style: TextStyle(color: r.silik, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _mfaRozeti(PanelKullanicisi u) =>
      u.mfa ? const Rozet('Açık', renk: Marka.zumrut, ikon: Simgeler.verifiedUser) : const SolukMetin('Kapalı');

  String get _altBaslik => switch (Uyg.rol) {
    'super_admin' => 'Platform ekibi, bayi ve müşteri yöneticileri',
    'reseller_admin' => 'Bayi ekibiniz ve müşterilerinizin panel kullanıcıları',
    _ => 'Firmanızın panel kullanıcıları ve yetkileri',
  };

  Widget _liste() {
    final roller = <(String, String)>[
      ('', 'Tüm roller'),
      if (Uyg.platformYoneticisi) ('super_admin', rolEtiketi('super_admin')),
      ('reseller_admin', rolEtiketi('reseller_admin')),
      ('org_admin', rolEtiketi('org_admin')),
    ];
    return VeriTablosu<PanelKullanicisi>(
      yukleyici: _y,
      bosMetin: _q.isEmpty && _rol.isEmpty ? 'Henüz kullanıcı yok.' : 'Eşleşen kullanıcı yok.',
      bosIkon: Simgeler.groups,
      onTap: _yonet,
      eylemler: _satirEylemleri,
      ust: FiltreCubugu(
        arama: AramaAlani(
          ipucu: 'Ad, e-posta veya firma ara…',
          ilk: _q,
          degisti: (v) {
            _q = v;
            _suz();
          },
        ),
        filtreler: [
          if (!Uyg.musteri)
            FiltreDugmesi<String>(
              etiket: 'Rol',
              ikon: Simgeler.badge,
              secenekler: roller,
              secili: _rol,
              secildi: (v) {
                setState(() => _rol = v);
                _suz();
              },
            ),
        ],
        etkinler: [
          if (_rol.isNotEmpty)
            EtkinFiltre('Rol: ${rolEtiketi(_rol)}', () {
              setState(() => _rol = '');
              _suz();
            }),
        ],
      ),
      sutunlar: [
        Sutun(
          'Kullanıcı',
          esnek: 4,
          hucre: (c, u) => IkiSatir(
            u.gorunenAd,
            alt: [if (u.ad.isNotEmpty) u.eposta, ?u.orgAdi].join(' · '),
            sol: Avatar(u.gorunenAd, tohum: u.eposta, boyut: 32),
          ),
        ),
        Sutun('Rol / yetki', esnek: 3, hucre: (c, u) => IkiSatir(rolEtiketi(u.rol), alt: sablonEtiketi(sablonBul(u.izinler, _katalog)), kalin: false)),
        Sutun('2FA', esnek: 2, hucre: (c, u) => Align(alignment: Alignment.centerLeft, child: _mfaRozeti(u))),
        Sutun('Durum', esnek: 2, hucre: (c, u) => Align(alignment: Alignment.centerLeft, child: DurumRozeti(u.durum))),
        Sutun('Son giriş', esnek: 2, hucre: (c, u) => SolukMetin(u.sonGiris == null ? 'Hiç' : goreliZaman(u.sonGiris))),
      ],
      kart: (c, u) => VeriKarti(
        sol: Avatar(u.gorunenAd, tohum: u.eposta),
        baslik: u.gorunenAd,
        alt: [if (u.ad.isNotEmpty) u.eposta, ?u.orgAdi].join(' · '),
        rozetler: [
          Rozet(rolEtiketi(u.rol), ikon: Simgeler.badge),
          if (!u.aktif) DurumRozeti(u.durum),
          if (u.mfa) const Rozet('2FA', renk: Marka.zumrut, ikon: Simgeler.verifiedUser),
        ],
        alanlar: [
          ('Yetki', sablonEtiketi(sablonBul(u.izinler, _katalog))),
          ('Son giriş', u.sonGiris == null ? 'Hiç' : goreliZaman(u.sonGiris)),
        ],
        eylemler: _satirEylemleri(u),
        onTap: () => _yonet(u),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Iskelet(
      baslik: 'Yöneticiler',
      alt: _altBaslik,
      yenile: _y.yenile,
      birincil: _yonetir ? BirincilEylem(Simgeler.personAddAlt, 'Yeni yönetici', _yeni) : null,
      sekmeler: const TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          Tab(text: 'Kullanıcılar'),
          Tab(text: '2FA politikası'),
        ],
      ),
      govde: TabBarView(children: [_liste(), const MfaPolitikasi()]),
    ),
  );
}

// ---- 2FA politikası -----------------------------------------------------------------------------------------------

/// İki adımlı doğrulama politikası: rol bazında (yalnızca süper yönetici; GET/PUT /security/mfa-policy) ve müşteri
/// bazında (GET/PATCH /organizations/{id}/mfa-policy, users.manage).
class MfaPolitikasi extends StatefulWidget {
  const MfaPolitikasi({super.key});

  @override
  State<MfaPolitikasi> createState() => _MfaPolitikasiState();
}

class _MfaPolitikasiState extends State<MfaPolitikasi> {
  List<String>? _roller;
  String? _rolHata;
  String? _orgId, _orgAdi;
  Map<String, dynamic>? _org;
  String? _orgHata;

  bool get _yonetir => Uyg.yetki('users.manage');

  @override
  void initState() {
    super.initState();
    if (Uyg.platformYoneticisi) _rolleriYukle();
    if (Uyg.musteri) {
      final id = Uyg.ben.value?['organization_id'];
      if (id is String && id.isNotEmpty) {
        _orgId = id;
        _orgYukle();
      }
    }
  }

  Future<void> _rolleriYukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/security/mfa-policy'));
      if (mounted) setState(() => _roller = metinler(v['required_roles']));
    } catch (e) {
      if (mounted) setState(() => _rolHata = hataMetni(e));
    }
  }

  Future<void> _orgYukle() async {
    setState(() {
      _org = null;
      _orgHata = null;
    });
    try {
      final v = harita(await Uyg.api.get('/api/v1/organizations/$_orgId/mfa-policy'));
      if (mounted) setState(() => _org = v);
    } catch (e) {
      if (mounted) setState(() => _orgHata = hataMetni(e));
    }
  }

  Future<void> _rolDegistir(String rol, bool zorunlu) async {
    final yeni = zorunlu ? {...?_roller, rol}.toList() : (_roller ?? []).where((x) => x != rol).toList();
    final v = await islem(() => Uyg.api.put('/api/v1/security/mfa-policy', {'required_roles': yeni}), tamam: 'Platform politikası kaydedildi');
    if (v != null && mounted) setState(() => _roller = metinler(harita(v)['required_roles']));
  }

  Future<void> _orgDegistir(String alan, bool deger) async {
    final v = await islem(() => Uyg.api.patch('/api/v1/organizations/$_orgId/mfa-policy', {alan: deger}), tamam: 'Müşteri politikası kaydedildi');
    if (v != null && mounted) setState(() => _org = harita(v));
  }

  Future<void> _musteriSec() async {
    final o = await musteriSec(context);
    if (o == null) return;
    setState(() {
      _orgId = o.id;
      _orgAdi = o.ad;
    });
    await _orgYukle();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final rolKarti = BolumKarti(
      ikon: Simgeler.adminPanelSettings,
      baslik: 'Rol bazında (platform)',
      child: _rolHata != null
          ? Text(_rolHata!, style: const TextStyle(color: Marka.gul))
          : _roller == null
          ? const LinearProgressIndicator()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final rol in const ['super_admin', 'reseller_admin', 'org_admin'])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('${rolEtiketi(rol)} için zorunlu'),
                    value: _roller!.contains(rol),
                    onChanged: _yonetir ? (v) => _rolDegistir(rol, v == true) : null,
                  ),
                Text("Süper yöneticiler için zorunlu kılmadan önce kendi hesabınızda 2FA'yı açın.", style: TextStyle(color: r.silik, fontSize: 12)),
              ],
            ),
    );
    final org = _org;
    final musteriKarti = BolumKarti(
      ikon: Simgeler.apartment,
      baslik: 'Müşteri bazında',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!Uyg.musteri) ...[SecimAlani(etiket: 'Müşteri', deger: _orgAdi, onTap: _musteriSec), const SizedBox(height: 8)],
          if (_orgHata != null)
            Text(_orgHata!, style: const TextStyle(color: Marka.gul))
          else if (_orgId != null && org == null)
            const LinearProgressIndicator()
          else if (org != null) ...[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Panel kullanıcıları için zorunlu'),
              value: mantik(org['panel']),
              onChanged: _yonetir ? (v) => _orgDegistir('panel', v) : null,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Posta kutuları (webmail) için zorunlu'),
              value: mantik(org['webmail']),
              onChanged: _yonetir ? (v) => _orgDegistir('webmail', v) : null,
            ),
            Text(
              '2FA açık posta kutuları Outlook/telefon (IMAP, POP3, SMTP, CalDAV) için yalnızca uygulama şifresiyle bağlanır.',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
          ] else
            Text('Politikasını görmek için bir müşteri seçin.', style: TextStyle(color: r.silik)),
        ],
      ),
    );
    return IcerikListesi(
      enFazla: 1100,
      children: [
        const SizedBox(height: 8),
        const Bant(
          "Zorunlu tutulan kullanıcılar bir sonraki girişlerinde kurulum yapmadan panele / webmail'e devam edemez. "
          "Telefonunu kaybeden kullanıcının 2FA'sını Kullanıcılar sekmesinden sıfırlayabilirsiniz (kayda geçer).",
          ikon: Simgeler.verifiedUser,
        ),
        const SizedBox(height: 12),
        if (Uyg.platformYoneticisi)
          LayoutBuilder(
            builder: (c, k) => k.maxWidth >= 800
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: rolKarti),
                      const SizedBox(width: 16),
                      Expanded(child: musteriKarti),
                    ],
                  )
                : Column(children: [rolKarti, const SizedBox(height: 12), musteriKarti]),
          )
        else
          musteriKarti,
      ],
    );
  }
}
