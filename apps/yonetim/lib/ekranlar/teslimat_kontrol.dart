import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import '../ortak/simgeler.dart';

const _frenTurleri = {
  'spike': 'Ani gönderim artışı',
  'new_recipients': 'Çok sayıda yeni alıcı',
  'deferral': 'Yüksek erteleme oranı',
  'unknown_user': 'Yüksek bilinmeyen alıcı oranı',
  'complaint': 'Spam şikâyeti oranı',
  'dnsbl': 'IP kara listede (DNSBL)',
};

const _frenEylemleri = {
  'hold_all': 'Tüm dış postalar bekletiliyor',
  'hold_bulk': 'Toplu gönderim bekletiliyor',
  'pause_bulk': 'Toplu gönderim platform genelinde durdu',
};

const _saglayiciDurumlari = {'normal': 'Normal', 'backoff': 'Geri çekildi', 'recovering': 'Toparlanıyor'};

String _n(Object? v) => sayiYaz(tamsayi(v));

/// Teslimat Kontrol (yalnızca süper yönetici): yüksek hacimli gönderim motoru, sağlayıcı sınırları, güvenlik frenleri,
/// IP ısınması, DNSBL, FBL ve gelen bağlantı koruması (GET /outbound/engine; PUT /outbound/engine/config,
/// PUT /outbound/brakes/config, POST /outbound/brakes/{id}/release, PUT /outbound/warmup, PUT /inbound/limits).
class TeslimatKontrolEkrani extends StatefulWidget {
  const TeslimatKontrolEkrani({super.key});
  @override
  State<TeslimatKontrolEkrani> createState() => _TeslimatKontrolEkraniState();
}

class _TeslimatKontrolEkraniState extends State<TeslimatKontrolEkrani> {
  final _anahtar = GlobalKey<TekYuklemeState<Map<String, dynamic>>>();
  Map<String, dynamic>? _veri;
  Timer? _zamanlayici;

