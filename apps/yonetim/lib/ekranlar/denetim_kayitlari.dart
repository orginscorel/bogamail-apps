import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/denetim.dart';
import '../veri/denetim_tablolari.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'liste_ortak.dart';

/// Denetim kayıtları (GET /audit-logs): zamana göre sıralanabilir tablo (telefonda kartlar), işlem grubu / tek işlem
/// süzgeci ve aranabilir okunur etiketler. Türkçe arama metni eylem etiketleriyle de eşleşir (q_actions), web panelindeki gibi.
class DenetimKayitlariEkrani extends StatefulWidget {
  const DenetimKayitlariEkrani({super.key});
  @override
  State<DenetimKayitlariEkrani> createState() => _DenetimKayitlariEkraniState();
}

class _DenetimKayitlariEkraniState extends State<DenetimKayitlariEkrani> {
  String _q = '';
  String _grup = '';
  String _eylem = '';
  bool _artan = false;

  late final _y = SayfaYukleyici<DenetimKaydi>((s, b) async {
    final eylemler = _q.isEmpty ? const <String>[] : eylemAra(_q);
    final suzgec = _eylem.isNotEmpty
        ? [_eylem]
        : _grup.isEmpty
        ? const <String>[]
        : [
            for (final e in denetimEylemleri.entries)
              if (e.value.$1 == _grup) e.key,
          ];
    return Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/audit-logs',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': 'at',
          'order': _artan ? 'asc' : 'desc',
          if (_q.isNotEmpty) 'q': _q,
          if (eylemler.isNotEmpty) 'q_actions': eylemler.join(','),
          if (suzgec.isNotEmpty) 'action': suzgec.join(','),
        },
      ),
      DenetimKaydi.coz,
    );
  }, sayfaBoyu: 50)..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _filtre(void Function() f) {
    setState(f);
    _y.yenile();
  }

  void _ac(DenetimKaydi k) => ayrintiAc(context, 'Kayıt ayrıntısı', DenetimDetay(k), genislik: 560);

  Future<void> _eylemSec() async {
    final l = [
      for (final e in denetimEylemleri.entries)
        if (_grup.isEmpty || e.value.$1 == _grup) (e.key, e.value.$2, denetimGruplari[e.value.$1]),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final v = await secimYap<String>(context, baslik: 'İşlem türü', secenekler: [('', 'Tüm işlemler', null), ...l], secili: _eylem);
    if (v != null) _filtre(() => _eylem = v);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final gruplar = {for (final e in denetimEylemleri.values) e.$1};
    Widget simge(DenetimEylemi e) => CircleAvatar(
      radius: 16,
      backgroundColor: (_tonRengi(e.ton) ?? r.birincil).withValues(alpha: .12),
      child: Icon(_grupIkonu(e.grup), size: 16, color: _tonRengi(e.ton) ?? r.birincil),
    );
    String kisi(DenetimKaydi k) => k.aktor.isEmpty ? 'sistem' : k.aktor;
    String? taklit(DenetimKaydi k) => k.taklitci == null ? null : (k.taklitci == k.aktor ? 'müşteri görünümünde' : 'yönetici: ${k.taklitci}');
    return Iskelet(
      baslik: 'Denetim Kayıtları',
      alt: 'Kim, ne zaman, hangi işlemi yaptı · kayıtlar değiştirilemez',
      yenile: _y.yenile,
      govde: VeriTablosu<DenetimKaydi>(
        yukleyici: _y,
        onTap: _ac,
        siralama: 'at',
        artan: _artan,
        siralamaDegisti: (_, a) => _filtre(() => _artan = a),
        bosMetin: 'Kayıt bulunamadı.',
        bosIkon: Icons.receipt_long_rounded,
        vurgulu: (k) => denetimEylemi(k.eylem).ton == 'danger',
        ust: FiltreCubugu(
          arama: AramaAlani(ipucu: 'İşlem veya kullanıcı ara…', degisti: (v) => _filtre(() => _q = v)),
          filtreler: [
            FiltreDugmesi<String>(
              etiket: 'Grup',
              ikon: Icons.category_outlined,
              secenekler: [
                ('', 'Tüm gruplar'),
                for (final g in denetimGruplari.entries)
                  if (gruplar.contains(g.key)) (g.key, g.value),
              ],
              secili: _grup,
              secildi: (v) => _filtre(() {
                _grup = v;
                if (_eylem.isNotEmpty && v.isNotEmpty && denetimEylemleri[_eylem]?.$1 != v) _eylem = '';
              }),
            ),
            ActionChip(
              avatar: const Icon(Icons.manage_search_rounded, size: 16),
              label: Text(_eylem.isEmpty ? 'İşlem türü' : denetimEylemi(_eylem).etiket),
              onPressed: _eylemSec,
            ),
          ],
          etkinler: [
            if (_grup.isNotEmpty) EtkinFiltre('Grup: ${denetimGruplari[_grup] ?? _grup}', () => _filtre(() => _grup = '')),
            if (_eylem.isNotEmpty) EtkinFiltre('İşlem: ${denetimEylemi(_eylem).etiket}', () => _filtre(() => _eylem = '')),
          ],
        ),
        sutunlar: [
          Sutun('Zaman', genislik: 150, siralama: 'at', hucre: (c, k) => IkiSatir(tamZaman(k.zaman), alt: goreliZaman(k.zaman), kalin: false)),
          Sutun(
            'İşlem',
            esnek: 4,
            hucre: (c, k) {
              final e = denetimEylemi(k.eylem);
              final hedef = denetimHedefi(k.hedefTuru, k.hedefId, k.orgAdi, k.ayrintilar);
              final ozet = denetimOzeti(k.ayrintilar);
              return IkiSatir(e.etiket, alt: [?hedef, if (ozet.isNotEmpty) ozet].join(' · '), sol: simge(e));
            },
          ),
          Sutun('Kullanıcı', esnek: 3, hucre: (c, k) => IkiSatir(kisi(k), alt: taklit(k), kalin: false)),
          if (!Uyg.musteri) Sutun('Müşteri', esnek: 2, hucre: (c, k) => SolukMetin(k.orgAdi ?? '')),
          Sutun('IP', genislik: 130, hucre: (c, k) => SolukMetin(k.ip ?? '', mono: true)),
        ],
        kart: (c, k) {
          final e = denetimEylemi(k.eylem);
          final hedef = denetimHedefi(k.hedefTuru, k.hedefId, k.orgAdi, k.ayrintilar);
          final ozet = denetimOzeti(k.ayrintilar);
          return VeriKarti(
            baslik: e.etiket,
            alt: [?hedef, if (ozet.isNotEmpty) ozet].join(' · '),
            sol: simge(e),
            vurgulu: e.ton == 'danger',
            alanlar: [
              ('Zaman', tamZaman(k.zaman)),
              ('Kullanıcı', kisi(k)),
              if (taklit(k) != null) ('Görünüm', taklit(k)!),
              if (!Uyg.musteri && k.orgAdi != null) ('Müşteri', k.orgAdi!),
            ],
            onTap: () => _ac(k),
          );
        },
      ),
    );
  }
}

