import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/secimler.dart';
import '../veri/json.dart';
import 'koruma_ortak.dart';

const _modEtiketi = {
  'platform': 'Platform ayarı',
  'on': 'Açık (ilk kez görülen her üçlü)',
  'suspicious': 'Yalnızca şüpheli (spam puanı eşiği)',
  'off': 'Kapalı',
};

String _sure(Object? v) {
  if (v is! num) return '—';
  final s = v.toDouble();
  if (s < 90) return '${s.round()} sn';
  if (s < 5400) return '${(s / 60).round()} dk';
  return '${(s / 3600).toStringAsFixed(1).replaceAll('.', ',')} sa';
}

/// Platform politikası notu: müşteriler bu ayarları yalnızca görür.
class PlatformPolitikasiNotu extends StatelessWidget {
  const PlatformPolitikasiNotu({super.key, this.metin});
  final String? metin;
  @override
  Widget build(BuildContext context) => Bant(
    metin ?? 'Bu ayar platform yöneticisi tarafından belirlenir; değişiklik için hizmet sağlayıcınıza başvurun.',
    renk: Marka.mavi,
    ikon: Icons.lock_outline_rounded,
  );
}

/// Greylisting: istatistikler, saatlik grafik, tekrar denemeyen ağlar, müşteri modu ve platform ayarı.
class GreylistEkrani extends StatefulWidget {
  const GreylistEkrani({super.key});
  @override
  State<GreylistEkrani> createState() => _GreylistEkraniState();
}

class _GreylistEkraniState extends State<GreylistEkrani> {
  int _saat = 24;
  String? _orgId, _orgAdi;
  final _yukleme = GlobalKey<TekYuklemeState<Map<String, dynamic>>>();
  Timer? _zamanlayici;

