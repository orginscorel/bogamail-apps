import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import '../veri/tehdit_modeller.dart';
import 'tehdit_ayarlar.dart';
import 'tehdit_listeler.dart';
import 'tehdit_ortak.dart';

/// Tehdit Koruması (web: admin/threats): tespitler, ek analizi, tıklama koruması, korunan kişiler (VIP),
/// bağlantı listesi, IP/ASN itibarı ve platform ayarları (son ikisi yalnızca süper yönetici).
class TehditEkrani extends StatefulWidget {
  const TehditEkrani({super.key});

  @override
  State<TehditEkrani> createState() => _TehditEkraniState();
}

class _TehditEkraniState extends State<TehditEkrani> {
  int _nesil = 0;

  @override
  Widget build(BuildContext context) {
    final suser = Uyg.platformYoneticisi;
    final sekmeler = <(String, Widget)>[
      ('Tespitler', const TehditTespitleri()),
      ('Ek analizi', const TehditEkRaporlari()),
      ('Tıklama koruması', const TehditTiklamaKorumasi()),
      ('Korunan kişiler', const TehditKorunanKisiler()),
      ('Bağlantı listesi', const TehditBaglantiListesi()),
      if (suser) ('IP / ASN itibarı', const TehditItibar()),
      if (suser) ('Ayarlar', const TehditPlatformAyarlari()),
    ];
    return DefaultTabController(
      length: sekmeler.length,
      child: Iskelet(
        baslik: 'Tehdit Koruması',
        alt: 'DMARC, sahte gönderen, kimlik taklidi, zararlı bağlantı, QR ve ek analizi',
        yenile: () => setState(() => _nesil++),
        sekmeler: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final (e, _) in sekmeler) Tab(text: e)],
        ),
        govde: TabBarView(
          children: [for (final (i, (_, w)) in sekmeler.indexed) KeyedSubtree(key: ValueKey('$_nesil-$i'), child: w)],
        ),
      ),
    );
  }
}

// ---- tespitler ----------------------------------------------------------------------------------------------

Color tespitSonucRengi(String a) => switch (a) {
  'reject' => Marka.gul,
  'junk' => Marka.kehribar,
  'allow' => Marka.zumrut,
  _ => Colors.blueGrey,
};

IconData tespitIkonu(String k) => switch (k) {
  'dmarc' => Icons.verified_user_outlined,
  'spoof' => Icons.person_off_outlined,
  'impersonation' => Icons.theater_comedy_outlined,
  'lookalike' => Icons.compare_arrows_rounded,
  'link' => Icons.link_off_rounded,
  'reputation' => Icons.public_off_rounded,
  'qr' => Icons.qr_code_2_rounded,
  'sandbox' => Icons.science_outlined,
  _ => Icons.shield_outlined,
};

/// Tespitler sekmesi: tür özetleri (7 gün / bugün) ve sayfalı tespit listesi.
class TehditTespitleri extends StatefulWidget {
  const TehditTespitleri({super.key});
  @override
  State<TehditTespitleri> createState() => _TehditTespitleriState();
}

class _TehditTespitleriState extends State<TehditTespitleri> {
  String _q = '', _tur = '', _sonuc = '';
  String? _orgId, _orgAdi;
  String _sira = 'at';
  bool _artan = false;
  Map<String, dynamic>? _ozet;

