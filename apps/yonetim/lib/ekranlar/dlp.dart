import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'bekletilenler.dart';
import 'tehdit_ortak.dart';

// Veri Sızıntısı Önleme (web: admin/dlp): platform geneli politikalar, olaylar ve onay bekleyen iletiler.
// Tüm uç noktalar yalnızca süper yönetici içindir (dlpSuper).

const dlpDedektorEtiketleri = <String, String>{
  'tckn': 'T.C. kimlik no',
  'card': 'Kart numarası',
  'iban': 'IBAN',
  'phone_tr': 'Cep telefonu (TR)',
  'email_list': 'E-posta listesi',
  'custom': 'Özel kural',
};

const dlpEylemEtiketleri = <String, String>{
  'log': 'Yalnızca kaydet',
  'warn': 'Göndereni uyar',
  'quarantine': 'Yönetici onayı',
  'block': 'Engelle',
};

const dlpSonucEtiketleri = <String, String>{
  'logged': 'Kaydedildi',
  'warned': 'Uyarıldı (gönderilmedi)',
  'confirmed': 'Uyarıya rağmen gönderildi',
  'blocked': 'Engellendi',
  'quarantined': 'Onay bekliyor',
  'approved': 'Onaylandı, gönderildi',
  'denied': 'Reddedildi',
};

String dlpDedektor(String k) => dlpDedektorEtiketleri[k] ?? k;
String dlpEylem(String k) => dlpEylemEtiketleri[k] ?? k;
String _yoksa(String s, String d) => s.isEmpty ? d : s;

Color dlpSonucRengi(String o) => switch (o) {
  'blocked' || 'denied' => Marka.gul,
  'quarantined' || 'warned' => Marka.kehribar,
  'approved' || 'confirmed' => Marka.zumrut,
  _ => Colors.blueGrey,
};

/// GET /dlp/policies → öğe.
class DlpPolitika {
  DlpPolitika(this.m);
  final Map<String, dynamic> m;
  factory DlpPolitika.coz(Map<String, dynamic> m) => DlpPolitika(m);
  String get id => metin(m['id']);
  String get ad => metin(m['name']);
  String get sablon => metin(m['template']);
  bool get etkin => mantik(m['enabled'], true);
  List<String> get dedektorler => metinler(m['detectors']);
  List<Map<String, dynamic>> get kurallar => haritalar(m['custom_rules']);
  int get listeEnAz => tamsayi(m['email_list_min'], 20);
  String get kapsam => metin(m['scope'], 'external');
  int get esik => tamsayi(m['threshold'], 1);
  String get eylem => metin(m['action'], 'log');
  List<String> get gonderenIstisna => metinler(m['except_senders']);
  List<String> get alanIstisna => metinler(m['except_domains']);
  DateTime? get guncelleme => tarihOku(m['updated_at']);
  String get dedektorMetni => [...dedektorler.map(dlpDedektor), ...kurallar.map((r) => metin(r['name']))].join(', ');
  String get kapsamMetni => kapsam == 'external' ? 'Yalnızca dış alıcılar' : 'İç ve dış alıcılar';
}

/// GET /dlp/incidents → öğe.
class DlpOlay {
  DlpOlay(this.m);
  final Map<String, dynamic> m;
  factory DlpOlay.coz(Map<String, dynamic> m) => DlpOlay(m);
  String get id => metin(m['id']);
  String get orgAdi => metin(m['organization_name']);
  String get gonderen => metin(m['sender']);
  String get konu => metin(m['subject_preview']);
  String get sonuc => metin(m['outcome']);
  String get kanal => metin(m['channel']);
  int get alici => tamsayi(m['recipients']);
  int get disAlici => tamsayi(m['external_recipients']);
  List<Map<String, dynamic>> get politikalar => haritalar(m['policies']);
  List<Map<String, dynamic>> get eslesmeler => haritalar(m['matches']);
  List<Map<String, dynamic>> get taranamayan => haritalar(m['unscanned']);
  DateTime? get zaman => tarihOku(m['created_at']);
  String? get karar => metinYa(m['decided_by']);
  String? get bekletme => metinYa(m['hold_status']);
  String get bulunan => eslesmeler.map((e) => '${metinYa(e['rule']) ?? dlpDedektor(metin(e['detector']))} ×${tamsayi(e['count'])}').join(', ');
}

