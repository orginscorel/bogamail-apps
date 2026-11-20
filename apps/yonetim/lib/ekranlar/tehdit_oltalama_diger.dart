import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'tehdit_oltalama_model.dart';
import 'tehdit_ortak.dart';
import '../ortak/simgeler.dart';

// Oltalama simülasyonu: raporlar, şablonlar ve çalışanların bildirdiği iletiler sekmeleri.

// ---- raporlar -----------------------------------------------------------------------------------------------

/// Farkındalık raporları (GET /phishing/reports?org=).
class OltaRaporlari extends StatefulWidget {
  const OltaRaporlari({super.key, required this.orgId});
  final String orgId;
  @override
  State<OltaRaporlari> createState() => _OltaRaporlariState();
}

class _OltaRaporlariState extends State<OltaRaporlari> {
  bool _tekrarlayan = false;

  @override
  Widget build(BuildContext context) => TekYukleme<Map<String, dynamic>>(
    getir: () async => harita(await Uyg.api.get('/api/v1/phishing/reports', q: {'org': widget.orgId})),
    icerik: (c, v, yenile) {
      final r = c.r;
      final toplam = OltaHunisi.coz(harita(v['total']));
      if (toplam.hedef == 0) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 60),
            Kapali('Henüz tamamlanmış bir tatbikat yok. Raporlar ilk kampanyadan sonra oluşur.', ikon: Simgeler.phishing),
          ],
        );
      }
      final kisiler = haritalar(v['users']).where((u) => !_tekrarlayan || mantik(u['repeat_clicker'])).toList();
      final alanlar = haritalar(v['domains']);
      Widget sayilar(List<(String, int)> l) => Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [for (final (e, n) in l) Text('$e $n', style: TextStyle(color: r.soluk, fontSize: 12.5))],
      );
      return IcerikListesi(
        children: [
          const SizedBox(height: 12),
          Izgara(
            enAz: 420,
            bosluk: 16,
            children: [
              BolumKarti(
                baslik: 'Tüm kampanyalar',
                ikon: Simgeler.filterAlt,
                altBaslik: '${toplam.teslim} teslim edilen tatbikat iletisi',
                child: HuniCubuklari(toplam),
              ),
              BolumKarti(
                baslik: 'Kampanyalara göre eğilim',
                ikon: Simgeler.trendingUp,
                altBaslik: 'Tıklama · Form · Bildirim (teslim edilenlere oranla)',
                child: Column(
                  children: [
                    for (final t in haritalar(v['trend']))
                      Builder(
                        builder: (c) {
                          final f = OltaHunisi.coz(t);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(metin(t['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                                    Text('%${f.yuzde(f.tiklayan)} · %${f.yuzde(f.formGonderen)} · %${f.yuzde(f.bildiren)}', style: TextStyle(color: r.silik, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    for (final (n, renk) in [(f.tiklayan, Marka.kehribar), (f.formGonderen, Marka.gul), (f.bildiren, Marka.zumrut)])
                                      Flexible(
                                        flex: f.yuzde(n).clamp(1, 100),
                                        child: Container(
                                          height: 7,
                                          margin: const EdgeInsets.only(right: 2),
                                          decoration: BoxDecoration(color: f.yuzde(n) == 0 ? r.ic : renk, borderRadius: BorderRadius.circular(3)),
                                        ),
                                      ),
                                    Flexible(flex: (300 - f.yuzde(f.tiklayan) - f.yuzde(f.formGonderen) - f.yuzde(f.bildiren)).clamp(1, 300), child: const SizedBox()),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          BolumKarti(
            baslik: 'Kişi bazında',
            ikon: Simgeler.peopleOutline,
            altBaslik: 'Birden fazla tatbikatta tıklayanlar "tekrarlayan" olarak işaretlenir.',
            sag: FilterChip(
              label: const Text('Yalnızca tekrarlayanlar'),
              selected: _tekrarlayan,
              onSelected: (b) => setState(() => _tekrarlayan = b),
            ),
            child: kisiler.isEmpty
                ? Text('Kayıt yok', style: TextStyle(color: r.silik))
                : Column(
                    children: [
                      for (final u in kisiler.take(200))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  metinYa(u['display_name']) ?? metin(u['address']),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (mantik(u['repeat_clicker'])) ...[const SizedBox(width: 8), const Rozet('Tekrarlayan', renk: Marka.gul)],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (metinYa(u['display_name']) != null) Text(metin(u['address']), style: TextStyle(color: r.silik, fontSize: 12)),
                              sayilar([
                                ('Aldığı', tamsayi(u['received'])),
                                ('Tıkladı', tamsayi(u['clicked'])),
                                ('Form', tamsayi(u['submitted'])),
                                ('Bildirdi', tamsayi(u['reported'])),
                              ]),
                            ],
                          ),
                        ),
                      if (kisiler.length > 200) Text('İlk 200 kişi gösteriliyor.', style: TextStyle(color: r.silik, fontSize: 12)),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          BolumKarti(
            baslik: 'Alan adına göre',
            ikon: Simgeler.language,
            child: Column(
              children: [
                for (final d in alanlar)
                  Builder(
                    builder: (c) {
                      final f = OltaHunisi.coz(d);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(metin(d['domain']), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: sayilar([('Teslim', f.teslim), ('Tıklama', f.tiklayan), ('Form', f.formGonderen), ('Bildirim', f.bildiren)]),
                        trailing: Text('%${f.yuzde(f.tiklayan)} tıklama', style: TextStyle(color: f.yuzde(f.tiklayan) >= 30 ? Marka.gul : r.soluk, fontSize: 12.5)),
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Departman bilgisi tutulmadığı için gruplama alan adına göredir. Raporlarda yalnızca kutu adı ve görünen ad yer alır.',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
        ],
      );
    },
  );
}

// ---- şablonlar ----------------------------------------------------------------------------------------------

/// Şablonlar sekmesi (GET /phishing/templates?org= → {builtin, custom}).
class OltaSablonlari extends StatefulWidget {
  const OltaSablonlari({super.key, required this.orgId, required this.acik, required this.yerTutucular});
  final String orgId;
  final bool acik;
  final List<Map<String, dynamic>> yerTutucular;
  @override
  State<OltaSablonlari> createState() => OltaSablonlariState();
}

class OltaSablonlariState extends State<OltaSablonlari> {
  late final _y = SayfaYukleyici.yerel<OltaSablon>(() async {
    final v = harita(await Uyg.api.get('/api/v1/phishing/templates', q: {'org': widget.orgId}));
    return [...haritalar(v['builtin']), ...haritalar(v['custom'])].map(OltaSablon.coz).toList();
  }, sayfaBoyu: 25)..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> duzenle([OltaSablon? s]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _SablonDialog(orgId: widget.orgId, sablon: s, yerTutucular: widget.yerTutucular),
    );
    if (ok == true) _y.yenile();
  }

  Future<void> _sil(OltaSablon s) async {
    if (!await onayla(context, 'Şablon silinsin mi?', mesaj: '"${s.ad}" silinecek. Bu şablonla yapılmış kampanyaların sonuçları korunur.', evet: 'Sil', tehlikeli: true)) {
      return;
    }
    if (await islem(() => Uyg.api.delete('/api/v1/phishing/templates/${s.anahtar}'), tamam: 'Şablon silindi') != null) {
      _y.degistir((x) => x.anahtar == s.anahtar, null);
    }
  }

  void _onizle(OltaSablon s) => ayrintiGoster(
    context,
    baslik: s.ad,
    alt: '${s.gonderen} — ${s.konu}',
    icerik: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.r.ic, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.r.kenar)),
        child: SelectableText(s.govde.replaceFirst('{{link}}', '[${s.baglantiMetni}]'), style: const TextStyle(fontSize: 13.5, height: 1.4)),
      ),
      if (s.isaretler.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('Eğitim sayfasında anlatılan uyarı işaretleri', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        const SizedBox(height: 8),
        for (final i in s.isaretler) Padding(padding: const EdgeInsets.only(bottom: 4), child: Aciklama('•  $i')),
      ],
    ],
  );

  List<SatirEylemi> _eylemler(OltaSablon s) => [
    SatirEylemi(Simgeler.visibility, 'Önizle', () => _onizle(s)),
    if (!s.hazir && widget.acik) SatirEylemi(Simgeler.edit, 'Düzenle', () => duzenle(s)),
    if (!s.hazir) SatirEylemi(Simgeler.deleteOutline, 'Sil', () => _sil(s), tehlikeli: true),
  ];

  Widget _tur(OltaSablon s) => Rozet(s.hazir ? 'Hazır' : 'Özel', renk: s.hazir ? Colors.blueGrey : Marka.mor);

  @override
  Widget build(BuildContext context) => VeriTablosu<OltaSablon>(
    yukleyici: _y,
    bosMetin: 'Şablon yok.',
    bosIkon: Simgeler.description,
    onTap: _onizle,
    eylemler: _eylemler,
    ust: FiltreCubugu(
      arama: const Aciklama('Hazır senaryolar hiçbir gerçek marka veya kurum adı kullanmaz. Kendi şablonlarınız da genel kalmalıdır.'),
      sag: widget.acik
          ? Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FilledButton.tonalIcon(onPressed: duzenle, icon: const Icon(Simgeler.add, size: 18), label: const Text('Yeni şablon')),
            )
          : null,
    ),
    sutunlar: [
      Sutun('Şablon', esnek: 4, hucre: (c, s) => IkiSatir(s.ad, alt: s.konu)),
      Sutun('Tür', genislik: 90, hucre: (c, s) => Align(alignment: Alignment.centerLeft, child: _tur(s))),
      Sutun('Gönderen', esnek: 4, hucre: (c, s) => SolukMetin(s.gonderen)),
    ],
    kart: (c, s) => VeriKarti(
      baslik: s.ad,
      alt: s.konu,
      onTap: () => _onizle(s),
      rozetler: [_tur(s)],
      eylemler: _eylemler(s),
      alanlar: [('Gönderen', s.gonderen)],
    ),
  );
}

class _SablonDialog extends StatefulWidget {
  const _SablonDialog({required this.orgId, required this.sablon, required this.yerTutucular});
  final String orgId;
  final OltaSablon? sablon;
  final List<Map<String, dynamic>> yerTutucular;
  @override
  State<_SablonDialog> createState() => _SablonDialogState();
}

class _SablonDialogState extends State<_SablonDialog> {
  late final OltaSablon? _s = widget.sablon;
  late final _k = {
    'name': TextEditingController(text: _s?.ad ?? ''),
    'from_name': TextEditingController(text: _s?.gonderenAdi ?? ''),
    'from_local': TextEditingController(text: _s?.gonderenYerel ?? ''),
    'from_domain': TextEditingController(text: _s?.gonderenAlan ?? ''),
    'subject': TextEditingController(text: _s?.konu ?? ''),
    'body': TextEditingController(text: _s?.govde ?? 'Merhaba {{ad}},\n\n\n\n{{link}}\n\n'),
    'link_text': TextEditingController(text: _s?.baglantiMetni ?? ''),
    'signs': TextEditingController(text: (_s?.isaretler ?? const []).join('\n')),
  };
  String? _hataAlan, _hata;
  bool _mesgul = false;

  @override
  void dispose() {
    for (final k in _k.values) {
      k.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = _hataAlan = null;
    });
    final govde = <String, dynamic>{
      for (final e in _k.entries)
        if (e.key != 'signs') e.key: e.value.text,
      'organization_id': widget.orgId,
      'signs': _k['signs']!.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    };
    try {
      final s = _s;
      if (s != null) {
        await Uyg.api.put('/api/v1/phishing/templates/${s.anahtar}', govde);
      } else {
        await Uyg.api.post('/api/v1/phishing/templates', govde);
      }
      bildir('Şablon kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      setState(() {
        _hata = e.mesaj;
        _hataAlan = e.alan;
      });
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  String? _alanHatasi(String k) => _hataAlan == k ? _hata : null;

  Widget _alan(String k, String etiket, {String? ipucu, String? yardim, int satir = 1, int? enFazla}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _k[k],
      minLines: satir,
      maxLines: satir == 1 ? 1 : satir + 6,
      maxLength: enFazla,
      decoration: InputDecoration(labelText: etiket, hintText: ipucu, helperText: yardim, helperMaxLines: 3, errorText: _alanHatasi(k), counterText: ''),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final yt = widget.yerTutucular.map((p) => metin(p['key'])).join('  ');
    final bilinen = {'name', 'from_name', 'from_local', 'from_domain', 'subject', 'body', 'link_text', 'signs'};
    return AlertDialog(
      title: Text(_s != null ? 'Şablonu düzenle' : 'Yeni şablon', style: gosterim(19, agirlik: FontWeight.w600)),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Bant(
                'Gerçek bir firma, banka, kargo şirketi, kamu kurumu veya yazılım markasının adını ya da logosunu kullanmayın. Senaryoyu genel tutun '
                '(ör. "kargo firması", "BT departmanı"). Bilinen marka adları reddedilir.',
                renk: Marka.kehribar,
                ikon: Simgeler.warningAmber,
              ),
              const SizedBox(height: 16),
              _alan('name', 'Şablon adı', enFazla: 120),
              _alan('from_name', 'Gönderen adı', ipucu: 'BT Destek', enFazla: 120),
              _alan('from_local', 'Gönderen kullanıcı', ipucu: 'it-destek', enFazla: 64),
              _alan('from_domain', 'Dış alan adı (isteğe bağlı)', ipucu: 'ornek-dis.example', yardim: 'Boş: alıcının alan adı. Doluysa .example / .invalid / .test ile bitmeli.'),
              _alan('subject', 'Konu', enFazla: 200),
              _alan('body', 'İleti metni', satir: 6, yardim: 'Yer tutucular: $yt — {{link}} tam bir kez geçmeli.'),
              _alan('link_text', 'Bağlantı düğmesi metni', ipucu: 'Belgeyi aç', enFazla: 120),
              _alan('signs', 'Uyarı işaretleri (her satıra bir tane)', satir: 3, yardim: 'Bağlantıya tıklayan çalışana eğitim sayfasında gösterilir.'),
              if (_hata != null && !bilinen.contains(_hataAlan)) Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 12.5)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}

// ---- bildirilen iletiler ------------------------------------------------------------------------------------

/// Çalışanların "Oltalama olarak bildir" ile işaretlediği iletiler (GET /phishing/user-reports?org=).
class OltaBildirimleri extends StatefulWidget {
  const OltaBildirimleri({super.key, required this.orgId, required this.degisti});
  final String orgId;
  final VoidCallback degisti;
  @override
  State<OltaBildirimleri> createState() => _OltaBildirimleriState();
}

class _OltaBildirimleriState extends State<OltaBildirimleri> {
  late final _y = SayfaYukleyici.yerel<OltaBildirim>(
    () async => haritalar(harita(await Uyg.api.get('/api/v1/phishing/user-reports', q: {'org': widget.orgId}))['items']).map(OltaBildirim.coz).toList(),
    sayfaBoyu: 25,
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _incele(OltaBildirim b) async {
    if (await islem(() => Uyg.api.post('/api/v1/phishing/user-reports/${b.id}/review'), tamam: 'İncelendi olarak işaretlendi') != null) {
      _y.yenile();
      widget.degisti();
    }
  }

  List<SatirEylemi> _eylemler(OltaBildirim b) => [
    if (b.durum == 'new') SatirEylemi(Simgeler.check, 'İncelendi', () => _incele(b)),
  ];

  String _alt(OltaBildirim b) => '${b.gonderen}${b.spam != null ? ' · spam puanı ${b.spam!.toStringAsFixed(1).replaceAll('.', ',')}' : ''}';

  Widget _durum(OltaBildirim b) => b.durum == 'new' ? const Rozet('Yeni', renk: Marka.kehribar) : const Rozet('İncelendi', renk: Marka.zumrut);

  @override
  Widget build(BuildContext context) => VeriTablosu<OltaBildirim>(
    yukleyici: _y,
    bosMetin: 'Henüz bildirilen şüpheli ileti yok.',
    bosIkon: Simgeler.inbox,
    eylemler: _eylemler,
    ust: const Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Aciklama(
        'Çalışanların webmail\'de "Oltalama olarak bildir" ile işaretlediği gerçek iletiler (tatbikat iletileri burada görünmez). '
        'Yalnızca gönderen ve konu saklanır; ileti kullanıcının kutusunda kalır.',
      ),
    ),
    sutunlar: [
      Sutun('İleti', esnek: 5, hucre: (c, b) => IkiSatir(b.konu.isEmpty ? '(konu yok)' : b.konu, alt: _alt(b))),
      Sutun('Bildiren', esnek: 3, hucre: (c, b) => SolukMetin(b.bildiren)),
      Sutun('Tarih', genislik: 130, hucre: (c, b) => SolukMetin(kisaZaman(b.zaman))),
      Sutun('Durum', genislik: 110, hucre: (c, b) => Align(alignment: Alignment.centerLeft, child: _durum(b))),
    ],
    kart: (c, b) => VeriKarti(
      baslik: b.konu.isEmpty ? '(konu yok)' : b.konu,
      alt: _alt(b),
      rozetler: [_durum(b)],
      eylemler: _eylemler(b),
      alanlar: [('Bildiren', b.bildiren), ('Tarih', kisaZaman(b.zaman))],
    ),
  );
}
