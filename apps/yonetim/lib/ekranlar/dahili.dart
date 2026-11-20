import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'alan_adlari.dart';
import 'musteri_detay.dart' show musteriDetayKimlikle;
import 'paketim.dart';
import 'posta_kutulari.dart';
import 'taklit_islemleri.dart';

/// Yönetici Kurumları: platformun kendi kuruluşları (müşterilerden ayrı, silinemez) ve silinen posta arşivi.
/// Web: admin/internal (CustomersView internal + RetainedMessages).
/// Uç noktalar: GET /organizations?internal=1, POST /organizations/{id}/internal, GET /internal/retained,
/// POST /internal/retained/{id}/restore (yalnızca süper yönetici, görünüm dışında).
class DahiliKurumlarEkrani extends StatefulWidget {
  const DahiliKurumlarEkrani({super.key});
  @override
  State<DahiliKurumlarEkrani> createState() => _DahiliKurumlarEkraniState();
}

/// Silinen posta arşivindeki ileti (GET /internal/retained → items).
class SaklananIleti {
  const SaklananIleti({
    required this.id,
    required this.orgId,
    required this.orgAdi,
    required this.adres,
    required this.klasor,
    required this.konu,
    required this.kimden,
    required this.boyut,
    required this.tarih,
    required this.silinme,
  });
  final String id, orgId, orgAdi, adres, klasor, konu, kimden;
  final int boyut;
  final DateTime? tarih, silinme;

  factory SaklananIleti.coz(Map<String, dynamic> m) => SaklananIleti(
    id: metin(m['id']),
    orgId: metin(m['organization_id']),
    orgAdi: metin(m['organization_name']),
    adres: metin(m['address']),
    klasor: metin(m['folder_name']),
    konu: metin(m['subject']),
    kimden: metin(m['from']),
    boyut: tamsayi(m['size_bytes']),
    tarih: tarihOku(m['internal_date']),
    silinme: tarihOku(m['deleted_at']),
  );
}

class _DahiliKurumlarEkraniState extends State<DahiliKurumlarEkrani> with SingleTickerProviderStateMixin {
  late final _sekme = TabController(length: 2, vsync: this);
  String _q = '', _sira = 'name';
  bool _artan = true;
  String _aq = '', _asira = 'deleted_at';
  bool _aartan = false;
  (String, String)? _arsivOrg;

