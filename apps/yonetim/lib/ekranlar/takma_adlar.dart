import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../ortak/tablo.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'liste_ortak.dart';
import '../ortak/simgeler.dart';

/// Takma adlar ve yönlendirme: takma adlar, dağıtım listeleri (GET/POST/PATCH/DELETE /aliases), alan adı bazında
/// catch-all (GET /catchall, PUT /domains/{id}/catchall) ve posta kutusu yönlendirmeleri (/mailboxes/{id}/forwarding).
class TakmaAdlarEkrani extends StatefulWidget {
  const TakmaAdlarEkrani({super.key, this.orgId, this.alanId, this.alanAdi});
  final String? orgId, alanId, alanAdi;
  @override
  State<TakmaAdlarEkrani> createState() => _TakmaAdlarEkraniState();
}

class _TakmaAdlarEkraniState extends State<TakmaAdlarEkrani> with SingleTickerProviderStateMixin {
  late final _sekme = TabController(length: 4, vsync: this)..addListener(() => setState(() {}));
  final _anahtarlar = [GlobalKey<_TakmaAdTablosuState>(), GlobalKey<_TakmaAdTablosuState>()];
  final _catchAll = GlobalKey<_CatchAllTablosuState>();
  final _yonlendirme = GlobalKey<_YonlendirmeTablosuState>();

  bool get _yonetir => Uyg.yetki('mailboxes.manage');

  @override
  void dispose() {
    _sekme.dispose();
    super.dispose();
  }

  void _yenile() => switch (_sekme.index) {
    0 || 1 => _anahtarlar[_sekme.index].currentState?.yenile(),
    2 => _catchAll.currentState?.yenile(),
    _ => _yonlendirme.currentState?.yenile(),
  };

  Future<void> _yeni() async {
    final liste = _sekme.index == 1;
    final t = await showDialog<TakmaAd>(
      context: context,
      builder: (_) => TakmaAdDialog(liste: liste, orgId: widget.orgId, alanId: widget.alanId, alanAdi: widget.alanAdi),
    );
    if (t != null) _anahtarlar[liste ? 1 : 0].currentState?.yenile();
  }

  @override
  Widget build(BuildContext context) {
    final i = _sekme.index;
    return Iskelet(
      baslik: widget.alanAdi == null ? 'Takma Adlar ve Yönlendirme' : 'Takma Adlar · ${widget.alanAdi}',
      alt: 'Takma adlar, dağıtım listeleri, catch-all ve posta kutusu yönlendirmeleri',
      yenile: _yenile,
      birincil: _yonetir && i < 2 ? BirincilEylem(Simgeler.add, i == 1 ? 'Yeni liste' : 'Yeni takma ad', _yeni) : null,
      sekmeler: TabBar(
        controller: _sekme,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [
          Tab(icon: Icon(Simgeler.alternateEmail, size: 18), text: 'Takma adlar', iconMargin: EdgeInsets.zero),
          Tab(icon: Icon(Simgeler.groups, size: 18), text: 'Dağıtım listeleri', iconMargin: EdgeInsets.zero),
          Tab(icon: Icon(Simgeler.inbox, size: 18), text: 'Catch-all', iconMargin: EdgeInsets.zero),
          Tab(icon: Icon(Simgeler.forwardToInbox, size: 18), text: 'Yönlendirme', iconMargin: EdgeInsets.zero),
        ],
      ),
      govde: TabBarView(
        controller: _sekme,
        children: [
          _TakmaAdTablosu(key: _anahtarlar[0], liste: false, orgId: widget.orgId, alanId: widget.alanId, yonetir: _yonetir),
          _TakmaAdTablosu(key: _anahtarlar[1], liste: true, orgId: widget.orgId, alanId: widget.alanId, yonetir: _yonetir),
          _CatchAllTablosu(key: _catchAll, orgId: widget.orgId, alanId: widget.alanId, yonetir: _yonetir),
          _YonlendirmeTablosu(key: _yonlendirme, orgId: widget.orgId, alanId: widget.alanId, yonetir: _yonetir),
        ],
      ),
    );
  }
}

// ---- takma adlar ve listeler ---------------------------------------------------------------------------------------

class _TakmaAdTablosu extends StatefulWidget {
  const _TakmaAdTablosu({super.key, required this.liste, required this.yonetir, this.orgId, this.alanId});
  final bool liste, yonetir;
  final String? orgId, alanId;
  @override
  State<_TakmaAdTablosu> createState() => _TakmaAdTablosuState();
}

