import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'musteri_detay.dart';
import 'musteri_form.dart';
import 'musteri_islemleri.dart';
import 'musteri_model.dart';
import '../ortak/simgeler.dart';

/// Müşteriler (GET /organizations?internal=0): sıralanabilir tablo (ad, oluşturulma, durum), arama, durum ve sektör
/// filtreleri, satır menüsü; telefonda kartlar. Ayrıntı panelinde müşterinin tüm yönetim işlemleri bulunur.
/// Bayiler ayrı bölümdedir.
class MusterilerEkrani extends StatefulWidget {
  const MusterilerEkrani({super.key});
  @override
  State<MusterilerEkrani> createState() => _MusterilerEkraniState();
}

class _MusterilerEkraniState extends State<MusterilerEkrani> {
  String _q = '', _durum = '', _sektor = '';
  String _siralama = 'created_at';
  bool _artan = false;

  late final _y = SayfaYukleyici<Musteri>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/organizations',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': _siralama,
          'order': _artan ? 'asc' : 'desc',
          'internal': '0',
          if (_q.isNotEmpty) 'q': _q,
          if (_durum.isNotEmpty) 'status': _durum,
          if (_sektor.isNotEmpty) 'sector': _sektor,
        },
      ),
      Musteri.coz,
    ),
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _degisti(String id, Musteri? y) {
    // Yönetici bölümüne taşınan müşteri bu listeden çıkar.
    _y.degistir((x) => x.id == id, y != null && y.dahili ? null : y);
  }

  void _ac(Musteri m) => musteriDetayAc(context, m, (y) => _degisti(m.id, y));

  Future<void> _yeni() async {
    final m = await musteriFormuAc(context);
    if (m == null || !mounted) return;
    await _y.yenile();
    if (mounted) _ac(m);
  }

  void _filtre(VoidCallback f) {
    setState(f);
    _y.yenile();
  }

  List<SatirEylemi> _eylemler(Musteri m) => [
    SatirEylemi(Simgeler.openInNew, 'Ayrıntılar', () => _ac(m)),
    if (MusteriYetki.yonetir)
      SatirEylemi(Simgeler.edit, 'Düzenle', () async {
        final y = await MusteriEylemleri.duzenle(context, m);
        if (y != null) _degisti(m.id, y);
      }),
    if (MusteriYetki.girer) SatirEylemi(Simgeler.login, 'Müşteri paneline gir', () => MusteriEylemleri.paneleGir(context, m)),
    SatirEylemi(Simgeler.language, 'Alan adları', () => MusteriEylemleri.alanAdlari(context, m)),
    SatirEylemi(Simgeler.inbox, 'Posta kutuları', () => MusteriEylemleri.postaKutulari(context, m)),
    if (Uyg.ortak) SatirEylemi(Simgeler.toggleOn, 'Özellikler', () => ozellikleriAc(context, m)),
    if (MusteriYetki.disaAktarir) SatirEylemi(Simgeler.inventory2, 'Tümünü dışa aktar', () => disaAktarmaAc(context, m)),
    if (MusteriYetki.yonetir)
      SatirEylemi(m.aktif ? Simgeler.pauseCircleOutline : Simgeler.playCircleOutline, m.aktif ? 'Askıya al' : 'Etkinleştir', () async {
        final y = await MusteriEylemleri.durumDegistir(context, m);
        if (y != null) _degisti(m.id, y);
      }, tehlikeli: m.aktif),
    if (MusteriYetki.yonetir && !m.dahili)
      SatirEylemi(Simgeler.deleteOutline, 'Sil', () async {
        if (await MusteriEylemleri.sil(context, m)) _degisti(m.id, null);
      }, tehlikeli: true),
  ];

  String _altSatir(Musteri m) => [
    m.p('contact_name'),
    m.p('contact_phone'),
    sektorler[m.p('sector')] ?? '',
    if (m.bayiAdi != null) 'Bayi: ${m.bayiAdi}',
  ].where((x) => x.isNotEmpty).join(' · ');

  String _kota(Musteri m) => '${boyutYaz(m.ayrilan)} / ${(m.toplamKota ?? 0) > 0 ? boyutYaz(m.toplamKota) : '∞'}';

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final aramaVar = _q.isNotEmpty || _durum.isNotEmpty || _sektor.isNotEmpty;
    final ust = FiltreCubugu(
      arama: AramaAlani(
        ipucu: 'Ad, unvan, yetkili, e-posta, telefon, vergi no…',
        ilk: _q,
        degisti: (v) {
          _q = v.trim();
          _y.yenile();
        },
      ),
      filtreler: [
        FiltreDugmesi<String>(
          etiket: 'Durum',
          ikon: Simgeler.toggleOn,
          secenekler: const [('', 'Tüm durumlar'), ('active', 'Aktif'), ('suspended', 'Askıda')],
          secili: _durum,
          secildi: (v) => _filtre(() => _durum = v),
        ),
        FiltreDugmesi<String>(
          etiket: 'Sektör',
          ikon: Simgeler.category,
          secenekler: [('', 'Tüm sektörler'), for (final e in sektorler.entries) (e.key, e.value)],
          secili: _sektor,
          secildi: (v) => _filtre(() => _sektor = v),
        ),
      ],
      etkinler: [
        if (_durum.isNotEmpty) EtkinFiltre('Durum: ${_durum == 'active' ? 'Aktif' : 'Askıda'}', () => _filtre(() => _durum = '')),
        if (_sektor.isNotEmpty) EtkinFiltre('Sektör: ${sektorler[_sektor] ?? _sektor}', () => _filtre(() => _sektor = '')),
      ],
    );
    return Iskelet(
      baslik: 'Müşteriler',
      alt: 'Organizasyonlar, paketleri ve kullanım durumları',
      yenile: _y.yenile,
      birincil: MusteriYetki.olusturur ? BirincilEylem(Simgeler.addBusiness, 'Yeni müşteri', _yeni) : null,
      govde: VeriTablosu<Musteri>(
        yukleyici: _y,
        ust: ust,
        siralama: _siralama,
        artan: _artan,
        siralamaDegisti: (alan, artan) => _filtre(() {
          _siralama = alan;
          _artan = artan;
        }),
        bosMetin: aramaVar
            ? 'Aramanızla eşleşen müşteri yok.'
            : 'Henüz müşteri yok. İlk müşterinizi ekleyin; ardından alan adı ve posta kutuları tanımlayabilirsiniz.',
        bosIkon: Simgeler.apartment,
        onTap: _ac,
        eylemler: _eylemler,
        tabloEnAz: 820,
        sutunlar: [
          Sutun(
            'Müşteri',
            esnek: 5,
            siralama: 'name',
            hucre: (c, m) {
              final alt = _altSatir(m);
              return IkiSatir(
                m.ad,
                alt: alt.isEmpty ? null : alt,
                sol: Avatar(m.ad, tohum: m.id, boyut: 32),
              );
            },
          ),
          Sutun(
            'Paket',
            esnek: 2,
            hucre: (c, m) => m.paketAdi == null ? const SolukMetin('Paketsiz') : Text(m.paketAdi!, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Sutun('Alan adı', esnek: 1, sagaYasla: true, hucre: (c, m) => _oran(c, m.alanSayisi, m.enFazlaAlan)),
          Sutun('Kutu', esnek: 1, sagaYasla: true, hucre: (c, m) => _oran(c, m.kutuSayisi, m.enFazlaKutu)),
          Sutun(
            'Kota',
            esnek: 2,
            hucre: (c, m) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _kota(m),
                  style: TextStyle(color: r.soluk, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                KullanimCubugu(kullanilan: m.ayrilan, toplam: m.toplamKota ?? 0, yazi: false, kalinlik: 5),
              ],
            ),
          ),
          Sutun(
            'Durum',
            esnek: 1,
            siralama: 'status',
            hucre: (c, m) => Align(alignment: Alignment.centerLeft, child: DurumRozeti(m.durum)),
          ),
          Sutun('Oluşturulma', esnek: 1, siralama: 'created_at', hucre: (c, m) => SolukMetin(kisaZaman(m.eklenme))),
        ],
        kart: (c, m) => VeriKarti(
          baslik: m.ad,
          alt: _altSatir(m).isEmpty ? null : _altSatir(m),
          sol: Avatar(m.ad, tohum: m.id, boyut: 36),
          rozetler: [DurumRozeti(m.durum)],
          alanlar: [
            ('Paket', m.paketAdi ?? 'Paketsiz'),
            ('Alan adı', '${m.alanSayisi} / ${sinirYaz(m.enFazlaAlan)}'),
            ('Posta kutusu', '${m.kutuSayisi} / ${sinirYaz(m.enFazlaKutu)}'),
            ('Kota', _kota(m)),
          ],
          eylemler: _eylemler(m),
          onTap: () => _ac(m),
        ),
      ),
    );
  }

  Widget _oran(BuildContext c, int n, int? enFazla) {
    final dolu = enFazla != null && enFazla > 0 && n >= enFazla;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$n',
            style: TextStyle(fontWeight: FontWeight.w600, color: dolu ? Marka.kehribar : null),
          ),
          TextSpan(
            text: ' / ${sinirYaz(enFazla)}',
            style: TextStyle(color: c.r.silik),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}
