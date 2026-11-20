import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'altyapi_ortak.dart';
import '../ortak/simgeler.dart';

/// Kiracı İzolasyonu (platform): müşteri başına gönderim sınırları, kuyruk payı, IP havuzu, risk; durdur / sürdür /
/// yavaşlat ve platform varsayılanları. web: admin/(panel)/tenants. API: /tenants/isolation, /tenants/{id}/limits,
/// /tenants/{id}/{pause|resume|throttle|unthrottle}, /tenants/defaults (hepsi süper yönetici).
class KiraciIzolasyonuEkrani extends StatefulWidget {
  const KiraciIzolasyonuEkrani({super.key});

  @override
  State<KiraciIzolasyonuEkrani> createState() => _KiraciIzolasyonuEkraniState();
}

String _sinir(int n) => n == 0 ? 'sınırsız' : sayiYaz(n);

/// /tenants/isolation → items[] satırı.
class Kiraci {
  Kiraci(this.m);
  final Map<String, dynamic> m;

  String get id => metin(m['id']);
  String get ad => metin(m['name']);
  String? get paket => metinYa(m['plan_name']);
  Map<String, dynamic> get ayar => harita(m['settings']);
  Map<String, dynamic> get etkin => harita(m['effective']);
  bool get durduruldu => mantik(etkin['paused']);
  bool get yavaslatildi => mantik(etkin['throttled']);
  int get bitti24 => tamsayi(m['finished_24h']);
  double get geriDonme => ondalik(m['bounce_rate']);
  int get risk => tamsayi(m['risk']);
  int get sonSaat => tamsayi(m['sent_last_hour']);
  int get kuyruk => tamsayi(m['queued']);
  int get bekletilen => tamsayi(m['held']);
  int get teslimde => tamsayi(m['running']);
  int get ozelIp => tamsayi(m['dedicated_ips']);
  String? get havuz => metinYa(ayar['ip_pool']);

  String get altSatir => [paket ?? 'Paketsiz', if (havuz != null) 'havuz $havuz', if (ozelIp > 0) '$ozelIp özel IP'].join(' · ');
  String get sinirlar =>
      '${_sinir(tamsayi(etkin['msgs_per_minute']))}/dk · ${_sinir(tamsayi(etkin['max_concurrent']))} bağ. · pay ${tamsayi(etkin['queue_weight'])}';
  String get geriDonmeMetni => '%${geriDonme.toStringAsFixed(1).replaceAll('.', ',')}';
}

class _KiraciIzolasyonuEkraniState extends State<KiraciIzolasyonuEkrani> {
  Map<String, dynamic> _varsayilan = {};
  bool _kuyrukVar = true;
  String _ara = '';
  List<Kiraci> _hepsi = [];

  late final _y = SayfaYukleyici.yerel<Kiraci>(() async {
    final v = harita(await Uyg.api.get('/api/v1/tenants/isolation'));
    final l = haritalar(v['items']).map(Kiraci.new).toList();
    if (mounted) {
      setState(() {
        _varsayilan = harita(v['defaults']);
        _kuyrukVar = mantik(v['queue_enabled'], true);
        _hepsi = l;
      });
    }
    final q = _ara.trim().toLowerCase();
    final f = q.isEmpty ? l : l.where((t) => t.ad.toLowerCase().contains(q)).toList();
    // En riskliler önce: durdurulan / yavaşlatılan, sonra risk ve geri dönme oranı.
    int s(Kiraci t) => t.durduruldu || t.yavaslatildi ? 1 : 0;
    f.sort((a, b) {
      final x = s(b).compareTo(s(a));
      if (x != 0) return x;
      final y = b.risk.compareTo(a.risk);
      return y != 0 ? y : b.geriDonme.compareTo(a.geriDonme);
    });
    return f;
  }, sayfaBoyu: 25)..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  int _v(String k) => tamsayi(_varsayilan[k]);
  double get _carpan => ondalik(_varsayilan['throttle_factor']);

  bool _geriDonmeKotu(Kiraci t) => t.bitti24 >= _v('min_finished') && t.geriDonme >= ondalik(_varsayilan['throttle_bounce_rate']);
  bool _riskKotu(Kiraci t) => _varsayilan.isNotEmpty && t.risk >= _v('throttle_risk');