class _TakmaAdTablosuState extends State<_TakmaAdTablosu> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String _durum = '';
  bool? _disYonlendirme;

  late final _y = SayfaYukleyici.yerel<TakmaAd>(() async {
    final v = harita(
      await Uyg.api.get(
        '/api/v1/aliases',
        q: {'kind': widget.liste ? 'list' : 'alias', if (_q.isNotEmpty) 'q': _q, 'domain_id': ?widget.alanId, 'organization_id': ?widget.orgId},
      ),
    );
    final d = v['external_forwarding'];
    if (d is bool && d != _disYonlendirme && mounted) setState(() => _disYonlendirme = d);
    final l = haritalar(v['items']).map(TakmaAd.coz);
    return [
      for (final t in l)
        if (_durum.isEmpty || (_durum == 'on') == t.etkin) t,
    ];
  }, sayfaBoyu: 25)..yenile();

  Future<void> yenile() => _y.yenile();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _duzenle(TakmaAd t) async {
    final y = await showDialog<TakmaAd>(
      context: context,
      builder: (_) => TakmaAdDialog(liste: t.liste, mevcut: t),
    );
    if (y != null) _y.degistir((x) => x.id == t.id, y);
  }

  Future<void> _ac(TakmaAd t) async {
    final liste = t.liste;
    await yonetimPenceresi(
      context,
      baslik: t.adres,
      alt: [liste ? 'Dağıtım listesi' : 'Takma ad', if (t.ad.isNotEmpty) t.ad, if (!Uyg.musteri) t.orgAdi].join(' · '),
      ozet: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (liste) BilgiSatiri('Kimler gönderebilir', gonderimIzinleri[t.gonderimIzni] ?? t.gonderimIzni),
          BilgiSatiri('Durum', t.etkin ? 'Etkin' : 'Devre dışı'),
          BilgiSatiri('Eklenme', tamZaman(t.eklenme)),
          const SizedBox(height: 4),
          Text(
            liste ? '${t.hedefler.length} üye' : 'Hedef adresler',
            style: TextStyle(color: context.r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(shrinkWrap: true, children: [for (final h in t.hedefler) KopyaKutusu(h)]),
          ),
        ],
      ),
      eylemler: widget.yonetir ? _eylemDugmeleri(t) : const [],
    );
  }

  List<SatirEylemiDugmesi> _eylemDugmeleri(TakmaAd t) => [
    SatirEylemiDugmesi(Simgeler.edit, 'Düzenle', () => _duzenle(t), ipucu: t.liste ? 'Üyeler, ad, gönderim izni' : 'Hedef adresler'),
    SatirEylemiDugmesi(
      Simgeler.powerSettingsNew,
      t.etkin ? 'Devre dışı bırak' : 'Etkinleştir',
      () => _ac2(t),
      ipucu: t.etkin ? 'Gelen posta reddedilir' : 'Postayı yeniden dağıt',
    ),
    SatirEylemiDugmesi(Simgeler.deleteOutline, 'Sil', () => _sil(t), ipucu: 'Adres boşa çıkar', tehlikeli: true),
  ];

  Future<void> _ac2(TakmaAd t) async {
    final v = await islem(() => Uyg.api.patch('/api/v1/aliases/${t.id}', {'enabled': !t.etkin}), tamam: t.etkin ? 'Devre dışı bırakıldı' : 'Etkinleştirildi');
    if (v is Map) _y.degistir((x) => x.id == t.id, TakmaAd.coz(harita(v)));
  }

  Future<void> _sil(TakmaAd t) async {
    if (!await onayla(
      context,
      '${t.adres} silinsin mi?',
      mesaj: 'Bu adrese gelen posta artık kabul edilmez (catch-all açıksa oraya düşer).',
      evet: 'Sil',
      tehlikeli: true,
    )) {
      return;
    }
    final v = await islem(() => Uyg.api.delete('/api/v1/aliases/${t.id}').then((_) => true), tamam: 'Silindi');
    if (v == true) _y.degistir((x) => x.id == t.id, null);
  }

  List<SatirEylemi> _satirEylemleri(TakmaAd t) => [
    for (final e in widget.yonetir ? _eylemDugmeleri(t) : <SatirEylemiDugmesi>[]) SatirEylemi(e.ikon, e.baslik, e.calistir, tehlikeli: e.tehlikeli),
  ];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final liste = widget.liste;
    final r = context.r;
    Widget simge() => Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: r.birincilYumusak, borderRadius: BorderRadius.circular(10)),
      child: Icon(liste ? Simgeler.groups : Simgeler.alternateEmail, color: r.birincil, size: 18),
    );
    return VeriTablosu<TakmaAd>(
      yukleyici: _y,
      onTap: _ac,
      eylemler: widget.yonetir ? _satirEylemleri : null,
      bosMetin: _q.isNotEmpty || _durum.isNotEmpty
          ? 'Eşleşen kayıt yok.'
          : liste
          ? 'Henüz dağıtım listesi yok. Örn. satis@ adresine gelen postayı ekibin tamamına dağıtın.'
          : 'Henüz takma ad yok. Örn. info@ adresini bir veya birden çok posta kutusuna yönlendirin.',
      bosIkon: liste ? Simgeler.groups : Simgeler.alternateEmail,
      ust: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FiltreCubugu(
            arama: AramaAlani(
              ipucu: liste ? 'Liste veya üye ara…' : 'Adres veya hedef ara…',
              degisti: (v) {
                _q = v;
                _y.yenile();
              },
            ),
            filtreler: [
              FiltreDugmesi<String>(
                etiket: 'Durum',
                ikon: Simgeler.toggleOn,
                secenekler: const [('', 'Tümü'), ('on', 'Etkin'), ('off', 'Devre dışı')],
                secili: _durum,
                secildi: (v) {
                  setState(() => _durum = v);
                  _y.yenile();
                },
              ),
            ],
            etkinler: [
              if (_durum.isNotEmpty)
                EtkinFiltre('Durum: ${_durum == 'on' ? 'Etkin' : 'Devre dışı'}', () {
                  setState(() => _durum = '');
                  _y.yenile();
                }),
            ],
          ),
          if (_disYonlendirme == false)
            Padding(
              padding: EdgeInsets.fromLTRB(context.genis ? 16 : 12, 0, context.genis ? 16 : 12, 8),
              child: const Bant(
                'Dış adreslere yönlendirme kapalı: sunucu giden posta modu doğrudan gönderim değil. Yalnızca kurum içi adresler hedef olabilir.',
                renk: Marka.kehribar,
                ikon: Simgeler.warningAmber,
              ),
            ),
        ],
      ),
      sutunlar: [
        Sutun(
          'Adres',
          esnek: 4,
          hucre: (c, t) => IkiSatir(t.adres, alt: [if (t.ad.isNotEmpty) t.ad, if (!Uyg.musteri) t.orgAdi].join(' · '), sol: simge()),
        ),
        Sutun(liste ? 'Üyeler' : 'Hedefler', esnek: 4, hucre: (c, t) => SolukMetin(liste ? '${t.hedefler.length} üye' : t.hedefler.join(', '))),
        if (liste) Sutun('Gönderim izni', esnek: 2, hucre: (c, t) => SolukMetin(gonderimIzinleri[t.gonderimIzni] ?? t.gonderimIzni)),
        Sutun('Durum', genislik: 120, hucre: (c, t) => Sigdir(DurumRozeti(t.etkin ? 'active' : 'suspended', etiket: t.etkin ? 'Etkin' : 'Kapalı'))),
      ],
      kart: (c, t) => VeriKarti(
        baslik: t.adres,
        alt: liste ? '${t.hedefler.length} üye · ${gonderimIzinleri[t.gonderimIzni] ?? t.gonderimIzni}' : '→ ${t.hedefler.join(', ')}',
        sol: simge(),
        rozetler: [if (!t.etkin) const Rozet('Kapalı', renk: Marka.kehribar)],
        alanlar: [if (t.ad.isNotEmpty) ('Ad', t.ad), if (!Uyg.musteri) ('Müşteri', t.orgAdi)],
        eylemler: widget.yonetir ? _satirEylemleri(t) : const [],
        onTap: () => _ac(t),
      ),
    );
  }
}

