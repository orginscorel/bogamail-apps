import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'altyapi_ortak.dart';
import '../ortak/simgeler.dart';

/// IP Yönetimi (platform): IP envanteri (rol, kullanım, ısınma, PTR/HELO, itibar), IP ekleme / düzenleme / silme,
/// PTR ve kara liste denetimi, platform SPF kaydı. web: admin/(panel)/ips + platform-spf-card.
/// API: GET /ips/inventory, POST /ips, PATCH|DELETE /ips/{id}, PATCH /ips/{id}/assignment, POST /ips/{id}/check, GET /platform/spf.
class IpYonetimiEkrani extends StatefulWidget {
  const IpYonetimiEkrani({super.key});

  @override
  State<IpYonetimiEkrani> createState() => _IpYonetimiEkraniState();
}

const _rolEtiketleri = {'inbound': 'Gelen', 'outbound': 'Giden', 'both': 'Gelen + giden'};
const _kullanimEtiketleri = {'dedicated': 'Müşteriye özel', 'pool': 'Havuz', 'plan': 'Paket havuzu', 'shared': 'Paylaşımlı'};

/// /ips/inventory → items[] satırı.
class EnvanterIp {
  EnvanterIp(this.m);
  final Map<String, dynamic> m;

  String get id => metin(m['id']);
  String get adres => metin(m['address']);
  String get rol => metin(m['role'], 'both');
  String get havuz => metin(m['pool'], 'default');
  String? get orgId => metinYa(m['organization_id']);
  String? get orgAdi => metinYa(m['organization_name']);
  bool? get orgOzellik => m['organization_has_feature'] is bool ? m['organization_has_feature'] as bool : null;
  String? get paketId => metinYa(m['plan_id']);
  String? get paketAdi => metinYa(m['plan_name']);
  String get not => metin(m['note']);
  bool get etkin => mantik(m['enabled'], true);
  String get helo => metin(m['helo_name']);
  bool get isinma => mantik(m['warmup_enabled']);
  int get bugun => tamsayi(m['sent_today']);
  int get havuzMusteri => tamsayi(m['pool_customers']);
  int get teslim7 => tamsayi(m['delivered_7d']);
  int get kalici7 => tamsayi(m['hard_7d']);
  int get gecici7 => tamsayi(m['soft_7d']);
  String get kullanim => metin(m['usage'], 'shared');
  bool get sunucuda => mantik(m['present']);
  int get isinmaGunu => tamsayi(m['warmup_day']);
  int get isinmaSiniri => tamsayi(m['warmup_cap']);
  List<String> get ptr => metinler(m['ptr']);
  bool get fcrdns => mantik(m['fcrdns']);
  bool? get ptrHelo => m['ptr_matches_helo'] is bool ? m['ptr_matches_helo'] as bool : null;
  int get listede => tamsayi(m['listed']);
  DateTime? get denetim => tarihOku(m['checked_at']);
  int? get itibar => tamsayiYa(m['reputation_score']);

  String get kullanimMetni => switch (kullanim) {
    'dedicated' => '${_kullanimEtiketleri[kullanim]} · ${orgAdi ?? ''}',
    'plan' => '${_kullanimEtiketleri[kullanim]} · ${paketAdi ?? ''}',
    'pool' => '${_kullanimEtiketleri[kullanim]} · $havuz · $havuzMusteri müşteri',
    _ => _kullanimEtiketleri[kullanim] ?? kullanim,
  };

  String get isinmaMetni {
    if (!isinma) return 'Kapalı';
    if (isinmaSiniri == 0) return 'Tamamlandı · bugün $bugun';
    return '${isinmaGunu + 1}. gün · $bugun/$isinmaSiniri';
  }

  String get ptrMetni {
    if (denetim == null) return 'denetlenmedi';
    return [
      ptr.isEmpty ? 'PTR yok' : ptr.first,
      if (ptr.isNotEmpty) fcrdns ? 'FCrDNS ✓' : 'FCrDNS ✗',
      if (ptrHelo == false) 'HELO ≠ PTR',
      if (listede > 0) '$listede kara listede',
    ].join(' · ');
  }
}

Color _itibarRengi(int s) => s >= 80 ? Marka.zumrut : (s >= 60 ? Marka.kehribar : Marka.gul);

