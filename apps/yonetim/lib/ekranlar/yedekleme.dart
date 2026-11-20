import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/secimler.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'altyapi_ortak.dart';
import '../ortak/simgeler.dart';
import 'kutu_islemleri.dart' show kutuyuDisariAktar;

/// Yedekleme (süper yönetici): günlük platform yedeği (zamanlama, son çalıştırmalar, "Şimdi yedekle"), yedek diski,
/// yedeklenen verilerin bugünkü durumu ve haftalık bütünlük taraması. web: admin/(panel)/backup + integrity-alert.
class YedeklemeEkrani extends StatefulWidget {
  const YedeklemeEkrani({super.key});

  @override
  State<YedeklemeEkrani> createState() => _YedeklemeEkraniState();
}

const _saatDilimleri = ['Europe/Istanbul', 'UTC', 'Europe/Berlin', 'Europe/London'];
const _gunler = ['Pazar', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi'];

const _calistirmaEtiketleri = {'running': 'Sürüyor', 'ok': 'Başarılı', 'failed': 'Başarısız', 'skipped': 'Atlandı', 'expired': 'Silindi (saklama)'};

Color _calistirmaRengi(BuildContext c, String d) => switch (d) {
  'ok' => Marka.zumrut,
  'running' => Marka.mavi,
  'failed' || 'skipped' => Marka.gul,
  _ => c.r.silik,
};

String _sn(double s) => '${s.round() < 1 ? 1 : s.round()} sn';

class _YedeklemeEkraniState extends State<YedeklemeEkrani> {
  Map<String, dynamic>? _durum;
  String? _hata;
  List<Map<String, dynamic>>? _calistirmalar;
  Map<String, dynamic>? _butunluk;
  String? _butunlukHatasi;
  bool _yukleniyor = false, _basliyor = false, _taraniyor = false;
  Timer? _zamanlayici;
  int _sayfa = 0;

  @override
  void initState() {
    super.initState();
    if (Uyg.platformYoneticisi) _yukle();
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  Map<String, dynamic>? get _bilgi => _durum?['backup'] is Map ? harita(_durum!['backup']) : null;
  bool get _yedekSuruyor => mantik(_bilgi?['running']);
  bool get _taramaSuruyor => _butunluk?['running'] is Map;

  Future<void> _yukle({bool sessiz = false}) async {
    if (!sessiz) setState(() => _yukleniyor = true);
    final api = Uyg.api;
    Object? durum, calistirma, butunluk;
    String? hata, bHata;
    await Future.wait([
      api.get('/api/v1/backup/status').then((v) => durum = v).catchError((Object e) => hata = hataMetni(e)),
      api.get('/api/v1/backup/runs').then((v) => calistirma = v).catchError((Object e) => null),
      api.get('/api/v1/backup/integrity').then((v) => butunluk = v).catchError((Object e) => bHata = hataMetni(e)),
    ]);
    if (!mounted) return;
    setState(() {
      _yukleniyor = false;
      _hata = hata;
      if (durum != null) _durum = harita(durum);
      if (calistirma != null) _calistirmalar = haritalar(harita(calistirma)['items']);
      _butunlukHatasi = bHata;
      if (butunluk != null) _butunluk = harita(butunluk);
    });
    _zamanlayiciKur();
  }

  /// Yedek ya da tarama sürüyorsa 3 sn'de bir yenile (web: refreshInterval 3000).
  void _zamanlayiciKur() {
    final gerek = _yedekSuruyor || _taramaSuruyor;
    if (gerek && _zamanlayici == null) {
      _zamanlayici = Timer.periodic(const Duration(seconds: 3), (_) => _yukle(sessiz: true));
    } else if (!gerek) {
      _zamanlayici?.cancel();
      _zamanlayici = null;
    }
  }

  Future<void> _simdiYedekle() async {
    if (!await onayla(context, 'Şimdi yedekle', mesaj: 'Veritabanı, ileti deposu ve kutu anlık görüntüleri yedeklenir. Başlatılsın mı?', evet: 'Başlat')) {
      return;
    }
    setState(() => _basliyor = true);
    await islem(() => Uyg.api.post('/api/v1/backup/run'), tamam: 'Yedekleme başlatıldı');
    if (mounted) setState(() => _basliyor = false);
    await _yukle(sessiz: true);
  }

  Future<void> _simdiTara() async {
    setState(() => _taraniyor = true);
    await islem(() => Uyg.api.post('/api/v1/backup/integrity/scan'), tamam: 'Bütünlük taraması başlatıldı');
    if (mounted) setState(() => _taraniyor = false);
    await _yukle(sessiz: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi) {
      return const Iskelet(baslik: 'Yedekleme', govde: Kapali('Yedekleme yalnızca platform yöneticisine açıktır.'));
    }
    return Iskelet(
      baslik: 'Yedekleme',
      alt: 'Günlük platform yedeği, saklama ve bütünlük taraması',
      yenile: _yukleniyor ? null : _yukle,
      govde: _durum == null && _hata == null
          ? const Durum.yukleniyor()
          : _durum == null
          ? Durum.hata(_hata!, tekrar: _yukle)
          : RefreshIndicator.adaptive(
              onRefresh: _yukle,
              child: IcerikListesi(children: _icerik(context)),
            ),
    );
  }

  List<Widget> _icerik(BuildContext context) {
    final r = context.r;
    final d = _durum!;
    final bilgi = _bilgi;
    final son = ButunlukTaramasi.coz(_butunluk?['last']);
    return [
      if (son != null && son.sorunlu) ...[ButunlukBandi(tarama: son), const SizedBox(height: 12)],
      const Bant(
        'Yedekler bu sunucunun diskinde duruyor. Günlük yedek silinen/bozulan veriyi geri getirir; disk veya sunucu kaybına karşı korumaz. '
        'Tüm platformu geri yükleme bilerek bir düğme değildir (geri alınamaz): adımlar docs/operations/BACKUP-RESTORE.md içinde.',
        renk: Marka.kehribar,
        ikon: Simgeler.warningAmber,
      ),
      const SizedBox(height: 12),
      if (bilgi == null)
        BolumKarti(
          baslik: 'Platform yedeği',
          child: Text('Yedekleme hizmeti bu süreçte yapılandırılmamış.', style: TextStyle(color: r.soluk)),
        )
      else ...[
        Izgara(
          enAz: 300,
          children: [
            _ZamanlamaKarti(key: ValueKey('z${bilgi['schedule']}'), bilgi: bilgi, kaydedildi: () => _yukle(sessiz: true)),
            _sonYedekKarti(context, bilgi),
            _diskKarti(context, bilgi),
          ],
        ),
        const SizedBox(height: 12),
        _calistirmalarKarti(context),
        const SizedBox(height: 12),
        _butunlukKarti(context),
      ],
      const SizedBox(height: 16),
      Text(
        'Yedeklenen veriler (bugünkü durum)',
        style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
      ),
      const SizedBox(height: 8),
      _veriler(context, d),
      const SizedBox(height: 8),
      Text(
        'Redis yalnızca oturum sınırlayıcıları ve canlı bildirimler içindir; yedeklenmesi gerekmez. '
        'Son dışa aktarma: ${tarihOku(d['last_export_at']) == null ? 'hiç' : goreliZaman(tarihOku(d['last_export_at']))}.',
        style: TextStyle(color: r.silik, fontSize: 12),
      ),
      const SizedBox(height: 16),
      BolumKarti(
        baslik: 'Dışa aktarma ve geri yükleme',
        ikon: Simgeler.unarchive,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bir posta kutusunun tüm iletilerini .zip (EML) olarak indirin: mobilde paylaşım sayfasıyla kaydedilir, masaüstünde İndirilenler '
              'klasörüne yazılır ve açılabilir. İşlem denetim kaydına yazılır ve kutu sahibi güvenlik kaydında görür. Kutu geri yükleme: '
              'Posta Kutuları → kutu → "Yedekten geri yükle". Bir müşterinin tüm kutuları için: Müşteriler → Yönet → "Tümünü dışa aktar".',
              style: TextStyle(color: r.soluk, fontSize: 13),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => _kutuDisaAktar(context),
              icon: const Icon(Simgeler.archive, size: 18),
              label: const Text('Posta kutusunu dışa aktar'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      BolumKarti(
        baslik: 'Planlanan: Sunucu dışı kopya',
        ikon: Simgeler.cloudUpload,
        sag: Rozet('Onay bekliyor', renk: r.soluk),
        child: Text(
          'Yedekler şu anda aynı diskte. Disk/sunucu kaybına karşı şifreli, sunucu dışı bir hedefe (S3 uyumlu depolama vb.) kopyalama sahibin '
          'onayı ve erişim bilgileri gerektirir.',
          style: TextStyle(color: r.soluk, fontSize: 13),
        ),
      ),
    ];
  }

  Widget _sonYedekKarti(BuildContext context, Map<String, dynamic> bilgi) {
    final r = context.r;
    final son = harita(bilgi['last_run']);
    final basarili = harita(bilgi['last_success']);
    final sonDurum = metin(son['status']);
    final suruyor = _yedekSuruyor;
    return BolumKarti(
      baslik: 'Son yedek',
      ikon: Simgeler.storage,
      altBaslik: basarili.isEmpty
          ? 'Henüz başarılı yedek yok'
          : 'Son başarılı: ${goreliZaman(tarihOku(basarili['finished_at']))} · ${boyutYaz(tamsayi(basarili['total_bytes']))}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (son.isNotEmpty && !{'ok', 'running', 'expired'}.contains(sonDurum)) ...[
            Text(
              'Son çalıştırma ${(_calistirmaEtiketleri[sonDurum] ?? sonDurum).toLowerCase()}: ${tire(metin(son['error']))}',
              style: const TextStyle(color: Marka.gul, fontSize: 13),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Veritabanı dökümü (pg_dump), ileti deposu + karantina arşivi ve paketinde yedek olan her kutu için ayrı anlık görüntü. '
            'Her dosyanın SHA-256 özeti manifest.json içinde.',
            style: TextStyle(color: r.soluk, fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _basliyor || suruyor ? null : _simdiYedekle,
            icon: _basliyor || suruyor
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Simgeler.playArrow),
            label: Text(suruyor ? 'Yedekleniyor…' : 'Şimdi yedekle'),
          ),
        ],
      ),
    );
  }

  Widget _diskKarti(BuildContext context, Map<String, dynamic> bilgi) {
    final r = context.r;
    final ok = mantik(bilgi['disk_stat_ok']);
    final toplam = tamsayi(bilgi['disk_total_bytes']), bos = tamsayi(bilgi['disk_free_bytes']);
    return BolumKarti(
      baslik: 'Yedek diski',
      ikon: Simgeler.save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(boyutYaz(tamsayi(bilgi['kept_bytes'])), style: gosterim(22, agirlik: FontWeight.w600, renk: r.metin)),
          const SizedBox(height: 8),
          if (ok && toplam > 0) ...[KullanimCubugu(kullanilan: toplam - bos, toplam: toplam), const SizedBox(height: 8)],
          Text(
            '${tamsayi(bilgi['kept_runs'])} yedek saklanıyor${ok ? ' · diskte ${boyutYaz(bos)} boş' : ''} · '
            '${tamsayi(bilgi['snapshot_mailboxes'])} kutu paketinde günlük yedek var',
            style: TextStyle(color: r.soluk, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            metin(bilgi['dir']),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: r.silik, fontSize: 11.5, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _calistirmalarKarti(BuildContext context) {
    final r = context.r;
    final l = _calistirmalar;
    const boy = 10;
    final sayfaSayisi = l == null || l.isEmpty ? 1 : (l.length / boy).ceil();
    final sayfa = _sayfa.clamp(0, sayfaSayisi - 1);
    final gorunen = l == null ? <Map<String, dynamic>>[] : l.skip(sayfa * boy).take(boy).toList();
    return BolumKarti(
      baslik: 'Son çalıştırmalar',
      ikon: Simgeler.history,
      sag: sayfaSayisi > 1
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Önceki sayfa',
                  onPressed: sayfa > 0 ? () => setState(() => _sayfa = sayfa - 1) : null,
                  icon: const Icon(Simgeler.chevronLeft),
                ),
                Text('${sayfa + 1} / $sayfaSayisi', style: TextStyle(color: r.soluk, fontSize: 12)),
                IconButton(
                  tooltip: 'Sonraki sayfa',
                  onPressed: sayfa < sayfaSayisi - 1 ? () => setState(() => _sayfa = sayfa + 1) : null,
                  icon: const Icon(Simgeler.chevronRight),
                ),
              ],
            )
          : null,
      child: l == null
          ? Text('Çalıştırmalar yüklenemedi.', style: TextStyle(color: r.soluk))
          : l.isEmpty
          ? Text('Henüz yedek alınmadı.', style: TextStyle(color: r.soluk))
          : Column(
              children: [
                for (final (i, c) in gorunen.indexed) ...[if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)), _calistirmaSatiri(context, c)],
              ],
            ),
    );
  }

  Widget _calistirmaSatiri(BuildContext context, Map<String, dynamic> c) {
    final r = context.r;
    final durum = metin(c['status']);
    final tamam = durum == 'ok' || durum == 'expired';
    final bitti = tarihOku(c['finished_at']) != null;
    final tur = metin(c['trigger']) == 'manual' ? 'Elle (${metin(c['requested_by'])})' : 'Zamanlanmış';
    final toplam = tamsayi(c['total_bytes']);
    final genis = context.genis;
    final ayrinti = [
      tur,
      if (bitti) _sn(ondalik(c['duration_seconds'])),
      if (tamam) 'Veritabanı ${boyutYaz(tamsayi(c['db_bytes']))}',
      if (tamam) 'Depo ${boyutYaz(tamsayi(c['store_bytes']))}',
      if (tamam) '${tamsayi(c['mailboxes'])} kutu · ${boyutYaz(tamsayi(c['mailbox_bytes']))}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        tamZaman(tarihOku(c['started_at'])),
                        style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Rozet(_calistirmaEtiketleri[durum] ?? durum, renk: _calistirmaRengi(context, durum)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  ayrinti,
                  maxLines: genis ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: r.soluk, fontSize: 12),
                ),
                if (metinYa(c['error']) != null)
                  Text(
                    metin(c['error']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Marka.gul, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            toplam > 0 ? boyutYaz(toplam) : '—',
            style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _butunlukKarti(BuildContext context) {
    final r = context.r;
    final b = _butunluk;
    final son = ButunlukTaramasi.coz(b?['last']);
    final suren = ButunlukTaramasi.coz(b?['running']);
    final sonraki = tarihOku(b?['next_run_at']);
    String durumMetni;
    if (suren != null) {
      durumMetni = 'Tarama sürüyor (${goreliZaman(suren.baslangic)} başladı)…';
    } else if (son != null) {
      durumMetni = 'Son tarama: ${tamZaman(son.bitis ?? son.baslangic)} · ${son.tetik == 'manual' ? 'elle' : 'zamanlanmış'} · ${_sn(son.sure)}';
    } else {
      durumMetni = 'Henüz tarama yapılmadı.';
    }
    if (sonraki != null) durumMetni += ' · Sonraki: ${tamZaman(sonraki)}';
    return BolumKarti(
      baslik: 'Bütünlük taraması',
      ikon: Simgeler.verifiedUser,
      altBaslik:
          'İleti dosyaları veritabanı kaydıyla (SHA-256 ve boyut) karşılaştırılır, sahipsiz dosyalar ve son yedeğin manifesti denetlenir. '
          'Salt okunurdur: hiçbir dosya silinmez veya onarılmaz.',
      sag: son == null
          ? null
          : Rozet(
              son.durum == 'ok' ? 'Sorun yok' : (son.durum == 'problems' ? 'Sorun bulundu' : 'Başarısız'),
              renk: son.durum == 'ok' ? Marka.zumrut : Marka.gul,
            ),
      child: b == null
          ? (_butunlukHatasi != null
                ? Text(_butunlukHatasi!, style: const TextStyle(color: Marka.gul))
                : const SizedBox(height: 60, child: Center(child: CircularProgressIndicator.adaptive())))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(durumMetni, style: TextStyle(color: r.soluk, fontSize: 13)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(onPressed: () => _gecmis(context), icon: const Icon(Simgeler.history, size: 18), label: const Text('Geçmiş')),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: _taraniyor || suren != null ? null : _simdiTara,
                          icon: _taraniyor || suren != null
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Simgeler.verifiedUser, size: 18),
                          label: Text(suren != null ? 'Taranıyor…' : 'Şimdi tara'),
                        ),
                      ],
                    ),
                  ],
                ),
                if (son != null) ...[const SizedBox(height: 12), _TaramaAyrintisi(tarama: son)],
                const SizedBox(height: 12),
                _TaramaZamanlamasi(key: ValueKey('t${b['schedule']}'), zamanlama: harita(b['schedule']), kaydedildi: () => _yukle(sessiz: true)),
              ],
            ),
    );
  }

  Future<void> _gecmis(BuildContext context) async {
    final govde = _TaramaGecmisi();
    if (context.genis) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Bütünlük taraması geçmişi'),
          content: SizedBox(width: 640, height: 520, child: govde),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        ),
      );
    } else {
      await sayfaAc<void>(context, 'Tarama geçmişi', govde);
    }
  }

  Widget _veriler(BuildContext context, Map<String, dynamic> d) {
    final db = harita(d['database']);
    final depo = harita(d['store']);
    final yollar = harita(d['paths']);
    Map<String, dynamic>? disk(String k) => yollar[k] is Map ? harita(yollar[k]) : null;
    final spool = disk('spool'), karantina = disk('quarantine');
    return Izgara(
      enAz: 240,
      children: [
        _VeriKutusu(
          ikon: Simgeler.dns,
          baslik: 'Veritabanı (PostgreSQL)',
          deger: boyutYaz(tamsayi(db['size_bytes'])),
          not: '${metin(db['name'])} · PostgreSQL ${metin(db['version'])} · hesaplar, klasörler, ileti dizini, denetim kayıtları',
        ),
        _VeriKutusu(
          ikon: Simgeler.inventory2,
          baslik: 'İleti deposu',
          deger: boyutYaz(tamsayi(depo['bytes'])),
          not: '${sayiYaz(tamsayi(depo['messages']))} ileti · ${tamsayi(depo['mailboxes'])} kutu',
          yol: metin(d['store_dir']),
          disk: disk('store'),
        ),
        _VeriKutusu(
          ikon: Simgeler.outbox,
          baslik: 'Spool (teslim bekleyen)',
          deger: spool == null ? 'Ölçülemedi' : '${boyutYaz(tamsayi(spool['free_bytes']))} boş',
          not: 'Geçici; teslimden sonra silinir',
          yol: metin(d['spool_dir']),
          disk: spool,
        ),
        _VeriKutusu(
          ikon: Simgeler.gppMaybe,
          baslik: 'Karantina',
          deger: karantina == null ? 'Ölçülemedi' : '${boyutYaz(tamsayi(karantina['free_bytes']))} boş',
          not: 'Süresi dolunca temizlenir',
          yol: metin(d['quarantine_dir']),
          disk: karantina,
        ),
      ],
    );
  }
}