// ---- catch-all ---------------------------------------------------------------------------------------------------

class _CatchAll {
  const _CatchAll(this.alanId, this.alan, this.orgId, this.orgAdi, this.kutuId, this.kutu);
  final String alanId, alan, orgId, orgAdi;
  final String? kutuId, kutu;
  factory _CatchAll.coz(Map<String, dynamic> m) => _CatchAll(
    metin(m['domain_id']),
    metin(m['domain']),
    metin(m['organization_id']),
    metin(m['organization_name']),
    metinYa(m['mailbox_id']),
    metinYa(m['mailbox']),
  );
}

class _CatchAllTablosu extends StatefulWidget {
  const _CatchAllTablosu({super.key, required this.yonetir, this.orgId, this.alanId});
  final bool yonetir;
  final String? orgId, alanId;
  @override
  State<_CatchAllTablosu> createState() => _CatchAllTablosuState();
}

class _CatchAllTablosuState extends State<_CatchAllTablosu> with AutomaticKeepAliveClientMixin {
  String _q = '';
  late final _y = SayfaYukleyici.yerel<_CatchAll>(() async {
    final l = haritalar(harita(await Uyg.api.get('/api/v1/catchall'))['items']).map(_CatchAll.coz);
    final q = _q.toLowerCase();
    return [
      for (final c in l)
        if ((widget.alanId == null || c.alanId == widget.alanId) &&
            (widget.orgId == null || c.orgId == widget.orgId) &&
            (q.isEmpty || c.alan.toLowerCase().contains(q) || c.orgAdi.toLowerCase().contains(q)))
          c,
    ];
  })..yenile();

