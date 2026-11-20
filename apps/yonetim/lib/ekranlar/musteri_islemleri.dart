import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import 'kutu_formlari.dart';
import 'kutu_islemleri.dart' show dosyaIndir;
import 'musteri_model.dart';

// Müşteri ekranının ayrı pencereleri (web: org-features, size-limits, org-bulk-settings, org-outbound-ip,
// promote-reseller, customer-export, login-host).

Widget _yukleniyor(bool mesgul, String metin) =>
    mesgul ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(metin);

/// Ortak pencere kabuğu: başlık + alt başlık, kaydırılabilir içerik, eylemler.
class _Pencere extends StatelessWidget {
  const _Pencere({required this.baslik, this.alt, required this.icerik, required this.eylemler, this.genislik = 560});
  final String baslik;
  final String? alt;
  final Widget icerik;
  final List<Widget> eylemler;
  final double genislik;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          baslik,
          style: gosterim(19, agirlik: FontWeight.w700),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (alt != null) ...[
          const SizedBox(height: 4),
          Text(
            alt!,
            style: TextStyle(color: context.r.silik, fontSize: 12.5, fontWeight: FontWeight.w400),
          ),
        ],
      ],
    ),
    content: SizedBox(
      width: genislik,
      child: SingleChildScrollView(child: icerik),
    ),
    actions: eylemler,
  );
}

/// Yükleme / hata durumunu gösteren küçük gövde.
Widget _durumGovdesi(String? hata, VoidCallback tekrar) => hata != null
    ? Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Bant(hata, renk: Marka.gul, ikon: Icons.cloud_off_rounded),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: tekrar, icon: const Icon(Icons.refresh_rounded), label: const Text('Tekrar dene')),
        ],
      )
    : const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );

// ---------------------------------------------------------------------------------------------------------------
// Özellikler: GET/PATCH /organizations/{id}/entitlements (features_override; "inherit" geçersiz kılmayı kaldırır) + GET /catalog.

Future<void> ozellikleriAc(BuildContext context, Musteri m) => showDialog<void>(context: context, builder: (_) => _Ozellikler(m));

class _Ozellikler extends StatefulWidget {
  const _Ozellikler(this.m);
  final Musteri m;
  @override
  State<_Ozellikler> createState() => _OzelliklerState();
}