  @override
  void initState() {
    super.initState();
    _zamanlayici = Timer.periodic(const Duration(seconds: 10), (_) => _anahtar.currentState?.yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _getir() async {
    final v = harita(await Uyg.api.get('/api/v1/outbound/engine'));
    if (mounted) setState(() => _veri = v);
    return v;
  }

  Future<void> _yenile() async => _anahtar.currentState?.yenile();

  Future<void> _dialog(Widget w) async {
    final kaydedildi = await showDialog<bool>(context: context, builder: (_) => w);
    if (kaydedildi == true) _yenile();
  }

  void _motor() {
    final v = _veri;
    if (v == null) return;
    _dialog(_MotorDialog(ayar: harita(v['engine_config']), profiller: haritalar(v['profiles'])));
  }

  void _frenler() {
    final v = _veri;
    if (v == null) return;
    _dialog(
      _SayiAyarDialog(
        baslik: 'Fren eşikleri',
        aciklama: 'Eşiği 0 yapmak o freni kapatır. Oranlar yüzde olarak girilir.',
        yol: '/api/v1/outbound/brakes/config',
        ayar: harita(v['brake_config']),
        alanlar: const [
          _Alan('spike_factor', 'Ani artış katsayısı', ipucu: 'Son saat ≥ 7 günlük saatlik ortalama × bu değer', ondalikli: true),
          _Alan('spike_min_hour', 'Ani artış alt sınırı', ipucu: 'Saatlik en az dış alıcı'),
          _Alan('spike_new_rcpts', 'Yeni alıcı sınırı', ipucu: 'Son saatte hiç yazılmamış farklı alıcı'),
          _Alan('deferral_rate', 'Erteleme oranı (%)', ondalikli: true),
          _Alan('deferral_min', 'Erteleme için en az deneme'),
          _Alan('unknown_user_rate', 'Bilinmeyen alıcı oranı (%)', ondalikli: true),
          _Alan('unknown_user_min', 'Bilinmeyen alıcı için en az teslim'),
          _Alan('complaint_rate', 'Şikâyet oranı (%)', ipucu: 'Gmail/Yahoo üst sınırı %0,3', ondalikli: true),
          _Alan('complaint_warn', 'Şikâyet uyarı oranı (%)', ondalikli: true),
          _Alan('complaint_min', 'Şikâyet için en az teslim (7 gün)'),
          _Alan('dnsbl_normal_factor', 'Kara listede normal hız', ipucu: '0–1 arası oran', ondalikli: true),
          _Alan('release_grace_hours', 'Kaldırma sonrası muafiyet (saat)'),
        ],
        anahtarlar: const [('dnsbl_pause_bulk', 'Büyük kara listeye girişte toplu gönderimi durdur')],
      ),
    );
  }

  void _gelen() {
    final v = _veri;
    if (v == null) return;
    _dialog(
      _SayiAyarDialog(
        baslik: 'Gelen bağlantı koruması',
        aciklama: 'MX dinleyicisinin istemci sınırları hemen uygulanır. Kendi IP\'lerimiz ve özel ağlar sınırlanmaz. 0 = kapalı.',
        yol: '/api/v1/inbound/limits',
        ayar: harita(harita(v['inbound'])['config']),
        alanlar: const [
          _Alan('max_per_ip', 'IP başına eşzamanlı bağlantı'),
          _Alan('per_ip_per_minute', 'IP başına dakikalık bağlantı'),
          _Alan('pregreet_ms', 'Selam öncesi bekleme (ms)', ipucu: 'Bu sürede konuşan istemci reddedilir'),
          _Alan('tarpit_ms', 'Hata yavaşlatma (ms)', ipucu: 'Üçüncü hatadan sonra her hatada'),
          _Alan('max_rcpt_failures', 'Reddedilen alıcı sınırı', ipucu: 'Aşılınca oturum kapanır'),
        ],
        anahtarlar: const [('dnsbl_enabled', 'Bağlanan IP\'yi kara listede kontrol et')],
        bolgeler: true,
      ),
    );
  }

  void _isinma() {
    final v = _veri;
    if (v == null) return;
    _dialog(_IsinmaDialog(baslangic: tarihOku(harita(v['warmup'])['started'])));
  }

  Future<void> _frenKaldir(Map<String, dynamic> b) async {
    final graceSaat = tamsayi(harita(_veri?['brake_config'])['release_grace_hours'], 24);
    final kim = '${metin(b['organization_name'])}${metin(b['mailbox']).isNotEmpty ? ' · ${metin(b['mailbox'])}' : ''}';
    final ok = await onayla(
      context,
      'Fren kaldırılsın mı?',
      mesaj:
          '${_frenTurleri[metin(b['kind'])] ?? metin(b['kind'])} — $kim. Bekletilen postalar hemen gönderilir. '
          'Aynı fren $graceSaat saat yeniden devreye girmez. İşlem denetim kaydına yazılır.',
      evet: 'Freni kaldır',
      tehlikeli: true,
    );
    if (!ok) return;
    final r = await islem(() => Uyg.api.post('/api/v1/outbound/brakes/${metin(b['id'])}/release', <String, dynamic>{}));
    if (r != null) {
      bildir('Fren kaldırıldı; ${tamsayi(harita(r)['queue_entries_released'])} ileti serbest bırakıldı', tur: MesajTur.basari);
      _yenile();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi) {
      return const Iskelet(baslik: 'Teslimat Kontrol', govde: Kapali('Bu sayfa yalnızca platform yöneticilerine açıktır.'));
    }
    final hazir = _veri != null;
    return Iskelet(
      baslik: 'Teslimat Kontrol',
      alt: 'Gönderim motoru, sağlayıcı sınırları, güvenlik frenleri ve gelen koruma',
      yenile: _yenile,
      eylemler: [
        PopupMenuButton<int>(
          tooltip: 'Ayarlar',
          icon: const Icon(Simgeler.tune),
          enabled: hazir,
          onSelected: (i) => [_motor, _frenler, _gelen, _isinma][i](),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0, child: ListTile(leading: Icon(Simgeler.settings), title: Text('Motor sınırları'), dense: true)),
            PopupMenuItem(value: 1, child: ListTile(leading: Icon(Simgeler.shield), title: Text('Fren eşikleri'), dense: true)),
            PopupMenuItem(value: 2, child: ListTile(leading: Icon(Simgeler.speed), title: Text('Gelen koruma'), dense: true)),
            PopupMenuItem(value: 3, child: ListTile(leading: Icon(Simgeler.localFireDepartment), title: Text('IP ısınması'), dense: true)),
          ],
        ),
      ],
      govde: TekYukleme<Map<String, dynamic>>(key: _anahtar, getir: _getir, icerik: (c, v, _) => _icerik(c, v)),
    );
  }