  Widget _durumRozeti(Kiraci t) {
    if (t.durduruldu) return const Rozet('Durduruldu', renk: Marka.gul, ikon: Simgeler.pauseCircleOutline);
    if (t.yavaslatildi) {
      final oto = mantik(t.ayar['throttle_auto']) ? ' (otomatik)' : '';
      final bitis = tarihOku(t.etkin['throttled_until']);
      return Rozet('Yavaşlatıldı$oto${bitis == null ? '' : ' · ${goreliZaman(bitis)}'}', renk: Marka.kehribar, ikon: Simgeler.speed);
    }
    return const Rozet('Normal', renk: Marka.zumrut);
  }

  Future<void> _yonet(Kiraci t) async {
    final degisti = await showDialog<bool>(
      context: context,
      builder: (_) => _KiraciYonetimi(kiraci: t, varsayilan: _varsayilan),
    );
    if (degisti == true) await _y.yenile();
  }

  Future<void> _varsayilanlar() async {
    if (_varsayilan.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _VarsayilanFormu(varsayilan: _varsayilan),
    );
    if (ok == true) await _y.yenile();
  }

  Widget _ust(BuildContext context) {
    final d = _varsayilan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(context.genis ? 16 : 0, 4, context.genis ? 16 : 0, 8),
            child: Bant(
              'Varsayılan: dakikada ${_sinir(_v('msgs_per_minute'))} ileti, saatte ${_sinir(_v('rcpts_per_hour'))} alıcı, '
              '${_sinir(_v('max_concurrent'))} eşzamanlı teslim. Otomatik yavaşlatma: son 24 saatte en az ${_v('min_finished')} teslimde kalıcı geri '
              'dönme ≥ %${metin(d['throttle_bounce_rate'])} veya risk ≥ ${_v('throttle_risk')}; ${_v('throttle_minutes')} dakika boyunca hız '
              '%${(_carpan * 100).round()}\'e düşer.${_kuyrukVar ? '' : ' Bu düğümde giden kuyruk yok: kuyruk sayıları gösterilemez.'}',
              ikon: Simgeler.shield,
            ),
          ),
        FiltreCubugu(
          arama: AramaAlani(
            ipucu: 'Müşteri ara…',
            ilk: _ara,
            degisti: (s) {
              _ara = s;
              _y.yenile();
            },
          ),
          sag: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('${_hepsi.length} müşteri', style: TextStyle(color: context.r.silik, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi) {
      return const Iskelet(baslik: 'Kiracı İzolasyonu', govde: Kapali('Kiracı izolasyonu yalnızca platform yöneticisine açıktır.'));
    }
    final r = context.r;
    return Iskelet(
      baslik: 'Kiracı İzolasyonu',
      alt: 'Müşteri başına gönderim sınırları, kuyruk payı, IP havuzu ve kötüye kullanım riski',
      yenile: _y.yenile,
      eylemler: [IconButton(tooltip: 'Platform varsayılanları', onPressed: _varsayilanlar, icon: const Icon(Simgeler.tune))],
      govde: VeriTablosu<Kiraci>(
        yukleyici: _y,
        ust: _ust(context),
        bosMetin: 'Eşleşen müşteri bulunamadı.',
        bosIkon: Simgeler.shield,
        tabloEnAz: 900,
        onTap: _yonet,
        eylemler: (t) => [SatirEylemi(Simgeler.tune, 'Yönet', () => _yonet(t))],
        sutunlar: [
          Sutun('Müşteri', esnek: 4, hucre: (c, t) => IkiSatir(t.ad, alt: t.altSatir)),
          Sutun(
            'Durum',
            esnek: 3,
            hucre: (c, t) => Align(alignment: Alignment.centerLeft, child: _durumRozeti(t)),
          ),
          Sutun(
            'Kuyruk',
            esnek: 2,
            hucre: (c, t) => IkiSatir(
              sayiYaz(t.kuyruk),
              kalin: false,
              alt: [if (t.bekletilen > 0) '${t.bekletilen} bekletilen', if (t.teslimde > 0) '${t.teslimde} teslimde'].join(' · '),
            ),
          ),
          Sutun('Son 1 saat', esnek: 2, hucre: (c, t) => SolukMetin('${sayiYaz(t.sonSaat)} / ${_sinir(tamsayi(t.etkin['rcpts_per_hour']))}')),
          Sutun(
            'Geri dönme (24 s)',
            esnek: 2,
            hucre: (c, t) => Text('${t.geriDonmeMetni} (${t.bitti24})', style: TextStyle(color: _geriDonmeKotu(t) ? Marka.gul : r.metin, fontSize: 13)),
          ),
          Sutun(
            'Risk',
            esnek: 1,
            hucre: (c, t) => Text(
              '${t.risk}',
              style: TextStyle(color: _riskKotu(t) ? Marka.gul : r.metin, fontWeight: FontWeight.w600),
            ),
          ),
          Sutun('Sınırlar', esnek: 3, hucre: (c, t) => SolukMetin(t.sinirlar)),
        ],
        kart: (c, t) => VeriKarti(
          baslik: t.ad,
          alt: t.altSatir,
          rozetler: [_durumRozeti(t)],
          onTap: () => _yonet(t),
          eylemler: [SatirEylemi(Simgeler.tune, 'Yönet', () => _yonet(t))],
          alanlar: [
            ('Kuyruk', '${t.kuyruk}${t.bekletilen > 0 ? ' (${t.bekletilen} bekletilen)' : ''}'),
            ('Geri dönme', '${t.geriDonmeMetni} (${t.bitti24})'),
            ('Risk', '${t.risk}'),
            ('Sınırlar', t.sinirlar),
          ],
        ),
      ),
    );
  }
}

/// Bir müşterinin sınırları ve durdur / yavaşlat işlemleri (web: ManageTenantDialog).
class _KiraciYonetimi extends StatefulWidget {
  const _KiraciYonetimi({required this.kiraci, required this.varsayilan});
  final Kiraci kiraci;
  final Map<String, dynamic> varsayilan;

