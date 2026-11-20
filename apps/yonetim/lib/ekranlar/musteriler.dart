import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/sayfali.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'alan_adlari.dart';
import 'posta_kutulari.dart';

/// Müşteriler (organizasyonlar): platform ve bayi yöneticileri için liste, ayrıntı ve askıya alma.
/// Süper yönetici bayileri ayrı sekmede görür (GET /resellers).
class MusterilerEkrani extends StatelessWidget {
  const MusterilerEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi) {
      return Scaffold(
        appBar: AppBar(title: const Text('Müşteriler')),
        body: const MusteriListesi(),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Müşteriler'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Müşteriler'),
              Tab(text: 'Bayiler'),
            ],
          ),
        ),
        body: const TabBarView(children: [MusteriListesi(), BayiListesi()]),
      ),
    );
  }
}

class MusteriListesi extends StatefulWidget {
  const MusteriListesi({super.key});
  @override
  State<MusteriListesi> createState() => _MusteriListesiState();
}

class _MusteriListesiState extends State<MusteriListesi> with AutomaticKeepAliveClientMixin {
  String _q = '', _durum = '';
  Organizasyon? _secili;

  late final _y = SayfaYukleyici<Organizasyon>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/organizations',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': 'name',
          'order': 'asc',
          'internal': '0',
          if (_q.isNotEmpty) 'q': _q,
          if (_durum.isNotEmpty) 'status': _durum,
        },
      ),
      Organizasyon.coz,
    ),
  )..yenile();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _ac(Organizasyon o) {
    if (bolunmus(context)) {
      setState(() => _secili = o);
    } else {
      sayfaAc(context, o.ad, MusteriDetay(org: o, degisti: (y) => _degisti(o.id, y)));
    }
  }

  void _degisti(String id, Organizasyon y) {
    _y.degistir((x) => x.id == id, y);
    if (_secili?.id == id) setState(() => _secili = y);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final liste = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
            children: [
              AramaAlani(
                ipucu: 'Müşteri ara…',
                degisti: (v) {
                  _q = v;
                  _y.yenile();
                },
              ),
              const SizedBox(height: 8),
              SecimCipleri<String>(
                secenekler: const [('', 'Tümü'), ('active', 'Aktif'), ('suspended', 'Askıda')],
                secili: _durum,
                secildi: (v) {
                  setState(() => _durum = v);
                  _y.yenile();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SayfaliListe<Organizasyon>(
            yukleyici: _y,
            ayrac: false,
            bosMetin: _q.isEmpty ? 'Henüz müşteri yok.' : 'Eşleşen müşteri yok.',
            bosIkon: Icons.apartment_rounded,
            oge: (c, o) => ListeSatiri(
              secili: _secili?.id == o.id && bolunmus(c),
              onTap: () => _ac(o),
              sol: Avatar(o.ad, tohum: o.id),
              baslik: o.ad,
              alt: [?o.paketAdi, if (Uyg.platformYoneticisi && o.bayiAdi != null) o.bayiAdi!].join(' · '),
              alt2: '${o.alanSayisi} alan adı · ${o.kutuSayisi} posta kutusu · ${boyutYaz(o.kullanilan)}',
              sag: o.durum == 'active' ? null : DurumRozeti(o.durum),
            ),
          ),
        ),
      ],
    );
    return AnaDetay(
      liste: liste,
      detay: _secili == null ? null : MusteriDetay(key: ValueKey(_secili!.id), org: _secili!, degisti: (y) => _degisti(_secili!.id, y)),
      bosMetin: 'Ayrıntı için bir müşteri seçin',
      listeGenisligi: 400,
    );
  }
}

/// Müşteri ayrıntısı (GET /organizations/{id}): paket sınırları, kullanım, iletişim profili ve kısayollar.
class MusteriDetay extends StatefulWidget {
  const MusteriDetay({super.key, required this.org, required this.degisti});
  final Organizasyon org;
  final void Function(Organizasyon) degisti;
  @override
  State<MusteriDetay> createState() => _MusteriDetayState();
}