  Widget _icerik(BuildContext context, Map<String, dynamic> v) {
    final r = context.r;
    final st = v['engine'] is Map ? harita(v['engine']) : null;
    final frenler = haritalar(v['brakes']);
    final etkin = frenler.where((b) => mantik(b['active'])).toList();
    final gecmis = frenler.where((b) => !mantik(b['active'])).toList();
    final dnsbl = haritalar(v['dnsbl']);
    final inb = harita(v['inbound']);
    final ic = harita(inb['config']);
    final ist = inb['stats'] is Map ? harita(inb['stats']) : null;
    final fbl = harita(v['fbl']);
    final fblSay = harita(fbl['counts']);
    final fblAdresler = metinler(fbl['addresses']);
    final genis = MediaQuery.sizeOf(context).width >= 1000;

    Widget ikili(Widget a, Widget b) => genis
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 16),
              Expanded(child: b),
            ],
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 16), b]);

    final kv = <Widget>[
      BilgiSatiri('IP başına bağlantı', '${tamsayi(ic['max_per_ip']) == 0 ? 'sınırsız' : _n(ic['max_per_ip'])} eşzamanlı · ${tamsayi(ic['per_ip_per_minute']) == 0 ? 'sınırsız' : _n(ic['per_ip_per_minute'])}/dk'),
      BilgiSatiri('Selam öncesi bekleme', '${tamsayi(ic['pregreet_ms'])} ms'),
      BilgiSatiri('Hata yavaşlatma', '${tamsayi(ic['tarpit_ms'])} ms × hata (en çok 10 sn)'),
      BilgiSatiri('Reddedilen alıcı sınırı', tamsayi(ic['max_rcpt_failures']) == 0 ? 'sınırsız' : _n(ic['max_rcpt_failures'])),
      BilgiSatiri('DNSBL', mantik(ic['dnsbl_enabled']) ? (metinler(ic['dnsbl_zones']).isEmpty ? 'bölge yok' : metinler(ic['dnsbl_zones']).join(', ')) : 'kapalı'),
    ];

    return IcerikListesi(
      children: [
        const SizedBox(height: 4),
        if (!mantik(v['available']) || st == null)
          const Bant('Gönderim kuyruğu bu sunucuda çalışmıyor; yalnızca ayarlar gösteriliyor.')
        else ...[
          if (mantik(st['bulk_paused']))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Bant(
                'Toplu gönderim platform genelinde durduruldu. ${metin(st['pause_reason'])} Normal posta hızı %${(ondalik(st['normal_factor']) * 100).round()}.',
                renk: Marka.gul,
                ikon: Simgeler.pauseCircleOutline,
              ),
            ),
          Izgara(
            enAz: 220,
            children: [
              KpiKarti(
                ikon: Simgeler.cable,
                etiket: 'Açık bağlantı',
                deger: '${tamsayi(st['running_connections'])} / ${tamsayi(st['max_connections'])}',
                alt: 'toplu ${tamsayi(st['running_bulk'])} · normal için ayrılan ${tamsayi(st['reserved_normal'])}',
              ),
              KpiKarti(
                ikon: Simgeler.doneAll,
                etiket: 'Son dakika teslim',
                deger: _n(st['delivered_last_minute']),
                alt: 'son 10 dk ${_n(st['delivered_10m'])}',
                renk: Marka.zumrut,
              ),
              KpiKarti(
                ikon: Simgeler.schedule,
                etiket: 'Ertelenen / hata (10 dk)',
                deger: '${_n(st['deferred_10m'])} / ${_n(st['failed_10m'])}',
                renk: tamsayi(st['deferred_10m']) > tamsayi(st['delivered_10m']) && tamsayi(st['deferred_10m']) > 0 ? Marka.kehribar : null,
              ),
              () {
                final q = harita(st['queued']);
                return KpiKarti(
                  ikon: Simgeler.formatListNumbered,
                  etiket: 'Kuyruk',
                  deger: sayiYaz(tamsayi(q['normal']) + tamsayi(q['bulk'])),
                  alt: 'normal ${_n(q['normal'])} · toplu ${_n(q['bulk'])} · bekletilen ${_n(q['held'])} (fren ${_n(q['held_by_brake'])})',
                );
              }(),
            ],
          ),
          const SizedBox(height: 16),
          BolumKarti(
            baslik: 'Son 10 dakika',
            ikon: Simgeler.barChart,
            altBaslik: 'Dakika başına teslim (yeşil), erteleme (sarı) ve kalıcı hata (kırmızı).',
            child: _Akis(noktalar: haritalar(st['per_minute'])),
          ),
          const SizedBox(height: 16),
          BolumKarti(
            baslik: 'Sağlayıcılar',
            ikon: Simgeler.hub,
            altBaslik:
                'MX adı sonekiyle tanınan sağlayıcılar ortak sınırı paylaşır; diğer alan adları kendi sınırını alır. Sağlayıcı "yavaşla" dediğinde (421 / 4.7.x) '
                'hız yarıya iner, bekleme süresi 1 dakikadan başlayıp ikiye katlanır (en çok 1 saat); sorunsuz her 5 dakikada hız ×1,5 artar.',
            child: haritalar(st['providers']).isEmpty
                ? Text('Son 10 dakikada doğrudan teslim yapılmadı.', style: TextStyle(color: r.soluk))
                : Column(
                    children: [
                      for (final (i, p) in haritalar(st['providers']).indexed) ...[if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)), _SaglayiciSatiri(p)],
                    ],
                  ),
          ),
          if (haritalar(st['down_domains']).isNotEmpty) ...[
            const SizedBox(height: 16),
            BolumKarti(
              baslik: 'Ulaşılamayan alan adları',
              ikon: Simgeler.cloudOff,
              altBaslik: 'Art arda bağlantı hatası veren alan adlarına bekleme süresince bağlanılmaz; iletiler kuyrukta kalır ve sonra yeniden denenir.',
              child: Column(
                children: [
                  for (final d in haritalar(st['down_domains']))
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(border: Border.all(color: r.kenar), borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metin(d['domain']), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                          Text(
                            '${tamsayi(d['failures'])} hata · ${_n(d['ready'])} ileti · ${tamZaman(tarihOku(d['open_until']))} sonra denenecek',
                            style: TextStyle(color: r.silik, fontSize: 12),
                          ),
                          if (metin(d['last_error']).isNotEmpty) Text(metin(d['last_error']), style: TextStyle(color: r.soluk, fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        BolumKarti(
          baslik: 'Güvenlik frenleri',
          ikon: Simgeler.shield,
          altBaslik:
              'Ani gönderim artışı, yüksek erteleme / bilinmeyen alıcı / şikâyet oranı veya büyük kara listeye giriş otomatik olarak frenlenir. Etkilenen postalar '
              'silinmez, kuyrukta bekletilir; freni kaldırdığınızda gönderilir. Kara liste freni, listeden çıkınca kendiliğinden kalkar.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (etkin.isEmpty)
                Row(
                  children: [
                    const Icon(Simgeler.verifiedUser, color: Marka.zumrut),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Etkin fren yok. Tüm gönderenler normal çalışıyor.', style: TextStyle(color: r.soluk))),
                  ],
                )
              else
                for (final b in etkin)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: Marka.gul.withValues(alpha: .35)), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(_frenTurleri[metin(b['kind'])] ?? metin(b['kind']), style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Rozet(_frenEylemleri[metin(b['action'])] ?? metin(b['action']), renk: Marka.gul),
                                ],
                              ),
                              Text(
                                '${metin(b['scope']) == 'platform' ? 'Platform geneli' : '${metin(b['organization_name'])}${metin(b['mailbox']).isNotEmpty ? ' · ${metin(b['mailbox'])}' : ''}'}'
                                ' · ${goreliZaman(tarihOku(b['created_at']))}',
                                style: TextStyle(color: r.silik, fontSize: 12.5),
                              ),
                              if (metin(b['reason']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(metin(b['reason']), style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                        ),
                        if (metin(b['kind']) != 'dnsbl')
                          OutlinedButton.icon(onPressed: () => _frenKaldir(b), icon: const Icon(Simgeler.lockOpen, size: 17), label: const Text('Kaldır')),
                      ],
                    ),
                  ),
              if (gecmis.isNotEmpty)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Son 7 günde kaldırılan frenler (${gecmis.length})', style: TextStyle(color: r.soluk, fontSize: 13.5)),
                    children: [
                      for (final b in gecmis)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${tamZaman(tarihOku(b['created_at']))} · ${_frenTurleri[metin(b['kind'])] ?? metin(b['kind'])} · '
                            '${metinYa(b['organization_name']) ?? 'Platform'} — ${metin(b['released_by'])} (${tamZaman(tarihOku(b['released_at']))})',
                            style: TextStyle(color: r.soluk, fontSize: 12.5),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ikili(
          _IsinmaKarti(w: harita(v['warmup']), duzenle: _isinma),
          BolumKarti(
            baslik: 'Kara liste (DNSBL)',
            ikon: Simgeler.gppBad,
            altBaslik: 'Gönderim IP\'lerinin itibar taramasından. Büyük bir listeye girilince toplu gönderim durur, normal posta yavaşlar.',
            child: dnsbl.isEmpty
                ? const Text('Hiçbir gönderim IP\'si kara listede değil.', style: TextStyle(color: Marka.zumrut))
                : Column(
                    children: [
                      for (final l in dnsbl)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          decoration: BoxDecoration(border: Border.all(color: r.kenar), borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(metin(l['ip']), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                                    Text('· ${metinYa(l['name']) ?? metin(l['zone'])}'),
                                    if (mantik(l['major'])) const Rozet('büyük liste', renk: Marka.gul),
                                  ],
                                ),
                              ),
                              if (metin(l['delist_url']).isNotEmpty)
                                TextButton.icon(
                                  onPressed: () => launchUrl(Uri.parse(metin(l['delist_url'])), mode: LaunchMode.externalApplication),
                                  icon: const Icon(SimgelerKalin.openInNew, size: 16),
                                  label: const Text('Listeden çıkarma'),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        ikili(
          BolumKarti(
            baslik: 'Şikâyet geri bildirimi (FBL)',
            ikon: Simgeler.reportGmailerrorred,
            altBaslik:
                'ARF raporları aşağıdaki adreslerde işlenir; şikâyet edilen alıcı o müşteri için toplu gönderimde bastırılır. Son 30 gün: ${_n(fblSay['parsed_30d'])} rapor'
                '${tamsayi(fblSay['unparsed_30d']) > 0 ? ', ${_n(fblSay['unparsed_30d'])} okunamayan' : ''}.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final a in fblAdresler) KopyaKutusu(a),
                const SizedBox(height: 8),
                for (final (ad, url) in const [
                  ('Microsoft JMRP + SNDS', 'https://sendersupport.olc.protection.outlook.com/snds/'),
                  ('Yahoo Complaint Feedback Loop', 'https://senders.yahooinc.com/complaint-feedback-loop/'),
                  ('Gmail Postmaster Tools', 'https://postmaster.google.com/'),
                ])
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    decoration: BoxDecoration(border: Border.all(color: r.kenar), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Expanded(child: Text(ad, style: const TextStyle(fontSize: 13))),
                        const Rozet('Onay bekliyor / sahip kaydı', renk: Marka.kehribar),
                        IconButton(
                          tooltip: '$ad kayıt sayfası',
                          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                          icon: const Icon(Simgeler.openInNew, size: 18),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Bu kayıtlar alan adı / IP sahibinin hesabıyla yapılır. Kayıtta rapor adresi olarak ${fblAdresler.firstOrNull ?? 'fbl@<platform sunucusu>'} verilmeli; '
                  'IP\'nin PTR kaydı tanımlanmadan bazı programlar başvuruyu kabul etmez.',
                  style: TextStyle(color: r.silik, fontSize: 12),
                ),
              ],
            ),
          ),
          BolumKarti(
            baslik: 'Gelen bağlantı koruması',
            ikon: Simgeler.speed,
            altBaslik: 'MX (25) dinleyicisi: IP başına eşzamanlı bağlantı ve dakikalık sınır, erken konuşan istemci tespiti, hatalı oturumları yavaşlatma ve DNSBL kontrolü.',
            sag: TextButton(onPressed: _gelen, child: const Text('Düzenle')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...kv,
                if (ist != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Başlangıçtan beri reddedilen: IP sınırı ${_n(ist['over_per_ip'])}, hız ${_n(ist['over_rate'])}, erken konuşan ${_n(ist['early_talker'])}, '
                      'alıcı denemesi ${_n(ist['rcpt_failure'])}, DNSBL ${_n(inb['dnsbl_rejected'])} / ${_n(inb['dnsbl_checked'])} kontrol. '
                      'Aktif istemci: ${tamsayi(ist['active_clients'])}.',
                      style: TextStyle(color: r.silik, fontSize: 12),
                    ),
                  ),
                if (!mantik(inb['listening']))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('MX dinleyicisi bu sunucuda çalışmıyor.', style: TextStyle(color: r.silik, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(onPressed: _motor, icon: const Icon(Simgeler.settings, size: 18), label: const Text('Motor sınırları')),
            OutlinedButton.icon(onPressed: _frenler, icon: const Icon(Simgeler.shield, size: 18), label: const Text('Fren eşikleri')),
            OutlinedButton.icon(onPressed: _gelen, icon: const Icon(Simgeler.speed, size: 18), label: const Text('Gelen koruma')),
          ],
        ),
      ],
    );
  }
}

class _SaglayiciSatiri extends StatelessWidget {
  const _SaglayiciSatiri(this.p);
  final Map<String, dynamic> p;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final durum = metin(p['state']);
    final renk = switch (durum) {
      'backoff' => Marka.gul,
      'recovering' => Marka.kehribar,
      _ => Marka.zumrut,
    };
    final hiz = ondalik(p['rate_per_minute']);
    final hazir = tamsayi(p['ready']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metin(p['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${hazir > 0 ? '${sayiYaz(hazir)} hazır ileti' : 'bekleyen yok'}${metin(p['last_reason']).isNotEmpty ? ' · ${metin(p['last_reason'])}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: r.silik, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '${tamsayi(p['connections'])}/${tamsayi(p['max_connections'])} bağlantı · '
                  '${hiz > 0 ? '${hiz.round()}/dk' : 'sınırsız'}${ondalik(p['factor'], 1) < 1 ? ' (taban ${tamsayi(p['base_rate_per_minute'])})' : ''} · '
                  '${_n(p['delivered_10m'])} teslim · ${_n(p['deferred_10m'])} ertelendi · ${_n(p['failed_10m'])} hata',
                  style: TextStyle(color: r.soluk, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Rozet(_saglayiciDurumlari[durum] ?? durum, renk: renk),
              if (durum == 'backoff' && tarihOku(p['cooldown_until']) != null)
                Text('${tamZaman(tarihOku(p['cooldown_until']))} sonrası', style: TextStyle(color: r.silik, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dakikalık teslim / erteleme / hata yığılmış çubukları.
class _Akis extends StatelessWidget {
  const _Akis({required this.noktalar});
  final List<Map<String, dynamic>> noktalar;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (noktalar.isEmpty) return Text('Henüz teslim denemesi yok.', style: TextStyle(color: r.soluk));
    final enFazla = noktalar.fold<int>(1, (a, p) {
      final t = tamsayi(p['delivered']) + tamsayi(p['deferred']) + tamsayi(p['failed']);
      return t > a ? t : a;
    });
    const h = 110.0;
    return SizedBox(
      height: h,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in noktalar)
            Expanded(
              child: Tooltip(
                message: '${tamZaman(tarihOku(p['minute']))}: ${tamsayi(p['delivered'])} teslim, ${tamsayi(p['deferred'])} erteleme, ${tamsayi(p['failed'])} hata',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(height: h * tamsayi(p['failed']) / enFazla, color: Marka.gul.withValues(alpha: .75)),
                      Container(height: h * tamsayi(p['deferred']) / enFazla, color: Marka.kehribar.withValues(alpha: .75)),
                      Container(
                        height: h * tamsayi(p['delivered']) / enFazla,
                        decoration: BoxDecoration(color: Marka.zumrut.withValues(alpha: .75), borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IsinmaKarti extends StatelessWidget {
  const _IsinmaKarti({required this.w, required this.duzenle});
  final Map<String, dynamic> w;
  final VoidCallback duzenle;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final bas = tarihOku(w['started']);
    final gun = tamsayi(w['day']), gunler = tamsayi(w['days']);
    final isiniyor = bas != null && gun >= 0;
    final plan = (w['schedule'] is List) ? (w['schedule'] as List).map((x) => tamsayi(x)).toList() : <int>[];
    final yarin = gun + 1 < plan.length ? plan[gun + 1] : 0;
    return BolumKarti(
      baslik: 'Platform IP ısınması',
      ikon: Simgeler.localFireDepartment,
      altBaslik: 'Yeni bir gönderim IP\'si günlük alıcı sınırı kademeli artırılarak ısıtılır. Paylaşımlı IP için geçerlidir; özel IP\'lerin ısınması IP Yönetimi sayfasındadır.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isiniyor) ...[
            Row(
              children: [
                Expanded(child: Text('Gün ${gun + 1} / $gunler', style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('${_n(w['sent_today'])} / ${_n(w['cap_today'])} bugün'),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: gunler == 0 ? 0 : ((gun + 1) / gunler).clamp(0.0, 1.0), minHeight: 8, backgroundColor: r.ic),
            ),
            const SizedBox(height: 8),
            Text(
              'Başlangıç ${tamZaman(bas)}. Bugünkü sınır dolunca dış posta ertelenir; yarın ${yarin == 0 ? 'sınırsız' : sayiYaz(yarin)}.',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
          ] else if (bas != null)
            Text(
              'Isınma tamamlandı (${tamZaman(bas)} başladı). Günlük sınır: ${tamsayi(w['base_daily_limit']) == 0 ? 'sınırsız' : _n(w['base_daily_limit'])}.',
              style: const TextStyle(color: Marka.zumrut),
            )
          else
            Text('Isınma planı etkin değil. Bugün ${_n(w['sent_today'])} dış alıcıya gönderildi.', style: TextStyle(color: r.soluk)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: duzenle, child: Text(bas != null ? 'Isınmayı değiştir' : 'Isınmayı başlat')),
          ),
        ],
      ),
    );
  }
}

// ---- ayar pencereleri ----

class _Alan {
  const _Alan(this.anahtar, this.etiket, {this.ipucu, this.ondalikli = false});
  final String anahtar, etiket;
  final String? ipucu;
  final bool ondalikli;
}

String _sayiMetni(Object? v) {
  final d = ondalik(v);
  return d == d.roundToDouble() ? d.toStringAsFixed(0) : '$d';
}

num? _sayiOku(String s, bool ondalikli) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return 0;
  return ondalikli ? double.tryParse(t) : int.tryParse(t);
}

/// Sayı alanlı ayar penceresi (fren eşikleri, gelen koruma): mevcut ayar + değişen alanlar PUT edilir.
class _SayiAyarDialog extends StatefulWidget {
  const _SayiAyarDialog({
    required this.baslik,
    required this.aciklama,
    required this.yol,
    required this.ayar,
    required this.alanlar,
    this.anahtarlar = const [],
    this.bolgeler = false,
  });
  final String baslik, aciklama, yol;
  final Map<String, dynamic> ayar;
  final List<_Alan> alanlar;
  final List<(String, String)> anahtarlar;

  /// DNSBL bölgeleri metin alanı (gelen koruma).
  final bool bolgeler;
  @override
  State<_SayiAyarDialog> createState() => _SayiAyarDialogState();
}

class _SayiAyarDialogState extends State<_SayiAyarDialog> {
  late final _k = {for (final a in widget.alanlar) a.anahtar: TextEditingController(text: _sayiMetni(widget.ayar[a.anahtar]))};
  late final _b = {for (final (k, _) in widget.anahtarlar) k: mantik(widget.ayar[k])};
  late final _bolge = TextEditingController(text: metinler(widget.ayar['dnsbl_zones']).join('\n'));
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    for (final k in _k.values) {
      k.dispose();
    }
    _bolge.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final govde = Map<String, dynamic>.from(widget.ayar);
    for (final a in widget.alanlar) {
      final v = _sayiOku(_k[a.anahtar]!.text, a.ondalikli);
      if (v == null || v < 0) return setState(() => _hata = '${a.etiket}: geçerli bir sayı girin');
      govde[a.anahtar] = v;
    }
    govde.addAll(_b);
    if (widget.bolgeler) govde['dnsbl_zones'] = _bolge.text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.put(widget.yol, govde);
      bildir('Kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.baslik, style: gosterim(19, agirlik: FontWeight.w600)),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.aciklama, style: TextStyle(color: context.r.soluk, fontSize: 13)),
            const SizedBox(height: 16),
            _SayiIzgarasi(alanlar: widget.alanlar, kontroller: _k),
            for (final (k, e) in widget.anahtarlar)
              SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(e, style: const TextStyle(fontSize: 14)), value: _b[k]!, onChanged: (v) => setState(() => _b[k] = v)),
            if (widget.bolgeler) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _bolge,
                minLines: 3,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'DNSBL bölgeleri (satır başına bir)',
                  alignLabelWithHint: true,
                  helperText: 'Spamhaus ücretsiz katmanı genel DNS çözücülerden gelen sorguları yanıtlamaz; bu durumda istemci reddedilmez.',
                  helperMaxLines: 3,
                ),
              ),
            ],
            if (_hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13))),
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

class _SayiIzgarasi extends StatelessWidget {
  const _SayiIzgarasi({required this.alanlar, required this.kontroller});
  final List<_Alan> alanlar;
  final Map<String, TextEditingController> kontroller;
  @override
  Widget build(BuildContext context) => Izgara(
    enAz: 240,
    bosluk: 12,
    children: [
      for (final a in alanlar)
        TextField(
          controller: kontroller[a.anahtar],
          keyboardType: TextInputType.numberWithOptions(decimal: a.ondalikli),
          decoration: InputDecoration(labelText: a.etiket, helperText: a.ipucu, helperMaxLines: 2),
        ),
    ],
  );
}

/// Motor sınırları: genel alanlar + sağlayıcı başına bağlantı / dakikalık ileti (PUT /outbound/engine/config).
class _MotorDialog extends StatefulWidget {
  const _MotorDialog({required this.ayar, required this.profiller});
  final Map<String, dynamic> ayar;
  final List<Map<String, dynamic>> profiller;
  @override
  State<_MotorDialog> createState() => _MotorDialogState();
}

class _MotorDialogState extends State<_MotorDialog> {
  static const _alanlar = [
    _Alan('max_connections', 'Toplam bağlantı', ipucu: 'Aynı anda açık giden SMTP bağlantısı'),
    _Alan('reserved_normal', 'Normal posta için ayrılan', ipucu: 'Toplu gönderim bu bağlantıları kullanamaz'),
    _Alan('max_msgs_per_conn', 'Bağlantı başına ileti', ipucu: 'Aynı oturumda gönderilen ileti sayısı'),
    _Alan('max_rcpts_per_txn', 'İşlem başına alıcı'),
    _Alan('bulk_share', 'Toplu gönderim payı', ipucu: 'Sağlayıcı hızının toplu sınıfa açık oranı (0–1)', ondalikli: true),
    _Alan('bulk_per_tenant_min', 'Müşteri başına toplu (dk)', ipucu: '0 = sınırsız'),
    _Alan('lifetime_hours', 'Kuyruk ömrü (saat)', ipucu: 'Bu süre sonunda gönderene hata bildirimi'),
    _Alan('circuit_failures', 'Devre kesici eşiği', ipucu: 'Art arda bağlantı hatası'),
  ];

  late final _k = {for (final a in _alanlar) a.anahtar: TextEditingController(text: _sayiMetni(widget.ayar[a.anahtar]))};
  late final Map<String, (TextEditingController, TextEditingController)> _p = {
    for (final p in widget.profiller)
      metin(p['key']): (
        TextEditingController(text: '${tamsayi(harita(harita(widget.ayar['providers'])[metin(p['key'])])['max_conns'], tamsayi(p['max_conns']))}'),
        TextEditingController(text: '${tamsayi(harita(harita(widget.ayar['providers'])[metin(p['key'])])['per_minute'], tamsayi(p['per_minute']))}'),
      ),
  };
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    for (final k in _k.values) {
      k.dispose();
    }
    for (final (a, b) in _p.values) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    final govde = Map<String, dynamic>.from(widget.ayar);
    for (final a in _alanlar) {
      final v = _sayiOku(_k[a.anahtar]!.text, a.ondalikli);
      if (v == null || v < 0) return setState(() => _hata = '${a.etiket}: geçerli bir sayı girin');
      govde[a.anahtar] = v;
    }
    final saglayicilar = Map<String, dynamic>.from(harita(widget.ayar['providers']));
    for (final p in widget.profiller) {
      final (b, d) = _p[metin(p['key'])]!;
      final bv = int.tryParse(b.text.trim()), dv = int.tryParse(d.text.trim());
      if (bv == null || dv == null || bv < 0 || dv < 0) return setState(() => _hata = '${metin(p['name'])}: geçerli bir sayı girin');
      saglayicilar[metin(p['key'])] = {'max_conns': bv, 'per_minute': dv};
    }
    govde['providers'] = saglayicilar;
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.put('/api/v1/outbound/engine/config', govde);
      bildir('Kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return AlertDialog(
      title: Text('Motor sınırları', style: gosterim(19, agirlik: FontWeight.w600)),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Toplam bağlantı, öncelik payı ve sağlayıcı bazında bağlantı / dakikalık ileti sınırları. Değişiklik bir dakika içinde uygulanır.',
                style: TextStyle(color: r.soluk, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _SayiIzgarasi(alanlar: _alanlar, kontroller: _k),
              const SizedBox(height: 16),
              const Text('Sağlayıcı sınırları', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final p in widget.profiller)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: metinler(p['mx_suffixes']).join(', '),
                          child: Text(metin(p['name']), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      SizedBox(
                        width: 96,
                        child: TextField(
                          controller: _p[metin(p['key'])]!.$1,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Bağlantı', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 96,
                        child: TextField(
                          controller: _p[metin(p['key'])]!.$2,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'İleti/dk', isDense: true),
                        ),
                      ),
                    ],
                  ),
                ),
              Text('Sütunlar: bağlantı · dakikada ileti (0 = sınırsız). "Diğer" satırı her alan adına ayrı uygulanır.', style: TextStyle(color: r.silik, fontSize: 12)),
              if (_hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13))),
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

/// Platform IP ısınması (PUT /outbound/warmup {started: YYYY-MM-DD | null}).
class _IsinmaDialog extends StatefulWidget {
  const _IsinmaDialog({this.baslangic});
  final DateTime? baslangic;
  @override
  State<_IsinmaDialog> createState() => _IsinmaDialogState();
}

class _IsinmaDialogState extends State<_IsinmaDialog> {
  late DateTime _tarih = widget.baslangic ?? DateTime.now();
  bool _mesgul = false;
  String? _hata;

  String get _metin => '${_tarih.year.toString().padLeft(4, '0')}-${_tarih.month.toString().padLeft(2, '0')}-${_tarih.day.toString().padLeft(2, '0')}';

  Future<void> _gonder(String? baslangic) async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.put('/api/v1/outbound/warmup', {'started': baslangic});
      bildir(baslangic == null ? 'Isınma durduruldu' : 'Kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _sec() async {
    final simdi = DateTime.now();
    final t = await showDatePicker(
      context: context,
      initialDate: _tarih.isAfter(simdi) ? simdi : _tarih,
      firstDate: DateTime(simdi.year - 1, simdi.month, simdi.day + 1),
      lastDate: simdi,
    );
    if (t != null) setState(() => _tarih = t);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Platform IP ısınması', style: gosterim(19, agirlik: FontWeight.w600)),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Başlangıç tarihi ısınma planının hangi gününde olunduğunu belirler. Durdurmak günlük sınırı ayarlardaki değere döndürür.',
            style: TextStyle(color: context.r.soluk, fontSize: 13),
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _sec,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Başlangıç tarihi', suffixIcon: Icon(Simgeler.calendarToday)),
              child: Text(_metin),
            ),
          ),
          if (widget.baslangic != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(onPressed: _mesgul ? null : () => _gonder(null), child: const Text('Isınmayı durdur')),
            ),
          ],
          if (_hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13))),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(onPressed: _mesgul ? null : () => _gonder(_metin), child: const Text('Kaydet')),
    ],
  );
}