  @override
  State<_KiraciYonetimi> createState() => _KiraciYonetimiState();
}

class _KiraciYonetimiState extends State<_KiraciYonetimi> {
  late Kiraci _t = widget.kiraci;
  late final _dk = TextEditingController(text: metin(_t.ayar['msgs_per_minute']));
  late final _saat = TextEditingController(text: metin(_t.ayar['rcpts_per_hour']));
  late final _baglanti = TextEditingController(text: metin(_t.ayar['max_concurrent']));
  late final _pay = TextEditingController(text: '${tamsayi(_t.ayar['queue_weight'], 1)}');
  late final _havuz = TextEditingController(text: metin(_t.ayar['ip_pool']));
  late bool _oto = mantik(_t.ayar['auto_throttle'], true);
  final _gerekce = TextEditingController();
  final _sure = TextEditingController(text: '60');
  bool _mesgul = false, _degisti = false;
  String? _hata, _alan;

  @override
  void dispose() {
    for (final c in [_dk, _saat, _baglanti, _pay, _havuz, _gerekce, _sure]) {
      c.dispose();
    }
    super.dispose();
  }

  int _v(String k) => tamsayi(widget.varsayilan[k]);
  int get _carpanYuzde => (ondalik(widget.varsayilan['throttle_factor']) * 100).round();

  int? _sayi(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());