  @override
  void initState() {
    super.initState();
    _zamanlayici = Timer.periodic(const Duration(seconds: 60), (_) => _yukleme.currentState?.yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  String? get _modOrg => Uyg.musteri ? metinYa(Uyg.ben.value?['organization_id']) : _orgId;

  Future<void> _musteriFiltresi() async {
    if (_orgId != null) {
      setState(() => _orgId = _orgAdi = null);
      await _yukleme.currentState?.yenile();
      return;
    }
    final o = await musteriSec(context);
    if (o == null) return;
    setState(() {
      _orgId = o.id;
      _orgAdi = o.ad;
    });
    await _yukleme.currentState?.yenile();
  }

  @override
  Widget build(BuildContext context) {
    return Iskelet(
      baslik: 'Greylisting',
      alt: 'İlk kez görülen gönderen üçlüsü birkaç dakika geçici olarak reddedilir',
      yenile: () => _yukleme.currentState?.yenile(),
      govde: TekYukleme<Map<String, dynamic>>(
        key: _yukleme,
        getir: () async => harita(await Uyg.api.get('/api/v1/greylist/stats', q: {'hours': '$_saat', 'organization_id': ?_orgId})),
        icerik: _icerik,
      ),
    );
  }

  Widget _icerik(BuildContext c, Map<String, dynamic> s, Future<void> Function() yenile) {
    final r = c.r;
    final ayar = harita(s['settings']);
    final aglar = haritalar(s['top_never_retried']);
    final modOrg = _modOrg;
    return IcerikListesi(
      children: [
        const SizedBox(height: 8),
        Text(
          'İlk kez görülen gönderen üçlüsü (IP ağı, gönderen, alıcı) geçici olarak reddedilir. Gerçek posta sunucuları tekrar dener ve teslim yalnızca gecikir; '
          'spam araçlarının çoğu tekrar denemez.',
          style: TextStyle(color: r.silik, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SecimCipleri<int>(
              secenekler: const [(24, 'Son 24 saat'), (72, 'Son 3 gün'), (168, 'Son 7 gün'), (720, 'Son 30 gün')],
              secili: _saat,
              secildi: (v) {
                setState(() => _saat = v);
                yenile();
              },
            ),
            if (!Uyg.musteri)
              InputChip(
                avatar: const Icon(Icons.business_rounded, size: 17),
                label: Text(_orgAdi ?? 'Tüm müşteriler'),
                selected: _orgId != null,
                showCheckmark: false,
                onPressed: _musteriFiltresi,
                onDeleted: _orgId == null ? null : _musteriFiltresi,
                deleteButtonTooltipMessage: 'Filtreyi kaldır',
              ),
            mantik(ayar['enabled'])
                ? Rozet(
                    'Platformda açık · ${metin(ayar['mode']) == 'on' ? 'tümü' : 'şüpheli ≥ ${metin(ayar['score'])}'}',
                    renk: Marka.zumrut,
                    ikon: Icons.check_circle_outline_rounded,
                  )
                : const Rozet('Platformda kapalı', renk: Marka.kehribar),
          ],
        ),
        const SizedBox(height: 12),
        Izgara(
          enAz: 200,
          children: [
            KpiKarti(
              ikon: Icons.hourglass_top_rounded,
              etiket: 'Geciktirilen',
              deger: sayiYaz(tamsayi(s['delayed'])),
              alt: 'geçici ret (451 4.7.1)',
              renk: Marka.mavi,
            ),
            KpiKarti(
              ikon: Icons.check_circle_outline_rounded,
              etiket: 'Tekrar deneyip geçen',
              deger: sayiYaz(tamsayi(s['passed'])),
              alt: 'ortanca bekleme ${_sure(s['median_delay_s'])}',
              renk: Marka.zumrut,
            ),
            KpiKarti(
              ikon: Icons.do_not_disturb_on_outlined,
              etiket: 'Hiç tekrar denemeyen',
              deger: sayiYaz(tamsayi(s['never_retried'])),
              alt: '${metin(ayar['pass_hours'])} saatlik pencere doldu',
              renk: Marka.gul,
            ),
            KpiKarti(
              ikon: Icons.pending_outlined,
              etiket: 'Beklemede',
              deger: sayiYaz(tamsayi(s['pending'])),
              alt: 'pencere henüz dolmadı',
              renk: Marka.kehribar,
            ),
          ],
        ),
        const SizedBox(height: 16),
        YanYana(
          esik: 900,
          bosluk: 16,
          children: [
            BolumKarti(
              baslik: 'Saatlik',
              ikon: Icons.bar_chart_rounded,
              altBaslik: 'Geciktirilen (gri) ve sonradan geçen (yeşil) üçlüler.',
              child: _GreylistGrafigi(seri: haritalar(s['timeline'])),
            ),
            BolumKarti(
              baslik: 'Tekrar denemeyen ağlar',
              ikon: Icons.lan_outlined,
              altBaslik: 'Büyük olasılıkla spam aracı. Saldırı Haritası\'nda da görünür.',
              child: aglar.isEmpty
                  ? Text('Veri yok.', style: TextStyle(color: r.soluk))
                  : Column(
                      children: [
                        for (final n in aglar)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: metin(n['net']),
                                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                                        ),
                                        TextSpan(
                                          text: '  ${metin(n['country'])}',
                                          style: TextStyle(color: r.silik, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(sayiYaz(tamsayi(n['count'])), style: TextStyle(color: r.soluk, fontSize: 12.5)),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (modOrg != null)
          _MusteriModu(key: ValueKey(modOrg), orgId: modOrg, orgAdi: _orgAdi)
        else if (!Uyg.musteri)
          Bant(
            'Bir müşterinin greylisting modunu değiştirmek için yukarıdan müşteri seçin.',
            ikon: Icons.touch_app_outlined,
            eylem: TextButton(onPressed: _musteriFiltresi, child: const Text('Müşteri seç')),
          ),
        if (Uyg.platformYoneticisi) ...[const SizedBox(height: 16), const _PlatformAyari()],
      ],
    );
  }
}

class _GreylistGrafigi extends StatelessWidget {
  const _GreylistGrafigi({required this.seri});
  final List<Map<String, dynamic>> seri;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (seri.isEmpty) return Text('Bu aralıkta kayıt yok.', style: TextStyle(color: r.soluk));
    final enCok = seri.fold<int>(1, (a, p) => tamsayi(p['delayed']) > a ? tamsayi(p['delayed']) : a);
    final gun = seri.length > 48;
    final bicim = DateFormat(gun ? 'd MMM' : 'HH:mm', 'tr_TR');
    final tam = DateFormat('d MMM HH:mm', 'tr_TR');
    String zaman(int i, DateFormat b) {
      final t = tarihOku(seri[i]['hour']);
      return t == null ? '' : b.format(t);
    }

    final adim = (seri.length / 6).ceil().clamp(1, 1000);
    final gri = r.koyu ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: enCok * 1.1,
          alignment: BarChartAlignment.spaceBetween,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: r.kenar, strokeWidth: 1, dashArray: const [4, 4]),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (v, m) => Text(sayiYaz(v.round()), style: TextStyle(color: r.silik, fontSize: 10.5)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, m) {
                  final i = v.round();
                  if (i < 0 || i >= seri.length || i % adim != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(zaman(i, bicim), style: TextStyle(color: r.silik, fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Marka.grafit,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                '${zaman(g.x, tam)}\n${tamsayi(seri[g.x]['delayed'])} geciktirildi · ${tamsayi(seri[g.x]['passed'])} geçti',
                const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          barGroups: [
            for (final (i, p) in seri.indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: tamsayi(p['delayed']).toDouble(),
                    width: (300 / seri.length).clamp(2, 12).toDouble(),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    color: gri,
                    rodStackItems: [
                      BarChartRodStackItem(0, tamsayi(p['passed']).clamp(0, tamsayi(p['delayed'])).toDouble(), Marka.zumrut),
                      BarChartRodStackItem(tamsayi(p['passed']).clamp(0, tamsayi(p['delayed'])).toDouble(), tamsayi(p['delayed']).toDouble(), gri),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Müşteri greylisting modu (GET/PUT /api/v1/greylist/orgs/{id}).
class _MusteriModu extends StatefulWidget {
  const _MusteriModu({super.key, required this.orgId, this.orgAdi});
  final String orgId;
  final String? orgAdi;
  @override
  State<_MusteriModu> createState() => _MusteriModuState();
}

class _MusteriModuState extends State<_MusteriModu> {
  String? _mod;
  final _puan = TextEditingController();
  bool _mesgul = false;
  String? _hata;

  // Greylisting platform politikasıdır: müşteriler yalnızca görür.
  bool get _yonetir => !Uyg.musteri && Uyg.yetki('spam.manage');

  @override
  void dispose() {
    _puan.dispose();
    super.dispose();
  }

  void _doldur(Map<String, dynamic> d) {
    _mod = metin(d['mode'], 'platform');
    _puan.text = metin(d['score']);
  }

  @override
  Widget build(BuildContext context) => GomuluYukleme<Map<String, dynamic>>(
    getir: () async {
      final d = harita(await Uyg.api.get('/api/v1/greylist/orgs/${widget.orgId}'));
      _doldur(d);
      return d;
    },
    icerik: (c, d, yenile) {
      final r = c.r;
      final platform = mantik(d['platform_enabled'])
          ? (metin(d['platform_mode']) == 'on' ? 'açık (tümü)' : 'yalnızca şüpheli (puan ≥ ${metin(d['platform_score'])})')
          : 'kapalı';
      return BolumKarti(
        baslik: widget.orgAdi == null ? 'Müşteri modu' : 'Müşteri modu · ${widget.orgAdi}',
        ikon: Icons.tune_rounded,
        altBaslik:
            'Platform ayarı şu an: $platform. Birden çok müşteriye giden iletide alıcılardan birinin modu gerektiriyorsa ileti geciktirilir. '
            'Gecikme yalnızca ilk iletide olur.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mod',
              style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _modEtiketi.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _mod == e.key,
                    showCheckmark: false,
                    onSelected: _yonetir ? (_) => setState(() => _mod = e.key) : null,
                  ),
              ],
            ),
            if (_mod == 'suspicious') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _puan,
                  enabled: _yonetir,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Spam puanı eşiği', helperText: '0–50'),
                ),
              ),
            ],
            if (_hata != null) ...[const SizedBox(height: 10), Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded)],
            const SizedBox(height: 12),
            if (_yonetir)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _mesgul
                      ? null
                      : () async {
                          final puan = double.tryParse(_puan.text.trim().replaceAll(',', '.'));
                          if (puan == null || puan < 0 || puan > 50) {
                            setState(() => _hata = 'Puan 0–50 arasında olmalı');
                            return;
                          }
                          setState(() {
                            _mesgul = true;
                            _hata = null;
                          });
                          try {
                            final v = harita(await Uyg.api.put('/api/v1/greylist/orgs/${widget.orgId}', {'mode': _mod, 'score': puan}));
                            bildir('Kaydedildi', tur: MesajTur.basari);
                            setState(() => _doldur(v));
                          } catch (e) {
                            setState(() => _hata = hataMetni(e));
                          } finally {
                            if (mounted) setState(() => _mesgul = false);
                          }
                        },
                  child: mesgulYazi(_mesgul, 'Kaydet'),
                ),
              )
            else
              const PlatformPolitikasiNotu(),
          ],
        ),
      );
    },
  );
}

/// Platform greylisting ayarı (yalnızca süper yönetici; PATCH /api/v1/security2/settings {greylist}).
class _PlatformAyari extends StatefulWidget {
  const _PlatformAyari();
  @override
  State<_PlatformAyari> createState() => _PlatformAyariState();
}

class _PlatformAyariState extends State<_PlatformAyari> {
  Map<String, dynamic> _g = {};
  final _puan = TextEditingController(), _bekleme = TextEditingController(), _pencere = TextEditingController();
  final _izinSayisi = TextEditingController(), _izinGun = TextEditingController(), _ptr = TextEditingController(), _asn = TextEditingController();
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    for (final k in [_puan, _bekleme, _pencere, _izinSayisi, _izinGun, _ptr, _asn]) {
      k.dispose();
    }
    super.dispose();
  }

  void _doldur(Map<String, dynamic> g) {
    _g = Map.of(g);
    _puan.text = metin(g['score']);
    _bekleme.text = metin(g['delay_seconds']);
    _pencere.text = metin(g['pass_hours']);
    _izinSayisi.text = metin(g['whitelist_after']);
    _izinGun.text = metin(g['whitelist_days']);
    _ptr.text = metinler(g['provider_ptr']).join('\n');
    _asn.text = metinler(g['provider_asn']).join('\n');
  }

  Future<void> _kaydet() async {
    final puan = double.tryParse(_puan.text.trim().replaceAll(',', '.'));
    final bekleme = aralikta(_bekleme.text, 30, 3600), pencere = aralikta(_pencere.text, 1, 168);
    final izinSayisi = aralikta(_izinSayisi.text, 1, 100), izinGun = aralikta(_izinGun.text, 1, 365);
    final asn = [
      for (final s in _asn.text.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty)) int.tryParse(s.replaceFirst(RegExp('^AS', caseSensitive: false), '')),
    ];
    if (puan == null || puan < 0 || puan > 50 || bekleme == null || pencere == null || izinSayisi == null || izinGun == null) {
      setState(() => _hata = 'Bekleme 30–3600 sn, geçiş penceresi 1–168 saat, beyaz liste 1–100 geçiş / 1–365 gün, puan 0–50 olmalı');
      return;
    }
    if (asn.contains(null)) {
      setState(() => _hata = 'Geçersiz AS numarası');
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final v = harita(
        await Uyg.api.patch('/api/v1/security2/settings', {
          'greylist': {
            ..._g,
            'score': puan,
            'delay_seconds': bekleme,
            'pass_hours': pencere,
            'whitelist_after': izinSayisi,
            'whitelist_days': izinGun,
            'provider_ptr': _ptr.text.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList(),
            'provider_asn': asn,
          },
        }),
      );
      bildir('Kaydedildi', tur: MesajTur.basari);
      if (v['greylist'] is Map) setState(() => _doldur(harita(v['greylist'])));
    } catch (e) {
      setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) => GomuluYukleme<Map<String, dynamic>>(
    getir: () async {
      final v = harita(await Uyg.api.get('/api/v1/security2/settings'));
      _doldur(harita(v['greylist']));
      return v;
    },
    icerik: (c, v, yenile) {
      final r = c.r;
      return BolumKarti(
        baslik: 'Platform ayarı',
        ikon: Icons.admin_panel_settings_outlined,
        altBaslik:
            'İlk kez görülen (IP ağı /24 veya /64, gönderen, alıcı) üçlüsü 451 4.7.1 ile geçici olarak reddedilir. Kimliği doğrulanmış gönderim, izin listeleri, '
            'kendi IP\'lerimiz, iyi itibarlı IP\'ler, SPF/DKIM ile doğrulanmış bilinen gönderenler ve büyük sağlayıcılar (PTR/ASN) atlanır.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Greylisting açık'),
              value: mantik(_g['enabled']),
              onChanged: (b) => setState(() => _g['enabled'] = b),
            ),
            Text(
              'Mod',
              style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            SecimCipleri<String>(
              secenekler: const [('suspicious', 'Yalnızca şüpheli iletiler'), ('on', 'Tüm ilk kez görülenler')],
              secili: metin(_g['mode'], 'suspicious'),
              secildi: (m) => setState(() => _g['mode'] = m),
            ),
            const SizedBox(height: 12),
            Izgara(
              enAz: 200,
              children: [
                TextField(
                  controller: _puan,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Şüpheli eşiği (spam puanı)'),
                ),
                SayiAlani(denetleyici: _bekleme, etiket: 'Bekleme (saniye)', sonEk: '30–3600'),
                SayiAlani(denetleyici: _pencere, etiket: 'Geçiş penceresi (saat)'),
                SayiAlani(denetleyici: _izinSayisi, etiket: 'Otomatik izin (geçiş sayısı)'),
                SayiAlani(denetleyici: _izinGun, etiket: 'Otomatik izin süresi (gün)'),
              ],
            ),
            const SizedBox(height: 12),
            YanYana(
              esik: 600,
              children: [
                TextField(
                  controller: _ptr,
                  minLines: 4,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                  decoration: const InputDecoration(
                    labelText: 'Sağlayıcı PTR sonekleri',
                    helperText: 'Satır başına bir sonek (ör. google.com)',
                    alignLabelWithHint: true,
                  ),
                ),
                TextField(
                  controller: _asn,
                  minLines: 4,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                  decoration: const InputDecoration(labelText: 'Sağlayıcı ASN\'leri', helperText: 'Satır başına bir ASN (ör. 15169)', alignLabelWithHint: true),
                ),
              ],
            ),
            if (_hata != null) ...[const SizedBox(height: 10), Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded)],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _mesgul ? null : _kaydet, child: mesgulYazi(_mesgul, 'Kaydet')),
            ),
          ],
        ),
      );
    },
  );
}
