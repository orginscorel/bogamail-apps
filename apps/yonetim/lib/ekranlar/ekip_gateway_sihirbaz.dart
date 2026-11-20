import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/json.dart';
import 'bolumler.dart';
import 'ekip_gateway_ortak.dart';
import '../ortak/simgeler.dart';

/// Yeni gateway müşterisi sihirbazı: platform → alan adı → platform ayarları → DNS → bağlantı testi → tamam.
Future<void> gatewaySihirbaziAc(BuildContext context, List<GwAlan> alanlar, VoidCallback bitti) {
  final govde = GatewaySihirbazi(alanlar: alanlar, bitti: bitti);
  if (!context.genis) return sayfaAc(context, 'Yeni gateway müşterisi', govde);
  return showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 720,
        height: MediaQuery.sizeOf(c).height * .86,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Yeni gateway müşterisi'),
            actions: [IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(c), icon: const Icon(Simgeler.close))],
          ),
          body: govde,
        ),
      ),
    ),
  );
}

class _Platform {
  const _Platform(this.anahtar, this.ad, this.ipucu, this.hedef, this.tls);
  final String anahtar, ad, ipucu, hedef, tls;
}

const _platformlar = [
  _Platform('m365', 'Microsoft 365', 'Exchange Online', '<tenant>.mail.protection.outlook.com', 'required'),
  _Platform('google', 'Google Workspace', 'Gmail', 'aspmx.l.google.com', 'required'),
  _Platform('cpanel', 'cPanel', 'Exim tabanlı sunucu', 'sunucu.alanadi.com', 'opportunistic'),
  _Platform('plesk', 'Plesk', 'Postfix / Qmail tabanlı sunucu', 'sunucu.alanadi.com', 'opportunistic'),
  _Platform('smtp', 'Diğer SMTP', 'Exchange, Zimbra, Kerio…', 'mail.alanadi.com', 'opportunistic'),
];

List<String> _adimlar(String platform, String ipler, String mx) => switch (platform) {
  'm365' => [
    'Exchange yönetim merkezi → Posta akışı → Bağlayıcılar → yeni bağlayıcı: İş ortağı kuruluştan → Office 365.',
    'Bağlayıcıda kimlik doğrulama: gönderen IP adresi şu aralıkta olmalı: $ipler (yalnızca BogaMail\'den gelen posta kabul edilsin).',
    'Güvenlik → Bağlayıcılar için gelişmiş filtreleme (Enhanced Filtering): bu bağlayıcıyı seçin, BogaMail IP\'lerini atlanacak IP olarak ekleyin; böylece Microsoft gerçek gönderen IP\'sini görür (SPF/DMARC doğru çalışır).',
    'Teslim hedefi: <tenant>.mail.protection.outlook.com — Microsoft 365\'teki mevcut MX değeriniz (ör. firma-com.mail.protection.outlook.com).',
    'Son adımda MX kaydını $mx olarak değiştirin.',
  ],
  'google' => [
    'Google Yönetici Konsolu → Uygulamalar → Google Workspace → Gmail → Spam, kimlik avı ve kötü amaçlı yazılım → Gelen ağ geçidi (Inbound gateway).',
    'Ağ geçidi IP\'leri: $ipler. "Gelen ağ geçidi IP\'lerinden gelmeyen tüm postayı reddet" seçeneğini MX değişikliği yayıldıktan sonra açın.',
    '"Başlıktan önce gelen IP\'leri otomatik algıla" seçeneğini işaretleyin (SPF/DMARC için gerçek gönderen).',
    'Teslim hedefi: aspmx.l.google.com (yedek: alt1.aspmx.l.google.com).',
    'Son adımda MX kaydını $mx olarak değiştirin.',
  ],
  'cpanel' => [
    'Teslim hedefi: cPanel sunucusunun ana bilgisayar adı (ör. server1.hostingfirmasi.com).',
    'WHM → Exim Configuration Manager: BogaMail IP\'lerini ($ipler) güvenilir/relay izinli konaklara ekleyin; ayrıca bu IP\'ler için RBL ve greylisting kontrollerini kapatın.',
    'cPanel → E-posta Yönlendirme (Email Routing): alan adı "Yerel posta değiştiricisi" (Local Mail Exchanger) olarak kalmalı; aksi halde sunucu postayı geri MX\'e gönderir.',
    'Son adımda MX kaydını $mx olarak değiştirin.',
  ],
  'plesk' => [
    'Teslim hedefi: Plesk sunucusunun ana bilgisayar adı.',
    'Araçlar ve Ayarlar → Posta Sunucusu Ayarları: BogaMail IP\'lerini ($ipler) beyaz listeye ekleyin (relay/greylisting/RBL dışı).',
    'Alan adının posta hizmeti bu sunucuda açık kalmalı (yerel teslim).',
    'Son adımda MX kaydını $mx olarak değiştirin.',
  ],
  _ => [
    'Teslim hedefi: kendi posta sunucunuzun adı ve SMTP portu (genelde 25).',
    'Sunucunuzda BogaMail IP\'lerinden ($ipler) gelen postayı alan adınız için kabul edin; bu IP\'leri RBL/greylisting dışında tutun.',
    'Mümkünse sunucuya doğrudan erişimi yalnızca BogaMail IP\'leriyle sınırlayın (atlatma girişimlerine karşı).',
    'Son adımda MX kaydını $mx olarak değiştirin.',
  ],
};