  Future<void> yenile() => _y.yenile();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _duzenle(_CatchAll c) async {
    if (!widget.yonetir) return;
    final secim = await araVeSec<(String?, String)>(
      context,
      baslik: 'Catch-all: ${c.alan}',
      ipucu: 'Posta kutusu ara…',
      yukle: (q) async => [
        if (q.isEmpty) (null, 'Kapalı (bilinmeyen adres reddedilir)'),
        ...Sayfa.coz(
          await Uyg.api.get('/api/v1/mailboxes', q: {'domain_id': c.alanId, 'page_size': '100', 'sort': 'address', 'order': 'asc', if (q.isNotEmpty) 'q': q}),
          PostaKutusu.coz,
        ).ogeler.map((m) => (m.id, m.adres)),
      ],
      ad: (x) => x.$2,
      alt: (x) => x.$1 != null && x.$1 == c.kutuId ? 'Şu anki catch-all kutusu' : null,
    );
    if (secim == null) return;
    final v = await islem(
      () => Uyg.api.put('/api/v1/domains/${c.alanId}/catchall', {'mailbox_id': secim.$1}).then((_) => true),
      tamam: secim.$1 == null ? 'Catch-all kapatıldı' : 'Catch-all ayarlandı',
    );
    if (v == true) _y.yenile();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final yatay = context.genis ? 16.0 : 12.0;
    return VeriTablosu<_CatchAll>(
      yukleyici: _y,
      onTap: widget.yonetir ? _duzenle : null,
      eylemler: widget.yonetir ? (c) => [SatirEylemi(Simgeler.edit, 'Catch-all kutusunu seç', () => _duzenle(c))] : null,
      bosMetin: _q.isEmpty
          ? 'Barındırılan alan adı yok. Catch-all yalnızca posta barındırma (hosting) alan adlarında kullanılabilir.'
          : 'Eşleşen alan adı yok.',
      bosIkon: Simgeler.inbox,
      ust: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(yatay, 8, yatay, 4),
            child: const Bant(
              'Catch-all açık alan adında, var olmayan adreslere gelen posta seçilen kutuya düşer (postmaster, abuse hariç). Spam yükünü artırabilir; yalnızca gerekiyorsa açın.',
            ),
          ),
          FiltreCubugu(
            arama: AramaAlani(
              ipucu: 'Alan adı ara…',
              degisti: (v) {
                _q = v;
                _y.yenile();
              },
            ),
          ),
        ],
      ),
      sutunlar: [
        Sutun('Alan adı', esnek: 4, hucre: (c, x) => IkiSatir(x.alan, alt: Uyg.musteri ? null : x.orgAdi)),
        Sutun(
          'Catch-all kutusu',
          esnek: 4,
          hucre: (c, x) => x.kutu == null
              ? Rozet('Kapalı', renk: c.r.silik)
              : Text(x.kutu!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
        ),
      ],
      kart: (c, x) => VeriKarti(
        baslik: x.alan,
        alt: Uyg.musteri ? null : x.orgAdi,
        rozetler: [x.kutu == null ? Rozet('Kapalı', renk: c.r.silik) : Rozet('→ ${x.kutu}', renk: Marka.zumrut)],
        eylemler: widget.yonetir ? [SatirEylemi(Simgeler.edit, 'Catch-all kutusunu seç', () => _duzenle(x))] : const [],
        onTap: widget.yonetir ? () => _duzenle(x) : null,
      ),
    );
  }
}

