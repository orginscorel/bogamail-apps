import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import '../veri/operasyon.dart';
import 'liste_ortak.dart';

/// Gönderilmeden bekletilen giden iletiler (GET /outbound-holds): kötüye kullanım şüphesi ve DLP onayı.
/// Yalnızca üst bilgi gösterilir (gönderen, alıcı sayısı, maskeli konu önizlemesi, boyut, puan); içerik ve alıcılar asla.
class BekletilenlerListesi extends StatefulWidget {
  const BekletilenlerListesi({super.key, this.kaynak, this.yenileme});

  /// Verilirse kaynak sabittir ('abuse' | 'dlp') ve seçici gizlenir.
  final String? kaynak;

  /// Her bildirimde liste yeniden yüklenir (üst ekrandaki yenile düğmesi).
  final Listenable? yenileme;

  @override
  State<BekletilenlerListesi> createState() => _BekletilenlerListesiState();
}

class _BekletilenlerListesiState extends State<BekletilenlerListesi> with AutomaticKeepAliveClientMixin {
  late String _kaynak = widget.kaynak ?? 'abuse';
  bool _tumu = false;
  String _q = '';
  Timer? _zamanlayici;

  late final _y = SayfaYukleyici.yerel<Bekletilen>(
    () async => haritalar(
      harita(await Uyg.api.get('/api/v1/outbound-holds', q: {'source': _kaynak, 'status': _tumu ? 'all' : 'held', if (_q.isNotEmpty) 'q': _q}))['items'],
    ).map(Bekletilen.coz).toList(),
    sayfaBoyu: 25,
  )..yenile();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.yenileme?.addListener(_y.yenile);
    // Web paneli gibi 15 saniyede bir tazeler (yalnızca ilk sayfadayken; sayfa gezintisini bozmasın).
    _zamanlayici = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_y.yukleniyor && _y.sayfa <= 1) _y.yenile();
    });
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    widget.yenileme?.removeListener(_y.yenile);
    _y.dispose();
    super.dispose();
  }

  void _filtre(void Function() f) {
    setState(f);
    _y.yenile();
  }

  /// Sunucu kuralları: kötüye kullanım bekletmesini yalnızca platform/bayi serbest bırakır; DLP kararını yalnızca
  /// (taklit etmeyen) platform yöneticisi verir. Silme quarantine.release yetkisi ister.
  bool _serbestBirakabilir(Bekletilen b) => b.kaynak == 'dlp' ? _dlpKarari : Uyg.ortak && Uyg.yetki('quarantine.release');
  bool get _dlpKarari => Uyg.platformYoneticisi && Uyg.taklit == null;
  bool _silebilir(Bekletilen b) => Uyg.yetki('quarantine.release') && (b.kaynak != 'dlp' || _dlpKarari);

  String _serbestEtiketi(Bekletilen b) => b.kaynak == 'dlp' ? 'Onayla ve gönder' : 'Serbest bırak';
  String _silEtiketi(Bekletilen b) => b.kaynak == 'dlp' ? 'Reddet ve sil' : 'Sil';

  Future<void> _karar(Bekletilen b, bool serbest) async {
    final etiket = serbest ? _serbestEtiketi(b) : _silEtiketi(b);
    final ok = await onayla(
      context,
      '$etiket?',
      mesaj: serbest
          ? 'İleti ${b.aliciSayisi} alıcıya gönderilecek. Bu karar denetim kaydına yazılır.'
          : 'İleti gönderilmeden kalıcı olarak silinecek. Bu işlem geri alınamaz ve denetim kaydına yazılır.',
      evet: etiket,
      tehlikeli: !serbest,
    );
    if (!ok) return;
    final v = await islem(
      () => serbest
          ? Uyg.api.post('/api/v1/outbound-holds/${b.id}/release').then((_) => true)
          : Uyg.api.delete('/api/v1/outbound-holds/${b.id}').then((_) => true),
      tamam: serbest ? 'İleti gönderim kuyruğuna alındı' : 'İleti silindi',
    );
    if (v != null) _y.yenile();
  }

  List<SatirEylemiDugmesi> _dugmeler(Bekletilen b) => [
    if (b.durum == 'held' && _serbestBirakabilir(b))
      SatirEylemiDugmesi(Icons.check_rounded, _serbestEtiketi(b), () => _karar(b, true), ipucu: 'İleti alıcılarına gönderilir (kayıt altında)'),
    if (b.durum == 'held' && _silebilir(b))
      SatirEylemiDugmesi(Icons.delete_outline_rounded, _silEtiketi(b), () => _karar(b, false), ipucu: 'İleti gönderilmeden kalıcı olarak silinir', tehlikeli: true),
  ];

  List<SatirEylemi> _eylemler(Bekletilen b) => [
    SatirEylemi(Icons.info_outline_rounded, 'Ayrıntı', () => _ayrinti(b)),
    for (final d in _dugmeler(b)) SatirEylemi(d.ikon, d.baslik, d.calistir, tehlikeli: d.tehlikeli),
  ];

  void _ayrinti(Bekletilen b) {
    final dugmeler = _dugmeler(b);
    yonetimPenceresi(
      context,
      baslik: b.gonderen,
      alt: [
        if (!Uyg.musteri && b.orgAdi.isNotEmpty) b.orgAdi,
        tamZaman(b.olusturma),
        b.koken == 'queue' ? 'kuyruktan alındı' : 'gönderim sırasında bekletildi',
      ].join(' · '),
      ozet: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BilgiSatiri('Konu', b.konu.isEmpty ? '(konu yok)' : b.konu),
          BilgiSatiri('Alıcı', '${b.aliciSayisi} alıcı (${b.disSayisi} dış)'),
          BilgiSatiri('Boyut', boyutYaz(b.boyut)),
          if (b.kaynak == 'abuse') BilgiSatiri('Risk puanı', b.puan.toStringAsFixed(1).replaceAll('.', ',')),
          BilgiSatiri('Neden', b.neden),
          BilgiSatiri('Durum', _durumMetni(b)),
          const SizedBox(height: 6),
          Text(
            'İçerik ve alıcı adresleri gizlilik nedeniyle gösterilmez.${b.durum == 'held' ? ' Bekleyen iletiler ${tamZaman(b.bitis)} tarihinde otomatik silinir.' : ''}',
            style: TextStyle(color: context.r.silik, fontSize: 12),
          ),
          if (b.durum == 'held' && dugmeler.isEmpty) ...[
            const SizedBox(height: 10),
            Bant(
              b.kaynak == 'dlp'
                  ? 'DLP nedeniyle bekletilen iletiye yalnızca platform yöneticisi karar verebilir.'
                  : 'Kötüye kullanım şüphesiyle bekletilen iletileri yalnızca platform/bayi yöneticisi serbest bırakabilir.',
            ),
          ],
        ],
      ),
      eylemler: dugmeler,
    );
  }

  String _durumMetni(Bekletilen b) => switch (b.durum) {
    'held' => 'Bekliyor',
    'released' => 'Gönderildi${b.kararVeren != null ? ' · ${b.kararVeren}' : ''}',
    _ => 'Silindi${b.kararVeren != null ? ' · ${b.kararVeren}' : ''}',
  };

  Widget _durumRozeti(BuildContext c, Bekletilen b) => switch (b.durum) {
    'held' => const Rozet('Bekliyor', renk: Marka.kehribar),
    'released' => const Rozet('Gönderildi', renk: Marka.zumrut),
    _ => Rozet('Silindi', renk: c.r.silik),
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = context.r;
    final abuse = _kaynak == 'abuse';
    return VeriTablosu<Bekletilen>(
      yukleyici: _y,
      onTap: _ayrinti,
      eylemler: _eylemler,
      bosIkon: Icons.verified_user_outlined,
      bosMetin: _q.isNotEmpty
          ? 'Eşleşen ileti yok.'
          : (abuse ? 'Kötüye kullanım şüphesiyle bekletilen ileti yok.' : 'Onay bekleyen DLP iletisi bulunmuyor.'),
      ust: FiltreCubugu(
        arama: AramaAlani(ipucu: 'Gönderen adresi…', degisti: (v) => _filtre(() => _q = v)),
        filtreler: [
          if (widget.kaynak == null)
            FiltreDugmesi<String>(
              etiket: 'Kaynak',
              ikon: Icons.shield_outlined,
              secenekler: const [('abuse', 'Kötüye kullanım'), ('dlp', 'DLP onayı')],
              secili: _kaynak,
              secildi: (v) => _filtre(() => _kaynak = v),
            ),
          FiltreDugmesi<bool>(
            etiket: 'Durum',
            ikon: Icons.flag_outlined,
            secenekler: const [(false, 'Bekleyen'), (true, 'Tümü (geçmiş dahil)')],
            secili: _tumu,
            secildi: (v) => _filtre(() => _tumu = v),
          ),
        ],
        etkinler: [
          if (widget.kaynak == null && !abuse) EtkinFiltre('Kaynak: DLP onayı', () => _filtre(() => _kaynak = 'abuse')),
          if (_tumu) EtkinFiltre('Geçmiş dahil', () => _filtre(() => _tumu = false)),
        ],
      ),
      sutunlar: [
        Sutun(
          'Gönderen',
          esnek: 4,
          hucre: (c, b) => IkiSatir(
            b.gonderen,
            alt: Uyg.musteri ? null : b.orgAdi,
            sol: Icon(b.kaynak == 'dlp' ? Icons.policy_rounded : Icons.gpp_maybe_rounded, size: 20, color: b.durum == 'held' ? Marka.kehribar : r.silik),
          ),
        ),
        Sutun('Konu (önizleme)', esnek: 3, hucre: (c, b) => SolukMetin(b.konu.isEmpty ? '(konu yok)' : b.konu)),
        Sutun('Alıcı', genislik: 100, hucre: (c, b) => SolukMetin('${b.aliciSayisi}${b.disSayisi > 0 ? ' (${b.disSayisi} dış)' : ''}')),
        Sutun('Boyut', genislik: 80, sagaYasla: true, hucre: (c, b) => SolukMetin(boyutYaz(b.boyut))),
        Sutun(
          abuse ? 'Puan' : 'Durum',
          genislik: 110,
          hucre: (c, b) => abuse && b.durum == 'held' ? Text(b.puan.toStringAsFixed(1).replaceAll('.', ','), style: const TextStyle(fontWeight: FontWeight.w700)) : Sigdir(_durumRozeti(c, b)),
        ),
        Sutun('Zaman', genislik: 110, hucre: (c, b) => Tooltip(message: tamZaman(b.olusturma), child: SolukMetin(goreliZaman(b.olusturma)))),
      ],
      kart: (c, b) => VeriKarti(
        baslik: b.gonderen,
        alt: b.konu.isEmpty ? '(konu yok)' : b.konu,
        sol: Icon(b.kaynak == 'dlp' ? Icons.policy_rounded : Icons.gpp_maybe_rounded, color: b.durum == 'held' ? Marka.kehribar : r.silik),
        rozetler: [_durumRozeti(c, b)],
        alanlar: [
          if (!Uyg.musteri && b.orgAdi.isNotEmpty) ('Müşteri', b.orgAdi),
          ('Alıcı', '${b.aliciSayisi}${b.disSayisi > 0 ? ' (${b.disSayisi} dış)' : ''}'),
          ('Boyut', boyutYaz(b.boyut)),
          if (abuse) ('Puan', b.puan.toStringAsFixed(1).replaceAll('.', ',')),
          ('Zaman', goreliZaman(b.olusturma)),
        ],
        eylemler: _eylemler(b),
        onTap: () => _ayrinti(b),
      ),
    );
  }
}
