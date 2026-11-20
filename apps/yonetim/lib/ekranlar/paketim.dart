import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import 'bolumler.dart';
import 'hizmet_ortak.dart';
import 'kutu_islemleri.dart' show dosyaIndir;

/// Paketim: müşterinin paketi, özellikleri, canlı kullanımı, gönderim sınırları ve toplu dışa aktarma.
/// Web: admin/package (PackageUsage + TenantUsageCard + CustomerExportPanel).
/// Uç noktalar: GET /organizations/{id}/entitlements, GET /catalog, GET /settings/limits, GET /tenants/{id}/usage,
/// GET/POST /organizations/{id}/exports.
class PaketimEkrani extends StatefulWidget {
  const PaketimEkrani({super.key, this.orgId, this.orgAdi});

  /// Ortaklar bir müşterinin paketini açarken verir; boşsa oturumdaki müşteri.
  final String? orgId, orgAdi;

  @override
  State<PaketimEkrani> createState() => _PaketimEkraniState();
}

class _PaketVerisi {
  _PaketVerisi({required this.ent, required this.katalog, required this.platform, required this.kullanim});
  final Map<String, dynamic> ent;
  final List<KatalogOzelligi> katalog;
  final Map<String, dynamic> platform;
  final Map<String, dynamic>? kullanim;
}

class _PaketimEkraniState extends State<PaketimEkrani> {
  final _anahtar = GlobalKey<TekYuklemeState<_PaketVerisi>>();
  Timer? _zamanlayici;

  String? get _org => widget.orgId ?? metinYa(Uyg.ben.value?['organization_id']);
  bool get _kendi => widget.orgId == null;