class _MusteriDetayState extends State<MusteriDetay> {
  late Organizasyon _o = widget.org;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = await Uyg.api.get('/api/v1/organizations/${_o.id}');
      if (mounted) {
        setState(() {
          _o = Organizasyon.coz(harita(v));
          _hata = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _durum() async {
    final askiya = _o.durum == 'active';
    if (askiya &&
        !await onayla(
          context,
          '${_o.ad} askıya alınsın mı?',
          mesaj: 'Müşterinin tüm posta kutuları giriş yapamaz ve posta gönderemez; panel erişimi kapanır.',
          evet: 'Askıya al',
          tehlikeli: true,
        )) {
      return;
    }
    final v = await islem(
      () => Uyg.api.patch('/api/v1/organizations/${_o.id}', {'status': askiya ? 'suspended' : 'active'}),
      tamam: askiya ? 'Müşteri askıya alındı' : 'Müşteri etkinleştirildi',
    );
    if (v != null && mounted) {
      setState(() => _o = Organizasyon.coz(harita(v)));
      widget.degisti(_o);
    }
  }

  void _git(Widget ekran) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ekran));

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final o = _o;
    final profil = [
      for (final e in profilAlanlari.entries)
        if (metin(o.profil[e.key]).trim().isNotEmpty) (e.value, metin(o.profil[e.key]).trim()),
    ];
    String sinir(int kullanilan, int? enFazla) => enFazla == null || enFazla <= 0 ? '$kullanilan / sınırsız' : '$kullanilan / $enFazla';
    return RefreshIndicator.adaptive(
      onRefresh: _yukle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Avatar(o.ad, tohum: o.id, boyut: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o.ad, style: gosterim(18, agirlik: FontWeight.w700)),
                          Text([o.paketAdi ?? 'Paket yok', if (o.bayiAdi != null) o.bayiAdi!].join(' · '), style: TextStyle(color: r.silik, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    DurumRozeti(o.durum),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Depolama',
                  style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                KullanimCubugu(kullanilan: o.kullanilan, toplam: o.toplamKota != null && o.toplamKota! > 0 ? o.toplamKota! : o.ayrilan),
                const SizedBox(height: 4),
                Text('${boyutYaz(o.ayrilan)} posta kutularına tahsis edildi', style: TextStyle(color: r.silik, fontSize: 12)),
              ],
            ),
          ),
          if (_hata != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Bant(_hata!, renk: Marka.gul, ikon: Icons.cloud_off_rounded),
            ),
          const Baslik('Paket kullanımı'),
          Kutu(
            child: Column(
              children: [
                BilgiSatiri('Alan adları', sinir(o.alanSayisi, o.enFazlaAlan)),
                BilgiSatiri('Posta kutuları', sinir(o.kutuSayisi, o.enFazlaKutu)),
                BilgiSatiri('Toplam kota', o.toplamKota == null || o.toplamKota! <= 0 ? 'Sınırsız' : boyutYaz(o.toplamKota!)),
                BilgiSatiri('Kayıt tarihi', tamZaman(o.eklenme)),
              ],
            ),
          ),
          const Baslik('Kısayollar'),
          EylemSatiri(
            ikon: Icons.language_rounded,
            baslik: 'Alan adları',
            ipucu: '${o.alanSayisi} alan adı',
            onTap: () => _git(AlanAdlariEkrani(orgId: o.id, orgAdi: o.ad)),
          ),
          const SizedBox(height: 8),
          EylemSatiri(
            ikon: Icons.inbox_rounded,
            baslik: 'Posta kutuları',
            ipucu: '${o.kutuSayisi} posta kutusu',
            onTap: () => _git(PostaKutulariEkrani(orgId: o.id, orgAdi: o.ad)),
          ),
          if (profil.isNotEmpty) ...[
            const Baslik('İletişim ve fatura bilgileri'),
            Kutu(
              child: Column(children: [for (final (a, d) in profil) BilgiSatiri(a, d, kopyalanabilir: !a.startsWith('Not'))]),
            ),
          ],
          if (Uyg.yetki('organizations.manage')) ...[
            const Baslik('İşlemler'),
            EylemSatiri(
              ikon: o.durum == 'active' ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
              baslik: o.durum == 'active' ? 'Müşteriyi askıya al' : 'Müşteriyi etkinleştir',
              ipucu: o.durum == 'active' ? 'Giriş ve gönderim durur' : 'Hesap yeniden kullanıma açılır',
              tehlikeli: o.durum == 'active',
              onTap: _durum,
            ),
          ],
        ],
      ),
    );
  }
}

class BayiListesi extends StatefulWidget {
  const BayiListesi({super.key});
  @override
  State<BayiListesi> createState() => _BayiListesiState();
}

class _BayiListesiState extends State<BayiListesi> with AutomaticKeepAliveClientMixin {
  List<Bayi>? _l;
  String? _hata;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = await Uyg.api.get('/api/v1/resellers');
      if (mounted) {
        setState(() {
          _l = haritalar(harita(v)['items']).map(Bayi.coz).toList();
          _hata = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = _l;
    return RefreshIndicator.adaptive(
      onRefresh: _yukle,
      child: _hata != null && l == null
          ? ListView(
              children: [SizedBox(height: 320, child: Durum.hata(_hata!, tekrar: _yukle))],
            )
          : l == null
          ? const Durum.yukleniyor()
          : l.isEmpty
          ? ListView(
              children: const [SizedBox(height: 320, child: Durum.bos('Henüz bayi yok.', ikon: Icons.storefront_rounded))],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: l.length,
              itemBuilder: (c, i) {
                final b = l[i];
                return ListeSatiri(
                  sol: Avatar(b.ad, tohum: b.id),
                  baslik: b.ad,
                  alt: '${b.musteriSayisi} müşteri',
                  alt2: 'Kayıt: ${kisaZaman(b.eklenme)}',
                  sag: b.durum == 'active' ? null : DurumRozeti(b.durum),
                  onTap: null,
                );
              },
            ),
    );
  }
}
