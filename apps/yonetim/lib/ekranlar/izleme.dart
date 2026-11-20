import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/trafik_grafigi.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/operasyon.dart';
import 'altyapi_ortak.dart';
import 'bolumler.dart';
import '../ortak/simgeler.dart';

/// İzleme (platform): bileşen sağlığı (10 sn), teslimat uyarıları, gateway uyarıları, 48 saatlik trafik ve bugünkü sayılar.
/// web: admin/(panel)/monitoring + delivery/monitor-alerts.
class IzlemeEkrani extends StatefulWidget {
  const IzlemeEkrani({super.key});

  @override
  State<IzlemeEkrani> createState() => _IzlemeEkraniState();
}

class _IzlemeEkraniState extends State<IzlemeEkrani> {
  List<Map<String, dynamic>>? _bilesenler;
  DateTime? _denetim;
  String? _saglikHatasi;
  Ozet? _ozet;
  List<TrafikDilimi>? _trafik;
  List<Map<String, dynamic>>? _uyarilar;
  List<Map<String, dynamic>> _gwUyarilar = [];
  bool _yukleniyor = false;
  Timer? _saglikZamanlayici, _genelZamanlayici;

  @override
  void initState() {
    super.initState();
    _yukle();
    _saglikZamanlayici = Timer.periodic(const Duration(seconds: 10), (_) => _saglik());
    _genelZamanlayici = Timer.periodic(const Duration(seconds: 60), (_) => _yukle(sessiz: true));
  }

  @override
  void dispose() {
    _saglikZamanlayici?.cancel();
    _genelZamanlayici?.cancel();
    super.dispose();
  }