  late final _y = SayfaYukleyici<Tespit>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/threat/detections',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': _sira,
          'order': _artan ? 'asc' : 'desc',
          if (_q.isNotEmpty) 'q': _q,
          if (_tur.isNotEmpty) 'kind': _tur,
          if (_sonuc.isNotEmpty) 'action': _sonuc,
          'organization_id': ?_orgId,
        },
      ),
      Tespit.coz,
    ),
  );

  @override
  void initState() {
    super.initState();
    _ozetYukle();
    _y.yenile();
  }

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _ozetYukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/threat/summary'));
      if (mounted) setState(() => _ozet = v);
    } catch (_) {}
  }

  void _turSec(String t) {
    setState(() => _tur = t);
    _y.yenile();
  }

  void _ac(Tespit t) => ayrintiGoster(
    context,
    baslik: '${tespitTuru(t.tur)}: ${t.kural}',
    alt: '${tamZaman(t.zaman)} · kuyruk ${t.kuyruk.isEmpty ? '—' : t.kuyruk}',
    icerik: [
      EtiketDeger('Ayrıntı', t.ayrinti),
      if (t.uyari.isNotEmpty) EtiketDeger('Uyarı', t.uyari),
      EtiketDeger('From', t.baslikFrom.isEmpty ? '—' : t.baslikFrom),
      EtiketDeger('Zarf', t.zarf.isEmpty ? '<>' : t.zarf),
      EtiketDeger('IP', t.ip ?? '—', mono: true),
      EtiketDeger('Sonuç', '${tespitSonucu(t.sonuc)} (+${puanYaz(t.puan)} puan)'),
      if (t.orgAdi != null) EtiketDeger('Müşteri', t.orgAdi!),
    ],
  );

  Widget _ozetSeridi(BuildContext context) {
    final r = context.r;
    final hafta = harita(_ozet?['week']), bugun = harita(_ozet?['today']);
    return SizedBox(
      height: 120,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        children: [
          for (final k in tespitTurleri.keys)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: _tur == k ? r.vurguYumusak : r.kart,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: _tur == k ? r.vurgu : r.kenar)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _turSec(_tur == k ? '' : k),
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(tespitIkonu(k), size: 15, color: r.soluk),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(tespitTuru(k), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(_ozet == null ? '–' : sayiYaz(tamsayi(hafta[k])), style: gosterim(20, renk: r.metin)),
                        Text('7 gün · bugün ${tamsayi(bugun[k])}', style: TextStyle(color: r.silik, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgGoster = !Uyg.musteri;
    return VeriTablosu<Tespit>(
      yukleyici: _y,
      bosMetin: 'Tespit yok. Sahte gönderen, kimlik taklidi, DMARC hatası veya zararlı bağlantı içeren iletiler burada listelenir.',
      bosIkon: Icons.verified_user_outlined,
      siralama: _sira,
      artan: _artan,
      siralamaDegisti: (a, b) {
        setState(() {
          _sira = a;
          _artan = b;
        });
        _y.yenile();
      },
      onTap: _ac,
      ust: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ozetSeridi(context),
          FiltreCubugu(
            arama: AramaAlani(
              ipucu: 'Gönderen, IP, kural, kuyruk kimliği…',
              degisti: (v) {
                _q = v;
                _y.yenile();
              },
            ),
            filtreler: [
              FiltreDugmesi<String>(
                etiket: 'Tür',
                ikon: Icons.category_outlined,
                secenekler: [('', 'Tüm türler'), for (final e in tespitTurleri.entries) (e.key, e.value)],
                secili: _tur,
                secildi: _turSec,
              ),
              FiltreDugmesi<String>(
                etiket: 'Sonuç',
                ikon: Icons.rule_rounded,
                secenekler: [('', 'Tüm sonuçlar'), for (final e in tespitSonuclari.entries) (e.key, e.value)],
                secili: _sonuc,
                secildi: (v) {
                  setState(() => _sonuc = v);
                  _y.yenile();
                },
              ),
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
            ],
            etkinler: [
              if (_tur.isNotEmpty) EtkinFiltre('Tür: ${tespitTuru(_tur)}', () => _turSec('')),
              if (_sonuc.isNotEmpty)
                EtkinFiltre('Sonuç: ${tespitSonucu(_sonuc)}', () {
                  setState(() => _sonuc = '');
                  _y.yenile();
                }),
            ],
          ),
        ],
      ),
      sutunlar: [
        Sutun('Zaman', genislik: 130, siralama: 'at', hucre: (c, t) => SolukMetin(kisaZaman(t.zaman))),
        Sutun(
          'Tespit',
          esnek: 4,
          hucre: (c, t) => IkiSatir(
            t.kural,
            alt: t.ayrinti,
            mono: true,
            sol: Rozet(tespitTuru(t.tur), renk: Marka.mor),
          ),
        ),
        Sutun('Gönderen', esnek: 3, hucre: (c, t) => SolukMetin(t.gonderen)),
        if (orgGoster) Sutun('Müşteri', esnek: 2, hucre: (c, t) => SolukMetin(t.orgAdi ?? '—')),
        Sutun(
          'Sonuç',
          genislik: 200,
          siralama: 'score',
          sagaYasla: true,
          hucre: (c, t) => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(child: Rozet(tespitSonucu(t.sonuc), renk: tespitSonucRengi(t.sonuc))),
              const SizedBox(width: 6),
              Text('+${puanYaz(t.puan)}', style: TextStyle(color: c.r.silik, fontSize: 12)),
            ],
          ),
        ),
      ],
      kart: (c, t) => VeriKarti(
        baslik: t.kural,
        alt: t.ayrinti,
        onTap: () => _ac(t),
        rozetler: [Rozet(tespitTuru(t.tur), renk: Marka.mor), Rozet('${tespitSonucu(t.sonuc)} · +${puanYaz(t.puan)}', renk: tespitSonucRengi(t.sonuc))],
        alanlar: [('Zaman', kisaZaman(t.zaman)), ('Gönderen', t.gonderen), if (orgGoster) ('Müşteri', t.orgAdi ?? '—')],
      ),
    );
  }
}

