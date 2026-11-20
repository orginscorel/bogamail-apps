import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import 'altyapi_ortak.dart';
import 'bolumler.dart';
import '../ortak/simgeler.dart';

/// Depolama: kutu kullanımı, kota durumu, disk alanı, en çok alan kullanan kutular, müşteri bazında kullanım,
/// depolama verimliliği (platform) ve Çöp Kutusu / Spam otomatik temizleme. Müşteriler kendi kullanımlarını görür.
/// web: admin/(panel)/storage + storage-efficiency.
class DepolamaEkrani extends StatefulWidget {
  const DepolamaEkrani({super.key});

  @override
  State<DepolamaEkrani> createState() => _DepolamaEkraniState();
}

class _DepolamaVerisi {
  _DepolamaVerisi(this.depo, this.saklama, this.verim);
  final Map<String, dynamic> depo;
  final Map<String, dynamic>? saklama;
  final Map<String, dynamic>? verim;
}

String _gunMetni(int? d, int varsayilan) {
  final v = d ?? varsayilan;
  final s = v == 0 ? 'süresiz' : '$v gün';
  return d == null ? '$s (platform)' : s;
}

/// web: pct — bir ondalık basamağa yuvarlanmış yüzde.
String _yuzde(num kisim, num butun) {
  if (butun <= 0) return '%0';
  final binde = (kisim / butun * 1000).round();
  return binde % 10 == 0 ? '%${binde ~/ 10}' : '%${(binde / 10).toStringAsFixed(1).replaceAll('.', ',')}';
}

class _DepolamaEkraniState extends State<DepolamaEkrani> {
  final _anahtar = GlobalKey<TekYuklemeState<_DepolamaVerisi>>();
  bool _olcuyor = false;
  int _orgSayfa = 0;

  Future<_DepolamaVerisi> _getir() async {
    final api = Uyg.api;
    final sonuc = await Future.wait<Object?>([
      api.get('/api/v1/storage'),
      api.get('/api/v1/storage/retention').then<Object?>((v) => v).catchError((Object _) => null),
      Uyg.platformYoneticisi ? api.get('/api/v1/storage/efficiency').then<Object?>((v) => v).catchError((Object _) => null) : Future.value(null),
    ]);
    return _DepolamaVerisi(harita(sonuc[0]), sonuc[1] == null ? null : harita(sonuc[1]), sonuc[2] == null ? null : harita(sonuc[2]));
  }

