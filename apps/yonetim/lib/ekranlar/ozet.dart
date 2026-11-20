import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/trafik_grafigi.dart';
import '../veri/bicim.dart';
import '../veri/denetim.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import '../veri/operasyon.dart';
import 'bolumler.dart';

/// Gösterge paneli (web: admin/(panel)/page.tsx). Her değer canlı bir uç noktadan gelir; platform genelindeki kartlar
/// (sunucu, teslimat motoru) yalnızca süper yöneticiye gösterilir.
class OzetEkrani extends StatefulWidget {
  const OzetEkrani({super.key});
  @override
  State<OzetEkrani> createState() => _OzetEkraniState();
}

class _OzetEkraniState extends State<OzetEkrani> {
  Ozet? _ozet;
  String? _hata;
  List<TrafikDilimi>? _trafik;
  int _saat = 24;
  List<EtkinAlarm>? _alarmlar;
  List<Map<String, dynamic>>? _saglik;
  DateTime? _saglikZamani;
  Map<String, dynamic>? _sistem;
  Map<String, dynamic>? _motor;
  List<DenetimKaydi>? _islemler;
  bool _yukleniyor = false;

  bool get _platform => Uyg.platformYoneticisi && Uyg.ben.value?['impersonation'] == null;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<Object?> _dene(Future<dynamic> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    final api = Uyg.api;
    final sonuc = await Future.wait<Object?>([
      api.get('/api/v1/stats/overview').then<Object?>((v) => v).catchError((Object e) => e),
      _dene(() => api.get('/api/v1/stats/traffic', q: {'hours': '$_saat'})),
      _dene(() => api.get('/api/v1/alerts/active')),
      _dene(() => api.get('/api/v1/health')),
      _platform ? _dene(() => api.get('/api/v1/system')) : Future.value(null),
      _platform ? _dene(() => api.get('/api/v1/outbound/engine')) : Future.value(null),
      Uyg.yetki('audit.view') ? _dene(() => api.get('/api/v1/audit-logs', q: {'page_size': '6'})) : Future.value(null),
    ]);
    if (!mounted) return;
    setState(() {
      _yukleniyor = false;
      final o = sonuc[0];
      if (o is Map) {
        _ozet = Ozet(harita(o));
        _hata = null;
      } else {
        _hata = hataMetni(o ?? 'yok');
      }
      if (sonuc[1] != null) _trafik = TrafikDilimi.coz(sonuc[1]);
      if (sonuc[2] != null) _alarmlar = haritalar(harita(sonuc[2])['items']).map(EtkinAlarm.coz).toList();
      if (sonuc[3] != null) {
        _saglik = haritalar(harita(sonuc[3])['components']);
        _saglikZamani = tarihOku(harita(sonuc[3])['checked_at']);
      }
      final s = haritalar(harita(sonuc[4])['nodes']);
      _sistem = s.isEmpty ? null : s.first;
      _motor = sonuc[5] == null ? null : harita(sonuc[5]);
      if (sonuc[6] != null) _islemler = Sayfa.coz(sonuc[6], DenetimKaydi.coz).ogeler;
    });
  }

  Future<void> _trafikDegis(int saat) async {
    setState(() {
      _saat = saat;
      _trafik = null;
    });
    final v = await _dene(() => Uyg.api.get('/api/v1/stats/traffic', q: {'hours': '$saat'}));
    if (mounted && saat == _saat) setState(() => _trafik = v == null ? [] : TrafikDilimi.coz(v));
  }

  String _selam() {
    final h = DateTime.now().hour;
    final p = h < 6 ? 'İyi geceler' : (h < 12 ? 'Günaydın' : (h < 18 ? 'İyi günler' : 'İyi akşamlar'));
    final ad = Uyg.ad.trim().split(RegExp(r'\s+')).first;
    return ad.isEmpty ? p : '$p, $ad';
  }