// ---- ek analizi ---------------------------------------------------------------------------------------------

Color ekKararRengi(String v) => switch (v) {
  'malicious' => Marka.gul,
  'suspicious' => Marka.kehribar,
  _ => Colors.blueGrey,
};

String ekKarari(String v) => ekKararlari[v] ?? v;
String ekSonucu(String v) => ekSonuclari[v] ?? v;

/// Ek analizi raporunun ayrıntısı.
void ekRaporuGoster(BuildContext context, EkRaporu e) => ayrintiGoster(
  context,
  baslik: e.dosya.isEmpty ? '(adsız ek)' : e.dosya,
  alt: '${tamZaman(e.zaman)} · kuyruk ${e.kuyruk}',
  icerik: [
    EtiketDeger(
      'Sonuç',
      '',
      sag: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Rozet(ekKarari(e.karar), renk: ekKararRengi(e.karar)),
          Text('puan ${puanYaz(e.puan)} · ${ekSonucu(e.sonuc)}', style: const TextStyle(fontSize: 13.5)),
        ],
      ),
    ),
    EtiketDeger(
      'Tür',
      'uzantı: ${e.bildirilen.isEmpty ? '—' : e.bildirilen} · içerik: ${e.algilanan.isEmpty ? 'bilinmiyor' : e.algilanan} · ${boyutYaz(e.boyut)}',
    ),
    EtiketDeger('SHA-256', e.sha256, mono: true),
    EtiketDeger('Analiz', 'Statik derin analiz (çalıştırma yok)${e.orgAdi != null ? ' · ${e.orgAdi}' : ''}'),
    const SizedBox(height: 10),
    if (e.bulgular.isEmpty)
      Text('Bulgu yok.', style: TextStyle(color: context.r.soluk))
    else
      for (final (kural, puan, ayrinti) in e.bulgular)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: context.r.kenar)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(kural, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                  if (puan > 0) Rozet('+${puanYaz(puan)}', renk: Marka.kehribar),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(ayrinti, style: const TextStyle(fontSize: 13.5)),
            ],
          ),
        ),
    if (e.qrAdresleri.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('QR kod hedefleri (maskeli): ${e.qrAdresleri.join(', ')}', style: TextStyle(color: context.r.silik, fontSize: 12)),
      ),
  ],
);

/// Ek analizi sekmesi (GET /attachment-reports).
class TehditEkRaporlari extends StatefulWidget {
  const TehditEkRaporlari({super.key});
  @override
  State<TehditEkRaporlari> createState() => _TehditEkRaporlariState();
}

class _TehditEkRaporlariState extends State<TehditEkRaporlari> {
  String _q = '', _karar = 'flagged';
  String? _orgId, _orgAdi;
  String _sira = 'at';
  bool _artan = false;

