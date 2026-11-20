import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import 'bolumler.dart';

/// İtibar Merkezim: müşterinin gönderim sağlığı, geri dönme nedenleri, gönderim IP'leri, göndericiler ve alan adları.
/// Web: admin/reputation-center. Uç noktalar: GET /reputation-center?range=&organization_id=, GET /dedicated-ip/status?org=,
/// GET /outbound/health?organization_id=, (ortaklar için) GET /organizations.
class ItibarMerkezimEkrani extends StatefulWidget {
  const ItibarMerkezimEkrani({super.key, this.orgId, this.orgAdi});
  final String? orgId, orgAdi;
  @override
  State<ItibarMerkezimEkrani> createState() => _ItibarMerkezimEkraniState();
}

class _Merkez {
  _Merkez(this.c, this.ip, this.saglik);
  final Map<String, dynamic> c;
  final Map<String, dynamic>? ip, saglik;
}

String _yuzde(Object? v, [int b = 1]) {
  final d = ondalikYa(v);
  if (d == null) return '—';
  var s = d.toStringAsFixed(b);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return '%${s.replaceAll('.', ',')}';
}

class _ItibarMerkezimEkraniState extends State<ItibarMerkezimEkrani> {
  final _anahtar = GlobalKey<TekYuklemeState<_Merkez>>();
  String _aralik = '7d';
  late String? _org = widget.orgId ?? (Uyg.musteri ? metinYa(Uyg.ben.value?['organization_id']) : null);
  late String? _orgAdi = widget.orgAdi;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 60), (_) => _anahtar.currentState?.yenile());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<Object?> _sessiz(Future<dynamic> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<_Merkez> _getir(String org) async {
    final s = await Future.wait<Object?>([
      Uyg.api.get('/api/v1/reputation-center', q: {'range': _aralik, if (!Uyg.musteri) 'organization_id': org}),
      _sessiz(Uyg.api.get('/api/v1/dedicated-ip/status', q: {'org': org})),
      _sessiz(Uyg.api.get('/api/v1/outbound/health', q: {'organization_id': org})),
    ]);
    return _Merkez(harita(s[0]), s[1] == null ? null : harita(s[1]), s[2] == null ? null : harita(s[2]));
  }

  Future<void> _musteriSec() async {
    try {
      final v = await Uyg.api.get('/api/v1/organizations', q: {'page_size': '100', 'sort': 'name', 'order': 'asc'});
      if (!mounted) return;
      final l = haritalar(harita(v)['items']);
      final s = await secimYap<String>(context, baslik: 'Müşteri seçin', secili: _org, secenekler: [for (final o in l) (metin(o['id']), metin(o['name']), null)]);
      if (s == null) return;
      setState(() {
        _org = s;
        _orgAdi = metin(l.firstWhere((o) => o['id'] == s)['name']);
      });
    } catch (e) {
      bildir('Müşteriler alınamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = _org;
    final aralik = SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: '24h', label: Text('24 saat')),
        ButtonSegment(value: '7d', label: Text('7 gün')),
        ButtonSegment(value: '30d', label: Text('30 gün')),
      ],
      selected: {_aralik},
      onSelectionChanged: (s) {
        setState(() => _aralik = s.first);
        _anahtar.currentState?.yenile();
      },
    );
    return Iskelet(
      baslik: Uyg.musteri ? 'İtibar Merkezim' : 'Müşteri itibar merkezi',
      alt: _orgAdi ?? 'Gönderim sağlığınız, geri dönme nedenleri, IP itibarı ve alan adı puanları',
      yenile: org == null ? null : () => _anahtar.currentState?.yenile(),
      eylemler: [
        if (!Uyg.musteri)
          IconButton(tooltip: 'Müşteri seçin', onPressed: _musteriSec, icon: const Icon(Icons.apartment_rounded)),
      ],
      govde: org == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Kapali('Bir müşterinin gönderim sağlığını görmek için müşteri seçin.', ikon: Icons.trending_up_rounded),
                  FilledButton.icon(onPressed: _musteriSec, icon: const Icon(Icons.apartment_rounded), label: const Text('Müşteri seçin')),
                ],
              ),
            )
          : TekYukleme<_Merkez>(
              key: _anahtar,
              getir: () => _getir(org),
              icerik: (c, v, yenile) => IcerikListesi(
                children: [
                  Align(alignment: Alignment.centerRight, child: aralik),
                  const SizedBox(height: 12),
                  ..._govde(c, v),
                ],
              ),
            ),
    );
  }

  List<Widget> _govde(BuildContext c, _Merkez m) {
    final r = c.r;
    final v = m.c;
    final t = harita(v['totals']);
    final o = harita(v['rates']);
    final hard = ondalik(o['hard_bounce_rate']);
    final mod = metin(v['outbound_mode'], 'direct');
    final sikayet = harita(v['complaints']);
    return [
      if (mod != 'direct') ...[
        Bant('Sunucuda dış gönderim kapalı (mod: $mod); teslim istatistikleri yalnızca platform içi gönderimleri içerir.', renk: r.silik),
        const SizedBox(height: 12),
      ],
      Izgara(
        enAz: 170,
        children: [
          KpiKarti(ikon: Icons.outbox_rounded, etiket: 'Gönderilen (dış)', deger: sayiYaz(tamsayi(t['queued'])), alt: 'alıcı'),
          KpiKarti(
            ikon: Icons.mark_email_read_rounded,
            etiket: 'Teslim edilen',
            deger: sayiYaz(tamsayi(t['delivered'])),
            alt: 'teslim oranı ${_yuzde(o['delivery_rate'])}',
            renk: Marka.zumrut,
          ),
          KpiKarti(
            ikon: Icons.schedule_rounded,
            etiket: 'Ertelenen',
            deger: sayiYaz(tamsayi(t['deferred_rcpts'])),
            alt: '${sayiYaz(tamsayi(t['deferrals']))} deneme',
            renk: Marka.kehribar,
          ),
          KpiKarti(
            ikon: Icons.block_rounded,
            etiket: 'Kalıcı geri dönme',
            deger: sayiYaz(tamsayi(t['hard_bounces'])),
            alt: _yuzde(o['hard_bounce_rate']),
            renk: hard > 5 ? Marka.gul : (hard > 2 ? Marka.kehribar : Marka.gul),
          ),
          KpiKarti(
            ikon: Icons.hourglass_bottom_rounded,
            etiket: 'Süresi dolan (yumuşak)',
            deger: sayiYaz(tamsayi(t['soft_bounces'])),
            alt: _yuzde(o['soft_bounce_rate']),
            renk: Marka.lavanta,
          ),
          KpiKarti(
            ikon: Icons.gpp_bad_outlined,
            etiket: 'Politika reddi',
            deger: sayiYaz(tamsayi(t['refused'])),
            alt: '${sayiYaz(tamsayi(t['refused_messages']))} ileti',
            renk: r.silik,
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (m.ip != null) ...[_ozelIp(c, m.ip!), const SizedBox(height: 16)],
      if (m.saglik != null) ...[_saglik(c, m.saglik!), const SizedBox(height: 16)],
      BolumKarti(
        baslik: 'Gönderim sonuçları zaman içinde',
        ikon: Icons.bar_chart_rounded,
        altBaslik: 'Şikâyetler: ${tamsayi(sikayet['suppressions'])} bastırma kaydı. ${metin(sikayet['fbl'])}.',
        child: _SonucGrafigi(seri: haritalar(v['series']), aralik: metin(v['range'], _aralik)),
      ),
      const SizedBox(height: 16),
      Izgara(
        enAz: 420,
        children: [_nedenler(c, haritalar(v['bounce_reasons'])), _ipler(c, haritalar(v['ips']))],
      ),
      const SizedBox(height: 16),
      _Gondericiler(liste: haritalar(v['senders']), duraklatma: harita(v['pause'])),
      const SizedBox(height: 16),
      _alanlar(c, mantik(v['dmarc_center']), haritalar(v['domains'])),
    ];
  }

  Widget _ozelIp(BuildContext c, Map<String, dynamic> d) {
    final r = c.r;
    final ipler = haritalar(d['ips']);
    const modlar = {'dedicated': 'Size özel IP', 'pool': 'Ayrılmış IP havuzu', 'plan': 'Paket IP havuzu', 'shared': 'Paylaşımlı IP havuzu'};
    final aciklama = ipler.isEmpty
        ? (mantik(d['feature'])
              ? 'Paketiniz özel IP içeriyor; henüz IP atanmadı. Atama yapılana kadar gönderim paylaşımlı havuzdan yapılır.'
              : 'İletileriniz platformun paylaşımlı IP havuzundan gönderilir. Özel IP, Enterprise ve Gateway paketlerinde bulunur.')
        : '${modlar[metin(d['mode'])] ?? metin(d['mode'])} üzerinden gönderiyorsunuz.';
    return BolumKarti(
      baslik: 'Gönderim IP\'si',
      ikon: Icons.dns_outlined,
      altBaslik: aciklama,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (metinYa(d['warning']) != null) ...[Bant(metin(d['warning']), renk: Marka.kehribar, ikon: Icons.warning_amber_rounded), const SizedBox(height: 8)],
          for (final ip in ipler) ...[
            Kutu(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(metin(ip['address']), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                      if (!mantik(ip['present'], true)) const Rozet('sunucuda yok', renk: Marka.kehribar),
                      if (tamsayi(ip['listed']) > 0) Rozet('${tamsayi(ip['listed'])} kara listede', renk: Marka.gul),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(() {
                    final ptr = metinler(ip['ptr']);
                    final uyum = ptr.isEmpty ? '' : (mantik(ip['fcrdns']) && mantik(ip['ptr_matches_helo']) ? ' · eşleşiyor' : ' · HELO/PTR uyumsuz');
                    return 'HELO ${metin(ip['helo_name'], '—')} · PTR ${ptr.isEmpty ? 'yok' : ptr.join(', ')}$uyum';
                  }(), style: TextStyle(color: r.silik, fontSize: 12)),
                  Text(
                    mantik(ip['warmup_enabled']) && tamsayi(ip['warmup_cap']) > 0
                        ? 'Isınma ${tamsayi(ip['warmup_day'])}. gün · bugün ${sayiYaz(tamsayi(ip['sent_today']))} / ${sayiYaz(tamsayi(ip['warmup_cap']))}'
                        : 'Bugün ${sayiYaz(tamsayi(ip['sent_today']))} alıcı',
                    style: TextStyle(color: r.silik, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _saglik(BuildContext c, Map<String, dynamic> d) {
    final r = c.r;
    final h = harita(d['health']);
    final esik = harita(d['thresholds']);
    const turler = {
      'spike': 'Ani gönderim artışı',
      'new_recipients': 'Çok sayıda yeni alıcı',
      'deferral': 'Yüksek erteleme oranı',
      'unknown_user': 'Yüksek bilinmeyen alıcı oranı',
      'complaint': 'Spam şikâyeti oranı',
      'dnsbl': 'IP kara listede (DNSBL)',
    };
    const eylemler = {
      'hold_all': 'Tüm dış postalar bekletiliyor',
      'hold_bulk': 'Toplu gönderim bekletiliyor',
      'pause_bulk': 'Toplu gönderim platform genelinde durdu',
    };
    Widget oran(String etiket, double deger, double sinir, String alt, {double? uyari}) {
      final u = uyari ?? sinir / 2;
      final renk = sinir > 0 && deger >= sinir ? Marka.gul : (u > 0 && deger >= u ? Marka.kehribar : Marka.zumrut);
      return Kutu(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiket, style: TextStyle(color: r.silik, fontSize: 12)),
            Text(_yuzde(deger, 2), style: gosterim(20, renk: renk)),
            Text('$alt · sınır ${_yuzde(sinir, 2)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 11.5)),
          ],
        ),
      );
    }

    return BolumKarti(
      baslik: 'Gönderim sağlığı',
      ikon: Icons.monitor_heart_outlined,
      altBaslik:
          'Erteleme, bilinmeyen alıcı ve şikâyet oranı sınırı aşarsa toplu gönderiminiz otomatik olarak bekletilir; ani bir gönderim artışında tüm dış '
          'postalarınız incelemeye alınır. Postalar silinmez, kuyrukta bekler.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in haritalar(d['brakes'])) ...[
            Bant(
              '${turler[metin(b['kind'])] ?? metin(b['kind'])} — ${eylemler[metin(b['action'])] ?? metin(b['action'])}'
              '${metinYa(b['mailbox']) != null ? ' (${metin(b['mailbox'])})' : ''}. ${metin(b['reason'])} Destek ekibimiz inceledikten sonra gönderim devam eder.',
              renk: Marka.gul,
              ikon: Icons.front_hand_outlined,
            ),
            const SizedBox(height: 8),
          ],
          Izgara(
            enAz: 170,
            children: [
              oran(
                'Erteleme (24 sa)',
                ondalik(h['deferral_rate']),
                ondalik(esik['deferral_rate']),
                '${tamsayi(h['deferred_24h'])}/${tamsayi(h['attempts_24h'])} deneme',
              ),
              oran('Bilinmeyen alıcı (24 sa)', ondalik(h['unknown_user_rate']), ondalik(esik['unknown_user_rate']), '${tamsayi(h['unknown_user_24h'])} adres'),
              oran(
                'Spam şikâyeti (7 gün)',
                ondalik(h['complaint_rate']),
                ondalik(esik['complaint_rate']),
                '${tamsayi(h['complaints_7d'])}/${tamsayi(h['delivered_7d'])} teslim',
                uyari: ondalik(esik['complaint_warn']),
              ),
              Kutu(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kuyruk', style: TextStyle(color: r.silik, fontSize: 12)),
                    Text(sayiYaz(tamsayi(d['queued'])), style: gosterim(20, renk: r.metin)),
                    Text(
                      'bekletilen ${tamsayi(d['held'])} · frende ${tamsayi(d['held_by_brake'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: r.silik, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Bastırma listenizde ${sayiYaz(tamsayi(d['suppressed']))} adres var (geri dönen, şikâyet eden veya elle eklenen).',
                style: TextStyle(color: r.silik, fontSize: 12),
              ),
              TextButton(onPressed: () => bolumeGit(Bolum.bastirma), child: const Text('Bastırma listesi')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nedenler(BuildContext c, List<Map<String, dynamic>> l) {
    final r = c.r;
    const turler = {'hard': 'Kalıcı (5xx)', 'soft': 'Süresi doldu', 'deferred': 'Ertelendi (4xx)'};
    return BolumKarti(
      baslik: 'En sık geri dönme nedenleri',
      ikon: Icons.report_outlined,
      altBaslik: 'Alıcı sunucuların yanıtları; e-posta adresleri maskelenir.',
      child: l.isEmpty
          ? Text('Bu dönemde geri dönme veya erteleme yok.', style: TextStyle(color: r.silik, fontSize: 13))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, b) in l.indexed) ...[
                  if (i > 0) const Divider(height: 16),
                  Row(
                    children: [
                      Rozet(turler[metin(b['kind'])] ?? metin(b['kind']), renk: b['kind'] == 'hard' ? Marka.gul : (b['kind'] == 'soft' ? Marka.lavanta : Marka.kehribar)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          metinYa(b['enhanced_code']) ?? metin(b['smtp_code']),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      Text('${sayiYaz(tamsayi(b['count']))} alıcı', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(metin(b['text']), style: TextStyle(color: r.soluk, fontSize: 12)),
                  Text(
                    '${metinler(b['recipient_domains']).join(', ')} · son ${tamZaman(tarihOku(b['last_at']))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: r.silik, fontSize: 11.5),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _ipler(BuildContext c, List<Map<String, dynamic>> l) {
    final r = c.r;
    return BolumKarti(
      baslik: 'Gönderim IP\'leri',
      ikon: Icons.lan_outlined,
      altBaslik: 'Postanızın çıktığı IP\'lerin genel itibarı (PTR ve kara listeler). Diğer müşterilerin verisi gösterilmez.',
      child: l.isEmpty
          ? Text('Etkin gönderim IP\'si yok.', style: TextStyle(color: r.silik, fontSize: 13))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, ip) in l.indexed) ...[
                  if (i > 0) const Divider(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(metin(ip['address']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Rozet(mantik(ip['dedicated']) ? 'size özel' : 'paylaşılan', renk: Marka.mavi),
                      if (ip['checked_at'] == null)
                        Rozet('henüz denetlenmedi', renk: r.silik)
                      else if (tamsayi(ip['listed']) > 0)
                        Rozet('${tamsayi(ip['listed'])} kara listede', renk: Marka.gul)
                      else
                        Rozet('${tamsayi(ip['lists_checked'])} listede temiz', renk: Marka.zumrut),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PTR: ${metinler(ip['ptr']).isEmpty ? 'yok' : metinler(ip['ptr']).join(', ')} · FCrDNS ${mantik(ip['fcrdns']) ? 'uyumlu' : 'uyumsuz'} · '
                    'HELO ${mantik(ip['helo_matches_ip']) ? 'uyumlu' : 'uyumsuz'}${ip['checked_at'] != null ? ' · ${tamZaman(tarihOku(ip['checked_at']))}' : ''}',
                    style: TextStyle(color: r.silik, fontSize: 12),
                  ),
                  for (final k in haritalar(ip['listings']))
                    Text(
                      '${metinYa(k['name']) ?? metin(k['zone'])}${mantik(k['major']) ? ' (büyük sağlayıcılar kullanır)' : ''}: ${metin(k['meaning'])}',
                      style: const TextStyle(color: Marka.gul, fontSize: 12),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _alanlar(BuildContext c, bool dmarc, List<Map<String, dynamic>> l) {
    final r = c.r;
    Widget puan(Object? s) {
      final p = tamsayiYa(s);
      if (p == null) return Text('denetlenmedi', style: TextStyle(color: r.silik, fontSize: 12));
      final renk = p >= 85 ? Marka.zumrut : (p >= 60 ? Marka.kehribar : Marka.gul);
      return Text('$p/100', style: TextStyle(color: renk, fontWeight: FontWeight.w700));
    }

    return BolumKarti(
      baslik: 'Alan adlarınız',
      ikon: Icons.language_rounded,
      altBaslik: 'Güvenlik puanı ve son 30 günün DMARC özeti. Ayrıntılar DMARC Merkezi\'nde.',
      sag: dmarc && l.isNotEmpty ? TextButton(onPressed: () => bolumeGit(Bolum.dmarc), child: const Text('DMARC Merkezi')) : null,
      child: !dmarc
          ? Text('DMARC Merkezi ve güvenlik puanı paketinizde yok (dmarc_center).', style: TextStyle(color: r.silik, fontSize: 13))
          : l.isEmpty
          ? Text('Alan adı yok.', style: TextStyle(color: r.silik, fontSize: 13))
          : Column(
              children: [
                for (final d in l)
                  ListeSatiri(
                    baslik: metin(d['name']),
                    alt:
                        '${tamsayi(d['dmarc_reports_30d'])} rapor · ${sayiYaz(tamsayi(d['dmarc_messages_30d']))} ileti · DMARC ${_yuzde(d['dmarc_pass_rate_30d'])} geçti',
                    sag: puan(d['score']),
                    onTap: Bolum.dmarc.gorunur && metin(d['id']).isNotEmpty
                        ? () => bolumeGit(Bolum.dmarc, alanId: metin(d['id']), alanAdi: metin(d['name']))
                        : null,
                  ),
              ],
            ),
    );
  }
}

/// Göndericiler (posta kutuları): yüksek geri dönme oranlılar üstte; 20'şer gösterilir.
class _Gondericiler extends StatefulWidget {
  const _Gondericiler({required this.liste, required this.duraklatma});
  final List<Map<String, dynamic>> liste;
  final Map<String, dynamic> duraklatma;
  @override
  State<_Gondericiler> createState() => _GondericilerState();
}

class _GondericilerState extends State<_Gondericiler> {
  int _adet = 20;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = widget.liste;
    final genis = context.genis;
    return BolumKarti(
      baslik: 'Göndericiler',
      ikon: Icons.people_alt_outlined,
      altBaslik:
          'Posta kutularınızın gönderim sonuçları; yüksek geri dönme oranlı olanlar üstte. 24 saatte en az ${tamsayi(widget.duraklatma['min_sends'])} '
          'gönderimde kalıcı geri dönme ${_yuzde(widget.duraklatma['rate'])}\'i aşarsa dış gönderim otomatik duraklatılır.',
      child: l.isEmpty
          ? Text('Bu dönemde gönderim yok.', style: TextStyle(color: r.silik, fontSize: 13))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (genis)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: DefaultTextStyle(
                      style: TextStyle(color: r.silik, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .4),
                      child: const Row(
                        children: [
                          Expanded(flex: 4, child: Text('GÖNDERİCİ')),
                          Expanded(child: Text('TESLİM', textAlign: TextAlign.right)),
                          Expanded(child: Text('KALICI', textAlign: TextAlign.right)),
                          Expanded(child: Text('ERTELENEN', textAlign: TextAlign.right)),
                          Expanded(child: Text('GERİ DÖNME', textAlign: TextAlign.right)),
                        ],
                      ),
                    ),
                  ),
                for (final s in l.take(_adet)) _satir(context, s, genis),
                if (l.length > _adet)
                  Center(
                    child: TextButton(onPressed: () => setState(() => _adet += 20), child: Text('Daha fazla göster (${l.length - _adet})')),
                  ),
              ],
            ),
    );
  }

  Widget _satir(BuildContext c, Map<String, dynamic> s, bool genis) {
    final r = c.r;
    final yuksek = mantik(s['high_bounce']);
    final oran = _yuzde(harita(s['rates'])['hard_bounce_rate']);
    final oranStil = TextStyle(fontWeight: yuksek ? FontWeight.w700 : FontWeight.w500, color: yuksek ? Marka.gul : r.metin);
    final adres = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metin(s['address']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        if (!genis)
          Text(
            '${tamsayi(s['delivered'])} teslim · ${tamsayi(s['hard_bounces'])} kalıcı · ${tamsayi(s['deferred_rcpts'])} ertelenen',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
        if (mantik(s['over_pause_threshold'])) const Text('Dış gönderim duraklatıldı (eşik aşıldı)', style: TextStyle(color: Marka.gul, fontSize: 12)),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: yuksek ? Marka.gul.withValues(alpha: .06) : null, borderRadius: BorderRadius.circular(10)),
      child: genis
          ? Row(
              children: [
                Expanded(flex: 4, child: adres),
                Expanded(child: Text(sayiYaz(tamsayi(s['delivered'])), textAlign: TextAlign.right)),
                Expanded(child: Text(sayiYaz(tamsayi(s['hard_bounces'])), textAlign: TextAlign.right)),
                Expanded(child: Text(sayiYaz(tamsayi(s['deferred_rcpts'])), textAlign: TextAlign.right)),
                Expanded(child: Text(oran, textAlign: TextAlign.right, style: oranStil)),
              ],
            )
          : Row(
              children: [
                Expanded(child: adres),
                const SizedBox(width: 8),
                Text(oran, style: oranStil),
              ],
            ),
    );
  }
}

/// Zaman içinde gönderim sonuçları: yığılmış sütun grafiği (teslim, ertelenen, süresi dolan, kalıcı, politika reddi).
class _SonucGrafigi extends StatelessWidget {
  const _SonucGrafigi({required this.seri, required this.aralik});
  final List<Map<String, dynamic>> seri;
  final String aralik;

  static const _parcalar = [
    ('delivered', 'Teslim', Marka.zumrut),
    ('deferred_rcpts', 'Ertelenen', Marka.kehribar),
    ('soft_bounces', 'Süresi dolan', Color(0xFFF472B6)),
    ('hard_bounces', 'Kalıcı geri dönme', Marka.gul),
    ('refused', 'Politika reddi', Color(0xFF94A3B8)),
  ];

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    var enCok = 1.0;
    for (final b in seri) {
      var t = 0;
      for (final p in _parcalar) {
        t += tamsayi(b[p.$1]);
      }
      if (t > enCok) enCok = t.toDouble();
    }
    final bicim = DateFormat(aralik == '30d' ? 'd MMM' : 'd MMM HH:mm', 'tr_TR');
    final ilk = seri.isEmpty ? null : tarihOku(seri.first['at']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final p in _parcalar)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 5),
                  Text(p.$2, style: TextStyle(color: r.soluk, fontSize: 12)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          child: BarChart(
            BarChartData(
              maxY: enCok,
              alignment: BarChartAlignment.spaceBetween,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: r.kenar))),
              titlesData: const FlTitlesData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => r.kart,
                  getTooltipItem: (g, _, _, _) {
                    final b = seri[g.x];
                    final at = tarihOku(b['at']);
                    return BarTooltipItem(
                      '${at == null ? '' : bicim.format(at)}\n'
                      'teslim ${tamsayi(b['delivered'])} · geri dönme ${tamsayi(b['hard_bounces'])} · ertelenen ${tamsayi(b['deferred_rcpts'])}',
                      TextStyle(color: r.metin, fontSize: 11.5),
                    );
                  },
                ),
              ),
              barGroups: [
                for (final (i, b) in seri.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      () {
                        var y = 0.0;
                        final parcalar = <BarChartRodStackItem>[];
                        for (final p in _parcalar) {
                          final v = tamsayi(b[p.$1]).toDouble();
                          if (v > 0) parcalar.add(BarChartRodStackItem(y, y + v, p.$3));
                          y += v;
                        }
                        return BarChartRodData(
                          toY: y,
                          width: (300 / (seri.isEmpty ? 1 : seri.length)).clamp(2.0, 14.0),
                          rodStackItems: parcalar,
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        );
                      }(),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(ilk == null ? '' : bicim.format(ilk), style: TextStyle(color: r.silik, fontSize: 11)),
            const Spacer(),
            Text('şimdi', style: TextStyle(color: r.silik, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}
