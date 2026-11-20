import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import 'ekip_gateway_ortak.dart';

/// Gateway alan adını yönetme: teslim hedefleri, failover ayarları, kesinti modu, bekleyen postayı deneme.
/// Geniş ekranda iletişim kutusu, telefonda tam sayfa açılır.
Future<void> gatewayYonetimiAc(BuildContext context, GwAlan alan, VoidCallback degisti) {
  final govde = GatewayYonetim(alan: alan, degisti: degisti);
  if (!context.genis) return sayfaAc(context, alan.ad, govde);
  return showDialog<void>(
    context: context,
    builder: (c) {
      final boy = MediaQuery.sizeOf(c);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 780,
          height: boy.height * .86,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Text(alan.ad, overflow: TextOverflow.ellipsis),
              actions: [IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close_rounded))],
            ),
            body: govde,
          ),
        ),
      );
    },
  );
}

class GatewayYonetim extends StatefulWidget {
  const GatewayYonetim({super.key, required this.alan, required this.degisti});
  final GwAlan alan;
  final VoidCallback degisti;
  @override
  State<GatewayYonetim> createState() => _GatewayYonetimState();
}

class _GatewayYonetimState extends State<GatewayYonetim> {
  late GwAlan _alan = widget.alan;
  int _surum = 0;

  /// Alan adını sunucudan tazeler; [sifirla] ise düzenleyiciler kayıtlı değerlerle yeniden kurulur.
  Future<void> _yenile({bool sifirla = true}) async {
    widget.degisti();
    try {
      final v = GwAlan(harita(await Uyg.api.get('/api/v1/gateway/domains/${_alan.id}')));
      if (!mounted) return;
      setState(() {
        _alan = v;
        if (sifirla) _surum++;
      });
    } catch (_) {}
  }