// ---- posta kutusu yönlendirme ----------------------------------------------------------------------------------------

class _YonlendirmeTablosu extends StatefulWidget {
  const _YonlendirmeTablosu({super.key, required this.yonetir, this.orgId, this.alanId});
  final bool yonetir;
  final String? orgId, alanId;
  @override
  State<_YonlendirmeTablosu> createState() => _YonlendirmeTablosuState();
}

class _YonlendirmeTablosuState extends State<_YonlendirmeTablosu> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String _sira = 'created_at';
  bool _artan = false;

  late final _y = SayfaYukleyici<PostaKutusu>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/mailboxes',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': _sira,
          'order': _artan ? 'asc' : 'desc',
          if (_q.isNotEmpty) 'q': _q,
          'domain_id': ?widget.alanId,
          'organization_id': ?widget.orgId,
        },
      ),
      PostaKutusu.coz,
    ),
  )..yenile();

  Future<void> yenile() => _y.yenile();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _ac(PostaKutusu m) {
    showDialog<void>(
      context: context,
      builder: (_) => YonlendirmeDialog(kutuId: m.id, adres: m.adres, yonetir: widget.yonetir),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final yatay = context.genis ? 16.0 : 12.0;
    return VeriTablosu<PostaKutusu>(
      yukleyici: _y,
      onTap: _ac,
      siralama: _sira,
      artan: _artan,
      siralamaDegisti: (a, b) {
        setState(() {
          _sira = a;
          _artan = b;
        });
        _y.yenile();
      },
      eylemler: (m) => [SatirEylemi(Simgeler.forwardToInbox, 'Yönlendirme', () => _ac(m))],
      bosMetin: _q.isEmpty ? 'Posta kutusu yok.' : 'Eşleşen posta kutusu yok.',
      bosIkon: Simgeler.forwardToInbox,
      ust: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FiltreCubugu(
            arama: AramaAlani(
              ipucu: 'Posta kutusu ara…',
              degisti: (v) {
                _q = v;
                _y.yenile();
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(yatay, 0, yatay, 8),
            child: Text(
              'Bir posta kutusunun gelen postasını başka adrese iletin. Kullanıcılar (paket izin veriyorsa) kendi yönlendirmelerini webmail ayarlarından da yönetebilir. Döngüler engellenir; dış yönlendirmeler günlük üst sınıra tabidir.',
              style: TextStyle(color: context.r.silik, fontSize: 12.5),
            ),
          ),
        ],
      ),
      sutunlar: [
        Sutun(
          'Posta kutusu',
          esnek: 5,
          siralama: 'address',
          hucre: (c, m) => IkiSatir(m.adres, alt: [m.gorunenAd, if (!Uyg.musteri) m.orgAdi].where((x) => x.isNotEmpty).join(' · ')),
        ),
        Sutun('Durum', genislik: 120, hucre: (c, m) => Sigdir(DurumRozeti(m.durum))),
        Sutun('Eklenme', genislik: 120, siralama: 'created_at', hucre: (c, m) => SolukMetin(kisaZaman(m.eklenme))),
      ],
      kart: (c, m) => VeriKarti(
        baslik: m.adres,
        alt: [m.gorunenAd, if (!Uyg.musteri) m.orgAdi].where((x) => x.isNotEmpty).join(' · '),
        rozetler: [if (m.durum != 'active') DurumRozeti(m.durum)],
        eylemler: [SatirEylemi(Simgeler.forwardToInbox, 'Yönlendirme', () => _ac(m))],
        onTap: () => _ac(m),
      ),
    );
  }
}

/// Posta kutusu yönlendirmesi (GET/PUT /mailboxes/{id}/forwarding): hedef adres ve kopya saklama.
class YonlendirmeDialog extends StatefulWidget {
  const YonlendirmeDialog({super.key, required this.kutuId, required this.adres, this.yonetir = true});
  final String kutuId, adres;
  final bool yonetir;
  @override
  State<YonlendirmeDialog> createState() => _YonlendirmeDialogState();
}