  Future<void> _olc() async {
    setState(() => _olcuyor = true);
    final s = await islem(() => Uyg.api.post('/api/v1/storage/measure'), tamam: 'Ölçüm başlatıldı; birkaç saniye içinde güncellenir');
    if (!mounted) return;
    setState(() => _olcuyor = false);
    if (s != null) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _anahtar.currentState?.yenile();
    }
  }

  @override
  Widget build(BuildContext context) => Iskelet(
    baslik: 'Depolama',
    alt: 'Kutu kullanımı, kota durumu, disk alanı ve otomatik temizleme',
    yenile: () => _anahtar.currentState?.yenile(),
    govde: TekYukleme<_DepolamaVerisi>(
      key: _anahtar,
      getir: _getir,
      icerik: (c, v, yenile) => IcerikListesi(children: _icerik(c, v, yenile)),
    ),
  );

  List<Widget> _icerik(BuildContext context, _DepolamaVerisi v, Future<void> Function() yenile) {
    final r = context.r;
    final t = harita(v.depo['totals']);
    final diskler = v.depo['disks'] is Map ? harita(v.depo['disks']) : null;
    final kutular = haritalar(v.depo['top_mailboxes']);
    final orgler = haritalar(v.depo['organizations']);
    return [
      Izgara(
        enAz: 200,
        children: [
          KpiKarti(
            ikon: Simgeler.pieChartOutline,
            etiket: 'Kullanılan',
            deger: boyutYaz(tamsayi(t['used_bytes'])),
            alt: '${boyutYaz(tamsayi(t['allocated_bytes']))} kota tahsis edildi',
          ),
          KpiKarti(
            ikon: Simgeler.mailOutline,
            etiket: 'Saklanan ileti',
            deger: sayiYaz(tamsayi(t['messages'])),
            alt: '${tamsayi(t['mailboxes'])} posta kutusunda',
            renk: Marka.mavi,
          ),
          KpiKarti(
            ikon: Simgeler.warningAmber,
            etiket: 'Kotası %90+ dolu',
            deger: sayiYaz(tamsayi(t['above_90_percent'])),
            alt: 'uyarı eşiği',
            renk: Marka.kehribar,
          ),
          KpiKarti(
            ikon: Simgeler.block,
            etiket: 'Kotası dolu',
            deger: sayiYaz(tamsayi(t['over_quota'])),
            alt: 'yeni posta 452 ile geri çevrilir',
            renk: Marka.gul,
          ),
        ],
      ),
      if (diskler != null) ...[
        const SizedBox(height: 12),
        Izgara(
          enAz: 320,
          children: [
            _DiskKarti(baslik: 'İleti deposu', disk: diskler['store'] is Map ? harita(diskler['store']) : null, not: 'posta kutusu içerikleri'),
            _DiskKarti(baslik: 'Spool', disk: diskler['spool'] is Map ? harita(diskler['spool']) : null, not: 'teslim bekleyen iletiler'),
          ],
        ),
      ],
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (c, k) {
          final a = _enCokKart(c, kutular);
          final b = _musteriKart(c, orgler);
          if (k.maxWidth < 1000) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 12), b]);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          );
        },
      ),
      if (v.verim != null) ...[const SizedBox(height: 20), ..._verimlilik(context, v.verim!)],
      if (v.saklama != null) ...[const SizedBox(height: 16), _temizleme(context, v.saklama!, v.verim, yenile)],
      const SizedBox(height: 12),
      Text(
        'Günlük yedekleme, haftalık bütünlük taraması ve posta kutusu geri yükleme Yedekleme bölümünde; posta kutusu dışa aktarma Posta Kutuları '
        'bölümünde, müşterinin tüm kutularını dışa aktarma Müşteriler bölümündedir.',
        style: TextStyle(color: r.silik, fontSize: 12),
      ),
    ];
  }

  Widget _enCokKart(BuildContext context, List<Map<String, dynamic>> l) {
    final r = context.r;
    return BolumKarti(
      baslik: 'En çok alan kullanan posta kutuları',
      ikon: Simgeler.inbox,
      child: l.isEmpty
          ? Text('Posta kutusu yok.', style: TextStyle(color: r.soluk))
          : Column(
              children: [
                for (final (i, m) in l.indexed) ...[
                  if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    metin(m['address']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                                  ),
                                  Text(
                                    '${metin(m['organization_name'])} · ${sayiYaz(tamsayi(m['messages']))} ileti',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: r.soluk, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        KullanimCubugu(kullanilan: tamsayi(m['used_bytes']), toplam: tamsayi(m['quota_bytes'])),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _musteriKart(BuildContext context, List<Map<String, dynamic>> l) {
    final r = context.r;
    const boy = 10;
    final sayfaSayisi = l.isEmpty ? 1 : (l.length / boy).ceil();
    final sayfa = _orgSayfa.clamp(0, sayfaSayisi - 1);
    final gorunen = l.skip(sayfa * boy).take(boy).toList();
    return BolumKarti(
      baslik: Uyg.musteri ? 'Kurum kullanımı' : 'Müşteri bazında',
      altBaslik: 'Kullanılan · tahsis edilen · paket kotası',
      ikon: Simgeler.apartment,
      sag: sayfaSayisi > 1
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Önceki sayfa',
                  onPressed: sayfa > 0 ? () => setState(() => _orgSayfa = sayfa - 1) : null,
                  icon: const Icon(Simgeler.chevronLeft),
                ),
                Text('${sayfa + 1} / $sayfaSayisi', style: TextStyle(color: r.soluk, fontSize: 12)),
                IconButton(
                  tooltip: 'Sonraki sayfa',
                  onPressed: sayfa < sayfaSayisi - 1 ? () => setState(() => _orgSayfa = sayfa + 1) : null,
                  icon: const Icon(Simgeler.chevronRight),
                ),
              ],
            )
          : null,
      child: l.isEmpty
          ? Text('Kayıt yok.', style: TextStyle(color: r.soluk))
          : Column(
              children: [
                for (final (i, o) in gorunen.indexed) ...[
                  if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
                  InkWell(
                    onTap: Bolum.musteriler.gorunur ? () => bolumeGit(Bolum.musteriler, musteriId: metinYa(o['id'])) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  metin(o['name']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                                ),
                                Text('${boyutYaz(tamsayi(o['used_bytes']))} kullanılan', style: TextStyle(color: r.soluk, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${boyutYaz(tamsayi(o['allocated_bytes']))} / ${o['plan_quota_bytes'] == null ? 'sınırsız' : boyutYaz(tamsayi(o['plan_quota_bytes']))}',
                            style: TextStyle(color: r.soluk, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  List<Widget> _verimlilik(BuildContext context, Map<String, dynamic> v) {
    final r = context.r;
    final s = v['latest'] is Map ? harita(v['latest']) : null;
    final olcuyor = mantik(v['measuring']);
    final yapilandirma = harita(v['config']);
    final esik = tamsayiYa(v['disk_alert_threshold']);
    final buyume = haritalar(v['growth']);
    final gecmis = haritalar(v['history']);
    final bicim = harita(v['formats']);
    final diskToplam = tamsayiYa(s?['disk_total_bytes']);
    final diskBos = tamsayiYa(s?['disk_free_bytes']);
    final diskYuzde = diskToplam != null && diskToplam > 0 && diskBos != null ? (diskToplam - diskBos) / diskToplam * 100 : null;
    final orgler = [...haritalar(v['organizations'])]..sort((a, b) => tamsayi(b['physical_bytes']).compareTo(tamsayi(a['physical_bytes'])));
    final enCokBuyume = buyume.fold<int>(1, (a, g) => tamsayi(g['bytes']) > a ? tamsayi(g['bytes']) : a);
    final eski = tamsayi(bicim['legacy']);
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Depolama verimliliği', style: gosterim(17, agirlik: FontWeight.w600, renk: r.metin)),
                const SizedBox(height: 2),
                Text(
                  '${s == null ? 'Henüz ölçüm yok' : 'Son ölçüm ${tamZaman(tarihOku(s['taken_at']))} (${ondalik(s['seconds']).toStringAsFixed(1).replaceAll('.', ',')} sn)'}'
                  ' · iletiler zstd ile sıkıştırılır, aynı müşterideki aynı ileti bir kez saklanır.',
                  style: TextStyle(color: r.soluk, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _olcuyor || olcuyor ? null : _olc,
            icon: _olcuyor || olcuyor
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Simgeler.refresh, size: 18),
            label: Text(olcuyor ? 'Ölçülüyor' : 'Şimdi ölç'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Izgara(
        enAz: 200,
        children: [
          KpiKarti(
            ikon: Simgeler.description,
            etiket: 'Mantıksal boyut',
            deger: s == null ? '—' : boyutYaz(tamsayi(s['logical_bytes'])),
            alt: 'kotaya sayılan, sıkıştırılmamış',
          ),
          KpiKarti(
            ikon: Simgeler.save,
            etiket: 'Diskte',
            deger: s == null ? '—' : boyutYaz(tamsayi(s['allocated_bytes'])),
            alt: s == null ? null : '${boyutYaz(tamsayi(s['physical_bytes']))} dosya boyutu · ${sayiYaz(tamsayi(s['inodes']))} nesne',
            renk: Marka.mavi,
          ),
          KpiKarti(
            ikon: Simgeler.compress,
            etiket: 'Sıkıştırma tasarrufu',
            deger: s == null ? '—' : boyutYaz(tamsayi(s['compress_saved_bytes']).clamp(0, 1 << 62)),
            alt: s == null
                ? null
                : '${_yuzde(tamsayi(s['compress_saved_bytes']), tamsayi(s['unique_logical_bytes']))} · ${sayiYaz(tamsayi(s['compressed_files']))} sıkıştırılmış dosya',
            renk: Marka.zumrut,
          ),
          KpiKarti(
            ikon: Simgeler.copyAll,
            etiket: 'Tekilleştirme tasarrufu',
            deger: s == null ? '—' : boyutYaz(tamsayi(s['dedup_saved_bytes'])),
            alt: s == null ? null : '${sayiYaz(tamsayi(s['files']) - tamsayi(s['inodes']))} kopya paylaşımlı saklanıyor',
            renk: Marka.mor,
          ),
        ],
      ),
      const SizedBox(height: 12),
      Izgara(
        enAz: 380,
        children: [
          BolumKarti(
            baslik: 'Disk ve uyarı eşiği',
            ikon: Simgeler.storage,
            altBaslik: esik != null
                ? 'Disk doluluğu uyarısı %$esik eşiğinde (Uyarılar)'
                : 'Disk doluluğu uyarı kuralı yok; Uyarılar bölümünden "Disk doluluğu" kuralı ekleyin',
            sag: Bolum.alarmlar.gorunur ? TextButton(onPressed: () => bolumeGit(Bolum.alarmlar), child: const Text('Uyarılar')) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (diskToplam != null && diskToplam > 0 && diskBos != null) ...[
                  KullanimCubugu(kullanilan: diskToplam - diskBos, toplam: diskToplam, yazi: false),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      text: '${_yuzde(diskToplam - diskBos, diskToplam)} dolu · ${boyutYaz(diskBos)} boş / ${boyutYaz(diskToplam)}',
                      children: [
                        if (esik != null && diskYuzde != null && diskYuzde >= esik)
                          const TextSpan(
                            text: ' · eşik aşıldı',
                            style: TextStyle(color: Marka.gul, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                    style: TextStyle(color: r.soluk, fontSize: 12),
                  ),
                ] else
                  Text('Veri yok', style: TextStyle(color: r.soluk)),
                const SizedBox(height: 8),
                Text(
                  'Kayıt biçimi: ${sayiYaz(tamsayi(bicim['compressed']))} sıkıştırılmış · ${sayiYaz(tamsayi(bicim['plain']))} düz (küçük/sıkışmayan) · '
                  '${sayiYaz(eski)} eski düz${eski > 0 ? (mantik(yapilandirma['Migrate']) ? ' (arka planda sıkıştırılıyor)' : ' (geçiş kapalı)') : ''}'
                  '${s != null && (tamsayi(s['tmp_leftovers']) > 0 || tamsayi(s['spool_leftovers']) > 0) ? ' · artık geçici dosya: depo ${tamsayi(s['tmp_leftovers'])}, spool ${tamsayi(s['spool_leftovers'])}' : ''}',
                  style: TextStyle(color: r.silik, fontSize: 12),
                ),
              ],
            ),
          ),
          BolumKarti(
            baslik: 'Büyüme (son 30 gün)',
            ikon: Simgeler.trendingUp,
            altBaslik: 'Gün içinde saklanan ve hâlâ duran iletilerin mantıksal boyutu',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 96,
                  child: buyume.isEmpty
                      ? Center(
                          child: Text('Veri yok', style: TextStyle(color: r.silik)),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final g in buyume)
                              Expanded(
                                child: Tooltip(
                                  message: '${metin(g['day'])}: ${boyutYaz(tamsayi(g['bytes']))} · ${tamsayi(g['messages'])} ileti',
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: .5),
                                    height: (tamsayi(g['bytes']) / enCokBuyume * 96).clamp(2, 96).toDouble(),
                                    decoration: BoxDecoration(
                                      color: r.birincil.withValues(alpha: .7),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Toplam ${boyutYaz(buyume.fold<int>(0, (a, g) => a + tamsayi(g['bytes'])))} · '
                  '${sayiYaz(buyume.fold<int>(0, (a, g) => a + tamsayi(g['messages'])))} ileti'
                  '${gecmis.length > 1 ? ' · ${gecmis.length} günlük ölçüm geçmişi' : ''}',
                  style: TextStyle(color: r.silik, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      if (orgler.isNotEmpty) ...[
        const SizedBox(height: 12),
        BolumKarti(
          baslik: 'Müşteri bazında disk kullanımı',
          altBaslik: 'Son ölçüme göre; paylaşılan (tekilleştirilmiş) dosyalar ilk sahibine sayılır',
          ikon: Simgeler.apartment,
          child: Column(
            children: [
              for (final (i, o) in orgler.take(20).indexed) ...[
                if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              metin(o['name']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                            ),
                            Text(
                              '${boyutYaz(tamsayi(o['logical_bytes']))} mantıksal · ${sayiYaz(tamsayi(o['files']))} dosya',
                              style: TextStyle(color: r.soluk, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        boyutYaz(tamsayi(o['physical_bytes'])),
                        style: TextStyle(color: r.metin, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  Widget _temizleme(BuildContext context, Map<String, dynamic> d, Map<String, dynamic>? verim, Future<void> Function() yenile) {
    final r = context.r;
    final p = harita(d['platform']);
    final cop = tamsayi(p['trash_days']), spam = tamsayi(p['junk_days']);
    final orgler = haritalar(d['organizations']);
    final temizlemeler = haritalar(verim?['cleanup_runs']);
    return BolumKarti(
      baslik: 'Otomatik temizleme',
      ikon: Simgeler.autoDelete,
      altBaslik:
          'Çöp Kutusu ve Spam klasöründeki iletiler, klasöre girdikten belirtilen gün sonra kalıcı olarak silinir (0 = süresiz sakla).'
          '${mantik(d['enabled'], true) ? '' : ' Sunucuda temizleme kapalı (BOGAMAIL_STORE_RETENTION=off).'}',
      sag: mantik(d['can_edit_platform'])
          ? IconButton(
              tooltip: 'Platform varsayılanını düzenle',
              onPressed: () => _saklamaDuzenle(context, d, null, yenile),
              icon: const Icon(Simgeler.tune),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              text: 'Platform varsayılanı: Çöp Kutusu ',
              children: [
                TextSpan(
                  text: cop == 0 ? 'süresiz' : '$cop gün',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const TextSpan(text: ' · Spam '),
                TextSpan(
                  text: spam == 0 ? 'süresiz' : '$spam gün',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            style: TextStyle(color: r.metin, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          for (final (i, o) in orgler.indexed) ...[
            if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                metin(o['name']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Çöp ${_gunMetni(tamsayiYa(o['trash_days']), cop)} · Spam ${_gunMetni(tamsayiYa(o['junk_days']), spam)}'),
              trailing: IconButton(
                tooltip: 'Temizleme ayarını düzenle',
                onPressed: () => _saklamaDuzenle(context, d, o, yenile),
                icon: const Icon(Simgeler.edit, size: 20),
              ),
            ),
          ],
          if (temizlemeler.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Son temizlemeler: ${temizlemeler.take(5).map((t) => '${kisaZaman(tarihOku(t['at']))}: ${tamsayi(t['messages'])} ileti, ${boyutYaz(tamsayi(t['bytes']))}${metinYa(t['error']) != null ? ' (hata)' : ''}').join(' · ')}',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  /// Platform (org == null) ya da müşteri temizleme ayarı: PUT /storage/retention/platform | /storage/retention/org/{id}.
  Future<void> _saklamaDuzenle(BuildContext context, Map<String, dynamic> d, Map<String, dynamic>? org, Future<void> Function() yenile) async {
    final p = harita(d['platform']);
    String ilk(Object? v) => v == null ? '' : '${tamsayi(v)}';
    final cop = TextEditingController(text: org == null ? '${tamsayi(p['trash_days'])}' : ilk(org['trash_days']));
    final spam = TextEditingController(text: org == null ? '${tamsayi(p['junk_days'])}' : ilk(org['junk_days']));
    final form = GlobalKey<FormState>();
    String? dogrula(String? s) {
      final t = (s ?? '').trim();
      if (t.isEmpty) return null;
      final n = int.tryParse(t);
      if (n == null || n < 0 || n > 3650) return '0–3650 gün olmalı (0 = süresiz sakla)';
      return null;
    }

    int? coz(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());
    final sonuc = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(org == null ? 'Platform varsayılanı: otomatik temizleme' : '${metin(org['name'])}: otomatik temizleme'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Gün sayısı ileti klasöre taşındığından itibaren sayılır. 0 = süresiz sakla.${org != null ? ' Boş bırakılan alan platform varsayılanını kullanır.' : ''}',
                  style: TextStyle(color: c.r.soluk, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: cop,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: dogrula,
                  decoration: InputDecoration(labelText: 'Çöp Kutusu (gün)', hintText: org != null ? 'platform: ${tamsayi(p['trash_days'])}' : null),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: spam,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: dogrula,
                  decoration: InputDecoration(labelText: 'Spam (gün)', hintText: org != null ? 'platform: ${tamsayi(p['junk_days'])}' : null),
                ),
                if (org != null) ...[
                  const SizedBox(height: 8),
                  EylemSatiri(
                    ikon: Simgeler.settingsBackupRestore,
                    baslik: 'Platform varsayılanına dön',
                    ipucu: 'Bu müşteriye özel ayarı kaldırır',
                    onTap: () => Navigator.pop(c, 'sifirla'),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, 'kaydet');
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    final copGun = coz(cop.text), spamGun = coz(spam.text);
    cop.dispose();
    spam.dispose();
    if (sonuc == null) return;
    final Future<dynamic> Function() f;
    if (org == null) {
      f = () => Uyg.api.put('/api/v1/storage/retention/platform', {'trash_days': copGun ?? 0, 'junk_days': spamGun ?? 0});
    } else {
      final govde = sonuc == 'sifirla' ? {'trash_days': null, 'junk_days': null} : {'trash_days': copGun, 'junk_days': spamGun};
      f = () => Uyg.api.put('/api/v1/storage/retention/org/${metin(org['id'])}', govde);
    }
    if (await islem(f, tamam: 'Temizleme ayarı kaydedildi') != null) await yenile();
  }
}

class _DiskKarti extends StatelessWidget {
  const _DiskKarti({required this.baslik, required this.disk, required this.not});
  final String baslik, not;
  final Map<String, dynamic>? disk;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = disk;
    return Kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(SimgelerKalin.storage, size: 16, color: r.soluk),
              const SizedBox(width: 8),
              Text(baslik, style: TextStyle(color: r.soluk, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text(d == null ? 'Ölçülemedi' : '${boyutYaz(tamsayi(d['free_bytes']))} boş', style: gosterim(20, agirlik: FontWeight.w600, renk: r.metin)),
          if (d != null) ...[const SizedBox(height: 8), KullanimCubugu(kullanilan: tamsayi(d['used_bytes']), toplam: tamsayi(d['total_bytes']), yazi: false)],
          const SizedBox(height: 8),
          Text(
            '${d == null ? '' : '${boyutYaz(tamsayi(d['used_bytes']))} / ${boyutYaz(tamsayi(d['total_bytes']))} · '}${tire(metin(d?['path']))} · $not',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
