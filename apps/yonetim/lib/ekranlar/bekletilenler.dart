import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/json.dart';
import '../veri/operasyon.dart';

/// Gönderilmeden bekletilen giden iletiler (GET /outbound-holds): kötüye kullanım şüphesi ve DLP onayı.
class BekletilenlerListesi extends StatefulWidget {
  const BekletilenlerListesi({super.key});
  @override
  State<BekletilenlerListesi> createState() => _BekletilenlerListesiState();
}

class _BekletilenlerListesiState extends State<BekletilenlerListesi> with AutomaticKeepAliveClientMixin {
  String _kaynak = 'abuse';
  bool _tumu = false;
  String _q = '';
  List<Bekletilen>? _liste;
  String? _hata;
  int _nesil = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final n = ++_nesil;
    try {
      final v = await Uyg.api.get('/api/v1/outbound-holds', q: {'source': _kaynak, 'status': _tumu ? 'all' : 'held', if (_q.isNotEmpty) 'q': _q});
      if (mounted && n == _nesil) {
        setState(() {
          _liste = haritalar(harita(v)['items']).map(Bekletilen.coz).toList();
          _hata = null;
        });
      }
    } catch (e) {
      if (mounted && n == _nesil) setState(() => _hata = hataMetni(e));
    }
  }

  void _filtre(void Function() f) {
    setState(() {
      f();
      _liste = null;
    });
    _yukle();
  }

  /// Sunucu kuralları: kötüye kullanım bekletmesini yalnızca platform/bayi serbest bırakır; DLP kararını yalnızca
  /// (taklit etmeyen) platform yöneticisi verir. Silme quarantine.release yetkisi ister.
  bool _serbestBirakabilir(Bekletilen b) => b.kaynak == 'dlp' ? _dlpKarari : Uyg.ortak && Uyg.yetki('quarantine.release');
  bool get _dlpKarari => Uyg.platformYoneticisi && Uyg.ben.value?['impersonation'] == null;
  bool _silebilir(Bekletilen b) => Uyg.yetki('quarantine.release') && (b.kaynak != 'dlp' || _dlpKarari);

  Future<void> _karar(Bekletilen b, bool serbest) async {
    final etiket = serbest ? (b.kaynak == 'dlp' ? 'Onayla ve gönder' : 'Serbest bırak') : (b.kaynak == 'dlp' ? 'Reddet ve sil' : 'Sil');
    final ok = await onayla(
      context,
      '$etiket?',
      mesaj: serbest ? 'İleti alıcılarına gönderilir. Bu karar denetim kaydına yazılır.' : 'İleti gönderilmeden kalıcı olarak silinir.',
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
    if (v != null) _yukle();
  }

  void _ayrinti(Bekletilen b) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(b.gonderen, style: gosterim(17, agirlik: FontWeight.w700)),
              if (b.orgAdi.isNotEmpty && !Uyg.musteri) Text(b.orgAdi, style: TextStyle(color: c.r.silik)),
              const SizedBox(height: 10),
              BilgiSatiri('Konu', b.konu.isEmpty ? '(konu yok)' : b.konu),
              BilgiSatiri('Alıcı', '${b.aliciSayisi} alıcı${b.disSayisi > 0 ? ' · ${b.disSayisi} dış' : ''}'),
              BilgiSatiri('Boyut', boyutYaz(b.boyut)),
              if (b.kaynak == 'abuse') BilgiSatiri('Risk puanı', b.puan.toStringAsFixed(1).replaceAll('.', ',')),
              BilgiSatiri('Neden', b.neden.isEmpty ? '—' : b.neden),
              if (b.koken.isNotEmpty)
                BilgiSatiri('Kaynak', b.koken == 'queue' ? 'Kuyruktan geri çekildi' : (b.koken == 'submission' ? 'Gönderim anında' : b.koken)),
              BilgiSatiri('Bekletilme', tamZaman(b.olusturma)),
              if (b.durum == 'held') BilgiSatiri('Otomatik silinme', tamZaman(b.bitis)),
              if (b.durum != 'held')
                BilgiSatiri('Karar', '${b.durum == 'released' ? 'Gönderildi' : 'Silindi'}${b.kararVeren != null ? ' · ${b.kararVeren}' : ''}'),
              if (b.durum == 'held') ...[
                const SizedBox(height: 14),
                if (_serbestBirakabilir(b)) ...[
                  EylemSatiri(
                    ikon: Icons.check_rounded,
                    baslik: b.kaynak == 'dlp' ? 'Onayla ve gönder' : 'Serbest bırak',
                    ipucu: 'İleti alıcılarına gönderilir (kayıt altında)',
                    onTap: () {
                      Navigator.pop(c);
                      _karar(b, true);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                if (_silebilir(b))
                  EylemSatiri(
                    ikon: Icons.delete_outline_rounded,
                    baslik: b.kaynak == 'dlp' ? 'Reddet ve sil' : 'Sil',
                    ipucu: 'İleti gönderilmeden kalıcı olarak silinir',
                    tehlikeli: true,
                    onTap: () {
                      Navigator.pop(c);
                      _karar(b, false);
                    },
                  ),
                if (!_serbestBirakabilir(b) && !_silebilir(b))
                  Bant(
                    b.kaynak == 'dlp'
                        ? 'DLP nedeniyle bekletilen iletiye yalnızca platform yöneticisi karar verebilir.'
                        : 'Bu iletiye karar verme yetkiniz yok.',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = context.r;
    final l = _liste;
    Widget govde;
    if (_hata != null && l == null) {
      govde = ListView(
        children: [SizedBox(height: 320, child: Durum.hata(_hata!, tekrar: _yukle))],
      );
    } else if (l == null) {
      govde = const Durum.yukleniyor();
    } else if (l.isEmpty) {
      govde = ListView(
        children: [
          SizedBox(
            height: 320,
            child: Durum.bos(
              _kaynak == 'dlp' ? 'Onay bekleyen DLP iletisi bulunmuyor.' : 'Kötüye kullanım şüphesiyle bekletilen ileti yok.',
              ikon: Icons.verified_user_outlined,
            ),
          ),
        ],
      );
    } else {
      govde = ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: l.length,
        itemBuilder: (c, i) {
          final b = l[i];
          return ListeSatiri(
            onTap: () => _ayrinti(b),
            sol: Icon(b.kaynak == 'dlp' ? Icons.policy_rounded : Icons.gpp_maybe_rounded, color: b.durum == 'held' ? Marka.kehribar : r.silik),
            baslik: b.gonderen,
            alt: b.konu.isEmpty ? '(konu yok)' : b.konu,
            alt2: [if (!Uyg.musteri) b.orgAdi, '${b.aliciSayisi} alıcı', if (b.neden.isNotEmpty) b.neden].where((s) => s.isNotEmpty).join(' · '),
            sag: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (b.durum != 'held') Rozet(b.durum == 'released' ? 'Gönderildi' : 'Silindi', renk: b.durum == 'released' ? Marka.zumrut : r.silik),
                Text(goreliZaman(b.olusturma), style: TextStyle(color: r.silik, fontSize: 11.5)),
              ],
            ),
          );
        },
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'abuse', label: Text('Kötüye kullanım')),
                        ButtonSegment(value: 'dlp', label: Text('DLP onayı')),
                      ],
                      selected: {_kaynak},
                      onSelectionChanged: (s) => _filtre(() => _kaynak = s.first),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AramaAlani(ipucu: 'Gönderen ara…', degisti: (v) => _filtre(() => _q = v)),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(label: const Text('Geçmiş dahil'), selected: _tumu, onSelected: (v) => _filtre(() => _tumu = v)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator.adaptive(onRefresh: _yukle, child: govde),
        ),
      ],
    );
  }
}
