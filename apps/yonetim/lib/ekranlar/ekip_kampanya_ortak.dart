import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';

// Toplu Gönderim ortak parçaları (internal/api/campaigns*.go; web: lib/campaigns.ts, components/admin/campaigns/shared.tsx).

/// Seçili müşterinin kampanya bağlamı: kimlik, genel bakış (GET /campaigns/overview) ve yenileme.
class KampanyaBaglami {
  const KampanyaBaglami({required this.orgId, required this.ov, required this.yenile});
  final String orgId;
  final Map<String, dynamic> ov;
  final VoidCallback yenile;

  bool get acik => mantik(harita(ov['organization'])['feature_enabled']);
  List<Map<String, dynamic>> get gondericiler => haritalar(ov['senders']);
  Map<String, dynamic> get ayarlar => harita(ov['settings']);
  Map<String, dynamic> get sinirlar => harita(ov['limits']);

  /// GET sorgusu (?org=).
  Map<String, String> get q => orgId.isEmpty ? const {} : {'org': orgId};
}

const kampanyaDurumlari = {
  'draft': 'Taslak',
  'pending_approval': 'Onay bekliyor',
  'scheduled': 'Planlandı',
  'sending': 'Gönderiliyor',
  'paused': 'Duraklatıldı',
  'completed': 'Tamamlandı',
  'cancelled': 'İptal',
  'rejected': 'Reddedildi',
};

Color kampanyaRengi(String d, Color soluk) => switch (d) {
  'pending_approval' || 'paused' => Marka.kehribar,
  'scheduled' || 'sending' => Marka.mavi,
  'completed' => Marka.zumrut,
  'rejected' => Marka.gul,
  _ => soluk,
};

const kisiDurumlari = {'pending': 'Onay bekliyor', 'subscribed': 'Abone', 'unsubscribed': 'Çıktı', 'bounced': 'Geri döndü', 'complained': 'Şikâyet'};

Color kisiRengi(String d, Color soluk) => switch (d) {
  'pending' => Marka.kehribar,
  'subscribed' => Marka.zumrut,
  'bounced' || 'complained' => Marka.gul,
  _ => soluk,
};

const kisiKaynaklari = {'manual': 'Elle eklendi', 'import': 'İçe aktarma', 'form': 'Web formu'};

const aliciDurumlari = {
  'pending': 'Sırada',
  'sending': 'Gönderiliyor',
  'queued': 'Kuyruğa alındı',
  'skipped': 'Atlandı',
  'failed': 'Gönderilemedi',
  'held': 'Bekletildi',
  'cancelled': 'İptal',
};

const teslimDurumlari = {'delivered': 'Teslim edildi', 'deferred': 'Ertelendi', 'bounced': 'Geri döndü'};

/// Yüzde (web: pct): 10'un altında bir ondalık.
String yuzdeOrani(num n, num d) {
  if (d == 0) return '0';
  final v = n * 100 / d;
  return v < 10 ? v.toStringAsFixed(1).replaceAll('.', ',') : v.toStringAsFixed(0);
}

class KampanyaRozeti extends StatelessWidget {
  const KampanyaRozeti(this.durum, {super.key});
  final String durum;
  @override
  Widget build(BuildContext context) => Rozet(kampanyaDurumlari[durum] ?? durum, renk: kampanyaRengi(durum, context.r.soluk));
}

/// Geniş ekranda iletişim kutusu, telefonda tam sayfa açar.
Future<T?> ekipPencere<T>(BuildContext context, String baslik, Widget govde, {double genislik = 760, List<Widget> eylemler = const []}) {
  if (!context.genis) return sayfaAc<T>(context, baslik, govde, eylemler: eylemler);
  return showDialog<T>(
    context: context,
    builder: (c) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: genislik,
        height: MediaQuery.sizeOf(c).height * .88,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(baslik, overflow: TextOverflow.ellipsis),
            actions: [
              ...eylemler,
              IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          body: govde,
        ),
      ),
    ),
  );
}