  Future<void> _calistir(Future<dynamic> Function() f, String tamam) async {
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    try {
      final v = await f();
      _degisti = true;
      if (v is Map && v['settings'] is Map && mounted) setState(() => _t = Kiraci(harita(v)));
      bildir(tamam, tur: MesajTur.basari);
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

  Future<dynamic> _eylem(String a, [Map<String, dynamic>? govde]) => Uyg.api.post('/api/v1/tenants/${_t.id}/$a', govde);

  void _sinirlariKaydet() {
    final pay = int.tryParse(_pay.text.trim());
    if (pay == null || pay < 1 || pay > 10) {
      setState(() {
        _alan = 'queue_weight';
        _hata = 'Kuyruk payı 1–10 arasında olmalı';
      });
      return;
    }
    final havuz = _havuz.text.trim().toLowerCase();
    if (havuz.isNotEmpty && !RegExp(r'^[a-z0-9_-]+$').hasMatch(havuz)) {
      setState(() {
        _alan = 'ip_pool';
        _hata = 'Havuz adı: küçük harf, rakam, - ve _';
      });
      return;
    }
    _calistir(
      () => Uyg.api.patch('/api/v1/tenants/${_t.id}/limits', {
        'msgs_per_minute': _sayi(_dk),
        'rcpts_per_hour': _sayi(_saat),
        'max_concurrent': _sayi(_baglanti),
        'queue_weight': pay,
        'ip_pool': havuz.isEmpty ? null : havuz,
        'auto_throttle': _oto,
      }),
      'Sınırlar kaydedildi',
    );
  }

  Widget _alanKutusu(TextEditingController c, String etiket, String anahtar) => TextField(
    controller: c,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: etiket, errorText: _alan == anahtar ? _hata : null, isDense: true),
  );

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final s = _t.ayar;
    final durdu = mantik(s['paused']);
    final yavas = _t.yavaslatildi;
    return AlertDialog(
      title: Text(_t.ad, style: gosterim(19, agirlik: FontWeight.w600)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Boş bırakılan sınır platform varsayılanını kullanır; 0 sınırsız demektir. Yavaşlatma sırasında hız %$_carpanYuzde\'e ve tek bağlantıya düşer.',
                style: TextStyle(color: r.soluk, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _alanKutusu(_dk, 'Dakikada ileti (vars. ${_sinir(_v('msgs_per_minute'))})', 'msgs_per_minute')),
                  const SizedBox(width: 8),
                  Expanded(child: _alanKutusu(_saat, 'Saatte alıcı (vars. ${_sinir(_v('rcpts_per_hour'))})', 'rcpts_per_hour')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _alanKutusu(_baglanti, 'Eşzamanlı teslim (vars. ${_sinir(_v('max_concurrent'))})', 'max_concurrent')),
                  const SizedBox(width: 8),
                  Expanded(child: _alanKutusu(_pay, 'Kuyruk payı (1–10)', 'queue_weight')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _havuz,
                decoration: InputDecoration(
                  labelText: 'IP havuzu (boş: paket / paylaşımlı)',
                  hintText: 'bulk',
                  errorText: _alan == 'ip_pool' ? _hata : null,
                  isDense: true,
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _oto,
                onChanged: (v) => setState(() => _oto = v),
                title: const Text('Otomatik yavaşlatma', style: TextStyle(fontSize: 14)),
                subtitle: const Text('Geri dönme / risk eşiği aşılınca', style: TextStyle(fontSize: 12)),
              ),
              FilledButton.icon(
                onPressed: _mesgul ? null : _sinirlariKaydet,
                icon: const Icon(Simgeler.speed, size: 18),
                label: const Text('Sınırları kaydet'),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _gerekce,
                      maxLength: 300,
                      decoration: InputDecoration(
                        labelText: 'Gerekçe (denetim kaydı)',
                        counterText: '',
                        isDense: true,
                        errorText: _alan == 'reason' ? _hata : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 100, child: _alanKutusu(_sure, 'Süre (dk)', 'minutes')),
                ],
              ),
              const SizedBox(height: 8),
              if (durdu)
                EylemSatiri(
                  ikon: Simgeler.playCircleOutline,
                  baslik: 'Gönderimi sürdür',
                  ipucu: 'Durduruldu: ${tire(metin(s['paused_reason'], 'gerekçe yok'))} · ${tamZaman(tarihOku(s['paused_at']))}',
                  onTap: _mesgul ? null : () => _calistir(() => _eylem('resume'), 'Gönderim sürdürüldü'),
                )
              else
                EylemSatiri(
                  ikon: Simgeler.pauseCircleOutline,
                  baslik: 'Gönderimi durdur',
                  ipucu: 'Dış gönderim reddedilir (geçici hata); kuyruktaki iletiler bekletilir',
                  tehlikeli: true,
                  onTap: _mesgul
                      ? null
                      : () async {
                          if (!await onayla(
                            context,
                            'Gönderim durdurulsun mu?',
                            mesaj: '${_t.ad} müşterisinin dış gönderimi durdurulacak.',
                            evet: 'Durdur',
                            tehlikeli: true,
                          )) {
                            return;
                          }
                          await _calistir(() => _eylem('pause', {'reason': _gerekce.text.trim()}), 'Gönderim durduruldu');
                        },
                ),
              if (yavas)
                EylemSatiri(
                  ikon: Simgeler.bolt,
                  baslik: 'Yavaşlatmayı kaldır',
                  ipucu: '${tire(metin(s['throttle_reason'], 'gerekçe yok'))} · bitiş ${tamZaman(tarihOku(s['throttled_until']))}',
                  onTap: _mesgul ? null : () => _calistir(() => _eylem('unthrottle'), 'Yavaşlatma kaldırıldı'),
                )
              else
                EylemSatiri(
                  ikon: Simgeler.speed,
                  baslik: 'Yavaşlat',
                  ipucu: 'Belirtilen süre boyunca hız %$_carpanYuzde',
                  onTap: _mesgul
                      ? null
                      : () {
                          final dk = int.tryParse(_sure.text.trim()) ?? 0;
                          if (dk < 1 || dk > 7 * 24 * 60) {
                            setState(() {
                              _alan = 'minutes';
                              _hata = 'Süre 1 dakika ile 7 gün arasında olmalı';
                            });
                            return;
                          }
                          _calistir(() => _eylem('throttle', {'minutes': dk, 'reason': _gerekce.text.trim()}), 'Müşteri yavaşlatıldı');
                        },
                ),
              if (_hata != null &&
                  (_alan == null ||
                      !const {'msgs_per_minute', 'rcpts_per_hour', 'max_concurrent', 'queue_weight', 'ip_pool', 'reason', 'minutes'}.contains(_alan)))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context, _degisti), child: const Text('Kapat'))],
    );
  }
}