class _OzelliklerState extends State<_Ozellikler> {
  Map<String, dynamic>? _hak;
  List<Map<String, dynamic>>? _katalog;
  final _degisen = <String, String>{}; // anahtar → inherit | on | off
  String? _hata;
  bool _mesgul = false;
  final bool _duzenler = MusteriYetki.haklariDuzenler;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final r = await Future.wait([Uyg.api.get('/api/v1/organizations/${widget.m.id}/entitlements'), Uyg.api.get('/api/v1/catalog')]);
      if (!mounted) return;
      setState(() {
        _hak = harita(r[0]);
        _katalog = haritalar(harita(r[1])['features']);
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  String _mevcut(String k) {
    final o = harita(_hak?['features_override']);
    return o.containsKey(k) ? (mantik(o[k]) ? 'on' : 'off') : 'inherit';
  }

  Future<void> _kaydet() async {
    final govde = <String, dynamic>{
      for (final e in _degisen.entries)
        if (e.value != _mevcut(e.key)) e.key: e.value == 'inherit' ? 'inherit' : e.value == 'on',
    };
    if (govde.isEmpty) return Navigator.pop(context);
    setState(() => _mesgul = true);
    final v = await islem(
      () => Uyg.api.patch('/api/v1/organizations/${widget.m.id}/entitlements', {'features_override': govde}),
      tamam: 'Müşteri özellikleri güncellendi',
    );
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (v != null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final hak = _hak, kat = _katalog;
    final paket = harita(hak?['plan']);
    final paketOz = harita(paket['features']);
    final gruplar = <String, List<Map<String, dynamic>>>{};
    for (final f in kat ?? const <Map<String, dynamic>>[]) {
      gruplar.putIfAbsent(metin(f['group'], 'Diğer'), () => []).add(f);
    }
    return _Pencere(
      baslik: '${widget.m.ad}: özellikler',
      alt:
          'Paket: ${metin(paket['name'], 'Paketsiz')}. "Paketten" seçili özellik paketteki ayarı izler; "Açık" / "Kapalı" yalnızca bu müşteri için paketi geçersiz kılar.',
      genislik: 640,
      icerik: hak == null || kat == null
          ? _durumGovdesi(_hata, _yukle)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in gruplar.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      g.key,
                      style: TextStyle(color: r.soluk, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: r.kenar),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        for (final (i, f) in g.value.indexed) ...[if (i > 0) Divider(height: 1, color: r.kenar), _satir(context, f, paketOz)],
                      ],
                    ),
                  ),
                ],
              ],
            ),
      eylemler: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_duzenler ? 'Vazgeç' : 'Kapat')),
        if (_duzenler) FilledButton(onPressed: _mesgul || hak == null ? null : _kaydet, child: _yukleniyor(_mesgul, 'Kaydet')),
      ],
    );
  }

  Widget _satir(BuildContext context, Map<String, dynamic> f, Map<String, dynamic> paketOz) {
    final r = context.r;
    final k = metin(f['key']);
    final kip = _degisen[k] ?? _mevcut(k);
    final pakette = mantik(paketOz[k]);
    final sonuc = kip == 'inherit' ? pakette : kip == 'on';
    final secici = SegmentedButton<String>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
      segments: const [
        ButtonSegment(value: 'inherit', label: Text('Paketten')),
        ButtonSegment(value: 'on', label: Text('Açık')),
        ButtonSegment(value: 'off', label: Text('Kapalı')),
      ],
      selected: {kip},
      onSelectionChanged: _duzenler ? (s) => setState(() => _degisen[k] = s.first) : null,
    );
    final bilgi = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metin(f['name'], k), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Pakette: ${pakette ? 'var' : 'yok'}', style: TextStyle(color: r.silik, fontSize: 12)),
            Text(
              'Sonuç: ${sonuc ? 'açık' : 'kapalı'}',
              style: TextStyle(color: sonuc ? Marka.zumrut : r.silik, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (!mantik(f['available'], true)) Rozet(metin(f['phase'], 'yakında'), renk: Marka.kehribar),
          ],
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (c, k) => k.maxWidth >= 480
            ? Row(
                children: [
                  Expanded(child: bilgi),
                  const SizedBox(width: 8),
                  secici,
                ],
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [bilgi, const SizedBox(height: 6), secici]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Boyut limitleri: limits_override (max_message_bytes, max_attachment_bytes, max_signature_bytes) + GET /settings/limits.

const _boyutAnahtarlari = {
  'max_message_bytes': 'En büyük ileti',
  'max_attachment_bytes': 'Ek yükleme (toplam)',
  'max_signature_bytes': 'İmza (resimler dahil)',
};

Future<void> boyutLimitleriniAc(BuildContext context, Musteri m) => showDialog<void>(context: context, builder: (_) => _BoyutLimitleri(m));

class _BoyutLimitleri extends StatefulWidget {
  const _BoyutLimitleri(this.m);
  final Musteri m;
  @override
  State<_BoyutLimitleri> createState() => _BoyutLimitleriState();
}

class _BoyutLimitleriState extends State<_BoyutLimitleri> {
  Map<String, dynamic>? _hak, _platform;
  final _k = {for (final a in _boyutAnahtarlari.keys) a: TextEditingController()};
  final _birim = {for (final a in _boyutAnahtarlari.keys) a: a == 'max_signature_bytes' ? 'KB' : 'MB'};
  String? _hata, _alan;
  bool _mesgul = false;
  final bool _duzenler = MusteriYetki.haklariDuzenler;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    for (final c in _k.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final r = await Future.wait([Uyg.api.get('/api/v1/organizations/${widget.m.id}/entitlements'), Uyg.api.get('/api/v1/settings/limits')]);
      if (!mounted) return;
      final hak = harita(r[0]);
      final o = harita(hak['limits_override']);
      for (final a in _boyutAnahtarlari.keys) {
        final b = tamsayiYa(o[a]);
        if (b == null) continue;
        if (b >= mib && b % (mib ~/ 1024) == 0 && a != 'max_signature_bytes') {
          _birim[a] = 'MB';
          _k[a]!.text = _sayi(b / mib);
        } else {
          _birim[a] = 'KB';
          _k[a]!.text = _sayi(b / 1024);
        }
      }
      setState(() {
        _hak = hak;
        _platform = harita(r[1]);
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  static String _sayi(double d) => (d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2)).replaceAll('.', ',');

  Future<void> _kaydet() async {
    setState(() => _hata = _alan = null);
    final govde = <String, dynamic>{};
    final sinirlar = harita(_platform?['bounds']);
    for (final e in _boyutAnahtarlari.entries) {
      final t = _k[e.key]!.text.trim().replaceAll(',', '.');
      if (t.isEmpty) {
        govde[e.key] = 'inherit';
        continue;
      }
      final n = double.tryParse(t);
      if (n == null || n <= 0) {
        setState(() {
          _alan = e.key;
          _hata = '${e.value}: geçerli bir sayı girin';
        });
        return;
      }
      final b = (n * (_birim[e.key] == 'MB' ? mib : 1024)).round();
      final s = sinirlar[e.key];
      if (s is List && s.length == 2) {
        final a = tamsayi(s[0]), z = tamsayi(s[1]);
        if (b < a || b > z) {
          setState(() {
            _alan = e.key;
            _hata = '${e.value}: ${boyutYaz(a)} – ${boyutYaz(z)} arasında olmalı';
          });
          return;
        }
      }
      govde[e.key] = b;
    }
    setState(() => _mesgul = true);
    try {
      await Uyg.api.patch('/api/v1/organizations/${widget.m.id}/entitlements', {'limits_override': govde});
      bildir('Müşteri limitleri kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context);
    } on ApiHata catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final hak = _hak, plat = _platform;
    return _Pencere(
      baslik: 'Boyut limitleri',
      alt: '${widget.m.ad} · müşteriye özel değerler paketin değerlerini geçersiz kılar; posta kutusu düzeyinde ayrıca değiştirilebilir.',
      icerik: hak == null || plat == null
          ? _durumGovdesi(_hata, _yukle)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in _boyutAnahtarlari.entries) ...[
                  Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _k[e.key],
                          enabled: _duzenler,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(hintText: 'Boş = devral', errorText: _alan == e.key ? _hata : null, isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _birim[e.key],
                        items: const [
                          DropdownMenuItem(value: 'MB', child: Text('MB')),
                          DropdownMenuItem(value: 'KB', child: Text('KB')),
                        ],
                        onChanged: _duzenler ? (v) => setState(() => _birim[e.key] = v ?? 'MB') : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_devralinan(e.key, hak, plat), style: TextStyle(color: r.silik, fontSize: 12)),
                  const SizedBox(height: 14),
                ],
                Text(
                  'Öncelik: Kutu > Müşteri > Paket > Platform; en özel düzeyde tanımlı değer geçerlidir. İleti boyutu SMTP sunucusunun üst '
                  'sınırını (${boyutYaz(tamsayi(plat['smtp_hard_max_bytes']))}) aşamaz; ekler en fazla ileti boyutunun 3/4\'ü kadar olabilir.',
                  style: TextStyle(color: r.silik, fontSize: 12),
                ),
                if (_hata != null && _alan == null) ...[const SizedBox(height: 10), Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded)],
              ],
            ),
      eylemler: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_duzenler ? 'Vazgeç' : 'Kapat')),
        if (_duzenler) FilledButton(onPressed: _mesgul || hak == null ? null : _kaydet, child: _yukleniyor(_mesgul, 'Kaydet')),
      ],
    );
  }

  String _devralinan(String k, Map<String, dynamic> hak, Map<String, dynamic> plat) {
    final paket = hak['plan'];
    final pf = harita(paket);
    final pv = tamsayiYa(pf[k]);
    if (paket != null && pv != null) return 'Devralınan: Paket (${metin(pf['name'])}) ${boyutYaz(pv)}';
    final pl = tamsayi(harita(plat['limits'])[k]);
    return 'Devralınan: ${paket == null ? 'Paketsiz' : 'Paket tanımlamıyor'} → Platform ${boyutYaz(pl)}';
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Toplu gönderim: GET/PUT /admin/campaigns/orgs/{id}/settings (approval, max_rate_per_hour, note).

Future<void> topluGonderimAc(BuildContext context, Musteri m) => showDialog<void>(context: context, builder: (_) => _TopluGonderim(m));

class _TopluGonderim extends StatefulWidget {
  const _TopluGonderim(this.m);
  final Musteri m;
  @override
  State<_TopluGonderim> createState() => _TopluGonderimState();
}

class _TopluGonderimState extends State<_TopluGonderim> {
  Map<String, dynamic>? _v;
  String _onay = 'default';
  final _hiz = TextEditingController();
  final _not = TextEditingController();
  String? _hata, _alan;
  bool _mesgul = false;

  String get _yol => '/api/v1/admin/campaigns/orgs/${widget.m.id}/settings';

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _hiz.dispose();
    _not.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final v = harita(await Uyg.api.get(_yol));
      if (!mounted) return;
      final s = harita(v['settings']);
      setState(() {
        _v = v;
        _onay = metin(s['approval'], 'default');
        _hiz.text = s['max_rate_per_hour'] == null ? '' : '${tamsayi(s['max_rate_per_hour'])}';
        _not.text = metin(s['note']);
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _kaydet() async {
    final h = _hiz.text.trim();
    final n = h.isEmpty ? null : int.tryParse(h);
    if (h.isNotEmpty && (n == null || n < 1)) {
      setState(() {
        _alan = 'max_rate_per_hour';
        _hata = 'Geçerli bir sayı girin';
      });
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    try {
      await Uyg.api.put(_yol, {'approval': _onay, 'max_rate_per_hour': n, 'note': _not.text.trim()});
      bildir('Toplu gönderim ayarları kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context);
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _hata = e.mesaj;
          _alan = e.alan;
        });
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final l = harita(v?['limits']);
    final ilkN = tamsayi(harita(v?['policy'])['approval_first_n'], 1);
    String sinir(Object? x) => x == null ? 'sınırsız' : sayiYaz(tamsayi(x));
    return _Pencere(
      baslik: 'Toplu gönderim',
      alt: '${widget.m.ad} · kampanyalar için onay kuralı ve gönderim hızı sınırı',
      icerik: v == null && _alan == null
          ? _durumGovdesi(_hata, _yukle)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!mantik(harita(v?['organization'])['feature_enabled'], true))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Bant('Toplu gönderim bu müşterinin paketinde kapalı; ayarlar özellik açıldığında geçerli olur.', renk: Marka.kehribar),
                  ),
                BilgiSatiri('Kişiler', '${sayiYaz(tamsayi(l['contacts']))} / ${sinir(l['max_contacts'])}'),
                BilgiSatiri('Bu ay gönderilen', '${sayiYaz(tamsayi(l['sent_this_month']))} / ${sinir(l['max_campaign_sends_monthly'])}'),
                BilgiSatiri('Sonraki kampanya', mantik(v?['next_campaign_needs_approval']) ? 'Onaya düşecek' : 'Doğrudan gönderilir'),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _onay,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Onay kuralı', errorText: _alan == 'approval' ? _hata : null),
                  items: [
                    DropdownMenuItem(
                      value: 'default',
                      child: Text('Platform politikası (ilk $ilkN kampanya onaylı)', overflow: TextOverflow.ellipsis),
                    ),
                    const DropdownMenuItem(value: 'always', child: Text('Her kampanya onaya düşsün')),
                    const DropdownMenuItem(value: 'never', child: Text('Onay gerekmesin')),
                  ],
                  onChanged: (x) => setState(() => _onay = x ?? 'default'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hiz,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Saatlik gönderim üst sınırı',
                    hintText: 'Boş = posta kutusu sınırı',
                    errorText: _alan == 'max_rate_per_hour' ? _hata : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _not,
                  maxLines: 2,
                  maxLength: 1000,
                  decoration: InputDecoration(labelText: 'İç not', hintText: 'Müşteri görmez', errorText: _alan == 'note' ? _hata : null),
                ),
                if (_hata != null && _alan == null && v != null) Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
              ],
            ),
      eylemler: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul || v == null ? null : _kaydet, child: _yukleniyor(_mesgul, 'Kaydet')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Çıkış IP'si (yalnızca süper yönetici): GET /ips/inventory + GET /dedicated-ip/status?org=; PATCH /ips/{id}/assignment.
// Paket "dedicated_ip" içermiyorsa önce bu müşteri için açılır (PATCH entitlements), yoksa atama yok sayılır.

Future<void> cikisIpAc(BuildContext context, Musteri m) => showDialog<void>(context: context, builder: (_) => _CikisIp(m));

class _CikisIp extends StatefulWidget {
  const _CikisIp(this.m);
  final Musteri m;
  @override
  State<_CikisIp> createState() => _CikisIpState();
}

class _CikisIpState extends State<_CikisIp> {
  static const _ortak = 'shared';
  List<Map<String, dynamic>>? _ipler;
  String _mx = '';
  bool? _ozellik;
  String? _secili;
  final _helo = TextEditingController();
  bool? _isinma;
  bool _heloDegisti = false;
  String? _hata;
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _helo.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final r = await Future.wait([
        Uyg.api.get('/api/v1/ips/inventory'),
        Uyg.api.get('/api/v1/dedicated-ip/status', q: {'org': widget.m.id}),
      ]);
      if (!mounted) return;
      final inv = harita(r[0]);
      setState(() {
        _ipler = haritalar(inv['items']).where((i) => mantik(i['enabled']) && metin(i['role']) != 'inbound').toList();
        _mx = metin(inv['mx_host']);
        _ozellik = mantik(harita(r[1])['feature']);
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Map<String, dynamic>? get _mevcut => _ipler?.where((i) => metin(i['organization_id']) == widget.m.id).firstOrNull;
  String get _seciliId => _secili ?? (_mevcut == null ? _ortak : metin(_mevcut!['id']));
  Map<String, dynamic>? get _secilen => _ipler?.where((i) => metin(i['id']) == _seciliId).firstOrNull;

  void _sec(String id) => setState(() {
    _secili = id;
    _isinma = null;
    _heloDegisti = false;
    _helo.text = metin(_secilen?['helo_name']);
  });

  Future<void> _kaydet() async {
    final secilen = _secilen;
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      for (final ip in _ipler!.where((i) => metin(i['organization_id']) == widget.m.id && metin(i['id']) != _seciliId)) {
        await Uyg.api.patch('/api/v1/ips/${metin(ip['id'])}/assignment', {'organization_id': ''});
      }
      if (secilen != null) {
        if (_ozellik != true) {
          await Uyg.api.patch('/api/v1/organizations/${widget.m.id}/entitlements', {
            'features_override': {'dedicated_ip': true},
          });
        }
        await Uyg.api.patch('/api/v1/ips/${metin(secilen['id'])}/assignment', {
          'organization_id': widget.m.id,
          'helo_name': _helo.text.trim(),
          'warmup_enabled': _isinma ?? mantik(secilen['warmup_enabled'], true),
        });
      }
      bildir(secilen != null ? 'Çıkış IP\'si ${metin(secilen['address'])} olarak ayarlandı' : 'Müşteri paylaşımlı IP havuzuna alındı', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Widget _secenek(
    BuildContext context, {
    required String id,
    required Widget baslik,
    required String ipucu,
    List<Widget> rozetler = const [],
    bool kapali = false,
  }) {
    final r = context.r;
    final aktif = _seciliId == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: aktif ? r.vurguYumusak : r.kart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: aktif ? r.vurgu : r.kenar),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: kapali ? null : () => _sec(id),
          child: Opacity(
            opacity: kapali ? .55 : 1,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(aktif ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 20, color: aktif ? r.vurgu : r.silik),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [baslik, ...rozetler]),
                        const SizedBox(height: 2),
                        Text(ipucu, style: TextStyle(color: r.silik, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ipler = _ipler;
    final secilen = _secilen;
    final degismedi = _secili == null || (_seciliId == (_mevcut == null ? _ortak : metin(_mevcut!['id'])) && !_heloDegisti && _isinma == null);
    return _Pencere(
      baslik: 'Çıkış IP\'si',
      alt: '${widget.m.ad} · dışarıya giden postanın gönderileceği IP adresi',
      icerik: ipler == null || _ozellik == null
          ? _durumGovdesi(_hata, _yukle)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _secenek(
                  context,
                  id: _ortak,
                  baslik: const Text('Paylaşımlı havuz', style: TextStyle(fontWeight: FontWeight.w600)),
                  ipucu: 'Platformun varsayılan çıkış IP\'si (diğer müşterilerle ortak)',
                ),
                for (final ip in ipler)
                  () {
                    final sahip = metin(ip['organization_id']);
                    final baska = sahip.isNotEmpty && sahip != widget.m.id ? metin(ip['organization_name'], 'başka müşteri') : null;
                    final ptr = metinler(ip['ptr']);
                    return _secenek(
                      context,
                      id: metin(ip['id']),
                      kapali: baska != null,
                      baslik: Text(
                        metin(ip['address']),
                        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                      ),
                      ipucu: 'PTR ${ptr.isEmpty ? 'yok' : ptr.join(', ')}${metin(ip['helo_name']).isEmpty ? '' : ' · HELO ${metin(ip['helo_name'])}'}',
                      rozetler: [
                        if (baska != null) Rozet(baska, renk: Marka.mavi),
                        if (!mantik(ip['present'], true)) const Rozet('sunucuda yok', renk: Marka.kehribar),
                        if (tamsayi(ip['listed']) > 0) Rozet('${tamsayi(ip['listed'])} kara listede', renk: Marka.gul),
                        if (ptr.isNotEmpty && !mantik(ip['fcrdns'])) const Rozet('FCrDNS yok', renk: Marka.kehribar),
                      ],
                    );
                  }(),
                if (secilen != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _helo,
                            autocorrect: false,
                            style: const TextStyle(fontFamily: 'monospace'),
                            onChanged: (_) => setState(() => _heloDegisti = true),
                            decoration: InputDecoration(
                              labelText: 'Sunucu adı (HELO)',
                              hintText: metinler(secilen['ptr']).firstOrNull?.replaceAll(RegExp(r'\.$'), '') ?? _mx,
                              helperText: 'IP\'nin PTR kaydıyla aynı olmalı ve bu ad aynı IP\'ye çözülmeli.',
                              helperMaxLines: 2,
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _isinma ?? mantik(secilen['warmup_enabled'], true),
                            onChanged: (v) => setState(() => _isinma = v),
                            title: const Text('Isınma', style: TextStyle(fontSize: 14)),
                            subtitle: const Text('Yeni IP için günlük gönderim kademeli artar; sınır dolunca posta bekletilir.'),
                          ),
                          if (_ozellik != true)
                            Text('Müşterinin paketinde özel IP yok; kaydedince bu müşteri için açılır.', style: TextStyle(color: r.silik, fontSize: 12)),
                          if (!mantik(secilen['present'], true))
                            const Text(
                              'Bu IP sunucuda tanımlı değil; tanımlanana kadar posta paylaşımlı havuzdan gider.',
                              style: TextStyle(color: Marka.kehribar, fontSize: 12),
                            ),
                          Text(
                            'Müşterinin alan adlarının SPF kaydı bu IP\'yi içermeli (ip4:${metin(secilen['address'])}).',
                            style: TextStyle(color: r.silik, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_hata != null) ...[const SizedBox(height: 10), Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded)],
              ],
            ),
      eylemler: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul || degismedi || ipler == null ? null : _kaydet, child: _yukleniyor(_mesgul, 'Kaydet')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Bayi yap (yalnızca süper yönetici, doğrudan müşteri): POST /organizations/{id}/promote-reseller, ardından isteğe bağlı
// POST /users (role reseller_admin). Başarıda true döner.

Future<bool> bayiYapAc(BuildContext context, Musteri m) async => await showDialog<bool>(context: context, builder: (_) => _BayiYap(m)) ?? false;

class _BayiYap extends StatefulWidget {
  const _BayiYap(this.m);
  final Musteri m;
  @override
  State<_BayiYap> createState() => _BayiYapState();
}

class _BayiYapState extends State<_BayiYap> {
  late final _ad = TextEditingController(text: widget.m.p('legal_name').isNotEmpty ? widget.m.p('legal_name') : widget.m.ad);
  late bool _giris = Uyg.yetki('users.manage');
  late final _eposta = TextEditingController(text: widget.m.p('contact_email'));
  final _sifre = TextEditingController(text: sifreUret());
  String? _hata;
  bool _mesgul = false;

  @override
  void dispose() {
    _ad.dispose();
    _eposta.dispose();
    _sifre.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_giris && _eposta.text.trim().isEmpty) {
      setState(() => _hata = 'Bayi paneli için giriş e-postası girin');
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final b = harita(await Uyg.api.post('/api/v1/organizations/${widget.m.id}/promote-reseller', {'name': _ad.text.trim()}));
      bildir('"${metin(b['name'])}" artık bir bayi', mesaj: '${widget.m.ad} bu bayinin ilk müşterisi oldu.', tur: MesajTur.basari);
      if (_giris) {
        final m = widget.m;
        final eposta = _eposta.text.trim().toLowerCase();
        try {
          await Uyg.api.post('/api/v1/users', {
            'email': eposta,
            'display_name': m.p('contact_name'),
            'phone': m.p('contact_mobile').isNotEmpty ? m.p('contact_mobile') : m.p('contact_phone'),
            'title': m.p('contact_title'),
            'password': _sifre.text,
            'role': 'reseller_admin',
            'reseller_id': metin(b['id']),
          });
          if (mounted) {
            await sifreGoster(context, adres: eposta, sifre: _sifre.text, not: 'Bayi paneli girişi oluşturuldu. Şifreyi bayiye güvenli bir kanaldan iletin.');
          }
        } catch (e) {
          bildir('Bayi oluşturuldu ancak giriş hesabı açılamadı', mesaj: '${hataMetni(e)} · Kullanıcılar bölümünden ekleyebilirsiniz.', tur: MesajTur.hata);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Pencere(
    baslik: '${widget.m.ad}: bayi yap',
    alt:
        'Bu müşteri adına yeni bir bayi açılır ve müşteri o bayinin ilk müşterisi olur. Alan adları, posta kutuları ve paketi değişmez. '
        'Bayi kendi müşterilerini açıp yönetebilir. İşlem denetim kaydına yazılır.',
    icerik: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ad,
          maxLength: 200,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Bayi adı', counterText: ''),
        ),
        if (Uyg.yetki('users.manage'))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _giris,
            onChanged: (v) => setState(() => _giris = v ?? false),
            title: const Text('Bayi paneli girişi oluştur'),
          ),
        if (_giris) ...[
          TextField(
            controller: _eposta,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Giriş e-postası', helperText: 'Müşteri yöneticisinden farklı bir adres olmalı.'),
          ),
          const SizedBox(height: 12),
          SifreAlani(denetleyici: _sifre),
        ],
        if (_hata != null) ...[const SizedBox(height: 10), Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded)],
      ],
    ),
    eylemler: [
      TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context, false), child: const Text('Vazgeç')),
      FilledButton(onPressed: _mesgul || _ad.text.trim().isEmpty ? null : _kaydet, child: _yukleniyor(_mesgul, 'Bayi yap')),
    ],
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Tümünü dışa aktar: GET/POST /organizations/{id}/exports. İndirme (GET …/exports/{export}/download) oturum çerezi
// ister ve büyük bir .zip döndürür; uygulama oturum çereziyle indirir (mobilde paylaş, masaüstünde İndirilenler).

Future<void> disaAktarmaAc(BuildContext context, Musteri m) => showDialog<void>(context: context, builder: (_) => _DisaAktarma(m));

class _DisaAktarma extends StatefulWidget {
  const _DisaAktarma(this.m);
  final Musteri m;
  @override
  State<_DisaAktarma> createState() => _DisaAktarmaState();
}

class _DisaAktarmaState extends State<_DisaAktarma> {
  List<MusteriDisaAktarma>? _l;
  bool _kullanilabilir = true;
  String? _hata;
  bool _mesgul = false;
  Timer? _zamanlayici;

  String get _yol => '/api/v1/organizations/${widget.m.id}/exports';

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get(_yol));
      if (!mounted) return;
      setState(() {
        _l = haritalar(v['items']).map(MusteriDisaAktarma.coz).toList();
        _kullanilabilir = mantik(v['available'], true);
        _hata = null;
      });
      _zamanlayici?.cancel();
      if (_l!.any((x) => x.suruyor)) _zamanlayici = Timer(const Duration(seconds: 3), _yukle);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _baslat() async {
    setState(() => _mesgul = true);
    final v = await islem(() => Uyg.api.post(_yol), tamam: 'Dışa aktarma başlatıldı; hazır olunca indirme bağlantısı burada görünür.');
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (v != null) await _yukle();
  }

  String _ozet(MusteriDisaAktarma x) => switch (x.durum) {
    'ready' =>
      '${x.kutu} kutu · ${sayiYaz(x.ileti)} ileti · ${x.kisi} kişi · ${x.etkinlik} etkinlik · ${boyutYaz(x.boyut)}'
          '${x.silinme == null ? '' : ' · silinme ${goreliZaman(x.silinme)}'}',
    'failed' => x.hata.isEmpty ? 'Başarısız' : x.hata,
    'expired' => '${x.kutu} kutu · ${boyutYaz(x.boyut)} · dosya silindi',
    _ => '${x.isteyen} tarafından istendi',
  };

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = _l;
    final suruyor = l?.any((x) => x.suruyor) ?? false;
    return _Pencere(
      baslik: 'Tümünü dışa aktar',
      alt: widget.m.ad,
      icerik: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tüm posta kutuları tek .zip arşivinde: iletiler klasör yapısıyla .eml, kişiler .vcf, takvimler .ics. Arka planda hazırlanır; '
            'bağlantı 48 saat geçerlidir, sonra dosya silinir. Talep ve her indirme denetim kaydına yazılır.',
            style: TextStyle(color: r.soluk, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _mesgul || suruyor || !_kullanilabilir || l == null ? null : _baslat,
              icon: _mesgul || suruyor
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.inventory_2_outlined, size: 18),
              label: Text(suruyor ? 'Hazırlanıyor…' : 'Tümünü dışa aktar'),
            ),
          ),
          if (!_kullanilabilir) ...[
            const SizedBox(height: 6),
            Text('Dışa aktarma hizmeti bu sunucuda yapılandırılmamış.', style: TextStyle(color: r.silik, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          if (l == null)
            _durumGovdesi(_hata, _yukle)
          else if (l.isEmpty)
            Text('Henüz dışa aktarma yapılmadı.', style: TextStyle(color: r.silik, fontSize: 13))
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: r.kenar),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (final (i, x) in l.indexed) ...[
                    if (i > 0) Divider(height: 1, color: r.kenar),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    DurumRozeti(
                                      x.durum == 'ready' ? 'active' : (x.suruyor ? 'pending' : (x.durum == 'failed' ? 'failed' : 'disabled')),
                                      etiket: disaAktarmaDurumlari[x.durum] ?? x.durum,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        tamZaman(x.olusturma),
                                        style: TextStyle(color: r.silik, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(_ozet(x), style: TextStyle(color: r.soluk, fontSize: 12.5)),
                                if (x.durum == 'ready' && x.indirme > 0) Text('${x.indirme} kez indirildi', style: TextStyle(color: r.silik, fontSize: 12)),
                              ],
                            ),
                          ),
                          if (x.durum == 'ready')
                            IconButton(
                              tooltip: 'İndir',
                              icon: const Icon(Icons.download_rounded),
                              onPressed: () => dosyaIndir(
                                '/api/v1/organizations/${widget.m.id}/exports/${x.id}/download',
                                'musteri-${widget.m.id.substring(0, 8)}-${x.id.substring(0, 8)}.zip',
                                baslik: 'Dışa aktarma indiriliyor',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
      eylemler: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Giriş adresi (kendi alan adıyla giriş): GET/PUT /organizations/{id}/login-host, POST …/login-host/verify.

Future<void> girisAdresiAc(BuildContext context, Musteri m) => showDialog<void>(context: context, builder: (_) => _GirisAdresi(m));

class _GirisAdresi extends StatefulWidget {
  const _GirisAdresi(this.m);
  final Musteri m;
  @override
  State<_GirisAdresi> createState() => _GirisAdresiState();
}

class _GirisAdresiState extends State<_GirisAdresi> {
  Map<String, dynamic>? _v;
  final _ad = TextEditingController();
  String? _hata;
  bool _mesgul = false;
  final bool _duzenler = MusteriYetki.girisAdresiDuzenler;

  String get _yol => '/api/v1/organizations/${widget.m.id}/login-host';

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  void _al(dynamic v) {
    final m = harita(v);
    setState(() {
      _v = m;
      _ad.text = metin(harita(m['login_host'])['hostname']);
    });
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final v = await Uyg.api.get(_yol);
      if (mounted) _al(v);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _kaydet(String ad) async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final v = await Uyg.api.put(_yol, {'hostname': ad});
      if (!mounted) return;
      _al(v);
      bildir(ad.isEmpty ? 'Giriş adresi kaldırıldı' : 'Giriş adresi kaydedildi', tur: MesajTur.basari);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _denetle() async {
    setState(() => _mesgul = true);
    final v = await islem(() => Uyg.api.post('$_yol/verify'));
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (v != null) _al(v);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final v = _v;
    final h = harita(v?['login_host']);
    final kayitli = metin(h['hostname']);
    final ornek = kayitli.isEmpty ? 'posta.firmaniz.com' : kayitli;
    final durum = metin(h['status']);
    final cname = metin(h['expected_cname']);
    final ipler = metinler(h['expected_ips']);
    return _Pencere(
      baslik: 'Kendi alan adıyla giriş',
      alt:
          '${widget.m.ad} · kullanıcılar webmail ve panele müşterinin kendi adresinden (ör. posta.firmaniz.com) girer; giriş sayfası müşterinin markasıyla görünür. '
          'Adres, müşterinin etkin alan adlarından birinin altında olmalıdır.',
      icerik: v == null
          ? _durumGovdesi(_hata, _yukle)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _ad,
                  enabled: _duzenler && !_mesgul,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: 'Giriş adresi', hintText: 'posta.firmaniz.com', errorText: _hata),
                ),
                if (_duzenler) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _mesgul || _ad.text.trim().isEmpty || _ad.text.trim() == kayitli ? null : () => _kaydet(_ad.text.trim()),
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Kaydet ve denetle'),
                      ),
                      if (kayitli.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: _mesgul ? null : _denetle,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Yeniden denetle'),
                        ),
                      if (kayitli.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: _mesgul ? null : () => _kaydet(''),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Marka.gul),
                          label: const Text('Kaldır', style: TextStyle(color: Marka.gul)),
                        ),
                    ],
                  ),
                ],
                if (kayitli.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  BilgiSatiri(
                    'DNS durumu',
                    metin(h['detail'], '–'),
                    sag: DurumRozeti(
                      durum == 'verified' ? 'active' : (durum == 'failed' ? 'failed' : 'pending'),
                      etiket: durum == 'verified' ? 'Doğrulandı' : (durum == 'failed' ? 'Başarısız' : 'Bekliyor'),
                    ),
                  ),
                  BilgiSatiri(
                    'HTTPS sertifikası',
                    metin(h['tls_status']) == 'active'
                        ? 'Etkin'
                        : 'Onay bekliyor: platform otomatik sertifika (on-demand TLS) ayarını açtıktan sonra ilk ziyarette alınır.',
                  ),
                  if (tarihOku(h['checked_at']) != null) BilgiSatiri('Son denetim', tamZaman(tarihOku(h['checked_at']))),
                ],
                const SizedBox(height: 14),
                const Text('DNS kaydı', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 4),
                Text('Alan adının DNS yönetiminde aşağıdakilerden birini ekleyin:', style: TextStyle(color: r.soluk, fontSize: 12.5)),
                const SizedBox(height: 6),
                if (cname.isNotEmpty) KopyaKutusu(cname, etiket: 'CNAME  $ornek  (önerilen)'),
                if (ipler.isNotEmpty) KopyaKutusu(ipler.join(', '), etiket: 'A/AAAA  $ornek'),
                const SizedBox(height: 6),
                Text('DNS her 6 saatte bir yeniden denetlenir; kayıt kaldırılırsa adres devre dışı kalır.', style: TextStyle(color: r.silik, fontSize: 12)),
                if (!mantik(v['branding_enabled'], true)) ...[
                  const SizedBox(height: 10),
                  const Bant('Paket özel marka içermediği için giriş sayfası markalanmaz.', renk: Marka.kehribar),
                ],
              ],
            ),
      eylemler: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}