/// Veri Sızıntısı Önleme ekranı (yalnızca süper yönetici).
class DlpEkrani extends StatefulWidget {
  const DlpEkrani({super.key});
  @override
  State<DlpEkrani> createState() => _DlpEkraniState();
}

class _DlpEkraniState extends State<DlpEkrani> {
  Map<String, dynamic>? _meta;
  int _nesil = 0;
  final _politikalarAnahtari = GlobalKey<_PolitikalarState>();

  @override
  void initState() {
    super.initState();
    if (Uyg.platformYoneticisi) _metaYukle();
  }

  Future<void> _metaYukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/dlp/meta'));
      if (mounted) setState(() => _meta = v);
    } catch (_) {}
  }

  void _kapsamGoster() {
    final m = _meta;
    if (m == null) return;
    ayrintiGoster(
      context,
      baslik: 'Tarama kapsamı ve sınırlar',
      icerik: [
        const Aciklama('Metin, HTML, konu ve txt/csv/html/eml ekleri taranır.'),
        for (final l in harita(m['limits']).values) Padding(padding: const EdgeInsets.only(top: 8), child: Aciklama(metin(l))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi) {
      return const Iskelet(baslik: 'Veri Sızıntısı (DLP)', govde: Kapali('Bu bölüm yalnızca platform yöneticisine açıktır.'));
    }
    return DefaultTabController(
      length: 3,
      child: Iskelet(
        baslik: 'Veri Sızıntısı Önleme (DLP)',
        alt: 'Platform geneli politikalar tüm müşterilerin giden iletilerine uygulanır',
        eylemler: [
          IconButton(tooltip: 'Tarama kapsamı ve sınırlar', onPressed: _meta == null ? null : _kapsamGoster, icon: const Icon(Icons.info_outline_rounded)),
        ],
        yenile: () {
          _metaYukle();
          setState(() => _nesil++);
        },
        birincil: _meta == null ? null : BirincilEylem(Icons.add_rounded, 'Yeni politika', () => _politikalarAnahtari.currentState?.duzenle()),
        sekmeler: const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [Tab(text: 'Politikalar'), Tab(text: 'Olaylar'), Tab(text: 'Onay bekleyenler')],
        ),
        govde: TabBarView(
          children: [
            _Politikalar(key: _politikalarAnahtari, meta: _meta, nesil: _nesil),
            _Olaylar(key: ValueKey('olay$_nesil')),
            BekletilenlerListesi(key: ValueKey('bek$_nesil'), kaynak: 'dlp'),
          ],
        ),
      ),
    );
  }
}

// ---- politikalar --------------------------------------------------------------------------------------------

class _Politikalar extends StatefulWidget {
  const _Politikalar({super.key, required this.meta, required this.nesil});
  final Map<String, dynamic>? meta;
  final int nesil;
  @override
  State<_Politikalar> createState() => _PolitikalarState();
}

class _PolitikalarState extends State<_Politikalar> {
  late final _y = SayfaYukleyici.yerel<DlpPolitika>(
    () async => haritalar(harita(await Uyg.api.get('/api/v1/dlp/policies'))['items']).map(DlpPolitika.coz).toList(),
    sayfaBoyu: 25,
  )..yenile();

  @override
  void didUpdateWidget(_Politikalar eski) {
    super.didUpdateWidget(eski);
    if (eski.nesil != widget.nesil) _y.yenile();
  }

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> duzenle({DlpPolitika? politika, String? sablon}) async {
    final meta = widget.meta;
    if (meta == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PolitikaDialog(meta: meta, politika: politika, sablon: sablon),
    );
    if (ok == true) _y.yenile();
  }

  Future<void> _sil(DlpPolitika p) async {
    final evet = await onayla(
      context,
      'Politika silinsin mi?',
      mesaj: '${p.ad} artık uygulanmaz. Geçmiş olaylar korunur. İşlem denetim kaydına yazılır.',
      evet: 'Sil',
      tehlikeli: true,
    );
    if (!evet) return;
    if (await islem(() => Uyg.api.delete('/api/v1/dlp/policies/${p.id}'), tamam: 'Politika silindi') != null) _y.degistir((x) => x.id == p.id, null);
  }