  @override
  void initState() {
    super.initState();
    // Web ile aynı: canlı kullanım 30 sn'de bir yenilenir.
    _zamanlayici = Timer.periodic(const Duration(seconds: 30), (_) => _anahtar.currentState?.yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  Future<Object?> _sessiz(Future<dynamic> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<_PaketVerisi> _getir(String org) async {
    final s = await Future.wait<Object?>([
      Uyg.api.get('/api/v1/organizations/$org/entitlements'),
      Uyg.api.get('/api/v1/catalog'),
      _sessiz(Uyg.api.get('/api/v1/settings/limits')),
      _sessiz(Uyg.api.get('/api/v1/tenants/$org/usage')),
    ]);
    return _PaketVerisi(
      ent: harita(s[0]),
      katalog: katalogOzellikleri(s[1]),
      platform: harita(harita(s[2])['limits']),
      kullanim: s[3] == null ? null : harita(s[3]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final org = _org;
    return Iskelet(
      baslik: _kendi ? 'Paketim' : '${widget.orgAdi ?? 'Müşteri'} · Paket',
      alt: _kendi ? 'Paketinizin özellikleri, canlı kullanımınız ve kalan haklarınız' : 'Müşterinin paketi, özellikleri ve canlı kullanımı',
      yenile: org == null ? null : () => _anahtar.currentState?.yenile(),
      govde: org == null
          ? const Kapali('Müşteriler bölümünde bir müşterinin menüsünden "Paket ve kullanım"ı açın.', ikon: Icons.verified_outlined)
          : TekYukleme<_PaketVerisi>(
              key: _anahtar,
              getir: () => _getir(org),
              icerik: (c, v, yenile) => IcerikListesi(
                children: [
                  ..._paket(c, v),
                  const SizedBox(height: 16),
                  if (v.kullanim != null) ...[_GonderimSinirlari(v.kullanim!), const SizedBox(height: 16)],
                  ..._ozellikler(c, v),
                  // Müşteriler kendi verilerini burada dışa aktarır; ortaklar Müşteriler → "Tümünü dışa aktar".
                  if (Uyg.musteri && _kendi && Uyg.yetki('mailboxes.manage')) ...[
                    const SizedBox(height: 16),
                    BolumKarti(
                      baslik: 'Verilerinizi dışa aktarın',
                      ikon: Icons.inventory_outlined,
                      child: DisaAktarma(orgId: org),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  List<Widget> _paket(BuildContext c, _PaketVerisi v) {
    final r = c.r;
    final plan = v.ent['plan'] is Map ? harita(v.ent['plan']) : null;
    final eff = harita(v.ent['effective']);
    final l = harita(eff['limits']);
    final f = harita(eff['features']);
    final u = harita(v.ent['usage']);
    int? sinir(String k) => tamsayiYa(l[k]);
    int k(String a) => tamsayi(u[a]);
    int? boyut(String a) => tamsayiYa(l[a]) ?? tamsayiYa(v.platform[a]);
    String bayt(int? n) => n == null ? 'Sınırsız' : boyutYaz(n);
    String alici(String a) => (sinir(a) ?? 0) > 0 ? '${sayiYaz(sinir(a))} alıcı' : 'Sınırsız';
    final varsayilan = tamsayi(plan?['default_mailbox_quota_bytes']);
    final satirlar = <(String, String)>[
      ('Kutu başı en fazla kota', bayt(sinir('max_mailbox_quota_bytes'))),
      ('Kutu başı varsayılan kota', varsayilan > 0 ? boyutYaz(varsayilan) : '—'),
      ('Gönderim (kutu başı, saatlik)', alici('send_limit_per_hour')),
      ('Gönderim (kutu başı, günlük)', alici('daily_send_limit')),
      ('Bir iletide en fazla alıcı', (sinir('max_recipients_per_message') ?? 0) > 0 ? sayiYaz(sinir('max_recipients_per_message')) : 'Sınırsız'),
      ('İleti boyutu', bayt(boyut('max_message_bytes'))),
      ('Ek toplamı (ileti başı)', bayt(boyut('max_attachment_bytes'))),
      ('İmza boyutu (resimler dahil)', bayt(boyut('max_signature_bytes'))),
    ];
    return [
      Kutu(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: r.birincil.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)),
              child: Icon(Icons.verified_rounded, color: r.birincil),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(metin(plan?['name'], 'Paketsiz (sınırsız)'), style: gosterim(18, agirlik: FontWeight.w700)),
                      const Rozet('Canlı', renk: Marka.zumrut),
                    ],
                  ),
                  Text('Kullanım 30 sn\'de bir yenilenir', style: TextStyle(color: r.silik, fontSize: 12)),
                  if (metinYa(plan?['description']) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(metin(plan?['description']), style: TextStyle(color: r.soluk, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text('Kullanım ve kalan', style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 8),
      Izgara(
        enAz: 220,
        children: [
          KullanimSayaci(
            etiket: 'Posta kutusu',
            kullanilan: k('mailboxes'),
            sinir: sinir('max_mailboxes'),
            not: '${k('mailboxes_active')} aktif · ${k('mailboxes_suspended')} askıda',
          ),
          KullanimSayaci(etiket: 'Alan adı', kullanilan: k('domains'), sinir: sinir('max_domains'), not: '${k('domains_verified')} doğrulanmış'),
          KullanimSayaci(
            etiket: 'Toplam alan (ayrılan)',
            kullanilan: k('allocated_bytes'),
            sinir: sinir('total_quota_bytes'),
            bayt: true,
            not: 'Kutularda kullanılan: ${boyutYaz(k('used_bytes'))}',
          ),
          KullanimSayaci(etiket: 'Takma ad', kullanilan: k('aliases'), sinir: sinir('max_aliases')),
          if (mantik(f['bulk_sending'])) ...[
            KullanimSayaci(etiket: 'Toplu gönderim kişileri', kullanilan: k('contacts'), sinir: sinir('max_contacts')),
            KullanimSayaci(
              etiket: 'Bu ay kampanya gönderimi',
              kullanilan: k('campaign_sends_month'),
              sinir: sinir('max_campaign_sends_monthly'),
              not: 'Takvim ayı (TSİ) başında sıfırlanır',
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),
      Izgara(
        enAz: 340,
        children: [
          Kutu(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gönderilen (tüm kutular)', style: TextStyle(color: r.soluk, fontSize: 13)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _sayi(c, k('sent_last_hour'), 'son 1 saat'),
                    const SizedBox(width: 28),
                    _sayi(c, k('sent_last_24h'), 'son 24 saat'),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Gönderim limitleri her posta kutusu için ayrı uygulanır.', style: TextStyle(color: r.silik, fontSize: 12)),
                if (_kendi) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => bolumeGit(Bolum.kutular),
                        icon: const Icon(Icons.inbox_outlined, size: 18),
                        label: const Text('Posta kutuları'),
                      ),
                      TextButton.icon(
                        onPressed: () => bolumeGit(Bolum.alanlar),
                        icon: const Icon(Icons.language_rounded, size: 18),
                        label: const Text('Alan adları'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Kutu(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Paket limitleri', style: TextStyle(color: r.soluk, fontSize: 13)),
                const SizedBox(height: 6),
                for (final (a, d) in satirlar) DegerSatiri(a, d),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Widget _sayi(BuildContext c, int n, String alt) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(sayiYaz(n), style: gosterim(22, renk: c.r.metin)),
      Text(alt, style: TextStyle(color: c.r.silik, fontSize: 12)),
    ],
  );

  List<Widget> _ozellikler(BuildContext c, _PaketVerisi v) {
    final r = c.r;
    final f = harita(harita(v.ent['effective'])['features']);
    final gruplar = KatalogOzelligi.grupla(v.katalog);
    return [
      Text(_kendi ? 'Paketinizdeki özellikler' : 'Paketteki özellikler', style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 8),
      Izgara(
        enAz: 300,
        children: [
          for (final g in gruplar.entries)
            Kutu(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(g.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 8),
                  for (final o in g.value) _ozellikSatiri(c, o, mantik(f[o.anahtar])),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '"Faz" ile işaretli özellikler pakette tanımlı olsa da henüz hizmete açılmadı; hazır olduğunda kendiliğinden etkinleşir.',
        style: TextStyle(color: r.silik, fontSize: 12),
      ),
    ];
  }

  Widget _ozellikSatiri(BuildContext c, KatalogOzelligi o, bool acik) {
    final r = c.r;
    final etkin = acik && o.hazir;
    final faz = o.faz.isEmpty ? 'yakında' : o.faz;
    final Widget rozet;
    if (!o.hazir) {
      rozet = Rozet(acik ? 'Pakette · $faz' : faz, renk: r.silik);
    } else if (acik) {
      rozet = const Rozet('Aktif', renk: Marka.zumrut);
    } else {
      rozet = Rozet(_kendi ? 'Paketinizde yok' : 'Pakette yok', renk: r.silik);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(etkin ? Icons.check_rounded : Icons.remove_rounded, size: 17, color: etkin ? Marka.zumrut : r.silik),
          const SizedBox(width: 8),
          Expanded(
            child: Text(o.ad, style: TextStyle(fontSize: 13, color: etkin ? r.metin : r.silik)),
          ),
          const SizedBox(width: 6),
          rozet,
        ],
      ),
    );
  }
}

/// Gönderim sınırları (GET /tenants/{id}/usage): müşteri başına dış gönderim sınırları ve anlık durum.
class _GonderimSinirlari extends StatelessWidget {
  const _GonderimSinirlari(this.v);
  final Map<String, dynamic> v;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final e = harita(v['effective']);
    String lim(int n) => n == 0 ? 'sınırsız' : sayiYaz(n);
    final durdu = mantik(e['paused']), yavas = mantik(e['throttled']);
    final saatlik = tamsayi(e['rcpts_per_hour']);
    final gonderilen = tamsayi(v['sent_last_hour']);
    final sebep = metin(e['reason']);
    final bekletilen = tamsayi(v['held']);
    return BolumKarti(
      baslik: 'Gönderim sınırları',
      ikon: Icons.speed_rounded,
      altBaslik: 'Platformun diğer müşterilerini korumak için müşteri başına uygulanan dış gönderim sınırları.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (durdu || yavas) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: durdu ? const Rozet('Gönderim durduruldu', renk: Marka.gul) : const Rozet('Geçici olarak yavaşlatıldı', renk: Marka.kehribar),
            ),
            const SizedBox(height: 8),
          ],
          if (durdu || yavas) ...[
            Bant(
              (durdu
                      ? 'Dış alıcılara gönderim yönetici tarafından durduruldu; iletiler kuyrukta bekletilir. Destek ile iletişime geçin.'
                      : 'Yüksek geri dönme veya kötüye kullanım riski nedeniyle gönderim hızınız ${tamZaman(tarihOku(e['throttled_until']))} saatine kadar düşürüldü.') +
                  (sebep.isEmpty ? '' : ' ($sebep)'),
              renk: Marka.kehribar,
              ikon: Icons.warning_amber_rounded,
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: Text('Son 1 saatte dış alıcı', style: TextStyle(color: r.silik, fontSize: 12)),
              ),
              Text('${sayiYaz(gonderilen)} / ${lim(saatlik)}', style: TextStyle(color: r.silik, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: saatlik <= 0 ? 0 : (gonderilen / saatlik).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: r.ic,
              color: r.birincil,
            ),
          ),
          const SizedBox(height: 12),
          Izgara(
            enAz: 150,
            children: [
              _oge(context, 'Dakikada ileti', lim(tamsayi(e['msgs_per_minute']))),
              _oge(context, 'Eşzamanlı teslim', '${tamsayi(v['running'])} / ${lim(tamsayi(e['max_concurrent']))}'),
              _oge(context, 'Kuyrukta', '${tamsayi(v['queued'])}${bekletilen > 0 ? ' ($bekletilen bekletilen)' : ''}'),
              _oge(
                context,
                'Geri dönme (24 s)',
                '%${ondalik(v['bounce_rate']).toStringAsFixed(1).replaceAll('.', ',')}',
                alt: '${sayiYaz(tamsayi(v['finished_24h']))} teslim denemesi',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _oge(BuildContext c, String etiket, String deger, {String? alt}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(etiket, style: TextStyle(color: c.r.silik, fontSize: 12)),
      Text(deger, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      if (alt != null) Text(alt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.r.silik, fontSize: 11.5)),
    ],
  );
}

/// Müşteri verilerinin toplu dışa aktarımı (GET/POST /organizations/{id}/exports). Hazır arşiv uygulama içinden İndirilenler klasörüne indirilir.
class DisaAktarma extends StatefulWidget {
  const DisaAktarma({super.key, required this.orgId});
  final String orgId;
  @override
  State<DisaAktarma> createState() => _DisaAktarmaState();
}

class _DisaAktarmaState extends State<DisaAktarma> {
  List<Map<String, dynamic>>? _liste;
  bool _hazir = true;
  String? _hata;
  bool _mesgul = false;
  Timer? _t;

  static const _etiketler = {'queued': 'Sırada', 'running': 'Hazırlanıyor', 'ready': 'Hazır', 'failed': 'Başarısız', 'expired': 'Süresi doldu'};

  bool get _etkin => (_liste ?? const []).any((x) => x['status'] == 'queued' || x['status'] == 'running');

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _yukle() async {
    _t?.cancel();
    try {
      final v = harita(await Uyg.api.get('/api/v1/organizations/${widget.orgId}/exports'));
      if (!mounted) return;
      setState(() {
        _liste = haritalar(v['items']);
        _hazir = mantik(v['available'], true);
        _hata = null;
      });
      // Hazırlanan arşiv varken 2 sn'de bir yoklanır (web ile aynı).
      if (_etkin) _t = Timer(const Duration(seconds: 2), _yukle);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _baslat() async {
    setState(() => _mesgul = true);
    final ok = await islem(
      () => Uyg.api.post('/api/v1/organizations/${widget.orgId}/exports'),
      tamam: 'Dışa aktarma başlatıldı; hazır olunca burada görünür.',
    );
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (ok != null) await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = _liste;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tüm posta kutuları tek .zip arşivinde: iletiler klasör yapısıyla .eml, kişiler .vcf, takvimler .ics. Arka planda hazırlanır; '
          'bağlantı 48 saat geçerlidir, sonra dosya silinir. Talep ve her indirme denetim kaydına yazılır.',
          style: TextStyle(color: r.soluk, fontSize: 13),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _mesgul || _etkin || !_hazir ? null : _baslat,
          icon: _mesgul || _etkin
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.inventory_outlined, size: 18),
          label: Text(_etkin ? 'Hazırlanıyor…' : 'Tümünü dışa aktar'),
        ),
        if (!_hazir)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Dışa aktarma hizmeti bu sunucuda yapılandırılmamış.', style: TextStyle(color: r.silik, fontSize: 12)),
          ),
        const SizedBox(height: 12),
        if (_hata != null)
          Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded, eylem: TextButton(onPressed: _yukle, child: const Text('Tekrar')))
        else if (l == null)
          const LinearProgressIndicator(minHeight: 2)
        else if (l.isEmpty)
          Text('Henüz dışa aktarma yapılmadı.', style: TextStyle(color: r.silik, fontSize: 13))
        else ...[
          for (final x in l) _satir(context, x),
        ],
      ],
    );
  }

  Widget _satir(BuildContext c, Map<String, dynamic> x) {
    final d = metin(x['status']);
    final renk = switch (d) {
      'ready' => Marka.zumrut,
      'failed' => Marka.gul,
      'expired' => c.r.silik,
      _ => Marka.mavi,
    };
    final silinme = tarihOku(x['expires_at']);
    final alt = switch (d) {
      'ready' =>
        '${tamsayi(x['mailboxes'])} kutu · ${sayiYaz(tamsayi(x['messages']))} ileti · ${tamsayi(x['contacts'])} kişi · '
            '${tamsayi(x['events'])} etkinlik · ${boyutYaz(tamsayi(x['size_bytes']))}${silinme != null ? ' · silinme ${tamZaman(silinme)}' : ''}',
      'failed' => metin(x['error'], 'Başarısız'),
      'expired' => '${tamsayi(x['mailboxes'])} kutu · ${boyutYaz(tamsayi(x['size_bytes']))} · dosya silindi',
      _ => '${metin(x['requested_by'])} tarafından istendi',
    };
    return ListeSatiri(
      baslik: tamZaman(tarihOku(x['created_at'])),
      alt: alt,
      sol: Rozet(_etiketler[d] ?? d, renk: renk),
      sag: d == 'ready' && x['id'] != null
          ? IconButton(
              tooltip: 'İndir',
              icon: const Icon(Icons.download_rounded),
              onPressed: () => dosyaIndir('/api/v1/organizations/${widget.orgId}/exports/${x['id']}/download',
                  'bogamail-disa-aktarim-${x['id']}.zip', baslik: 'Arşiv indiriliyor'),
            )
          : null,
    );
  }
}