class GatewaySihirbazi extends StatefulWidget {
  const GatewaySihirbazi({super.key, required this.alanlar, required this.bitti});
  final List<GwAlan> alanlar;
  final VoidCallback bitti;
  @override
  State<GatewaySihirbazi> createState() => _GatewaySihirbaziState();
}

class _GatewaySihirbaziState extends State<GatewaySihirbazi> {
  static const _basliklar = ['Platform', 'Alan adı', 'Platform ayarları', 'DNS değerleri', 'Bağlantı testi', 'Tamam'];
  int _adim = 1;
  _Platform? _platform;
  String? _alanId;
  final _sunucu = TextEditingController();
  final _port = TextEditingController(text: '25');
  String _tls = 'opportunistic';
  Map<String, dynamic>? _ob;
  String? _obHata;
  Map<String, dynamic>? _sonda;
  bool _mesgul = false;
  String? _hata;

  GwAlan? get _alan => widget.alanlar.where((d) => d.id == _alanId).firstOrNull;

  @override
  void dispose() {
    _sunucu.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _obYukle() async {
    setState(() {
      _ob = null;
      _obHata = null;
    });
    try {
      final v = harita(await Uyg.api.get('/api/v1/gateway/domains/$_alanId/onboarding'));
      if (mounted) setState(() => _ob = v);
    } catch (e) {
      if (mounted) setState(() => _obHata = hataMetni(e));
    }
  }

  int get _portNo => int.tryParse(_port.text.trim()) ?? 25;

  Future<void> _test() async {
    setState(() {
      _hata = null;
      _sonda = null;
      _mesgul = true;
    });
    try {
      final v = harita(await Uyg.api.post('/api/v1/gateway/probe', {'domain_id': _alanId, 'host': _sunucu.text.trim(), 'port': _portNo, 'tls_policy': _tls}));
      if (mounted) setState(() => _sonda = v);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _kaydet() async {
    final d = _alan;
    if (d == null) return;
    setState(() {
      _hata = null;
      _mesgul = true;
    });
    try {
      final h = _sunucu.text.trim().toLowerCase().replaceAll(RegExp(r'\.$'), '');
      final digerleri = d.hedefler.where((t) => !(t.sunucu == h && t.port == _portNo)).toList();
      await Uyg.api.put('/api/v1/gateway/domains/${d.id}/targets', {
        'targets': [
          {'host': h, 'port': _portNo, 'priority': 10, 'tls_policy': _tls, 'enabled': true},
          if (d.failover)
            for (var i = 0; i < digerleri.length; i++)
              {'host': digerleri[i].sunucu, 'port': digerleri[i].port, 'priority': 20 + i * 10, 'tls_policy': digerleri[i].tls, 'enabled': digerleri[i].etkin},
        ],
      });
      bildir('Birincil teslim hedefi kaydedildi', tur: MesajTur.basari);
      widget.bitti();
      if (mounted) setState(() => _adim = 6);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  void _git(int n) {
    setState(() => _adim = n);
    if (n == 3 && _ob == null) _obYukle();
  }

  Widget _gezinti({VoidCallback? devam, String devamEtiket = 'Devam'}) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      children: [
        TextButton(onPressed: () => _git(_adim - 1), child: const Text('Geri')),
        const Spacer(),
        if (devamEtiket.isNotEmpty) FilledButton(onPressed: devam, child: Text(devamEtiket)),
      ],
    ),
  );

  Widget _icerik() {
    final r = context.r;
    switch (_adim) {
      case 1:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _platformlar)
              SizedBox(
                width: 300,
                child: Kutu(
                  onTap: () {
                    setState(() {
                      _platform = p;
                      _tls = p.tls;
                      _sunucu.text = p.anahtar == 'google' ? 'aspmx.l.google.com' : '';
                    });
                    _git(2);
                  },
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(p.ipucu, style: TextStyle(color: r.soluk, fontSize: 12.5)),
                    ],
                  ),
                ),
              ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.alanlar.isEmpty)
              Bant(
                'Önce müşteri için MX Gateway modunda bir alan adı ekleyin, sonra sihirbaza dönün.',
                renk: Marka.kehribar,
                eylem: TextButton(onPressed: () => bolumeGit(Bolum.alanlar), child: const Text('Alan adı ekle')),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _alanId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Gateway alan adı'),
                hint: const Text('Alan adı seçin'),
                items: [
                  for (final d in widget.alanlar)
                    DropdownMenuItem(
                      value: d.id,
                      child: Text('${d.ad} · ${d.orgAdi}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _alanId = v;
                  _ob = null;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'Listede yoksa Alan Adları\'ndan MX Gateway modunda ekleyin. Paket türü "Mail Gateway" olmalı.',
                style: TextStyle(color: r.silik, fontSize: 12),
              ),
            ],
            _gezinti(devam: _alanId == null ? null : () => _git(3)),
          ],
        );
      case 3:
        final ob = _ob;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ob == null)
              _obHata != null
                  ? Durum.hata(_obHata!, tekrar: _obYukle)
                  : const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
            else
              ...() {
                final ips = metinler(ob['ips']);
                final l = _adimlar(
                  _platform?.anahtar ?? 'smtp',
                  ips.isEmpty ? '(platform IP adresi tanımlı değil — BOGAMAIL_PUBLIC_IPS)' : ips.join(', '),
                  metin(ob['mx_host']),
                );
                return [
                  for (var i = 0; i < l.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: r.vurguYumusak,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(fontSize: 12, color: r.vurgu, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: SelectableText(l[i], style: const TextStyle(fontSize: 13.5))),
                        ],
                      ),
                    ),
                ];
              }(),
            _gezinti(devam: () => _git(4)),
          ],
        );
      case 4:
        final ob = _ob ?? const {};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Bant(
              'MX değişikliğini müşteri kendi DNS panelinde yapar. BogaMail müşterinin DNS kayıtlarına dokunmaz. Önce teslim hedefini kaydedip test edin, '
              'MX\'i en son değiştirin; eski MX kaydını değişiklik yayılana kadar (TTL) silmeyin.',
              renk: Marka.kehribar,
            ),
            const SizedBox(height: 8),
            for (final k in haritalar(ob['records']))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Kutu(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${metin(k['type'])} · ${metin(k['name'])}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 4),
                      KopyaKutusu(metin(k['value'])),
                      const SizedBox(height: 4),
                      Text(metin(k['note']), style: TextStyle(color: r.soluk, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            Text(
              'Alan adı durumu: ${mantik(ob['verified']) ? 'doğrulandı' : 'doğrulanmadı — doğrulama TXT kaydı yayınlanıp Alan Adları sayfasından doğrulanana kadar posta kabul edilmez'}.',
              style: TextStyle(color: r.silik, fontSize: 12.5),
            ),
            _gezinti(devam: () => _git(5)),
          ],
        );
      case 5:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sunucu,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(labelText: 'Teslim hedefi (müşterinin sunucusu)', hintText: _platform?.hedef),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _tls,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'TLS politikası'),
              items: [for (final e in gwTlsEtiketi.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _tls = v ?? _tls),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _sunucu.text.trim().isEmpty || _mesgul ? null : _test,
                  icon: const Icon(Simgeler.wifi, size: 18),
                  label: const Text('Bağlantıyı test et'),
                ),
                FilledButton(onPressed: _sunucu.text.trim().isEmpty || _mesgul ? null : _kaydet, child: const Text('Hedefi kaydet')),
              ],
            ),
            const SizedBox(height: 8),
            Text('Test yalnızca bağlanır, EHLO ve STARTTLS dener; ileti göndermez.', style: TextStyle(color: r.silik, fontSize: 12)),
            if (_sonda != null) ...[const SizedBox(height: 8), SondaSonucu(_sonda!)],
            if (_hata != null) ...[const SizedBox(height: 8), Bant(_hata!, renk: Marka.gul, ikon: Simgeler.errorOutline)],
            _gezinti(devamEtiket: ''),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Simgeler.checkCircle, color: Marka.zumrut),
                SizedBox(width: 8),
                Text('Teslim hedefi kaydedildi.', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Kalan adım müşteride: platform ayarlarını tamamlayıp MX kaydını kendi DNS\'inde değiştirmek. Yedek hedef ve kesinti modu için kartta "Yönet"i kullanın.',
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.maybePop(context), child: const Text('Kapat')),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Adım $_adim/6 · ${_basliklar[_adim - 1]}',
          style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 6; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(color: i < _adim ? r.vurgu : r.kenar, borderRadius: BorderRadius.circular(2)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _icerik(),
      ],
    );
  }
}