  void _ac(DlpPolitika p) => ayrintiGoster(
    context,
    baslik: p.ad,
    alt: 'Tüm müşteriler · güncellendi ${tamZaman(p.guncelleme)}',
    icerik: [
      EtiketDeger('Durum', p.etkin ? 'Etkin' : 'Kapalı'),
      EtiketDeger('Eylem', dlpEylem(p.eylem)),
      EtiketDeger('Kapsam', p.kapsamMetni),
      EtiketDeger('Eşik', '${p.esik} eşleşme'),
      EtiketDeger('Dedektörler', _yoksa(p.dedektorMetni, '—')),
      EtiketDeger('İstisnalar', _yoksa([...p.gonderenIstisna, ...p.alanIstisna].join(', '), '—')),
      const SizedBox(height: 12),
      Builder(
        builder: (c) => EylemSatiri(
          ikon: Icons.edit_outlined,
          baslik: 'Düzenle',
          ipucu: 'Dedektör, eylem, istisnalar',
          onTap: () {
            Navigator.pop(c);
            duzenle(politika: p);
          },
        ),
      ),
      const SizedBox(height: 8),
      Builder(
        builder: (c) => EylemSatiri(
          ikon: Icons.delete_outline_rounded,
          baslik: 'Sil',
          ipucu: 'Politika kaldırılır',
          tehlikeli: true,
          onTap: () {
            Navigator.pop(c);
            _sil(p);
          },
        ),
      ),
    ],
  );

  List<SatirEylemi> _eylemler(DlpPolitika p) => [
    SatirEylemi(Icons.edit_outlined, 'Düzenle', () => duzenle(politika: p)),
    SatirEylemi(Icons.delete_outline_rounded, 'Sil', () => _sil(p), tehlikeli: true),
  ];