class _VeriKutusu extends StatelessWidget {
  const _VeriKutusu({required this.ikon, required this.baslik, required this.deger, required this.not, this.yol, this.disk});
  final IconData ikon;
  final String baslik, deger, not;
  final String? yol;
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
              Icon(ikon, size: 16, color: r.soluk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(baslik, style: TextStyle(color: r.soluk, fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(deger, style: gosterim(19, agirlik: FontWeight.w600, renk: r.metin)),
          const SizedBox(height: 8),
          if (d != null && tamsayi(d['total_bytes']) > 0) ...[
            KullanimCubugu(kullanilan: tamsayi(d['used_bytes']), toplam: tamsayi(d['total_bytes'])),
            const SizedBox(height: 8),
          ],
          Text(not, style: TextStyle(color: r.soluk, fontSize: 12)),
          if (yol != null && yol!.isNotEmpty)
            Text(
              yol!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: r.silik, fontSize: 11.5, fontFamily: 'monospace'),
            ),
        ],
      ),
    );
  }
}

/// Saat seçici alanı ("SS:DD").
class _SaatAlani extends StatelessWidget {
  const _SaatAlani({required this.deger, required this.degisti, this.hata});
  final String deger;
  final ValueChanged<String> degisti;
  final String? hata;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () async {
      final p = deger.split(':');
      final s = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: int.tryParse(p.first) ?? 3, minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
      );
      if (s != null) degisti('${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}');
    },
    child: InputDecorator(
      decoration: InputDecoration(labelText: 'Saat', errorText: hata, suffixIcon: const Icon(Simgeler.schedule, size: 18)),
      child: Text(deger),
    ),
  );
}