/// PUT /tenants/defaults (web: DefaultsDialog).
class _VarsayilanFormu extends StatefulWidget {
  const _VarsayilanFormu({required this.varsayilan});
  final Map<String, dynamic> varsayilan;

  @override
  State<_VarsayilanFormu> createState() => _VarsayilanFormuState();
}

class _VarsayilanFormuState extends State<_VarsayilanFormu> {
  static const _alanlar = [
    ('msgs_per_minute', 'Dakikada ileti (0 = sınırsız)'),
    ('rcpts_per_hour', 'Saatte alıcı (0 = sınırsız)'),
    ('max_concurrent', 'Eşzamanlı teslim (0 = sınırsız)'),
    ('throttle_bounce_rate', 'Yavaşlatma: geri dönme oranı %'),
    ('min_finished', 'Yavaşlatma: en az teslim (24 s)'),
    ('throttle_risk', 'Yavaşlatma: risk puanı'),
    ('throttle_minutes', 'Yavaşlatma süresi (dk)'),
    ('throttle_factor', 'Yavaşlatma hız oranı (0–1)'),
  ];
  late final _c = {for (final (k, _) in _alanlar) k: TextEditingController(text: metin(widget.varsayilan[k]))};
  bool _mesgul = false;
  String? _hata, _alan;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    final govde = <String, dynamic>{};
    for (final (k, _) in _alanlar) {
      final s = _c[k]!.text.trim().replaceAll(',', '.');
      final num? n = const {'throttle_bounce_rate', 'throttle_factor'}.contains(k) ? double.tryParse(s) : int.tryParse(s);
      if (n == null || n < 0) {
        setState(() {
          _alan = k;
          _hata = 'Geçersiz değer';
        });
        return;
      }
      govde[k] = n;
    }
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    try {
      await Uyg.api.put('/api/v1/tenants/defaults', govde);
      bildir('Varsayılanlar kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Platform varsayılanları', style: gosterim(19, agirlik: FontWeight.w600)),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Kendi sınırı olmayan tüm müşterilere uygulanır.', style: TextStyle(color: context.r.soluk, fontSize: 13)),
            const SizedBox(height: 8),
            Izgara(
              enAz: 200,
              bosluk: 10,
              children: [
                for (final (k, etiket) in _alanlar)
                  TextField(
                    controller: _c[k],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: etiket, isDense: true, errorText: _alan == k ? (_hata ?? 'Geçersiz değer') : null),
                  ),
              ],
            ),
            if (_hata != null && _alan == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
    ],
  );
}