class _YonlendirmeDialogState extends State<YonlendirmeDialog> {
  final _hedef = TextEditingController();
  bool _sakla = true;
  bool _izinli = true, _disIzinli = true;
  String _ayarlayan = '';
  bool _yuklendi = false, _mesgul = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _hedef.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final m = harita(await Uyg.api.get('/api/v1/mailboxes/${widget.kutuId}/forwarding'));
      if (!mounted) return;
      setState(() {
        _hedef.text = metin(m['forward_to']);
        _sakla = mantik(m['keep_copy'], true);
        _izinli = mantik(m['allowed'], true);
        _disIzinli = mantik(m['external_allowed'], true);
        _ayarlayan = metin(m['set_by']);
        _yuklendi = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hata = hataMetni(e);
          _yuklendi = true;
        });
      }
    }
  }

  Future<void> _kaydet({bool kapat = false}) async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.put('/api/v1/mailboxes/${widget.kutuId}/forwarding', {'forward_to': kapat ? '' : _hedef.text.trim(), 'keep_copy': _sakla});
      bildir(kapat || _hedef.text.trim().isEmpty ? 'Yönlendirme kapatıldı' : 'Yönlendirme kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final duzenler = widget.yonetir && _izinli;
    return AlertDialog(
      title: Text('Yönlendirme', style: gosterim(19, agirlik: FontWeight.w600)),
      content: SizedBox(
        width: 440,
        child: !_yuklendi
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator.adaptive()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.adres, style: TextStyle(color: r.soluk, fontSize: 13)),
                  const SizedBox(height: 12),
                  if (!_izinli)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Bant('Yönlendirme bu posta kutusu için kapalı (paket veya kutu ayarı).', renk: Marka.kehribar, ikon: Simgeler.lockOutline),
                    ),
                  TextField(
                    controller: _hedef,
                    enabled: duzenler,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Hedef adres',
                      hintText: 'ad@ornek.com (boş = kapalı)',
                      helperText: _disIzinli ? null : 'Bu posta kutusu yalnızca iç adreslere yönlendirilebilir.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _sakla,
                    onChanged: duzenler ? (v) => setState(() => _sakla = v) : null,
                    title: const Text('Bu kutuda da bir kopya sakla'),
                  ),
                  if (_ayarlayan.isNotEmpty)
                    Text(
                      'Son ayarlayan: ${_ayarlayan.startsWith('admin:') ? 'yönetici (${_ayarlayan.substring(6)})' : (_ayarlayan == 'user' ? 'kullanıcı (webmail)' : _ayarlayan)}',
                      style: TextStyle(color: r.silik, fontSize: 12),
                    ),
                  if (_hata != null) ...[const SizedBox(height: 8), Bant(_hata!, renk: Marka.gul, ikon: Simgeler.errorOutline)],
                ],
              ),
      ),
      actions: [
        if (duzenler && _hedef.text.isNotEmpty)
          TextButton(
            onPressed: _mesgul ? null : () => _kaydet(kapat: true),
            style: TextButton.styleFrom(foregroundColor: Marka.gul),
            child: const Text('Kapat'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        if (duzenler) FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}

/// Yeni takma ad / dağıtım listesi (POST /aliases) ya da [mevcut] verilirse düzenleme (PATCH /aliases/{id}:
/// hedefler, liste adı, gönderim izni).
class TakmaAdDialog extends StatefulWidget {
  const TakmaAdDialog({super.key, required this.liste, this.orgId, this.alanId, this.alanAdi, this.mevcut});
  final bool liste;
  final String? orgId, alanId, alanAdi;
  final TakmaAd? mevcut;
  @override
  State<TakmaAdDialog> createState() => _TakmaAdDialogState();
}

class _TakmaAdDialogState extends State<TakmaAdDialog> {
  late String? _alanId = widget.alanId;
  late String? _alanAdi = widget.alanAdi;
  final _yerel = TextEditingController();
  late final _ad = TextEditingController(text: widget.mevcut?.ad ?? '');
  late final _hedefler = TextEditingController(text: widget.mevcut?.hedefler.join('\n') ?? '');
  late String _izin = widget.mevcut?.gonderimIzni ?? (widget.liste ? 'members' : 'anyone');
  bool _mesgul = false;
  String? _hata, _alan;

  @override
  void dispose() {
    _yerel.dispose();
    _ad.dispose();
    _hedefler.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
      _alan = null;
    });
    try {
      final m = widget.mevcut;
      if (m != null) {
        final v = await Uyg.api.patch('/api/v1/aliases/${m.id}', {
          'destinations': adresleriAyir(_hedefler.text),
          'name': _ad.text.trim(),
          'send_policy': _izin,
        });
        bildir('Kaydedildi', tur: MesajTur.basari);
        if (mounted) Navigator.pop(context, TakmaAd.coz(harita(v)));
        return;
      }
      final v = await Uyg.api.post('/api/v1/aliases', {
        'domain_id': _alanId,
        'local_part': _yerel.text.trim().toLowerCase(),
        'kind': widget.liste ? 'list' : 'alias',
        if (widget.liste && _ad.text.trim().isNotEmpty) 'name': _ad.text.trim(),
        'destinations': adresleriAyir(_hedefler.text),
        if (widget.liste) 'send_policy': _izin,
      });
      bildir(widget.liste ? 'Dağıtım listesi oluşturuldu' : 'Takma ad oluşturuldu', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, TakmaAd.coz(harita(v)));
    } on ApiHata catch (e) {
      setState(() {
        _hata = e.mesaj;
        _alan = e.alan;
      });
    } catch (e) {
      setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final yeni = widget.mevcut == null;
    final hazir = !_mesgul && (!yeni || (_alanId != null && _yerel.text.trim().isNotEmpty)) && adresleriAyir(_hedefler.text).isNotEmpty;
    return AlertDialog(
      title: Text(
        widget.mevcut?.adres ?? (widget.liste ? 'Yeni dağıtım listesi' : 'Yeni takma ad'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: gosterim(19, agirlik: FontWeight.w600),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.liste
                    ? 'Listeye gelen posta tüm üyelere dağıtılır. Üyeler kurum içi posta kutuları veya (izin varsa) dış adresler olabilir.'
                    : 'Takma ada gelen posta hedef posta kutularına teslim edilir; takma adla posta kutusu yoktur.',
                style: TextStyle(color: context.r.silik, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (yeni) ...[
                SecimAlani(
                  etiket: 'Alan adı',
                  deger: _alanAdi,
                  hata: _alan == 'domain_id' ? _hata : null,
                  onTap: () async {
                    final d = await alanSec(context, orgId: widget.orgId);
                    if (d != null) {
                      setState(() {
                        _alanId = d.id;
                        _alanAdi = d.gorunenAd;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _yerel,
                  autocorrect: false,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Adres',
                    hintText: widget.liste ? 'satis' : 'info',
                    suffixText: _alanAdi == null ? null : '@$_alanAdi',
                    errorText: _alan == 'local_part' ? _hata : null,
                  ),
                ),
              ],
              if (widget.liste) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _ad,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Liste adı', hintText: 'Satış ekibi'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _hedefler,
                minLines: 3,
                maxLines: 8,
                autocorrect: false,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.liste ? 'Üyeler (her satıra bir adres)' : 'Hedef adresler (her satıra bir adres)',
                  alignLabelWithHint: true,
                  errorText: _alan == 'destinations' ? _hata : null,
                  helperText: 'En çok ${widget.liste ? 500 : 50} adres. Dış adreslere giden kopyalarda gönderen SRS ile yeniden yazılır.',
                  helperMaxLines: 2,
                ),
              ),
              if (widget.liste) ...[
                const SizedBox(height: 12),
                Text(
                  'Kimler gönderebilir?',
                  style: TextStyle(color: context.r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SecimCipleri<String>(
                  secenekler: [for (final e in gonderimIzinleri.entries) (e.key, e.value)],
                  secili: _izin,
                  secildi: (v) => setState(() => _izin = v),
                ),
              ],
              if (_hata != null && !{'domain_id', 'local_part', 'destinations'}.contains(_alan)) ...[
                const SizedBox(height: 12),
                Bant(_hata!, renk: Marka.gul, ikon: Simgeler.errorOutline),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: hazir ? _kaydet : null,
          child: _mesgul
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(yeni ? 'Oluştur' : 'Kaydet'),
        ),
      ],
    );
  }
}