class _IpYonetimiEkraniState extends State<IpYonetimiEkrani> {
  List<String> _yerel = [];
  List<String> _havuzlar = [];
  List<int> _isinmaPlani = [];
  String _mx = '';
  final _spf = GlobalKey<TekYuklemeState<Map<String, dynamic>>>();

  late final _y = SayfaYukleyici.yerel<EnvanterIp>(() async {
    final v = harita(await Uyg.api.get('/api/v1/ips/inventory'));
    if (mounted) {
      setState(() {
        _yerel = metinler(v['local_addresses']);
        _havuzlar = metinler(v['pools']);
        _isinmaPlani = (v['warmup_schedule'] is List ? v['warmup_schedule'] as List : const []).map(tamsayi).toList();
        _mx = metin(v['mx_host']);
      });
    }
    return haritalar(v['items']).map(EnvanterIp.new).toList();
  }, sayfaBoyu: 25)..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  bool get _yonetir => Uyg.platformYoneticisi && Uyg.taklit == null;

  Future<void> _ekle() async {
    final adres = TextEditingController();
    final havuz = TextEditingController(text: 'default');
    String? hata;
    final eklendi = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) {
          Future<void> kaydet() async {
            if (adres.text.trim().isEmpty) return;
            try {
              await Uyg.api.post('/api/v1/ips', {'address': adres.text.trim(), 'pool': havuz.text.trim()});
              if (c.mounted) Navigator.pop(c, true);
            } catch (e) {
              yenile(() => hata = hataMetni(e));
            }
          }

          return AlertDialog(
            title: Text('IP ekle', style: gosterim(19, agirlik: FontWeight.w600)),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'IP\'yi önce sunucunun ağ arayüzüne tanımlayın ve PTR kaydını sağlayıcıda ayarlayın; ekledikten sonra "PTR ve kara liste denetimi" ile doğrulayın.',
                    style: TextStyle(color: c.r.soluk, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: adres,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(labelText: 'IP adresi', hintText: '203.0.113.10', errorText: hata),
                    onChanged: (_) => yenile(() {}),
                    onSubmitted: (_) => kaydet(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: havuz,
                    decoration: const InputDecoration(labelText: 'Havuz'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
              FilledButton(onPressed: adres.text.trim().isEmpty ? null : kaydet, child: const Text('IP ekle')),
            ],
          );
        },
      ),
    );
    adres.dispose();
    havuz.dispose();
    if (eklendi == true) {
      bildir('IP eklendi', tur: MesajTur.basari);
      await _y.yenile();
    }
  }

  Future<void> _yonet(EnvanterIp ip) async {
    if (!_yonetir) return;
    final sonuc = await showDialog<String>(
      context: context,
      builder: (_) => _IpYonetimi(ip: ip, havuzlar: _havuzlar),
    );
    if (sonuc == 'sil') {
      await _sil(ip);
    } else if (sonuc != null) {
      await _y.yenile();
    }
  }

  Future<void> _sil(EnvanterIp ip) async {
    if (!await onayla(
      context,
      'IP kaydı silinsin mi?',
      mesaj: '${ip.adres} kaydı ve atamaları silinecek. Sunucunun ağ yapılandırması değişmez.',
      evet: 'Sil',
      tehlikeli: true,
    )) {
      return;
    }
    if (await islem(() => Uyg.api.delete('/api/v1/ips/${ip.id}'), tamam: 'Silindi') != null) await _y.yenile();
  }

  Future<void> _denetle(EnvanterIp ip) async {
    if (await islem(() => Uyg.api.post('/api/v1/ips/${ip.id}/check'), tamam: 'Denetlendi') != null) await _y.yenile();
  }

  Future<void> _etkinlik(EnvanterIp ip) async {
    if (await islem(() => Uyg.api.patch('/api/v1/ips/${ip.id}', {'enabled': !ip.etkin}), tamam: ip.etkin ? 'Devre dışı bırakıldı' : 'Etkinleştirildi') !=
        null) {
      await _y.yenile();
    }
  }

  List<SatirEylemi> _eylemler(EnvanterIp ip) => !_yonetir
      ? const []
      : [
          SatirEylemi(Simgeler.tune, 'Yönet', () => _yonet(ip)),
          SatirEylemi(Simgeler.refresh, 'PTR ve kara liste denetimi', () => _denetle(ip)),
          SatirEylemi(Simgeler.powerSettingsNew, ip.etkin ? 'Devre dışı bırak' : 'Etkinleştir', () => _etkinlik(ip)),
          SatirEylemi(Simgeler.deleteOutline, 'IP kaydını sil', () => _sil(ip), tehlikeli: true),
        ];

  List<Widget> _rozetler(EnvanterIp ip) => [
    if (!ip.etkin) Rozet('Devre dışı', renk: context.r.soluk),
    ip.sunucuda ? const Rozet('sunucuda', renk: Marka.zumrut) : const Rozet('sunucuda yok', renk: Marka.kehribar),
  ];

  Widget _ptrHucre(BuildContext c, EnvanterIp ip) {
    if (ip.denetim == null) return const SolukMetin('denetlenmedi');
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (ip.ptr.isEmpty)
          const Rozet('PTR yok', renk: Marka.gul)
        else ...[
          Text(
            ip.ptr.first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.r.metin, fontSize: 12, fontFamily: 'monospace'),
          ),
          ip.fcrdns ? const Rozet('FCrDNS ✓', renk: Marka.zumrut) : const Rozet('FCrDNS ✗', renk: Marka.kehribar),
        ],
        if (ip.ptrHelo == false) const Rozet('HELO ≠ PTR', renk: Marka.kehribar),
        if (ip.listede > 0) Rozet('${ip.listede} kara listede', renk: Marka.gul),
      ],
    );
  }

  Widget _itibarHucre(BuildContext c, EnvanterIp ip) {
    final s = ip.itibar;
    if (s == null) return const SolukMetin('veri yok');
    return Tooltip(
      message: '7 gün: ${ip.teslim7} teslim, ${ip.kalici7} kalıcı, ${ip.gecici7} geçici',
      child: Text(
        '$s/100',
        style: TextStyle(color: _itibarRengi(s), fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _ust(BuildContext context) {
    final r = context.r;
    final yatay = context.genis ? 16.0 : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(yatay, 4, yatay, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Bant(
            'Sunucudaki genel IP adresleri: ${_yerel.isEmpty ? '—' : _yerel.join(', ')}. Sunucuda tanımlı olmayan bir IP\'ye atanmış müşteriler '
            'uyarıyla paylaşımlı havuzdan gönderir.',
            ikon: Simgeler.lan,
          ),
          if (_isinmaPlani.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Isınma planı (günlük alıcı sınırı): ${_isinmaPlani.take(8).join(' → ')} → … → ${_isinmaPlani.last}; sonra sınırsız. '
              'Sınır dolunca o müşterinin iletileri ertelenir (paylaşımlı IP\'ye kaydırılmaz).',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi) {
      return const Iskelet(baslik: 'IP Yönetimi', govde: Kapali('IP yönetimi yalnızca platform yöneticisine açıktır.'));
    }
    return DefaultTabController(
      length: 2,
      child: Iskelet(
        baslik: 'IP Yönetimi',
        alt: 'IP envanteri, ısınma, PTR / HELO ve platform SPF kaydı',
        yenile: () {
          _y.yenile();
          _spf.currentState?.yenile();
        },
        birincil: _yonetir ? BirincilEylem(Simgeler.add, 'IP ekle', _ekle) : null,
        sekmeler: const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'IP envanteri'),
            Tab(text: 'Platform SPF'),
          ],
        ),
        govde: TabBarView(
          children: [
            VeriTablosu<EnvanterIp>(
              yukleyici: _y,
              ust: _ust(context),
              bosMetin: 'IP yok. Sunucunun genel IP\'leri açılışta otomatik eklenir.',
              bosIkon: Simgeler.lan,
              tabloEnAz: 900,
              onTap: _yonetir ? _yonet : null,
              eylemler: _yonetir ? _eylemler : null,
              sutunlar: [
                Sutun(
                  'Adres',
                  esnek: 4,
                  hucre: (c, ip) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            ip.adres,
                            style: TextStyle(color: c.r.metin, fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 13),
                          ),
                          ..._rozetler(ip),
                        ],
                      ),
                      const SizedBox(height: 2),
                      SolukMetin(
                        '${_rolEtiketleri[ip.rol] ?? ip.rol} · HELO ${ip.helo.isNotEmpty ? ip.helo : tire(_mx)}${ip.not.isNotEmpty ? ' · ${ip.not}' : ''}',
                      ),
                    ],
                  ),
                ),
                Sutun(
                  'Kullanım',
                  esnek: 3,
                  hucre: (c, ip) => Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        ip.kullanimMetni,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.r.metin, fontSize: 13),
                      ),
                      if (ip.kullanim == 'dedicated' && ip.orgOzellik == false) const Rozet('paket özelliği yok', renk: Marka.gul),
                    ],
                  ),
                ),
                Sutun('Isınma', esnek: 2, hucre: (c, ip) => SolukMetin(ip.isinmaMetni)),
                Sutun('PTR / HELO', esnek: 3, hucre: _ptrHucre),
                Sutun('İtibar', esnek: 1, hucre: _itibarHucre),
              ],
              kart: (c, ip) => VeriKarti(
                baslik: ip.adres,
                alt: '${_rolEtiketleri[ip.rol] ?? ip.rol} · HELO ${ip.helo.isNotEmpty ? ip.helo : tire(_mx)}',
                rozetler: _rozetler(ip),
                onTap: _yonetir ? () => _yonet(ip) : null,
                eylemler: _eylemler(ip),
                alanlar: [
                  ('Kullanım', ip.kullanimMetni),
                  ('Isınma', ip.isinmaMetni),
                  ('PTR', ip.ptrMetni),
                  ('İtibar', ip.itibar == null ? 'veri yok' : '${ip.itibar}/100'),
                ],
              ),
            ),
            _SpfSekmesi(anahtar: _spf),
          ],
        ),
      ),
    );
  }
}

