import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/sayfali.dart';
import '../veri/denetim.dart';
import '../veri/denetim_tablolari.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'ozet.dart' show tonRengi;

/// Denetim kayıtları (GET /audit-logs): sayfalı, aranabilir, okunur etiketlerle. Türkçe arama metni eylem
/// etiketleriyle de eşleşir (q_actions), web panelindeki gibi.
class DenetimKayitlariEkrani extends StatefulWidget {
  const DenetimKayitlariEkrani({super.key});
  @override
  State<DenetimKayitlariEkrani> createState() => _DenetimKayitlariEkraniState();
}

class _DenetimKayitlariEkraniState extends State<DenetimKayitlariEkrani> {
  String _q = '';
  String _grup = '';
  DenetimKaydi? _secili;

  late final _y = SayfaYukleyici<DenetimKaydi>((s, b) async {
    final eylemler = _q.isEmpty ? const <String>[] : eylemAra(_q);
    final grupEylemleri = _grup.isEmpty
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
          if (_q.isNotEmpty) 'q': _q,
          if (eylemler.isNotEmpty) 'q_actions': eylemler.join(','),
          if (grupEylemleri.isNotEmpty) 'action': grupEylemleri.join(','),
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

  void _ac(DenetimKaydi k) {
    if (bolunmus(context)) {
      setState(() => _secili = k);
    } else {
      sayfaAc(context, 'Kayıt ayrıntısı', DenetimDetay(k));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final gruplar = {for (final e in denetimEylemleri.values) e.$1};
    final liste = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Column(
            children: [
              AramaAlani(
                ipucu: 'İşlem veya kişi ara…',
                degisti: (v) {
                  _q = v;
                  _y.yenile();
                },
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (k, e) in [
                      ('', 'Tümü'),
                      for (final g in denetimGruplari.entries)
                        if (gruplar.contains(g.key)) (g.key, g.value),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(e),
                          selected: _grup == k,
                          showCheckmark: false,
                          onSelected: (_) {
                            setState(() => _grup = k);
                            _y.yenile();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SayfaliListe<DenetimKaydi>(
            yukleyici: _y,
            ayrac: false,
            bosMetin: 'Kayıt bulunamadı.',
            bosIkon: Icons.receipt_long_rounded,
            oge: (c, k) {
              final e = denetimEylemi(k.eylem);
              final hedef = denetimHedefi(k.hedefTuru, k.hedefId, k.orgAdi, k.ayrintilar);
              final ozet = denetimOzeti(k.ayrintilar);
              return ListeSatiri(
                secili: _secili?.id == k.id && bolunmus(c),
                onTap: () => _ac(k),
                sol: CircleAvatar(
                  radius: 18,
                  backgroundColor: (tonRengi(e.ton) ?? r.birincil).withValues(alpha: .12),
                  child: Icon(_grupIkonu(e.grup), size: 18, color: tonRengi(e.ton) ?? r.birincil),
                ),
                baslik: e.etiket,
                alt: [?hedef, if (ozet.isNotEmpty) ozet].join(' · '),
                alt2: [
                  k.aktor.isEmpty ? 'sistem' : k.aktor,
                  if (k.taklitci != null) '(${k.taklitci} adına)',
                  if (!Uyg.musteri && k.orgAdi != null) k.orgAdi!,
                ].join(' · '),
                sag: Tooltip(
                  message: tamZaman(k.zaman),
                  child: Text(goreliZaman(k.zaman), style: TextStyle(color: r.silik, fontSize: 11.5)),
                ),
              );
            },
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Denetim Kayıtları'),
        actions: [IconButton(tooltip: 'Yenile', onPressed: _y.yenile, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: AnaDetay(
        liste: liste,
        detay: _secili == null ? null : DenetimDetay(_secili!, key: ValueKey(_secili!.id)),
        bosMetin: 'Ayrıntı için bir kayıt seçin',
      ),
    );
  }
}

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
                style: gosterim(17, agirlik: FontWeight.w700, renk: tonRengi(e.ton)),
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