  Widget _sablonlar(BuildContext context) {
    final r = context.r;
    final sablonlar = haritalar(widget.meta?['templates']);
    if (sablonlar.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        children: [
          for (final t in sablonlar)
            Container(
              width: 270,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(14), border: Border.all(color: r.kenar)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(metin(t['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Text(metin(t['description']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 12)),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => duzenle(sablon: metin(t['key'])),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Şablondan ekle'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _eylemRozeti(DlpPolitika p) => Rozet(dlpEylem(p.eylem), renk: p.eylem == 'block' ? Marka.gul : (p.eylem == 'log' ? Colors.blueGrey : Marka.kehribar));

  @override
  Widget build(BuildContext context) => VeriTablosu<DlpPolitika>(
    yukleyici: _y,
    bosMetin: 'Politika yok. Bir şablonla başlayın: KVKK (T.C. kimlik), PCI (kart) veya Finans (IBAN).',
    bosIkon: Icons.policy_outlined,
    onTap: _ac,
    eylemler: _eylemler,
    ust: _sablonlar(context),
    sutunlar: [
      Sutun('Politika', esnek: 3, hucre: (c, p) => IkiSatir(p.ad, alt: p.etkin ? null : 'kapalı')),
      Sutun('Dedektörler', esnek: 4, hucre: (c, p) => SolukMetin(p.dedektorMetni)),
      Sutun('Kapsam', esnek: 3, hucre: (c, p) => SolukMetin('${p.kapsam == 'external' ? 'Yalnızca dış alıcı' : 'İç ve dış'} · eşik ${p.esik}')),
      Sutun('Eylem', genislik: 160, hucre: (c, p) => Align(alignment: Alignment.centerLeft, child: _eylemRozeti(p))),
    ],
    kart: (c, p) => VeriKarti(
      baslik: p.ad,
      alt: p.dedektorMetni,
      onTap: () => _ac(p),
      eylemler: _eylemler(p),
      rozetler: [_eylemRozeti(p), if (!p.etkin) const Rozet('Kapalı', renk: Colors.blueGrey)],
      alanlar: [('Kapsam', p.kapsamMetni), ('Eşik', '${p.esik}')],
    ),
  );
}

List<String> _satirlar(String s) => s.split(RegExp(r'[\n,;]+')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

class _Kural {
  _Kural(String ad, this.tur, String desen) : ad = TextEditingController(text: ad), desen = TextEditingController(text: desen);
  final TextEditingController ad, desen;
  String tur;
}

class _PolitikaDialog extends StatefulWidget {
  const _PolitikaDialog({required this.meta, this.politika, this.sablon});
  final Map<String, dynamic> meta;
  final DlpPolitika? politika;
  final String? sablon;
  @override
  State<_PolitikaDialog> createState() => _PolitikaDialogState();
}

class _PolitikaDialogState extends State<_PolitikaDialog> {
  late final Map<String, dynamic>? _sablon = haritalar(widget.meta['templates']).where((t) => metin(t['key']) == widget.sablon).firstOrNull;
  late final DlpPolitika? _p = widget.politika;
  late final _ad = TextEditingController(text: _p?.ad ?? metin(_sablon?['name']));
  late bool _etkin = _p?.etkin ?? true;
  late final Set<String> _dedektorler = {...(_p?.dedektorler ?? metinler(_sablon?['detectors']))};
  late final List<_Kural> _kurallar = [
    for (final r in _p?.kurallar ?? const <Map<String, dynamic>>[]) _Kural(metin(r['name']), metin(r['kind'], 'keyword'), metin(r['pattern'])),
  ];
  late String _kapsam = _p?.kapsam ?? 'external';
  late final _esik = TextEditingController(text: '${_p?.esik ?? (tamsayi(_sablon?['threshold']) > 0 ? tamsayi(_sablon?['threshold']) : 1)}');
  late String _eylem = _p?.eylem ?? metin(_sablon?['action'], 'log');
  late final _listeEnAz = TextEditingController(text: '${_p?.listeEnAz ?? 20}');
  late final _gonderenler = TextEditingController(text: (_p?.gonderenIstisna ?? const []).join('\n'));
  late final _alanlar = TextEditingController(text: (_p?.alanIstisna ?? const []).join('\n'));
  String? _hata;
  bool _mesgul = false;

  @override
  void dispose() {
    for (final k in [_ad, _esik, _listeEnAz, _gonderenler, _alanlar]) {
      k.dispose();
    }
    for (final k in _kurallar) {
      k.ad.dispose();
      k.desen.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _hata = null;
      _mesgul = true;
    });
    final p = _p;
    final govde = {
      'name': _ad.text.trim(),
      'template': p?.sablon ?? widget.sablon ?? '',
      'enabled': _etkin,
      'detectors': _dedektorler.toList(),
      'custom_rules': [
        for (final k in _kurallar) {'name': k.ad.text.trim(), 'kind': k.tur, 'pattern': k.desen.text},
      ],
      'scope': _kapsam,
      'threshold': (int.tryParse(_esik.text.trim()) ?? 1).clamp(1, 1000000),
      'action': _eylem,
      'email_list_min': (int.tryParse(_listeEnAz.text.trim()) ?? 2).clamp(2, 1000000),
      'except_senders': _satirlar(_gonderenler.text),
      'except_domains': _satirlar(_alanlar.text),
    };
    try {
      if (p != null) {
        await Uyg.api.patch('/api/v1/dlp/policies/${p.id}', govde);
      } else {
        await Uyg.api.post('/api/v1/dlp/policies', govde);
      }
      bildir('Politika kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final dedektorler = haritalar(widget.meta['detectors']);
    final genis = MediaQuery.sizeOf(context).width >= 600;
    Widget ikili(Widget a, Widget b) => genis
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)])
        : Column(children: [a, const SizedBox(height: 12), b]);
    final sablon = _sablon;
    return AlertDialog(
      title: Text(_p != null ? 'Politikayı düzenle' : 'Yeni DLP politikası', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Aciklama(sablon != null ? metin(sablon['description']) : 'Dedektörleri, eşiği ve eylemi seçin.'),
              const SizedBox(height: 14),
              ikili(
                TextField(controller: _ad, decoration: const InputDecoration(labelText: 'Ad')),
                DropdownButtonFormField<String>(
                  initialValue: dlpEylemEtiketleri.containsKey(_eylem) ? _eylem : 'log',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Eylem'),
                  items: const [
                    DropdownMenuItem(value: 'log', child: Text('Yalnızca kaydet')),
                    DropdownMenuItem(value: 'warn', child: Text('Göndereni uyar (webmail onay ister)')),
                    DropdownMenuItem(value: 'quarantine', child: Text('Yönetici onayına al')),
                    DropdownMenuItem(value: 'block', child: Text('Engelle')),
                  ],
                  onChanged: (v) => setState(() => _eylem = v ?? _eylem),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Dedektörler', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final d in dedektorler)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _dedektorler.contains(metin(d['key'])),
                  onChanged: (v) => setState(() => v == true ? _dedektorler.add(metin(d['key'])) : _dedektorler.remove(metin(d['key']))),
                  title: Text(metin(d['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(metin(d['check']), style: TextStyle(color: r.silik, fontSize: 12)),
                ),
              if (_dedektorler.contains('email_list'))
                Padding(
                  padding: const EdgeInsets.only(left: 40, bottom: 8),
                  child: SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _listeEnAz,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Liste eşiği', suffixText: 'farklı adres'),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(child: Text('Özel kurallar', style: TextStyle(fontWeight: FontWeight.w700))),
                  OutlinedButton.icon(
                    onPressed: _kurallar.length >= 20 ? null : () => setState(() => _kurallar.add(_Kural('', 'keyword', ''))),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Kural'),
                  ),
                ],
              ),
              for (final (i, k) in _kurallar.indexed)
                Padding(
                  key: ObjectKey(k),
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(width: 170, child: TextField(controller: k.ad, decoration: const InputDecoration(labelText: 'Ad'))),
                      SizedBox(
                        width: 130,
                        child: DropdownButtonFormField<String>(
                          initialValue: k.tur == 'regex' ? 'regex' : 'keyword',
                          decoration: const InputDecoration(labelText: 'Tür'),
                          items: const [DropdownMenuItem(value: 'keyword', child: Text('Kelime')), DropdownMenuItem(value: 'regex', child: Text('Regex'))],
                          onChanged: (v) => setState(() => k.tur = v ?? k.tur),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: k.desen,
                          style: const TextStyle(fontFamily: 'monospace'),
                          decoration: InputDecoration(labelText: 'Desen', hintText: k.tur == 'regex' ? r'örn. SZL-\d{6}' : 'örn. gizli'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kuralı sil',
                        onPressed: () => setState(() {
                          final x = _kurallar.removeAt(i);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            x.ad.dispose();
                            x.desen.dispose();
                          });
                        }),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Text('Regex en fazla 256 karakter; çok karmaşık veya her şeyi eşleştiren desenler reddedilir.', style: TextStyle(color: r.silik, fontSize: 12)),
              const SizedBox(height: 16),
              ikili(
                DropdownButtonFormField<String>(
                  initialValue: _kapsam == 'all' ? 'all' : 'external',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kapsam'),
                  items: const [
                    DropdownMenuItem(value: 'external', child: Text('Yalnızca dış alıcılar')),
                    DropdownMenuItem(value: 'all', child: Text('İç ve dış alıcılar')),
                  ],
                  onChanged: (v) => setState(() => _kapsam = v ?? _kapsam),
                ),
                TextField(controller: _esik, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Eşik (eşleşme sayısı)')),
              ),
              const SizedBox(height: 12),
              ikili(
                TextField(
                  controller: _gonderenler,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Gönderen istisnaları',
                    hintText: 'muhasebe@firma.com\n@ik.firma.com',
                    helperText: 'Adres veya @alan (gönderen grubu)',
                  ),
                ),
                TextField(
                  controller: _alanlar,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'Alıcı alan adı istisnaları', hintText: 'bankamiz.com.tr'),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _etkin, onChanged: (v) => setState(() => _etkin = v), title: const Text('Etkin')),
              if (_hata != null) Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 12.5)),
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

// ---- olaylar ------------------------------------------------------------------------------------------------

class _Olaylar extends StatefulWidget {
  const _Olaylar({super.key});
  @override
  State<_Olaylar> createState() => _OlaylarState();
}

class _OlaylarState extends State<_Olaylar> {
  String _q = '', _sonuc = '';

  late final _y = SayfaYukleyici.yerel<DlpOlay>(
    () async => haritalar(
      harita(await Uyg.api.get('/api/v1/dlp/incidents', q: {if (_sonuc.isNotEmpty) 'outcome': _sonuc, if (_q.isNotEmpty) 'q': _q}))['items'],
    ).map(DlpOlay.coz).toList(),
    sayfaBoyu: 25,
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _ac(DlpOlay o) {
    final r = context.r;
    ayrintiGoster(
      context,
      baslik: o.gonderen,
      alt: '${o.orgAdi} · ${tamZaman(o.zaman)} · ${o.kanal}',
      icerik: [
        EtiketDeger('Sonuç', '${dlpSonucEtiketleri[o.sonuc] ?? o.sonuc}${o.karar != null ? ' (${o.karar})' : ''}'),
        EtiketDeger('Politika', _yoksa(o.politikalar.map((p) => '${metin(p['name'])} (${dlpEylem(metin(p['action']))})').join(', '), '—')),
        EtiketDeger('Alıcı', '${o.alici} (${o.disAlici} dış)'),
        EtiketDeger('Konu', _yoksa(o.konu, '(konu yok)')),
        const SizedBox(height: 8),
        for (final e in o.eslesmeler)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(8), border: Border.all(color: r.kenar)),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: metinYa(e['rule']) ?? dlpDedektor(metin(e['detector'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: ' · ${tamsayi(e['count'])} adet'),
                  if (metinler(e['samples']).isNotEmpty)
                    TextSpan(text: '  (${metinler(e['samples']).join(', ')})', style: const TextStyle(fontFamily: 'monospace')),
                ],
              ),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        if (o.taranamayan.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('Taranamayan bölümler', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          for (final u in o.taranamayan) Aciklama('${metin(u['name'])}: ${metin(u['reason'])}'),
        ],
        const SizedBox(height: 8),
        Text('Yalnızca maskelenmiş örnekler saklanır; tam değerler hiçbir yerde tutulmaz.', style: TextStyle(color: r.silik, fontSize: 12)),
        if (o.bekletme == 'held')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Bant('İleti "Onay bekleyenler" sekmesinde kararınızı bekliyor.', renk: Marka.kehribar),
          ),
      ],
    );
  }

  Widget _rozet(DlpOlay o) => Rozet(dlpSonucEtiketleri[o.sonuc] ?? o.sonuc, renk: dlpSonucRengi(o.sonuc));

  @override
  Widget build(BuildContext context) => VeriTablosu<DlpOlay>(
    yukleyici: _y,
    bosMetin: 'Olay yok. Politikalarla eşleşen giden ileti bulunmadı.',
    bosIkon: Icons.file_present_outlined,
    onTap: _ac,
    ust: FiltreCubugu(
      arama: AramaAlani(
        ipucu: 'Gönderen…',
        degisti: (v) {
          _q = v;
          _y.yenile();
        },
      ),
      filtreler: [
        FiltreDugmesi<String>(
          etiket: 'Sonuç',
          ikon: Icons.rule_rounded,
          secenekler: [('', 'Tüm sonuçlar'), for (final e in dlpSonucEtiketleri.entries) (e.key, e.value)],
          secili: _sonuc,
          secildi: (v) {
            setState(() => _sonuc = v);
            _y.yenile();
          },
        ),
      ],
    ),
    sutunlar: [
      Sutun('Gönderen', esnek: 4, hucre: (c, o) => IkiSatir(o.gonderen, alt: _yoksa(o.konu, '(konu yok)'))),
      Sutun('Bulunan', esnek: 3, hucre: (c, o) => SolukMetin(o.bulunan)),
      Sutun('Müşteri', esnek: 2, hucre: (c, o) => SolukMetin(o.orgAdi)),
      Sutun('Sonuç', genislik: 190, hucre: (c, o) => Align(alignment: Alignment.centerLeft, child: _rozet(o))),
      Sutun('Zaman', genislik: 110, hucre: (c, o) => SolukMetin(goreliZaman(o.zaman))),
    ],
    kart: (c, o) => VeriKarti(
      baslik: o.gonderen,
      alt: _yoksa(o.konu, '(konu yok)'),
      onTap: () => _ac(o),
      rozetler: [_rozet(o)],
      alanlar: [('Bulunan', o.bulunan), ('Müşteri', o.orgAdi), ('Zaman', goreliZaman(o.zaman))],
    ),
  );
}