  late final _y = SayfaYukleyici<EkRaporu>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/attachment-reports',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': _sira,
          'order': _artan ? 'asc' : 'desc',
          if (_q.isNotEmpty) 'q': _q,
          if (_karar != 'all') 'verdict': _karar,
          'organization_id': ?_orgId,
        },
      ),
      EkRaporu.coz,
    ),
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  static const _kararlar = [('flagged', 'Şüpheli + zararlı'), ('malicious', 'Zararlı'), ('suspicious', 'Şüpheli'), ('clean', 'Temiz'), ('all', 'Tümü')];

  @override
  Widget build(BuildContext context) {
    final orgGoster = !Uyg.musteri;
    String ilkBulgu(EkRaporu e) => e.bulgular.isEmpty ? 'Bulgu yok' : e.bulgular.first.$3;
    return VeriTablosu<EkRaporu>(
      yukleyici: _y,
      bosMetin: 'Seçilen filtreyle eşleşen ek analizi yok.',
      bosIkon: Icons.find_in_page_outlined,
      siralama: _sira,
      artan: _artan,
      siralamaDegisti: (a, b) {
        setState(() {
          _sira = a;
          _artan = b;
        });
        _y.yenile();
      },
      onTap: (e) => ekRaporuGoster(context, e),
      ust: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Aciklama(
              'Gelişmiş tehdit koruması olan müşterilerin gelen postasındaki her ek statik olarak incelenir: makrolar, DDE, dış şablon, '
              'gömülü nesneler, PDF eylemleri, arşivler, uzantı/içerik uyumsuzluğu, HTML smuggling ve QR kodlar. Hiçbir ek çalıştırılmaz.',
            ),
          ),
          FiltreCubugu(
            arama: AramaAlani(
              ipucu: 'Dosya adı, SHA-256, kuyruk kimliği…',
              degisti: (v) {
                _q = v;
                _y.yenile();
              },
            ),
            filtreler: [
              FiltreDugmesi<String>(
                etiket: 'Sonuç',
                ikon: Icons.rule_rounded,
                secenekler: _kararlar,
                secili: _karar,
                secildi: (v) {
                  setState(() => _karar = v);
                  _y.yenile();
                },
              ),
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
            ],
          ),
        ],
      ),
      sutunlar: [
        Sutun('Zaman', genislik: 130, siralama: 'at', hucre: (c, e) => SolukMetin(kisaZaman(e.zaman))),
        Sutun(
          'Ek',
          esnek: 4,
          hucre: (c, e) => IkiSatir(
            e.dosya.isEmpty ? '(adsız)' : e.dosya,
            alt: ilkBulgu(e),
            sol: e.qrAdresleri.isEmpty ? null : Icon(Icons.qr_code_2_rounded, size: 18, color: c.r.soluk),
          ),
        ),
        Sutun(
          'Tür',
          esnek: 2,
          hucre: (c, e) => IkiSatir('${e.bildirilen.isEmpty ? '—' : e.bildirilen} → ${e.algilanan.isEmpty ? '?' : e.algilanan}', alt: boyutYaz(e.boyut), kalin: false),
        ),
        if (orgGoster) Sutun('Müşteri', esnek: 2, hucre: (c, e) => SolukMetin(e.orgAdi ?? '—')),
        Sutun(
          'Sonuç',
          genislik: 170,
          siralama: 'score',
          sagaYasla: true,
          hucre: (c, e) => Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Rozet(ekKarari(e.karar), renk: ekKararRengi(e.karar)),
              Text('${puanYaz(e.puan)} · ${ekSonucu(e.sonuc)}', style: TextStyle(color: c.r.silik, fontSize: 11.5)),
            ],
          ),
        ),
      ],
      kart: (c, e) => VeriKarti(
        baslik: e.dosya.isEmpty ? '(adsız)' : e.dosya,
        alt: ilkBulgu(e),
        onTap: () => ekRaporuGoster(context, e),
        rozetler: [
          Rozet(ekKarari(e.karar), renk: ekKararRengi(e.karar)),
          Rozet(ekSonucu(e.sonuc), renk: Colors.blueGrey),
          if (e.qrAdresleri.isNotEmpty) const Rozet('QR', ikon: Icons.qr_code_2_rounded),
        ],
        alanlar: [
          ('Zaman', kisaZaman(e.zaman)),
          ('Tür', e.algilanan.isEmpty ? '?' : e.algilanan),
          ('Puan', puanYaz(e.puan)),
          if (orgGoster) ('Müşteri', e.orgAdi ?? '—'),
        ],
      ),
    );
  }
}

// ---- tıklama koruması ---------------------------------------------------------------------------------------

const tiklamaKararlari = <String, String>{'clean': 'Temiz', 'suspicious': 'Şüpheli', 'blocked': 'Engellendi'};