  Future<Object?> _dene(Future<dynamic> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saglik() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/health'));
      if (!mounted) return;
      setState(() {
        _bilesenler = haritalar(v['components']);
        _denetim = tarihOku(v['checked_at']);
        _saglikHatasi = null;
      });
    } catch (e) {
      if (mounted) setState(() => _saglikHatasi = hataMetni(e));
    }
  }

  Future<void> _yukle({bool sessiz = false}) async {
    if (!sessiz) setState(() => _yukleniyor = true);
    final api = Uyg.api;
    final s = await Future.wait<Object?>([
      _saglik(),
      _dene(() => api.get('/api/v1/stats/overview')),
      _dene(() => api.get('/api/v1/stats/traffic', q: {'hours': '48'})),
      _dene(() => api.get('/api/v1/monitor/alerts', q: {'hours': '72'})),
      _dene(() => api.get('/api/v1/gateway/alerts', q: {'limit': '10'})),
    ]);
    if (!mounted) return;
    setState(() {
      _yukleniyor = false;
      if (s[1] != null) _ozet = Ozet(harita(s[1]));
      _trafik = s[2] == null ? (_trafik ?? []) : TrafikDilimi.coz(s[2]);
      if (s[3] != null) _uyarilar = haritalar(harita(s[3])['items']);
      _uyarilar ??= [];
      if (s[4] != null) _gwUyarilar = haritalar(harita(s[4])['items']);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Iskelet(
      baslik: 'İzleme',
      alt: 'Bileşen sağlığı (10 sn) ve posta akışı (saatlik)',
      yenile: _yukleniyor ? null : _yukle,
      govde: RefreshIndicator.adaptive(
        onRefresh: _yukle,
        child: IcerikListesi(
          children: [
            _durumBandi(context),
            const SizedBox(height: 12),
            ButunlukUyarisi(ayrintilar: () => bolumeGit(Bolum.yedekleme)),
            _teslimatUyarilari(context),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (c, k) {
                final bilesen = _bilesenKarti(c);
                final sag = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_trafikKarti(c), const SizedBox(height: 12), _bugunKarti(c)]);
                if (k.maxWidth < 900) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [bilesen, const SizedBox(height: 12), sag]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: bilesen),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: sag),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Eşik tabanlı uyarılar ve bildirim kanalları (e-posta, webhook, panel) Uyarılar bölümündedir.',
              style: TextStyle(color: context.r.silik, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _durumBandi(BuildContext context) {
    final b = _bilesenler;
    if (b == null) {
      return _saglikHatasi != null
          ? Bant(_saglikHatasi!, renk: Marka.gul, ikon: Simgeler.cloudOff)
          : const Bant('Kontrol ediliyor…', ikon: Simgeler.hourglassTop);
    }
    final kapali = [
      for (final c in b)
        if (metin(c['status']) == 'down') metin(c['name']),
    ];
    final zaman = _denetim == null ? '' : ' (${goreliZaman(_denetim)})';
    if (kapali.isNotEmpty) {
      return Bant('Sorunlu bileşen: ${kapali.map((x) => saglikEtiketleri[x] ?? x).join(', ')}$zaman', renk: Marka.gul, ikon: Simgeler.errorOutline);
    }
    return Bant('Tüm çalışan bileşenler sağlıklı.$zaman', renk: Marka.zumrut, ikon: Simgeler.checkCircleOutline);
  }

  Widget _bilesenKarti(BuildContext context) {
    final r = context.r;
    final b = _bilesenler;
    return BolumKarti(
      baslik: 'Bileşenler',
      ikon: Simgeler.memory,
      child: b == null
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator.adaptive()))
          : Column(
              children: [
                for (final (i, c) in b.indexed) ...[
                  if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        DurumNoktasi(switch (metin(c['status'])) {
                          'ok' => Marka.zumrut,
                          'down' => Marka.gul,
                          _ => r.silik,
                        }),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                saglikEtiketleri[metin(c['name'])] ?? metin(c['name']),
                                style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                              Text(
                                metin(c['name']),
                                style: TextStyle(color: r.silik, fontSize: 11.5, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _bilesenDetay(c),
                            textAlign: TextAlign.end,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: r.soluk, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  String _bilesenDetay(Map<String, dynamic> c) {
    final d = metin(c['status']);
    final gecikme = ondalikYa(c['latency_ms']);
    final detay = metinYa(c['detail']);
    if (d == 'ok') return gecikme != null ? '${gecikme.toStringAsFixed(1).replaceAll('.', ',')} ms' : (detay ?? 'çalışıyor');
    if (d == 'disabled') return detay ?? 'devre dışı';
    return detay ?? d;
  }

  Widget _trafikKarti(BuildContext context) => BolumKarti(
    baslik: 'Posta akışı',
    altBaslik: 'Son 48 saat (saatlik)',
    ikon: Simgeler.showChart,
    child: _trafik == null ? const SizedBox(height: 190, child: Center(child: CircularProgressIndicator.adaptive())) : TrafikGrafigi(dilimler: _trafik!),
  );

  Widget _bugunKarti(BuildContext context) {
    final o = _ozet;
    String s(int? v) => v == null ? '—' : sayiYaz(v);
    return BolumKarti(
      baslik: 'Bugün',
      altBaslik: 'Canlı değerler (mesaj takibi kayıtlarından)',
      ikon: Simgeler.today,
      child: Izgara(
        enAz: 120,
        children: [
          SayacKutusu(etiket: 'Kabul', deger: s(o?.alinan)),
          SayacKutusu(etiket: 'Teslim', deger: s(o?.teslim)),
          SayacKutusu(etiket: 'Ret', deger: s(o?.reddedilen)),
          SayacKutusu(etiket: 'Başarısız', deger: s(o?.basarisiz), kotu: (o?.basarisiz ?? 0) > 0),
        ],
      ),
    );
  }

  Widget _teslimatUyarilari(BuildContext context) {
    final r = context.r;
    final u = _uyarilar;
    final acik = u?.where((a) => metinYa(a['current_status']) != null && a['current_status'] == a['status']).length ?? 0;
    return BolumKarti(
      baslik: 'Teslimat uyarıları',
      altBaslik: 'Son 72 saatte kötüleşen Monitor denetimleri${u == null ? '' : ' · $acik açık'}',
      ikon: Simgeler.reportProblem,
      sag: TextButton(onPressed: () => bolumeGit(Bolum.teslimatSorunlari), child: const Text('Teslimat Sorunları')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (u == null)
            const SizedBox(height: 60, child: Center(child: CircularProgressIndicator.adaptive()))
          else if (u.isEmpty)
            Text('Uyarı yok: son 72 saatte kötüleşen denetim olmadı.', style: TextStyle(color: r.soluk, fontSize: 13))
          else
            for (final (i, a) in u.take(12).indexed) ...[if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)), _uyariSatiri(context, a)],
          if (_gwUyarilar.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Gateway uyarıları',
                    style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ),
                if (Bolum.gateway.gorunur) TextButton(onPressed: () => bolumeGit(Bolum.gateway), child: const Text('Mail Gateway')),
              ],
            ),
            for (final (i, a) in _gwUyarilar.indexed) ...[if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)), _gwSatiri(context, a)],
          ],
        ],
      ),
    );
  }

  Widget _uyariSatiri(BuildContext context, Map<String, dynamic> a) {
    final r = context.r;
    final hedef = metin(a['target']);
    final once = metinYa(a['prev_status']);
    final simdi = metinYa(a['current_status']);
    final durum = metin(a['status']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                hedef == 'platform' ? 'Platform' : hedef,
                style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              Text('·', style: TextStyle(color: r.silik)),
              Text(metin(a['label']), style: TextStyle(color: r.metin, fontSize: 13.5)),
              if (once != null) MonRozeti(once),
              Icon(SimgelerKalin.arrowForward, size: 14, color: r.silik),
              MonRozeti(durum),
              if (simdi != null && simdi != durum) ...[Text('şimdi', style: TextStyle(color: r.silik, fontSize: 12)), MonRozeti(simdi)],
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  metin(a['detail']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: r.soluk, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(tamZaman(tarihOku(a['at'])), style: TextStyle(color: r.silik, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }

  static const _gwEtiketleri = {
    'target_down': 'Hedef kapandı',
    'target_up': 'Hedef düzeldi',
    'target_half_open': 'Yoklama başarılı',
    'all_down': 'Tüm hedefler kapalı',
    'recovered': 'Teslim yeniden başladı',
    'continuity_on': 'Kesinti modu açıldı',
    'continuity_off': 'Kesinti modu kapandı',
    'continuity_quota': 'Kesinti modu kotası doldu',
  };

  Widget _gwSatiri(BuildContext context, Map<String, dynamic> a) {
    final r = context.r;
    final ciddiyet = metin(a['severity']);
    final tur = metin(a['kind']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Rozet(_gwEtiketleri[tur] ?? tur, renk: ciddiyet == 'critical' ? Marka.gul : (ciddiyet == 'warning' ? Marka.kehribar : r.soluk)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metin(a['domain']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Text(goreliZaman(tarihOku(a['at'])), style: TextStyle(color: r.silik, fontSize: 11.5)),
            ],
          ),
          if (metinYa(a['message']) != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                metin(a['message']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: r.soluk, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