  Future<void> _bosalt() async {
    final v = await islem(() => Uyg.api.post('/api/v1/gateway/domains/${_alan.id}/flush'));
    if (v == null) return;
    final n = tamsayi(harita(v)['flushed']);
    bildir(n > 0 ? '$n bekleyen ileti yeniden denenecek' : 'Kuyrukta bekleyen ileti yok', tur: MesajTur.basari);
    _yenile(sifirla: false);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _alan.orgAdi,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: r.soluk),
                  ),
                ),
                TextButton.icon(onPressed: _bosalt, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Bekleyen postayı şimdi dene')),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Teslim hedefleri'),
              Tab(text: 'Failover ayarları'),
              Tab(text: 'Kesinti modu'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _Hedefler(key: ValueKey('h$_surum'), alan: _alan, kaydedildi: _yenile, tazele: () => _yenile(sifirla: false)),
                _Ayarlar(key: ValueKey('a$_surum'), alan: _alan, kaydedildi: _yenile),
                _Kesinti(key: ValueKey('k$_surum'), alan: _alan, degisti: () => _yenile(sifirla: false)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Satir {
  _Satir({
    String sunucu = '',
    int port = 25,
    int oncelik = 10,
    this.tls = 'opportunistic',
    this.etkin = true,
    this.kimlik = 'none',
    String kullanici = '',
    this.parolaVar = false,
  }) : sunucu = TextEditingController(text: sunucu),
       port = TextEditingController(text: '$port'),
       oncelik = TextEditingController(text: '$oncelik'),
       kullanici = TextEditingController(text: kullanici);
  final TextEditingController sunucu, port, oncelik, kullanici;
  final parola = TextEditingController();
  String tls, kimlik;
  bool etkin;
  final bool parolaVar;

  void kapat() {
    for (final k in [sunucu, port, oncelik, kullanici, parola]) {
      k.dispose();
    }
  }
}

class _Hedefler extends StatefulWidget {
  const _Hedefler({super.key, required this.alan, required this.kaydedildi, required this.tazele});
  final GwAlan alan;
  final Future<void> Function() kaydedildi;
  final VoidCallback tazele;
  @override
  State<_Hedefler> createState() => _HedeflerState();
}

class _HedeflerState extends State<_Hedefler> {
  late final List<_Satir> _satirlar = [
    for (final t in widget.alan.hedefler)
      _Satir(
        sunucu: t.sunucu,
        port: t.port,
        oncelik: t.oncelik,
        tls: t.tls,
        etkin: t.etkin,
        kimlik: t.kimlikTuru,
        kullanici: t.kullanici,
        parolaVar: t.parolaVar,
      ),
  ];
  final Map<String, Object> _sonda = {}; // hedef id → 'mesgul' | sonuç haritası
  bool _mesgul = false;
  String? _hata;

  bool get _yonetir => Uyg.yetki('domains.manage');

  @override
  void dispose() {
    for (final s in _satirlar) {
      s.kapat();
    }
    super.dispose();
  }

  GwHedef? _kayitli(_Satir s) {
    final h = s.sunucu.text.trim().toLowerCase().replaceAll(RegExp(r'\.$'), '');
    return widget.alan.hedefler.where((t) => t.sunucu == h && '${t.port}' == s.port.text.trim()).firstOrNull;
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.put('/api/v1/gateway/domains/${widget.alan.id}/targets', {
        'targets': [
          for (final s in _satirlar)
            {
              'host': s.sunucu.text.trim(),
              'port': int.tryParse(s.port.text.trim()) ?? 25,
              'priority': int.tryParse(s.oncelik.text.trim()) ?? 0,
              'tls_policy': s.tls,
              'enabled': s.etkin,
              'auth_mode': s.kimlik,
              'auth_username': s.kimlik == 'none' ? '' : s.kullanici.text.trim(),
              // Boş parola kayıtlı parolayı korur.
              if (s.kimlik != 'none' && s.parola.text.isNotEmpty) 'auth_password': s.parola.text,
            },
        ],
      });
      bildir('Teslim hedefleri kaydedildi', tur: MesajTur.basari);
      await widget.kaydedildi();
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _test(GwHedef t) async {
    setState(() => _sonda[t.id] = 'mesgul');
    try {
      final v = harita(await Uyg.api.post('/api/v1/gateway/domains/${widget.alan.id}/targets/${t.id}/probe'));
      if (mounted) setState(() => _sonda[t.id] = v);
      widget.tazele();
    } catch (e) {
      bildir('Test yapılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
      if (mounted) setState(() => _sonda.remove(t.id));
    }
  }

  Widget _satir(int i, _Satir s) {
    final r = context.r;
    final kayitli = _kayitli(s);
    final sonda = kayitli == null ? null : _sonda[kayitli.id];
    final dar = MediaQuery.sizeOf(context).width < 560;
    final sayi = [FilteringTextInputFormatter.digitsOnly];
    final sunucu = TextField(
      controller: s.sunucu,
      enabled: _yonetir,
      style: const TextStyle(fontFamily: 'monospace'),
      decoration: const InputDecoration(labelText: 'Sunucu', hintText: 'mail.musteri.com'),
    );
    final port = TextField(
      controller: s.port,
      enabled: _yonetir,
      keyboardType: TextInputType.number,
      inputFormatters: sayi,
      decoration: const InputDecoration(labelText: 'Port'),
    );
    final oncelik = TextField(
      controller: s.oncelik,
      enabled: _yonetir,
      keyboardType: TextInputType.number,
      inputFormatters: sayi,
      decoration: const InputDecoration(labelText: 'Öncelik'),
    );
    return Kutu(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dar) ...[
            sunucu,
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: port),
                const SizedBox(width: 8),
                Expanded(child: oncelik),
              ],
            ),
          ] else
            Row(
              children: [
                Expanded(child: sunucu),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: port),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: oncelik),
              ],
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue: s.tls,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'TLS politikası'),
                  items: [for (final e in gwTlsEtiketi.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: _yonetir ? (v) => setState(() => s.tls = v ?? s.tls) : null,
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('k$i${s.kimlik}'),
                  initialValue: s.kimlik,
                  decoration: const InputDecoration(labelText: 'SMTP AUTH'),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('Yok')),
                    DropdownMenuItem(value: 'plain', child: Text('PLAIN')),
                    DropdownMenuItem(value: 'login', child: Text('LOGIN')),
                  ],
                  onChanged: !_yonetir
                      ? null
                      : (v) => setState(() {
                          s.kimlik = v ?? 'none';
                          if (s.kimlik != 'none' && s.tls == 'opportunistic') s.tls = 'required';
                        }),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(value: s.etkin, onChanged: _yonetir ? (v) => setState(() => s.etkin = v ?? true) : null),
                  const Text('Etkin'),
                ],
              ),
            ],
          ),
          if (s.kimlik != 'none') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: s.kullanici,
                    enabled: _yonetir,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Kullanıcı adı'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: s.parola,
                    enabled: _yonetir,
                    obscureText: true,
                    decoration: InputDecoration(labelText: 'Parola', hintText: s.parolaVar ? 'Kayıtlı (değiştirmek için yazın)' : null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Kimlik bilgisi yalnızca STARTTLS kurulduktan sonra gönderilir (TLS politikası "zorunlu" veya "doğrula" olmalı). Parola şifrelenmiş saklanır ve bir daha gösterilmez.',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
          ],
          if (kayitli != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                DurumNoktasi(gwHedefRengi(kayitli, r.silik)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      'Durum: ${gwDurumEtiketi[kayitli.durum] ?? kayitli.durum}',
                      'ardışık hata ${kayitli.ardisikHata}',
                      if (kayitli.sonBasari != null) 'son başarı ${goreliZaman(kayitli.sonBasari)}',
                      if (kayitli.sonrakiYoklama != null && kayitli.durum != 'closed') 'sonraki yoklama ${tamZaman(kayitli.sonrakiYoklama)}',
                    ].join(' · '),
                    style: TextStyle(color: r.soluk, fontSize: 12.5),
                  ),
                ),
              ],
            ),
            if (kayitli.sonHata.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Son hata: ${kayitli.sonHata}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: r.silik, fontSize: 12),
                ),
              ),
          ],
          if (_yonetir)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  if (kayitli != null)
                    OutlinedButton.icon(
                      onPressed: sonda == 'mesgul' ? null : () => _test(kayitli),
                      icon: const Icon(Icons.wifi_rounded, size: 17),
                      label: Text(sonda == 'mesgul' ? 'Test ediliyor…' : 'Bağlantıyı test et'),
                    ),
                  IconButton(
                    tooltip: 'Hedefi kaldır',
                    onPressed: () => setState(() => _satirlar.removeAt(i).kapat()),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          if (sonda is Map<String, dynamic>) ...[const SizedBox(height: 6), SondaSonucu(sonda)],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ekleyebilir = _satirlar.length < (widget.alan.failover ? 5 : 1);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          'Hedefler öncelik sırasına göre (küçük sayı önce) denenir. Bağlantı hatası veya geçici (4xx) yanıtta sıradaki hedefe geçilir; '
          'bir alıcı için kalıcı (5xx) ret kesindir. Yerel / özel ağ adresleri güvenlik nedeniyle kabul edilmez.',
          style: TextStyle(color: r.soluk, fontSize: 13),
        ),
        const SizedBox(height: 10),
        if (!widget.alan.failover) ...[
          const Bant('Paketinizde Akıllı MX Failover yok: tek teslim hedefi tanımlanabilir.', renk: Marka.kehribar),
          const SizedBox(height: 10),
        ],
        if (_satirlar.isEmpty) const Bant('Teslim hedefi yok: gelen posta 451 ile geri çevrilir.', renk: Marka.kehribar, ikon: Icons.warning_amber_rounded),
        for (var i = 0; i < _satirlar.length; i++) Padding(padding: const EdgeInsets.only(bottom: 10), child: _satir(i, _satirlar[i])),
        if (_hata != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
          ),
        if (_yonetir)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: ekleyebilir ? () => setState(() => _satirlar.add(_Satir(oncelik: (_satirlar.length + 1) * 10))) : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Hedef ekle'),
              ),
              FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
            ],
          ),
        const SizedBox(height: 10),
        Text(
          'Bağlantı testi yalnızca bağlanır, EHLO ve (varsa) STARTTLS dener; ileti göndermez. Kaydedilmemiş hedefi test etmek için önce kaydedin.',
          style: TextStyle(color: r.silik, fontSize: 12),
        ),
      ],
    );
  }
}