Widget tiklamaRozeti(Tiklama t) => switch (t.karar) {
  'blocked' => const Rozet('Engellendi', renk: Marka.gul),
  'suspicious' => Rozet(t.devamEtti ? 'Şüpheli · devam etti' : 'Şüpheli', renk: Marka.kehribar),
  _ => Rozet(tiklamaKararlari[t.karar] ?? t.karar, renk: Colors.blueGrey),
};

/// Tıklama koruması sekmesi: maskeli tıklama kaydı ve tıklama engel listesi (iki alt görünüm).
class TehditTiklamaKorumasi extends StatefulWidget {
  const TehditTiklamaKorumasi({super.key});
  @override
  State<TehditTiklamaKorumasi> createState() => _TehditTiklamaKorumasiState();
}

class _TehditTiklamaKorumasiState extends State<TehditTiklamaKorumasi> {
  int _gorunum = 0;
  String _q = '', _karar = '';
  String? _orgId, _orgAdi;

  late final _y = SayfaYukleyici<Tiklama>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/clicks',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': 'at',
          'order': 'desc',
          if (_q.isNotEmpty) 'q': _q,
          if (_karar.isNotEmpty) 'verdict': _karar,
          'organization_id': ?_orgId,
        },
      ),
      Tiklama.coz,
    ),
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orgGoster = !Uyg.musteri;
    final secici = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, icon: Icon(Icons.ads_click_rounded, size: 18), label: Text('Tıklama kaydı')),
            ButtonSegment(value: 1, icon: Icon(Icons.block_rounded, size: 18), label: Text('Engel listesi')),
          ],
          selected: {_gorunum},
          onSelectionChanged: (s) => setState(() => _gorunum = s.first),
        ),
      ),
    );
    if (_gorunum == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [secici, const Expanded(child: TiklamaEngelListesi())],
      );
    }
    return VeriTablosu<Tiklama>(
      yukleyici: _y,
      bosMetin: 'Tıklama kaydı yok. Webmail\'de korunan bir bağlantıya tıklandığında burada görünür.',
      bosIkon: Icons.ads_click_rounded,
      ust: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          secici,
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Aciklama(
              'Webmail\'de açılan iletilerdeki bağlantılar imzalı bir yönlendirme adresinden geçer ve tıklandığı anda yeniden denetlenir. '
              'Şüpheli bağlantıda uyarı sayfası gösterilir, engelli bağlantı açılmaz. Kayıtlarda adresin yalnızca maskeli hali tutulur. '
              'IMAP istemcilerinde bağlantı yeniden yazma kapalıdır (Faz 2).',
            ),
          ),
          FiltreCubugu(
            arama: AramaAlani(
              ipucu: 'Alan adı veya posta kutusu…',
              degisti: (v) {
                _q = v;
                _y.yenile();
              },
            ),
            filtreler: [
              FiltreDugmesi<String>(
                etiket: 'Sonuç',
                ikon: Icons.rule_rounded,
                secenekler: const [('', 'Tüm tıklamalar'), ('blocked', 'Engellendi'), ('suspicious', 'Şüpheli'), ('clean', 'Temiz')],
                secili: _karar,
                secildi: (v) {
                  setState(() => _karar = v);
                  _y.yenile();
                },
              ),
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
            ],
          ),
        ],
      ),
      sutunlar: [
        Sutun('Zaman', genislik: 130, hucre: (c, t) => SolukMetin(kisaZaman(t.zaman))),
        Sutun('Bağlantı', esnek: 4, hucre: (c, t) => IkiSatir(t.maskeliUrl, alt: t.nedenler.isEmpty ? null : t.nedenler.join(' · '), mono: true)),
        Sutun('Posta kutusu', esnek: 3, hucre: (c, t) => SolukMetin(t.adres)),
        if (orgGoster) Sutun('Müşteri', esnek: 2, hucre: (c, t) => SolukMetin(t.orgAdi ?? '—')),
        Sutun('Sonuç', genislik: 170, sagaYasla: true, hucre: (c, t) => tiklamaRozeti(t)),
      ],
      kart: (c, t) => VeriKarti(
        baslik: t.maskeliUrl,
        alt: t.nedenler.join(' · '),
        rozetler: [tiklamaRozeti(t)],
        alanlar: [('Zaman', kisaZaman(t.zaman)), ('Posta kutusu', t.adres), if (orgGoster) ('Müşteri', t.orgAdi ?? '—')],
      ),
    );
  }
}