/// IP düzenleme (web: ManageIPDialog). Sonuç: 'kaydedildi' | 'sil' | null.
class _IpYonetimi extends StatefulWidget {
  const _IpYonetimi({required this.ip, required this.havuzlar});
  final EnvanterIp ip;
  final List<String> havuzlar;

  @override
  State<_IpYonetimi> createState() => _IpYonetimiState();
}

class _IpYonetimiState extends State<_IpYonetimi> {
  EnvanterIp get ip => widget.ip;
  late String _rol = ip.rol;
  late String _tur = ip.kullanim;
  late String? _orgId = ip.orgId;
  late String? _orgAdi = ip.orgAdi;
  late String? _paketId = ip.paketId;
  late final _havuz = TextEditingController(text: ip.havuz);
  late final _helo = TextEditingController(text: ip.helo);
  late bool _isinma = ip.isinma;
  List<(String, String)>? _paketler;
  bool _mesgul = false, _degisti = false;
  String? _hata, _alan;

  @override
  void initState() {
    super.initState();
    _paketleriYukle();
  }

  @override
  void dispose() {
    _havuz.dispose();
    _helo.dispose();
    super.dispose();
  }

  Future<void> _paketleriYukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/plans'));
      final l = [for (final p in haritalar(v['items'])) (metin(p['id']), metin(p['name']))];
      if (mounted) setState(() => _paketler = l);
    } catch (_) {
      if (mounted) setState(() => _paketler = []);
    }
  }

  bool get _gecerli => !(_tur == 'dedicated' && _orgId == null) && !(_tur == 'plan' && _paketId == null);

  Future<void> _kaydet({bool yeniden = false}) async {
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    try {
      if (_rol != ip.rol) await Uyg.api.patch('/api/v1/ips/${ip.id}', {'role': _rol});
      await Uyg.api.patch('/api/v1/ips/${ip.id}/assignment', {
        'helo_name': _helo.text.trim(),
        'warmup_enabled': _isinma,
        'warmup_restart': yeniden,
        'organization_id': _tur == 'dedicated' ? _orgId : '',
        'plan_id': _tur == 'plan' ? _paketId : '',
        'pool': _tur == 'pool' ? _havuz.text.trim().toLowerCase() : (_tur == 'shared' ? 'default' : ip.havuz),
      });
      bildir('IP güncellendi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, 'kaydedildi');
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _hata = e.mesaj;
          _alan = e.alan;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _denetle() async {
    if (await islem(() => Uyg.api.post('/api/v1/ips/${ip.id}/check'), tamam: 'Denetlendi') != null) _degisti = true;
  }

  Future<void> _etkinlik() async {
    final v = await islem(() => Uyg.api.patch('/api/v1/ips/${ip.id}', {'enabled': !ip.etkin}), tamam: ip.etkin ? 'Devre dışı bırakıldı' : 'Etkinleştirildi');
    if (v != null && mounted) Navigator.pop(context, 'kaydedildi');
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return AlertDialog(
      title: Text(
        ip.adres,
        style: gosterim(19, agirlik: FontWeight.w600).copyWith(fontFamily: 'monospace'),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${ip.sunucuda ? 'Bu sunucuda tanımlı.' : 'Bu sunucunun ağ arayüzünde tanımlı değil: atanan müşteriler paylaşımlı havuzdan gönderir.'}'
                '${ip.denetim != null ? ' Son denetim ${tamZaman(ip.denetim)}.' : ''}',
                style: TextStyle(color: r.soluk, fontSize: 13),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _rol,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Rol', errorText: _alan == 'role' ? _hata : null),
                items: [for (final e in _rolEtiketleri.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _rol = v ?? _rol),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _tur,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kullanım'),
                items: const [
                  DropdownMenuItem(
                    value: 'shared',
                    child: Text('Paylaşımlı (varsayılan havuz)', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'dedicated',
                    child: Text('Müşteriye özel (dedicated)', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'plan',
                    child: Text('Paket havuzu (paketin tüm müşterileri)', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'pool',
                    child: Text('Adlandırılmış havuz (müşteriler Kiracı İzolasyonu\'ndan atanır)', overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (v) => setState(() => _tur = v ?? _tur),
              ),
              if (_tur == 'dedicated') ...[
                const SizedBox(height: 8),
                SecimAlani(
                  etiket: 'Müşteri',
                  deger: _orgAdi,
                  hata: _alan == 'organization_id' ? _hata : null,
                  onTap: () async {
                    final o = await musteriSec(context);
                    if (o != null) {
                      setState(() {
                        _orgId = o.id;
                        _orgAdi = o.ad;
                      });
                    }
                  },
                ),
                const SizedBox(height: 4),
                Text('Müşterinin paketinde "Özel gönderim IP\'si" özelliği olmalıdır.', style: TextStyle(color: r.silik, fontSize: 12)),
              ],
              if (_tur == 'plan') ...[
                const SizedBox(height: 8),
                if (_paketler == null)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  DropdownButtonFormField<String>(
                    initialValue: _paketler!.any((p) => p.$1 == _paketId) ? _paketId : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Paket', hintText: 'Paket seçin', errorText: _alan == 'plan_id' ? _hata : null),
                    items: [for (final p in _paketler!) DropdownMenuItem(value: p.$1, child: Text(p.$2))],
                    onChanged: (v) => setState(() => _paketId = v),
                  ),
              ],
              if (_tur == 'pool') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _havuz,
                  decoration: InputDecoration(labelText: 'Havuz adı', hintText: 'bulk', errorText: _alan == 'pool' ? _hata : null),
                ),
                if (widget.havuzlar.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final h in widget.havuzlar)
                        ActionChip(label: Text(h), visualDensity: VisualDensity.compact, onPressed: () => setState(() => _havuz.text = h)),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _helo,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'HELO adı (PTR ile aynı olmalı)',
                  hintText: 'posta2.ornek.com',
                  errorText: _alan == 'helo_name' ? _hata : null,
                  helperText: ip.ptr.isEmpty ? null : 'PTR: ${ip.ptr.join(', ')}',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _isinma,
                onChanged: (v) => setState(() => _isinma = v),
                title: const Text('Isınma planı', style: TextStyle(fontSize: 14)),
                subtitle: const Text('Günlük alıcı sınırı kademeli artar', style: TextStyle(fontSize: 12)),
              ),
              if (_hata != null && !const {'role', 'organization_id', 'plan_id', 'pool', 'helo_name'}.contains(_alan))
                Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13)),
              const SizedBox(height: 8),
              Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
              const SizedBox(height: 8),
              EylemSatiri(ikon: Simgeler.refresh, baslik: 'PTR ve kara liste denetimi', ipucu: 'PTR/FCrDNS ve DNSBL\'leri şimdi sorgula', onTap: _denetle),
              if (_isinma && ip.isinma)
                EylemSatiri(
                  ikon: Simgeler.restartAlt,
                  baslik: 'Isınmayı baştan başlat',
                  ipucu: 'Günlük sınır 1. günden yeniden başlar',
                  onTap: _mesgul || !_gecerli ? null : () => _kaydet(yeniden: true),
                ),
              EylemSatiri(
                ikon: Simgeler.powerSettingsNew,
                baslik: ip.etkin ? 'Devre dışı bırak' : 'Etkinleştir',
                ipucu: ip.etkin ? 'Gönderimde kullanılmaz' : 'Gönderimde yeniden kullanılır',
                onTap: _etkinlik,
              ),
              EylemSatiri(
                ikon: Simgeler.deleteOutline,
                baslik: 'IP kaydını sil',
                ipucu: 'Envanterden kaldırır; sunucu ağ ayarı değişmez',
                tehlikeli: true,
                onTap: () => Navigator.pop(context, 'sil'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context, _degisti ? 'kaydedildi' : null), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul || !_gecerli ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}

/// Platform SPF kaydı (GET /platform/spf).
class _SpfSekmesi extends StatelessWidget {
  const _SpfSekmesi({required this.anahtar});
  final GlobalKey<TekYuklemeState<Map<String, dynamic>>> anahtar;

  @override
  Widget build(BuildContext context) => TekYukleme<Map<String, dynamic>>(
    key: anahtar,
    getir: () async => harita(await Uyg.api.get('/api/v1/platform/spf')),
    icerik: (c, d, yenile) => IcerikListesi(
      enFazla: 900,
      children: [PlatformSpfKarti(veri: d, yenile: yenile)],
    ),
  );
}

/// web: PlatformSPFCard.
class PlatformSpfKarti extends StatelessWidget {
  const PlatformSpfKarti({super.key, required this.veri, this.yenile});
  final Map<String, dynamic> veri;
  final Future<void> Function()? yenile;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = veri;
    final tanimli = mantik(d['configured']);
    final ok = mantik(d['ok']);
    final bulunan = metinler(d['found']);
    return BolumKarti(
      baslik: 'Platform SPF kaydı',
      ikon: Simgeler.verifiedUser,
      sag: tanimli ? (ok ? const Rozet('Tüm IP\'ler yetkili', renk: Marka.zumrut) : const Rozet('Güncelleme gerekli', renk: Marka.kehribar)) : null,
      child: !tanimli
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ortak SPF kaydı tanımlı değil (BOGAMAIL_SPF_INCLUDE). Müşterilere IP\'ler doğrudan önerilir:',
                  style: TextStyle(color: r.soluk, fontSize: 13),
                ),
                const SizedBox(height: 8),
                KopyaKutusu(metin(d['direct_value'])),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tüm gönderim IP\'leri tek bir kayıtta tutulur. Müşteriler bu kaydı SPF\'lerine dahil eder; yeni IP eklediğinizde yalnızca aşağıdaki '
                  'kaydı güncellemeniz yeterlidir, müşterilerin DNS\'ine dokunulmaz.',
                  style: TextStyle(color: r.soluk, fontSize: 13),
                ),
                const SizedBox(height: 8),
                KopyaKutusu(metin(d['expected']), etiket: '1) ${metin(d['include'])} için TXT kaydı (sizin DNS\'iniz)'),
                const SizedBox(height: 8),
                KopyaKutusu(metin(d['customer_value']), etiket: '2) Müşteri alan adlarının SPF kaydı (panel otomatik önerir)'),
                const SizedBox(height: 8),
                Text(
                  'Şu an DNS\'te',
                  style: TextStyle(color: r.soluk, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: r.kenar),
                  ),
                  child: SelectableText(
                    bulunan.isEmpty ? 'kayıt yok' : bulunan.join('  |  '),
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: r.metin),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final i in haritalar(d['ips']))
                      Tooltip(
                        message: 'SPF sonucu: ${metin(i['result'])}',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: r.kenar),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                mantik(i['ok']) ? Simgeler.checkCircle : Simgeler.cancel,
                                size: 14,
                                color: mantik(i['ok']) ? Marka.zumrut : Marka.gul,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                metin(i['ip']),
                                style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: r.metin),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (yenile != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(onPressed: yenile, icon: const Icon(Simgeler.refresh, size: 18), label: const Text('Yeniden kontrol et')),
                  ),
                ],
              ],
            ),
    );
  }
}