/// Günlük yedek zamanlaması (PUT /backup/schedule: enabled, time, timezone, retention_days).
class _ZamanlamaKarti extends StatefulWidget {
  const _ZamanlamaKarti({super.key, required this.bilgi, required this.kaydedildi});
  final Map<String, dynamic> bilgi;
  final VoidCallback kaydedildi;

  @override
  State<_ZamanlamaKarti> createState() => _ZamanlamaKartiState();
}

class _ZamanlamaKartiState extends State<_ZamanlamaKarti> {
  late Map<String, dynamic> _ilk;
  late bool _acik;
  late String _saat, _dilim;
  late final TextEditingController _saklama;
  bool _mesgul = false;
  String? _alan, _hata;

  @override
  void initState() {
    super.initState();
    _ilk = harita(widget.bilgi['schedule']);
    _acik = mantik(_ilk['enabled']);
    _saat = metin(_ilk['time'], '03:00');
    _dilim = metin(_ilk['timezone'], 'Europe/Istanbul');
    _saklama = TextEditingController(text: '${tamsayi(_ilk['retention_days'], 7)}');
    _saklama.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _saklama.dispose();
    super.dispose();
  }

  int get _gun => int.tryParse(_saklama.text.trim()) ?? 0;

  bool get _degisti =>
      _acik != mantik(_ilk['enabled']) || _saat != metin(_ilk['time']) || _dilim != metin(_ilk['timezone']) || _gun != tamsayi(_ilk['retention_days']);