  late final _kurumlar = SayfaYukleyici<Organizasyon>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/organizations',
        q: {'page': '$s', 'page_size': '$b', 'internal': '1', 'sort': _sira, 'order': _artan ? 'asc' : 'desc', if (_q.isNotEmpty) 'q': _q},
      ),
      Organizasyon.coz,
    ),
  )..yenile();

  late final _arsiv = SayfaYukleyici<SaklananIleti>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/internal/retained',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': _asira,
          'order': _aartan ? 'asc' : 'desc',
          if (_aq.isNotEmpty) 'q': _aq,
          if (_arsivOrg != null) 'organization_id': _arsivOrg!.$1,
        },
      ),
      SaklananIleti.coz,
    ),
  )..yenile();

  @override
  void dispose() {
    _sekme.dispose();
    _kurumlar.dispose();
    _arsiv.dispose();
    super.dispose();
  }

  bool get _yonetir => Uyg.platformYoneticisi && Uyg.taklit == null;

  Future<void> _musterilereTasi(Organizasyon o) async {
    if (!await onayla(
      context,
      '"${o.ad}" müşterilere taşınsın mı?',
      mesaj:
          'Silme koruması kalkar: kuruluş, alan adları ve posta kutuları silinebilir hale gelir; bundan sonra silinen postalar arşivlenmez. '
          'Önceden arşivlenenler korunur.',
      evet: 'Taşı',
    )) {
      return;
    }
    final ok = await islem(() => Uyg.api.post('/api/v1/organizations/${o.id}/internal', {'internal': false}), tamam: 'Müşterilere taşındı');
    if (ok != null) _kurumlar.yenile();
  }

  Future<void> _geriYukle(SaklananIleti m) async {
    if (!await onayla(context, 'İleti geri yüklensin mi?', mesaj: '${m.adres} posta kutusunda "Geri Yüklenenler" klasörüne konur.', evet: 'Geri yükle')) {
      return;
    }
    final ok = await islem(() => Uyg.api.post('/api/v1/internal/retained/${m.id}/restore'), tamam: 'Geri yüklendi: ${m.adres} → "Geri Yüklenenler" klasörü');
    if (ok != null) _arsiv.yenile();
  }

  void _arsiveGit(Organizasyon o) {
    setState(() => _arsivOrg = (o.id, o.ad));
    _arsiv.yenile();
    _sekme.animateTo(1);
  }

  List<SatirEylemi> _kurumEylemleri(Organizasyon o) => [
    if (_yonetir)
      SatirEylemi(Icons.tune_rounded, 'Yönet (düzenle, limitler, özellikler, IP, dışa aktar)',
          () => musteriDetayKimlikle(context, o.id, degisti: (_) => _kurumlar.yenile())),
    SatirEylemi(Icons.verified_outlined, 'Paket ve kullanım', () => sayfaAc(context, o.ad, PaketimEkrani(orgId: o.id, orgAdi: o.ad))),
    SatirEylemi(Icons.language_rounded, 'Alan adları', () => sayfaAc(context, o.ad, AlanAdlariEkrani(orgId: o.id, orgAdi: o.ad))),
    SatirEylemi(Icons.inbox_outlined, 'Posta kutuları', () => sayfaAc(context, o.ad, PostaKutulariEkrani(orgId: o.id, orgAdi: o.ad))),
    SatirEylemi(Icons.restore_from_trash_outlined, 'Silinen postalar', () => _arsiveGit(o)),
    if (Uyg.girebilir) SatirEylemi(Icons.login_rounded, 'Müşteri paneline gir', () => musteriPanelineGir(context, id: o.id, ad: o.ad)),
    if (_yonetir) SatirEylemi(Icons.shield_outlined, 'Müşterilere taşı', () => _musterilereTasi(o), tehlikeli: true),
  ];

  Future<void> _kurumAc(Organizasyon o) async {
    final eylemler = _kurumEylemleri(o);
    await showDialog<void>(
      context: context,
      builder: (c) {
        final r = c.r;
        Widget sayi(String d, String e) => Expanded(
          child: Column(
            children: [
              Text(d, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(e, style: TextStyle(color: r.silik, fontSize: 12)),
            ],
          ),
        );
        String lim(int? n) => n == null ? '∞' : '$n';
        return AlertDialog(
          title: Text(o.ad, style: gosterim(19, agirlik: FontWeight.w700)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${o.paketAdi ?? 'Paketsiz'} · ${kisaZaman(o.eklenme)}', style: TextStyle(color: r.soluk, fontSize: 13)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        sayi('${o.alanSayisi} / ${lim(o.enFazlaAlan)}', 'Alan adı'),
                        sayi('${o.kutuSayisi} / ${lim(o.enFazlaKutu)}', 'Posta kutusu'),
                        sayi(boyutYaz(o.ayrilan), '/ ${o.toplamKota == null ? 'Sınırsız' : boyutYaz(o.toplamKota)}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      DurumRozeti(o.durum),
                      const Spacer(),
                      Icon(Icons.shield_rounded, size: 15, color: r.silik),
                      const SizedBox(width: 4),
                      Text('Korumalı: silinemez', style: TextStyle(color: r.silik, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final e in eylemler)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: EylemSatiri(
                        ikon: e.ikon,
                        baslik: e.etiket,
                        tehlikeli: e.tehlikeli,
                        onTap: () {
                          Navigator.pop(c);
                          e.calistir();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi || Uyg.taklit != null) {
      return const Iskelet(baslik: 'Yönetici Kurumları', govde: Kapali('Bu bölüm yalnızca platform yöneticilerine açıktır.'));
    }
    return Iskelet(
      baslik: 'Yönetici Kurumları',
      alt: 'Platformun kendi kuruluşları: silinemez, silinen postalar arşivde saklanır',
      yenile: () => _sekme.index == 0 ? _kurumlar.yenile() : _arsiv.yenile(),
      sekmeler: TabBar(
        controller: _sekme,
        tabs: const [
          Tab(text: 'Kuruluşlar'),
          Tab(text: 'Silinen posta arşivi'),
        ],
      ),
      govde: TabBarView(controller: _sekme, children: [_kurumListesi(), _arsivListesi()]),
    );
  }

  Widget _kurumListesi() => VeriTablosu<Organizasyon>(
    yukleyici: _kurumlar,
    bosMetin: _q.isEmpty ? 'Yönetici bölümünde kuruluş yok. Müşteriler bölümünde bir kuruluşu "Yönetici bölümüne taşı" ile ekleyin.' : 'Aramanızla eşleşen kuruluş yok.',
    bosIkon: Icons.admin_panel_settings_outlined,
    siralama: _sira,
    artan: _artan,
    siralamaDegisti: (a, b) {
      setState(() {
        _sira = a;
        _artan = b;
      });
      _kurumlar.yenile();
    },
    onTap: _kurumAc,
    eylemler: _kurumEylemleri,
    ust: FiltreCubugu(
      arama: AramaAlani(
        ipucu: 'Kuruluş ara…',
        degisti: (v) {
          _q = v;
          _kurumlar.yenile();
        },
      ),
    ),
    sutunlar: [
      Sutun('Kuruluş', esnek: 4, siralama: 'name', hucre: (c, o) => IkiSatir(o.ad, alt: o.profil['contact_name'] is String ? '${o.profil['contact_name']}' : null)),
      Sutun('Paket', esnek: 2, hucre: (c, o) => SolukMetin(o.paketAdi ?? 'Paketsiz')),
      Sutun('Alan adı', esnek: 1, sagaYasla: true, hucre: (c, o) => Text('${o.alanSayisi} / ${o.enFazlaAlan ?? '∞'}')),
      Sutun('Posta kutusu', esnek: 1, sagaYasla: true, hucre: (c, o) => Text('${o.kutuSayisi} / ${o.enFazlaKutu ?? '∞'}')),
      Sutun(
        'Kota',
        esnek: 2,
        hucre: (c, o) => KullanimCubugu(kullanilan: o.ayrilan, toplam: o.toplamKota ?? 0, kalinlik: 5),
      ),
      Sutun('Durum', esnek: 1, siralama: 'status', hucre: (c, o) => DurumRozeti(o.durum)),
      Sutun('Oluşturulma', esnek: 2, siralama: 'created_at', hucre: (c, o) => SolukMetin(kisaZaman(o.eklenme))),
    ],
    kart: (c, o) => VeriKarti(
      baslik: o.ad,
      alt: o.paketAdi ?? 'Paketsiz',
      sol: Avatar(o.ad, tohum: o.id),
      rozetler: [DurumRozeti(o.durum)],
      alanlar: [
        ('Alan adı', '${o.alanSayisi} / ${o.enFazlaAlan ?? '∞'}'),
        ('Posta kutusu', '${o.kutuSayisi} / ${o.enFazlaKutu ?? '∞'}'),
        ('Ayrılan', boyutYaz(o.ayrilan)),
      ],
      eylemler: _kurumEylemleri(o),
      onTap: () => _kurumAc(o),
    ),
  );

  Widget _arsivListesi() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Text(
          'Yönetici bölümündeki posta kutularından silinen her ileti (çöp kutusu boşaltma, kalıcı silme, IMAP/POP3/mobil silme ve otomatik temizlik dahil) '
          'burada süresiz saklanır. Geri yüklenen ileti, posta kutusunda "Geri Yüklenenler" klasörüne konur.',
          style: TextStyle(color: context.r.silik, fontSize: 12.5),
        ),
      ),
      Expanded(
        child: VeriTablosu<SaklananIleti>(
          yukleyici: _arsiv,
          bosMetin: _aq.isEmpty ? 'Arşivde silinmiş ileti yok.' : 'Aramanızla eşleşen ileti yok.',
          bosIkon: Icons.restore_from_trash_outlined,
          siralama: _asira,
          artan: _aartan,
          siralamaDegisti: (a, b) {
            setState(() {
              _asira = a;
              _aartan = b;
            });
            _arsiv.yenile();
          },
          eylemler: (m) => [SatirEylemi(Icons.unarchive_outlined, 'Geri yükle', () => _geriYukle(m))],
          ust: FiltreCubugu(
            arama: AramaAlani(
              ipucu: 'Konu, gönderen veya alıcı ara…',
              degisti: (v) {
                _aq = v;
                _arsiv.yenile();
              },
            ),
            etkinler: [
              if (_arsivOrg != null)
                EtkinFiltre('Kuruluş: ${_arsivOrg!.$2}', () {
                  setState(() => _arsivOrg = null);
                  _arsiv.yenile();
                }),
            ],
          ),
          sutunlar: [
            Sutun(
              'İleti',
              esnek: 5,
              hucre: (c, m) => IkiSatir(m.konu.isEmpty ? '(konu yok)' : m.konu, alt: '${m.kimden} · ${tamZaman(m.tarih)}'),
            ),
            Sutun('Posta kutusu', esnek: 3, hucre: (c, m) => IkiSatir(m.adres, alt: m.orgAdi, kalin: false)),
            Sutun('Klasör', esnek: 2, hucre: (c, m) => SolukMetin(m.klasor.isEmpty ? '—' : m.klasor)),
            Sutun('Boyut', esnek: 1, siralama: 'size', sagaYasla: true, hucre: (c, m) => SolukMetin(boyutYaz(m.boyut))),
            Sutun('Silinme', esnek: 2, siralama: 'deleted_at', hucre: (c, m) => SolukMetin(tamZaman(m.silinme))),
          ],
          kart: (c, m) => VeriKarti(
            baslik: m.konu.isEmpty ? '(konu yok)' : m.konu,
            alt: m.kimden,
            alanlar: [('Posta kutusu', m.adres), ('Klasör', m.klasor.isEmpty ? '—' : m.klasor), ('Boyut', boyutYaz(m.boyut)), ('Silinme', tamZaman(m.silinme))],
            eylemler: [SatirEylemi(Icons.unarchive_outlined, 'Geri yükle', () => _geriYukle(m))],
          ),
        ),
      ),
    ],
  );
}