  @override
  Widget build(BuildContext context) {
    final genislik = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Özet'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _yukleniyor ? null : _yukle,
            icon: _yukleniyor ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2)) : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _ozet == null && _hata == null
          ? const Durum.yukleniyor()
          : _ozet == null
          ? Durum.hata(_hata!, tekrar: _yukle)
          : RefreshIndicator.adaptive(
              onRefresh: _yukle,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(genislik >= 700 ? 24 : 12, 0, genislik >= 700 ? 24 : 12, 28),
                children: _icerik(context, _ozet!),
              ),
            ),
    );
  }

  List<Widget> _icerik(BuildContext context, Ozet o) {
    final r = context.r;
    final genis = MediaQuery.sizeOf(context).width >= 1200;
    final alarmSay = _alarmlar?.length;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_selam(), style: gosterim(22, agirlik: FontWeight.w700)),
            Text('${Uyg.panelAdi} · ${DateFormat('d MMMM EEEE', 'tr_TR').format(DateTime.now())} · canlı veri', style: TextStyle(color: r.silik, fontSize: 13)),
          ],
        ),
      ),
      if (_hata != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Bant('Özet yenilenemedi: $_hata', renk: Marka.gul, ikon: Icons.cloud_off_rounded),
        ),
      Izgara(
        enAz: 160,
        children: [
          if (Uyg.ortak)
            IstatistikKarti(
              ikon: Icons.apartment_rounded,
              etiket: 'Müşteriler',
              deger: sayiYaz(o.musteriler),
              alt: 'kayıtlı müşteri',
              onTap: () => bolumeGit(Bolum.musteriler),
            ),
          IstatistikKarti(
            ikon: Icons.language_rounded,
            etiket: 'Alan adları',
            deger: sayiYaz(o.alanlar),
            alt: '${o.bekleyenAlanlar} bekliyor · ${o.gatewayAlanlari} gateway',
            onTap: () => bolumeGit(Bolum.alanlar),
          ),
          if (Bolum.kutular.gorunur)
            IstatistikKarti(
              ikon: Icons.inbox_rounded,
              etiket: 'Posta kutuları',
              deger: sayiYaz(o.aktifKutular),
              alt: 'toplam ${sayiYaz(o.kutular)}',
              onTap: () => bolumeGit(Bolum.kutular),
            ),
          IstatistikKarti(
            ikon: Icons.storage_rounded,
            etiket: 'Depolama',
            deger: boyutYaz(o.kullanilan),
            ek: KullanimCubugu(kullanilan: o.kullanilan, toplam: o.ayrilan, yazi: false, kalinlik: 5),
            alt: '${boyutYaz(o.ayrilan)} tahsis',
          ),
          IstatistikKarti(
            ikon: Icons.format_list_numbered_rounded,
            etiket: 'Kuyruk',
            deger: o.kuyruk == null ? '—' : sayiYaz(o.kuyruk),
            alt: o.kuyruk == null ? (o.yok['queue_depth'] ?? 'veri yok') : 'bekleyen ileti',
            onTap: Bolum.kuyruk.gorunur ? () => bolumeGit(Bolum.kuyruk) : null,
          ),
          IstatistikKarti(
            ikon: Icons.notifications_active_rounded,
            etiket: 'Etkin uyarılar',
            deger: alarmSay == null ? '—' : sayiYaz(alarmSay),
            alt: 'eşik aşan kurallar',
            renk: (alarmSay ?? 0) > 0 ? Marka.kehribar : null,
            onTap: () => bolumeGit(Bolum.alarmlar),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (genis)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _trafikKarti(o)),
            const SizedBox(width: 14),
            Expanded(child: _dikkatKarti(o)),
          ],
        )
      else ...[
        _trafikKarti(o),
        const SizedBox(height: 14),
        _dikkatKarti(o),
      ],
      if (_platform && (_sistem != null || _motor != null)) ...[
        const SizedBox(height: 14),
        Izgara(enAz: 340, children: [if (_sistem != null) _sunucuKarti(_sistem!), if (_motor != null) _motorKarti(_motor!)]),
      ],
      const SizedBox(height: 14),
      Izgara(enAz: 340, children: [if (_saglik != null) _saglikKarti(), if (_islemler != null) _islemlerKarti()]),
    ];
  }

  Widget _trafikKarti(Ozet o) {
    final r = context.r;
    Widget stat(String e, String d, {String? ipucu, Color? renk}) => Tooltip(
      message: ipucu ?? '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(e, style: TextStyle(color: r.silik, fontSize: 11.5)),
          Text(d, style: gosterim(18, renk: renk)),
        ],
      ),
    );
    final oran = o.teslimOrani;
    return BolumKarti(
      baslik: 'Posta trafiği',
      ikon: Icons.show_chart_rounded,
      sag: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: 24, label: Text('24 saat')),
          ButtonSegment(value: 168, label: Text('7 gün')),
        ],
        selected: {_saat},
        onSelectionChanged: (s) => _trafikDegis(s.first),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bugün',
            style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 22,
            runSpacing: 10,
            children: [
              stat('Alınan', sayiYaz(o.alinan)),
              stat('Teslim edilen', sayiYaz(o.teslim)),
              stat('Reddedilen', sayiYaz(o.reddedilen)),
              stat('Gönderilen', sayiYaz(o.gonderilen), ipucu: 'Kimlik doğrulamalı gönderim (alıcı sayısı)'),
              stat('Spam', sayiYaz(o.spam), ipucu: 'Gereksiz klasörüne düşen + reddedilen'),
              if ((o.gateway ?? 0) > 0 || o.gatewayAlanlari > 0) stat('Gateway', sayiYaz(o.gateway), ipucu: 'Müşteri sunucusuna iletilen'),
              oran != null
                  ? stat('Teslim başarısı', yuzdeYaz(oran), ipucu: '${o.basarisiz ?? 0} başarısız', renk: oran < 90 ? Marka.kehribar : Marka.zumrut)
                  : stat('Teslim başarısı', '—', ipucu: o.yok['delivery_success_rate']),
            ],
          ),
          const SizedBox(height: 16),
          _trafik == null ? const SizedBox(height: 190, child: Center(child: CircularProgressIndicator.adaptive())) : TrafikGrafigi(dilimler: _trafik!),
        ],
      ),
    );
  }

  Widget _dikkatKarti(Ozet o) {
    final maddeler = <(Color, String, String?, Bolum)>[];
    for (final a in _alarmlar ?? const <EtkinAlarm>[]) {
      maddeler.add((
        a.kritik ? Marka.gul : Marka.kehribar,
        a.etiket.isEmpty ? a.ad : '${a.ad} · ${a.etiket}',
        [a.ayrinti, suredir(a.baslangic)].where((s) => s.isNotEmpty).join(' · '),
        Bolum.alarmlar,
      ));
    }
    final e = harita(_motor?['engine']);
    if (mantik(e['bulk_paused'])) maddeler.add((Marka.gul, 'Toplu gönderim durduruldu', metinYa(e['pause_reason']), Bolum.kuyruk));
    for (final b in haritalar(_motor?['brakes']).where((b) => mantik(b['active'], true))) {
      final kim = metinYa(b['mailbox']) ?? metinYa(b['organization_name']) ?? 'platform';
      maddeler.add((Marka.kehribar, 'Gönderim freni: $kim', metinYa(b['reason']), Bolum.kuyruk));
    }
    final bekletilen = tamsayi(harita(e['queued'])['held']);
    if (bekletilen > 0) maddeler.add((Marka.kehribar, '$bekletilen ileti bekletiliyor', 'Kuyrukta onay ya da fren bekleyen iletiler', Bolum.kuyruk));
    if (o.bekleyenAlanlar > 0) maddeler.add((Marka.mor, '${o.bekleyenAlanlar} alan adı DNS doğrulaması bekliyor', null, Bolum.alanlar));
    maddeler.sort((a, b) => _sira(a.$1).compareTo(_sira(b.$1)));
    final r = context.r;
    return BolumKarti(
      baslik: 'Dikkat gerektirenler',
      ikon: maddeler.isEmpty ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
      sag: maddeler.isEmpty ? null : Rozet('${maddeler.length}', renk: Marka.kehribar),
      child: maddeler.isEmpty
          ? const Bant('Her şey yolunda; bekleyen bir iş yok.', renk: Marka.zumrut, ikon: Icons.check_circle_outline_rounded)
          : Column(
              children: [
                for (final (renk, baslik, ayrinti, bolum) in maddeler.take(8))
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: bolum.gorunur ? () => bolumeGit(bolum) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, size: 18, color: renk),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  baslik,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                ),
                                if (ayrinti != null && ayrinti.isNotEmpty)
                                  Text(
                                    ayrinti,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: r.silik, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: r.silik, size: 18),
                        ],
                      ),
                    ),
                  ),
                if (maddeler.length > 8) Text('+${maddeler.length - 8} madde daha', style: TextStyle(color: r.silik, fontSize: 12)),
              ],
            ),
    );
  }

  int _sira(Color c) => c == Marka.gul ? 0 : (c == Marka.kehribar ? 1 : 2);

  Widget _sunucuKarti(Map<String, dynamic> n) {
    final r = context.r;
    final yuk = (n['load_avg'] is List ? n['load_avg'] as List : const []).map((v) => ondalik(v).toStringAsFixed(2).replaceAll('.', ',')).join(' · ');
    final bellekTop = tamsayi(n['mem_total']), bellekBos = tamsayi(n['mem_available']);
    final diskler = harita(n['disks']);
    final gorulen = <String>{};
    final diskSatirlari = <Widget>[];
    for (final e in diskler.entries) {
      final d = harita(e.value);
      final top = tamsayi(d['total_bytes']);
      if (top == 0 || !gorulen.add('$top/${d['free_bytes']}')) continue;
      diskSatirlari.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                diskler.length > 1 && gorulen.length > 1 ? metin(d['path']) : 'Disk (posta deposu ve kuyruk)',
                style: TextStyle(color: r.soluk, fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              KullanimCubugu(kullanilan: tamsayi(d['used_bytes']), toplam: top),
            ],
          ),
        ),
      );
    }
    return BolumKarti(
      baslik: 'Sunucu',
      ikon: Icons.dns_rounded,
      altBaslik: '${metin(n['hostname'])} · sürüm ${metin(n['version'], '—')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BilgiSatiri('Çalışma süresi', sureYaz(ondalikYa(n['host_uptime']))),
          BilgiSatiri('Yük ortalaması', yuk.isEmpty ? '—' : '$yuk  (${tamsayi(n['cpus'])} çekirdek)'),
          if (bellekTop > 0) ...[
            Text('Bellek', style: TextStyle(color: r.soluk, fontSize: 12.5)),
            const SizedBox(height: 4),
            KullanimCubugu(kullanilan: bellekTop - bellekBos, toplam: bellekTop),
          ],
          ...diskSatirlari,
        ],
      ),
    );
  }

  Widget _motorKarti(Map<String, dynamic> m) {
    final r = context.r;
    final e = harita(m['engine']);
    if (!mantik(m['available']) || m['engine'] is! Map) {
      return BolumKarti(
        baslik: 'Teslimat motoru',
        ikon: Icons.send_rounded,
        child: Text('Giden posta motoru bu sunucuda çalışmıyor.', style: TextStyle(color: r.silik)),
      );
    }
    final q = harita(e['queued']);
    Widget mini(String a, String d, {Color? renk}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(a, style: TextStyle(color: r.silik, fontSize: 11)),
          Text(
            d,
            style: TextStyle(fontWeight: FontWeight.w700, color: renk),
          ),
        ],
      ),
    );
    final ertele = tamsayi(e['deferred_10m']), hata = tamsayi(e['failed_10m']), bekle = tamsayi(q['held']);
    final mod = metin(e['mode']);
    return BolumKarti(
      baslik: 'Teslimat motoru',
      ikon: Icons.send_rounded,
      altBaslik: 'Mod: ${mod == 'direct' ? 'doğrudan teslim' : mod}${mantik(e['bulk_paused']) ? ' · toplu gönderim durdu' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(sayiYaz(tamsayi(e['delivered_10m'])), style: gosterim(26)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('teslim · son 10 dk', style: TextStyle(color: r.silik, fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              mini('Erteleme', sayiYaz(ertele), renk: ertele > 0 ? Marka.kehribar : null),
              mini('Hata', sayiYaz(hata), renk: hata > 0 ? Marka.gul : null),
              mini('Bağlantı', '${tamsayi(e['running_connections'])}/${tamsayi(e['max_connections'])}'),
              mini('Kuyruk', sayiYaz(tamsayi(q['normal']))),
              mini('Toplu', sayiYaz(tamsayi(q['bulk']))),
              mini('Bekletilen', sayiYaz(bekle), renk: bekle > 0 ? Marka.kehribar : null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _saglikKarti() {
    final r = context.r;
    return BolumKarti(
      baslik: 'Sistem sağlığı',
      ikon: Icons.monitor_heart_outlined,
      altBaslik: _saglikZamani == null ? null : 'Son kontrol ${goreliZaman(_saglikZamani)}',
      child: Column(
        children: [
          for (final c in _saglik!)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: switch (metin(c['status'])) {
                        'ok' => Marka.zumrut,
                        'down' => Marka.gul,
                        _ => r.silik.withValues(alpha: .5),
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(saglikEtiketleri[metin(c['name'])] ?? metin(c['name']), style: const TextStyle(fontSize: 13.5))),
                  Flexible(
                    child: Text(
                      switch (metin(c['status'])) {
                        'ok' =>
                          c['latency_ms'] != null
                              ? '${ondalik(c['latency_ms']).toStringAsFixed(1).replaceAll('.', ',')} ms'
                              : (metinYa(c['detail']) ?? 'çalışıyor'),
                        'down' => 'erişilemiyor',
                        _ => metinYa(c['detail'])?.replaceAll('Phase', 'Faz') ?? 'kapalı',
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(color: r.silik, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _islemlerKarti() {
    final r = context.r;
    return BolumKarti(
      baslik: 'Son işlemler',
      ikon: Icons.receipt_long_rounded,
      sag: TextButton(onPressed: () => bolumeGit(Bolum.denetim), child: const Text('Tümü')),
      child: _islemler!.isEmpty
          ? Text('Henüz kayıt yok.', style: TextStyle(color: r.silik))
          : Column(
              children: [
                for (final a in _islemler!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [denetimEylemi(a.eylem).etiket, denetimHedefi(a.hedefTuru, a.hedefId, a.orgAdi, a.ayrintilar)].whereType<String>().join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: tonRengi(denetimEylemi(a.eylem).ton)),
                              ),
                              Text(
                                [a.aktor.isEmpty ? 'sistem' : a.aktor, ?a.orgAdi].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: r.silik, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(goreliZaman(a.zaman), style: TextStyle(color: r.silik, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

Color? tonRengi(String ton) => switch (ton) {
  'danger' => Marka.gul,
  'warning' => Marka.kehribar,
  _ => null,
};

/// Genişliğe göre sütun sayısı ayarlanan kart ızgarası (her kart en az [enAz] piksel).
class Izgara extends StatelessWidget {
  const Izgara({super.key, required this.children, this.enAz = 180, this.bosluk = 12});
  final List<Widget> children;
  final double enAz, bosluk;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, k) {
      if (children.isEmpty) return const SizedBox.shrink();
      final sutun = ((k.maxWidth + bosluk) / (enAz + bosluk)).floor().clamp(1, children.length);
      final g = (k.maxWidth - bosluk * (sutun - 1)) / sutun;
      return Wrap(
        spacing: bosluk,
        runSpacing: bosluk,
        children: [for (final c in children) SizedBox(width: g, child: c)],
      );
    },
  );
}