class _Ayarlar extends StatefulWidget {
  const _Ayarlar({super.key, required this.alan, required this.kaydedildi});
  final GwAlan alan;
  final Future<void> Function() kaydedildi;
  @override
  State<_Ayarlar> createState() => _AyarlarState();
}

class _AyarlarState extends State<_Ayarlar> {
  late final _esik = TextEditingController(text: '${tamsayi(widget.alan.ayar['fail_threshold'], 3)}');
  late final _yoklama = TextEditingController(text: '${(tamsayi(widget.alan.ayar['probe_interval_seconds'], 300) / 60).round()}');
  late final _tutma = TextEditingController(text: '${tamsayi(widget.alan.ayar['retention_hours'], 120)}');
  final _form = GlobalKey<FormState>();
  String? _hata;

  @override
  void dispose() {
    _esik.dispose();
    _yoklama.dispose();
    _tutma.dispose();
    super.dispose();
  }

  String? Function(String?) _aralik(int a, int z) => (v) {
    final n = int.tryParse((v ?? '').trim());
    return n == null || n < a || n > z ? '$a–$z arasında olmalı' : null;
  };

  Future<void> _kaydet() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _hata = null);
    try {
      await Uyg.api.patch('/api/v1/gateway/domains/${widget.alan.id}/settings', {
        'retention_hours': int.parse(_tutma.text.trim()),
        'fail_threshold': int.parse(_esik.text.trim()),
        'probe_interval_seconds': (int.parse(_yoklama.text.trim()) * 60).clamp(30, 1 << 30),
      });
      bildir('Ayarlar kaydedildi', tur: MesajTur.basari);
      await widget.kaydedildi();
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final kapali = !widget.alan.failover || !Uyg.yetki('domains.manage');
    final sayi = [FilteringTextInputFormatter.digitsOnly];
    Widget alan(TextEditingController k, String e, int a, int z) => SizedBox(
      width: 220,
      child: TextFormField(
        controller: k,
        enabled: !kapali,
        keyboardType: TextInputType.number,
        inputFormatters: sayi,
        validator: _aralik(a, z),
        decoration: InputDecoration(labelText: e, helperText: '$a–$z'),
      ),
    );
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (!widget.alan.failover) ...[
            const Bant('Paketinizde Akıllı MX Failover yok; varsayılanlar geçerli (5 gün kuyrukta tutma).', renk: Marka.kehribar),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              alan(_esik, 'Devre açma eşiği (ardışık hata)', 1, 50),
              alan(_yoklama, 'Yoklama aralığı (dakika)', 1, 60),
              alan(_tutma, 'Kuyrukta tutma (saat)', 1, 720),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tüm hedefler erişilemezken posta geri çevrilmez, kuyrukta tutulur (MX yedeği gibi, varsayılan 120 saat = 5 gün). Devresi açık hedef her yoklama '
            'aralığında yalnızca bağlantı + EHLO ile yoklanır; yanıt verdiğinde bekleyen posta en eskiden başlayarak otomatik gönderilir. Süre dolarsa '
            'gönderene teslim edilemedi bildirimi (DSN) gider.',
            style: TextStyle(color: context.r.silik, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          if (_hata != null) ...[Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded), const SizedBox(height: 8)],
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(onPressed: kapali ? null : _kaydet, child: const Text('Kaydet')),
          ),
        ],
      ),
    );
  }
}