/// Küçük istatistik kutusu.
class KucukSayi extends StatelessWidget {
  const KucukSayi(this.etiket, this.deger, {super.key, this.alt, this.kotu = false});
  final String etiket;
  final num deger;
  final String? alt;
  final bool kotu;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: r.kart,
        border: Border.all(color: r.kenar),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiket,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: r.silik, fontSize: 11.5),
          ),
          Text(sayiYaz(deger), style: gosterim(19, renk: kotu ? Marka.gul : r.metin)),
          if (alt != null)
            Text(
              alt!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: r.silik, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

/// Kampanya raporu: canlı sayılar (gönderilirken 15 sn'de bir yenilenir) ve alıcı bazında tablo.
class KampanyaRaporu extends StatefulWidget {
  const KampanyaRaporu({super.key, required this.id});
  final String id;
  @override
  State<KampanyaRaporu> createState() => _KampanyaRaporuState();
}

class _KampanyaRaporuState extends State<KampanyaRaporu> {
  Map<String, dynamic>? _c;
  String? _hata;
  String _ara = '';
  String _durum = 'all';
  bool _kapandi = false;

  late final _y = SayfaYukleyici<Map<String, dynamic>>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/campaigns/c/${widget.id}/recipients',
        q: {'page': '$s', 'page_size': '$b', if (_ara.isNotEmpty) 'q': _ara, if (_durum != 'all') 'status': _durum},
      ),
      (m) => m,
    ),
  )..yenile();

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _kapandi = true;
    _y.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final c = harita(await Uyg.api.get('/api/v1/campaigns/c/${widget.id}'));
      if (!mounted) return;
      setState(() {
        _c = c;
        _hata = null;
      });
      final d = metin(c['status']);
      if (const {'scheduled', 'sending', 'pending_approval'}.contains(d)) {
        Future.delayed(const Duration(seconds: 15), () {
          if (_kapandi) return;
          _yukle();
          if (d == 'sending') _y.yenile();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Widget _ozet(Map<String, dynamic> c) {
    final r = context.r;
    final s = harita(c['stats']);
    final neden = metin(c['status_reason']), bekleme = metin(c['wait_reason']);
    int n(String k) => tamsayi(s[k]);
    final kuyruk = n('queued');
    return Padding(
      padding: EdgeInsets.fromLTRB(context.genis ? 16 : 12, 10, context.genis ? 16 : 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              kampanyaDurumlari[metin(c['status'])] ?? metin(c['status']),
              metin(c['from_address'], '—'),
              '${sayiYaz(tamsayi(c['total_recipients']))} alıcı',
              if (tarihOku(c['started_at']) != null) 'başladı ${tamZaman(tarihOku(c['started_at']))}',
            ].join(' · '),
            style: TextStyle(color: r.soluk, fontSize: 13),
          ),
          if (neden.isNotEmpty || bekleme.isNotEmpty) ...[
            const SizedBox(height: 8),
            Bant([if (neden.isNotEmpty) neden, if (bekleme.isNotEmpty) 'Bekleme: $bekleme'].join('\n'), renk: Marka.kehribar),
          ],
          const SizedBox(height: 10),
          if (s.isEmpty)
            Text('Taslak kampanyanın raporu yok.', style: TextStyle(color: r.soluk))
          else
            Izgara(
              enAz: 150,
              bosluk: 8,
              children: [
                KucukSayi('Sırada', n('pending')),
                KucukSayi('Kuyruğa alındı', kuyruk, alt: 'son 1 saat: ${sayiYaz(n('queued_last_hour'))}'),
                KucukSayi('Teslim edildi', n('delivered'), alt: '%${yuzdeOrani(n('delivered'), kuyruk)}'),
                KucukSayi('Ertelendi', n('deferred')),
                KucukSayi(
                  'Kalıcı geri dönüş',
                  n('bounced_hard'),
                  alt: '%${yuzdeOrani(n('bounced_hard'), kuyruk)}',
                  kotu: kuyruk > 0 && n('bounced_hard') / kuyruk > .05,
                ),
                KucukSayi('Geçici hata (süre doldu)', n('bounced_soft')),
                KucukSayi('Şikâyet', n('complained'), alt: '%${yuzdeOrani(n('complained'), kuyruk)}', kotu: kuyruk > 0 && n('complained') / kuyruk > .001),
                KucukSayi('Abonelikten çıktı', n('unsubscribed'), alt: '%${yuzdeOrani(n('unsubscribed'), kuyruk)}'),
                KucukSayi('Atlandı', n('skipped'), alt: 'çıkmış / bastırılmış'),
                KucukSayi('Gönderilemedi', n('failed') + n('held')),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            'Açılma/tıklama takibi kapalı (gizlilik). Teslim bilgisi alıcı sunucuların yanıtlarından, şikâyetler geri bildirim döngüsü (FBL) raporlarından gelir.',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _teslim(Map<String, dynamic> x) =>
      [teslimDurumlari[metin(x['delivery'])] ?? '—', if (tarihOku(x['unsubscribed_at']) != null) 'çıktı', if (mantik(x['complained'])) 'şikâyet'].join(' · ');

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return _hata != null ? Durum.hata(_hata!, tekrar: _yukle) : const Durum.yukleniyor();
    const filtreler = [
      ('all', 'Tümü'),
      ('pending', 'Sırada'),
      ('queued', 'Kuyruğa alındı'),
      ('delivered', 'Teslim edildi'),
      ('deferred', 'Ertelendi'),
      ('bounced', 'Geri döndü'),
      ('unsubscribed', 'Abonelikten çıktı'),
      ('skipped', 'Atlandı'),
      ('failed', 'Gönderilemedi'),
      ('cancelled', 'İptal'),
    ];
    return VeriTablosu<Map<String, dynamic>>(
      yukleyici: _y,
      bosMetin: 'Kayıt yok.',
      bosIkon: Icons.people_outline_rounded,
      tabloEnAz: 640,
      ust: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ozet(c),
          FiltreCubugu(
            arama: AramaAlani(
              ipucu: 'Alıcı ara',
              degisti: (v) {
                _ara = v.trim();
                _y.yenile();
              },
            ),
            filtreler: [
              FiltreDugmesi<String>(
                etiket: 'Durum',
                ikon: Icons.filter_list_rounded,
                secenekler: filtreler,
                secili: _durum,
                secildi: (v) {
                  setState(() => _durum = v);
                  _y.yenile();
                },
              ),
            ],
          ),
        ],
      ),
      sutunlar: [
        Sutun('Alıcı', esnek: 4, hucre: (c, x) => IkiSatir(metin(x['email']), alt: metinYa(x['name']))),
        Sutun('Durum', esnek: 3, hucre: (c, x) => IkiSatir(aliciDurumlari[metin(x['status'])] ?? metin(x['status']), alt: metinYa(x['reason']), kalin: false)),
        Sutun(
          'Teslim',
          esnek: 3,
          hucre: (c, x) => IkiSatir(_teslim(x), alt: metinYa('${metin(x['delivery_code'])} ${metin(x['delivery_detail'])}'), kalin: false),
        ),
        Sutun('Zaman', esnek: 2, hucre: (c, x) => SolukMetin(tamZaman(tarihOku(x['delivery_at']) ?? tarihOku(x['queued_at'])))),
      ],
      kart: (c, x) => VeriKarti(
        baslik: metin(x['email']),
        alt: metinYa(x['name']),
        alanlar: [
          ('Durum', aliciDurumlari[metin(x['status'])] ?? metin(x['status'])),
          ('Teslim', _teslim(x)),
          ('Zaman', tamZaman(tarihOku(x['delivery_at']) ?? tarihOku(x['queued_at']))),
          if (metin(x['reason']).isNotEmpty) ('Neden', metin(x['reason'])),
        ],
      ),
    );
  }
}