/// Denetim işleminin tonuna göre renk (ozet.dart'taki ile aynı kural; o dosya ayrı yönetildiği için yerel kopya).
Color? _tonRengi(String ton) => switch (ton) {
  'danger' => Marka.gul,
  'warning' => Marka.kehribar,
  _ => null,
};

IconData _grupIkonu(String g) => switch (g) {
  'auth' => Icons.login_rounded,
  'user' => Icons.person_rounded,
  'organization' => Icons.apartment_rounded,
  'mailbox' => Icons.inbox_rounded,
  'domain' => Icons.language_rounded,
  'plan' => Icons.inventory_2_rounded,
  'settings' => Icons.tune_rounded,
  'backup' => Icons.backup_rounded,
  'security' || 'abuse' => Icons.shield_rounded,
  'delivery' => Icons.send_rounded,
  'gateway' => Icons.alt_route_rounded,
  'dmarc' => Icons.verified_rounded,
  'phishing' => Icons.phishing_rounded,
  'migration' => Icons.move_down_rounded,
  'branding' => Icons.palette_rounded,
  _ => Icons.receipt_long_rounded,
};

class DenetimDetay extends StatelessWidget {
  const DenetimDetay(this.k, {super.key});
  final DenetimKaydi k;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final e = denetimEylemi(k.eylem);
    final ayrintilar = denetimAyrintilari(k.ayrintilar);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Kutu(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                e.etiket,
                style: gosterim(17, agirlik: FontWeight.w700, renk: _tonRengi(e.ton)),
              ),
              Text(denetimGruplari[e.grup] ?? e.grup, style: TextStyle(color: r.silik, fontSize: 12.5)),
              const SizedBox(height: 10),
              BilgiSatiri('Zaman', tamZaman(k.zaman)),
              BilgiSatiri('Kişi', k.aktor.isEmpty ? 'Sistem' : k.aktor),
              if (k.taklitci != null) BilgiSatiri('Asıl yönetici', '${k.taklitci} (müşteri görünümünde)'),
              if (k.orgAdi != null) BilgiSatiri('Müşteri', k.orgAdi!),
              if (denetimHedefi(k.hedefTuru, k.hedefId, k.orgAdi, k.ayrintilar) case final h?) BilgiSatiri('Hedef', h),
              if (k.ip != null) BilgiSatiri('IP adresi', k.ip!, mono: true, kopyalanabilir: true),
              BilgiSatiri('İşlem kodu', k.eylem, mono: true),
            ],
          ),
        ),
        if (ayrintilar.isNotEmpty) ...[
          const Baslik('Ayrıntılar'),
          Kutu(child: Column(children: [for (final (a, d) in ayrintilar) BilgiSatiri(a, d)])),
        ],
      ],
    );
  }
}