  Future<void> _kaydet() async {
    if (_gun < 1 || _gun > 90) {
      setState(() {
        _alan = 'retention_days';
        _hata = 'Saklama 1–90 arasında olmalı';
      });
      return;
    }
    setState(() {
      _mesgul = true;
      _alan = _hata = null;
    });
    try {
      await Uyg.api.put('/api/v1/backup/schedule', {'enabled': _acik, 'time': _saat, 'timezone': _dilim, 'retention_days': _gun});
      bildir('Yedekleme zamanı kaydedildi', tur: MesajTur.basari);
      widget.kaydedildi();
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _alan = e.alan;
          _hata = e.mesaj;
        });
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final sonraki = tarihOku(widget.bilgi['next_run_at']);
    final dilimler = _saatDilimleri.contains(_dilim) ? _saatDilimleri : [_dilim, ..._saatDilimleri];
    return BolumKarti(
      baslik: 'Zamanlama',
      ikon: Simgeler.eventRepeat,
      altBaslik: mantik(_ilk['enabled']) && sonraki != null ? 'Sonraki yedek: ${tamZaman(sonraki)}' : 'Zamanlanmış yedek kapalı',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _acik,
            onChanged: (v) => setState(() => _acik = v),
            title: const Text('Her gün otomatik yedek al', style: TextStyle(fontSize: 14)),
          ),
          Row(
            children: [
              Expanded(
                child: _SaatAlani(deger: _saat, hata: _alan == 'time' ? _hata : null, degisti: (v) => setState(() => _saat = v)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _saklama,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Saklanan yedek', errorText: _alan == 'retention_days' ? _hata : null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _dilim,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Saat dilimi', errorText: _alan == 'timezone' ? _hata : null),
            items: [for (final z in dilimler) DropdownMenuItem(value: z, child: Text(z))],
            onChanged: (v) => setState(() => _dilim = v ?? _dilim),
          ),
          const SizedBox(height: 8),
          Text(
            'Son ${_gun > 0 ? _gun : 'N'} başarılı yedek tutulur, daha eskileri silinir (elle alınanlar da sayılır).',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
          if (_hata != null && _alan == null) Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 12.5)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: !_degisti || _mesgul ? null : _kaydet,
              icon: _mesgul
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Simgeler.save, size: 18),
              label: const Text('Kaydet'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Haftalık bütünlük taraması zamanlaması (PUT /backup/integrity/schedule).
class _TaramaZamanlamasi extends StatefulWidget {
  const _TaramaZamanlamasi({super.key, required this.zamanlama, required this.kaydedildi});
  final Map<String, dynamic> zamanlama;
  final VoidCallback kaydedildi;

  @override
  State<_TaramaZamanlamasi> createState() => _TaramaZamanlamasiState();
}

class _TaramaZamanlamasiState extends State<_TaramaZamanlamasi> {
  late bool _acik;
  late int _gun;
  late String _saat;
  late final TextEditingController _hiz;
  bool _mesgul = false;
  String? _alan, _hata;

  Map<String, dynamic> get _z => widget.zamanlama;

  @override
  void initState() {
    super.initState();
    _acik = mantik(_z['enabled']);
    _gun = tamsayi(_z['weekday']).clamp(0, 6);
    _saat = metin(_z['time'], '04:00');
    _hiz = TextEditingController(text: '${tamsayi(_z['read_mb_per_sec'], 50)}');
    _hiz.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _hiz.dispose();
    super.dispose();
  }

  int get _mb => int.tryParse(_hiz.text.trim()) ?? 0;

  bool get _degisti => _acik != mantik(_z['enabled']) || _gun != tamsayi(_z['weekday']) || _saat != metin(_z['time']) || _mb != tamsayi(_z['read_mb_per_sec']);

  Future<void> _kaydet() async {
    if (_mb < 1 || _mb > 1000) {
      setState(() {
        _alan = 'read_mb_per_sec';
        _hata = 'Okuma hızı 1–1000 MB/sn arasında olmalı';
      });
      return;
    }
    setState(() {
      _mesgul = true;
      _alan = _hata = null;
    });
    try {
      await Uyg.api.put('/api/v1/backup/integrity/schedule', {
        'enabled': _acik,
        'weekday': _gun,
        'time': _saat,
        'timezone': metin(_z['timezone'], 'Europe/Istanbul'),
        'read_mb_per_sec': _mb,
      });
      bildir('Tarama zamanı kaydedildi', tur: MesajTur.basari);
      widget.kaydedildi();
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _alan = e.alan;
          _hata = e.mesaj;
        });
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final gun = DropdownButtonFormField<int>(
      initialValue: _gun,
      isExpanded: true,
      decoration: InputDecoration(labelText: 'Gün', errorText: _alan == 'weekday' ? _hata : null),
      items: [for (final (i, g) in _gunler.indexed) DropdownMenuItem(value: i, child: Text(g))],
      onChanged: (v) => setState(() => _gun = v ?? _gun),
    );
    final saat = _SaatAlani(deger: _saat, hata: _alan == 'time' ? _hata : null, degisti: (v) => setState(() => _saat = v));
    final hiz = TextField(
      controller: _hiz,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: 'Okuma (MB/sn)', errorText: _alan == 'read_mb_per_sec' ? _hata : null),
    );
    return Material(
      color: r.ic,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: r.kenar),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _acik,
              onChanged: (v) => setState(() => _acik = v),
              title: Text('Haftalık otomatik tarama (${metin(_z['timezone'])})', style: const TextStyle(fontSize: 14)),
            ),
            LayoutBuilder(
              builder: (c, k) => k.maxWidth >= 520
                  ? Row(
                      children: [
                        Expanded(child: gun),
                        const SizedBox(width: 8),
                        Expanded(child: saat),
                        const SizedBox(width: 8),
                        Expanded(child: hiz),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        gun,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: saat),
                            const SizedBox(width: 8),
                            Expanded(child: hiz),
                          ],
                        ),
                      ],
                    ),
            ),
            if (_hata != null && _alan == null) Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 12.5)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: !_degisti || _mesgul ? null : _kaydet,
                icon: _mesgul
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Simgeler.save, size: 18),
                label: const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarama sayaçları + sorun listesi.