class _Kesinti extends StatefulWidget {
  const _Kesinti({super.key, required this.alan, required this.degisti});
  final GwAlan alan;
  final VoidCallback degisti;
  @override
  State<_Kesinti> createState() => _KesintiState();
}

class _KesintiState extends State<_Kesinti> {
  Map<String, dynamic>? _v;
  String? _hata;
  final _sonra = TextEditingController();
  final _gun = TextEditingController();
  final _yerel = TextEditingController();
  (String, String, String)? _gizli; // başlık, değer, not

  String get _yol => '/api/v1/gateway/domains/${widget.alan.id}';
  bool get _yonetir => Uyg.yetki('domains.manage');

  @override
  void initState() {
    super.initState();
    _yukle(ilk: true);
  }

  @override
  void dispose() {
    _sonra.dispose();
    _gun.dispose();
    _yerel.dispose();
    super.dispose();
  }

  Future<void> _yukle({bool ilk = false}) async {
    try {
      final v = harita(await Uyg.api.get('$_yol/continuity'));
      if (!mounted) return;
      setState(() {
        _v = v;
        _hata = null;
        final st = harita(v['settings']);
        if (ilk) {
          _sonra.text = '${tamsayi(st['continuity_after_minutes'], 30)}';
          _gun.text = '${tamsayi(st['continuity_retention_days'], 14)}';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _ayar(Map<String, dynamic> govde, String tamam) async {
    final v = await islem(() => Uyg.api.patch('$_yol/settings', govde), tamam: tamam);
    if (v == null) return;
    await _yukle();
    widget.degisti();
  }

  Future<void> _sureKaydet() async {
    final a = int.tryParse(_sonra.text.trim()), g = int.tryParse(_gun.text.trim());
    if (a == null || a < 0 || a > 10080) {
      bildir('Otomatik açılma 0–10080 dakika olmalı', tur: MesajTur.hata);
      return;
    }
    if (g == null || g < 1 || g > 90) {
      bildir('Saklama 1–90 gün olmalı', tur: MesajTur.hata);
      return;
    }
    await _ayar({'continuity_after_minutes': a, 'continuity_retention_days': g}, 'Kaydedildi');
  }

  Future<void> _eylem(String yol, Object? govde, String tamam) async {
    try {
      final r = harita(await Uyg.api.post(yol, govde));
      final adres = metin(r['address']);
      final bitis = tamZaman(tarihOku(r['expires_at']));
      final sunucu = Uyg.api.sunucu.replaceAll(RegExp(r'/+$'), '');
      if (metinYa(r['path']) != null) {
        setState(
          () => _gizli = (
            '$adres için tek kullanımlık giriş bağlantısı',
            '$sunucu${r['path']}',
            'Geçerlilik: $bitis. Bir kez kullanılabilir. Kullanıcıya siz iletin; sistem e-posta göndermez.',
          ),
        );
      } else if (metinYa(r['password']) != null) {
        setState(
          () => _gizli = (
            '$adres için geçici şifre',
            metin(r['password']),
            'Giriş adresi: $sunucu/mail/continuity · geçerlilik $bitis. Bu şifre yalnızca şimdi gösterilir.',
          ),
        );
      } else if (tamam.isNotEmpty) {
        bildir(tamam, tur: MesajTur.basari);
      }
      await _yukle();
    } catch (e) {
      bildir('Yapılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _ekle() async {
    final l = _yerel.text.trim();
    if (l.isEmpty) return;
    await _eylem('$_yol/continuity/users', {'local_part': l}, 'Kullanıcı eklendi');
    _yerel.clear();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final v = _v;
    if (v == null) {
      if (_hata != null) return Durum.hata(_hata!, tekrar: _yukle);
      return const Durum.yukleniyor();
    }
    if (!mantik(v['available'])) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Bant('Paketinizde Mail Continuity (kesinti modu) yok.', renk: Marka.kehribar),
      );
    }
    final st = harita(v['settings']);
    final aktif = mantik(v['active']);
    final kota = harita(v['quota']);
    final limit = tamsayiYa(kota['limit_bytes']);
    final erisim = mantik(st['continuity_access']);
    final kullanicilar = haritalar(v['users']);
    return RefreshIndicator.adaptive(
      onRefresh: _yukle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Kutu(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Durum: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    Flexible(child: Rozet(aktif ? 'Kesinti modu açık: kopya saklanıyor' : 'Kapalı', renk: aktif ? Marka.kehribar : r.soluk)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Kesinti modunda gelen her iletinin bir kopyası alıcı adresi başına saklanır; asıl ileti yine kuyrukta bekler ve sunucu düzelince '
                  'müşteri sunucusuna bir kez teslim edilir (kayıp ya da çift kayıt olmaz). Kopyalar ${tamsayi(st['continuity_retention_days'])} gün sonra silinir. '
                  'Kullanım: ${boyutYaz(tamsayi(kota['used_bytes']))} / ${limit == null ? 'sınırsız' : boyutYaz(limit)}',
                  style: TextStyle(color: r.soluk, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Continuity modu (elle)'),
            subtitle: const Text('Hedefler çalışsa bile kopyalamayı başlatır.'),
            value: mantik(st['continuity_manual']),
            onChanged: !_yonetir ? null : (x) => _ayar({'continuity_manual': x}, x ? 'Kesinti modu elle açıldı' : 'Elle açma kapatıldı'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Geçici webmail erişimi'),
            subtitle: const Text('Kapatınca tüm açık oturumlar sonlanır.'),
            value: erisim,
            onChanged: !_yonetir ? null : (x) => _ayar({'continuity_access': x}, x ? 'Geçici webmail erişimi açıldı' : 'Geçici webmail erişimi kapatıldı'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _sonra,
                  enabled: _yonetir,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Otomatik açılma (dk kesinti)', helperText: '0–10080'),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _gun,
                  enabled: _yonetir,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Saklama (gün)', helperText: '1–90'),
                ),
              ),
              if (_yonetir) OutlinedButton(onPressed: _sureKaydet, child: const Text('Kaydet')),
            ],
          ),
          if (_gizli != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: r.vurguYumusak,
                border: Border.all(color: r.vurgu.withValues(alpha: .4)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_gizli!.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  KopyaKutusu(_gizli!.$2),
                  const SizedBox(height: 6),
                  Text(_gizli!.$3, style: TextStyle(color: r.soluk, fontSize: 12)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Kullanıcılar (${kullanicilar.length})', style: gosterim(15, agirlik: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_yonetir) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _yerel,
                    autocorrect: false,
                    onSubmitted: (_) => _ekle(),
                    decoration: InputDecoration(labelText: 'Adres ekle', hintText: 'ad@${widget.alan.ad}'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: _ekle, icon: const Icon(Icons.add_rounded), label: const Text('Ekle')),
              ],
            ),
            const SizedBox(height: 4),
            Text('Kesinti modunda posta alan adresler otomatik eklenir; önceden de ekleyebilirsiniz.', style: TextStyle(color: r.silik, fontSize: 12)),
            const SizedBox(height: 8),
          ],
          if (kullanicilar.isEmpty) Text('Henüz kullanıcı yok.', style: TextStyle(color: r.soluk)),
          for (final u in kullanicilar)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(metin(u['address']), overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  '${tamsayi(u['messages'])} ileti · ${boyutYaz(tamsayi(u['bytes']))}',
                  if (tarihOku(u['password_expires_at']) != null) 'şifre ${tamZaman(tarihOku(u['password_expires_at']))} tarihine kadar',
                  if (tarihOku(u['link_expires_at']) != null) 'bağlantı ${tamZaman(tarihOku(u['link_expires_at']))} tarihine kadar',
                  if (tarihOku(u['last_login_at']) != null) 'son giriş ${goreliZaman(tarihOku(u['last_login_at']))}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: !_yonetir
                  ? null
                  : PopupMenuButton<String>(
                      tooltip: 'İşlemler',
                      onSelected: (e) {
                        final id = metin(u['id']);
                        switch (e) {
                          case 'link':
                            _eylem('/api/v1/gateway/continuity/users/$id/link', <String, dynamic>{}, '');
                          case 'password':
                            _eylem('/api/v1/gateway/continuity/users/$id/password', <String, dynamic>{}, '');
                          default:
                            _eylem('/api/v1/gateway/continuity/users/$id/revoke', null, 'Erişim kaldırıldı');
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'link',
                          enabled: erisim,
                          child: const ListTile(leading: Icon(Icons.link_rounded), title: Text('Tek kullanımlık bağlantı')),
                        ),
                        PopupMenuItem(
                          value: 'password',
                          enabled: erisim,
                          child: const ListTile(leading: Icon(Icons.key_rounded), title: Text('Geçici şifre')),
                        ),
                        const PopupMenuItem(
                          value: 'revoke',
                          child: ListTile(leading: Icon(Icons.remove_moderator_outlined), title: Text('Erişimi kaldır')),
                        ),
                      ],
                    ),
            ),
          if (!erisim && kullanicilar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Bağlantı/şifre üretmek için önce geçici webmail erişimini açın.', style: TextStyle(color: Marka.kehribar, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}