class _TaramaAyrintisi extends StatefulWidget {
  const _TaramaAyrintisi({required this.tarama});
  final ButunlukTaramasi tarama;

  @override
  State<_TaramaAyrintisi> createState() => _TaramaAyrintisiState();
}

class _TaramaAyrintisiState extends State<_TaramaAyrintisi> {
  int _goster = 20;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final s = widget.tarama;
    final sorunlar = s.sorunlar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Izgara(
          enAz: 130,
          bosluk: 8,
          children: [
            SayacKutusu(etiket: 'Denetlenen ileti', deger: sayiYaz(s.iletiler), ipucu: boyutYaz(s.baytlar)),
            SayacKutusu(etiket: 'Eksik dosya', deger: sayiYaz(s.eksik), kotu: s.eksik > 0),
            SayacKutusu(etiket: 'Bozuk (SHA-256)', deger: sayiYaz(s.bozuk), kotu: s.bozuk > 0),
            SayacKutusu(etiket: 'Boyut uyuşmazlığı', deger: sayiYaz(s.boyutHatasi), kotu: s.boyutHatasi > 0),
            SayacKutusu(etiket: 'Sahipsiz dosya', deger: sayiYaz(s.sahipsiz), ipucu: '${s.dosyalar} dosya', kotu: s.sahipsiz > 0),
            SayacKutusu(
              etiket: 'Son yedek manifesti',
              deger: s.manifestDurumu == 'none' ? '—' : (s.manifestDurumu == 'ok' ? 'Doğru' : '${s.manifestSorunlari} sorun'),
              ipucu: s.manifestCalistirma.isEmpty ? null : '${s.manifestCalistirma} · ${s.manifestDosyalari} dosya',
              kotu: s.manifestSorunlari > 0,
            ),
          ],
        ),
        if (s.durum != 'ok' && s.durum != 'running') ...[const SizedBox(height: 8), Text(s.ozet, style: const TextStyle(color: Marka.gul, fontSize: 13))],
        if (sorunlar.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: r.kenar),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, p) in sorunlar.take(_goster).indexed) ...[
                  if (i > 0) Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metin(p['path']),
                          style: TextStyle(color: r.metin, fontSize: 12, fontFamily: 'monospace'),
                        ),
                        Text(
                          [
                            butunlukSorunEtiketleri[metin(p['kind'])] ?? metin(p['kind']),
                            if (metinYa(p['message_id']) != null)
                              'ileti ${p['message_id']}'
                            else if (metinYa(p['mailbox_id']) != null)
                              'kutu ${p['mailbox_id']}',
                          ].join(' · '),
                          style: TextStyle(color: r.soluk, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
                if (sorunlar.length > _goster)
                  TextButton(onPressed: () => setState(() => _goster += 20), child: Text('Daha fazla göster (${sorunlar.length - _goster})')),
                if (s.kesik)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Liste ilk 200 sorunla sınırlı; sayılar tamdır.', style: TextStyle(color: r.silik, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// GET /backup/integrity/scans (son 30) — dokununca GET /backup/integrity/scans/{id} ayrıntısı.
class _TaramaGecmisi extends StatelessWidget {
  @override
  Widget build(BuildContext context) => TekYukleme<List<ButunlukTaramasi>>(
    getir: () async => [for (final m in haritalar(harita(await Uyg.api.get('/api/v1/backup/integrity/scans'))['items'])) ButunlukTaramasi(m)],
    icerik: (c, l, _) {
      final r = c.r;
      if (l.isEmpty) return ListView(children: const [SizedBox(height: 200, child: Durum.bos('Henüz tarama yapılmadı.'))]);
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: l.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
        itemBuilder: (c, i) {
          final s = l[i];
          final renk = switch (s.durum) {
            'ok' => Marka.zumrut,
            'running' => Marka.mavi,
            _ => Marka.gul,
          };
          return ListTile(
            title: Text(tamZaman(s.baslangic)),
            subtitle: Text('${s.tetik == 'manual' ? 'Elle (${s.isteyen})' : 'Zamanlanmış'} · ${s.ozet}', maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Rozet(switch (s.durum) {
              'ok' => 'Sorun yok',
              'problems' => 'Sorun bulundu',
              'running' => 'Sürüyor',
              _ => 'Başarısız',
            }, renk: renk),
            onTap: () => sayfaAc<void>(
              c,
              'Tarama ${tamZaman(s.baslangic)}',
              TekYukleme<ButunlukTaramasi>(
                getir: () async => ButunlukTaramasi(harita(await Uyg.api.get('/api/v1/backup/integrity/scans/${s.kimlik}'))),
                icerik: (c, t, _) => IcerikListesi(children: [_TaramaAyrintisi(tarama: t)]),
              ),
            ),
          );
        },
      );
    },
  );
}

/// Kutu seçtirip .zip dışa aktarmayı başlatır (GET /mailboxes/{id}/export).
Future<void> _kutuDisaAktar(BuildContext context) async {
  final k = await araVeSec<PostaKutusu>(
    context,
    baslik: 'Dışa aktarılacak posta kutusu',
    ipucu: 'Kutu ara…',
    yukle: (q) async => Sayfa.coz(
      await Uyg.api.get('/api/v1/mailboxes', q: {'page_size': '50', 'sort': 'address', 'order': 'asc', if (q.isNotEmpty) 'q': q}),
      PostaKutusu.coz,
    ).ogeler,
    ad: (x) => x.adres,
    alt: (x) => '${boyutYaz(x.kullanilan)}${x.gorunenAd.isEmpty ? '' : ' · ${x.gorunenAd}'}',
  );
  if (k != null && context.mounted) await kutuyuDisariAktar(context, k);
}
