import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/secimler.dart';
import '../veri/json.dart';
import 'ekip_kampanya.dart';
import 'ekip_kampanya_liste.dart';
import 'ekip_kampanya_ortak.dart';
import 'ekip_kampanya_sablon.dart';
import '../ortak/simgeler.dart';

const _onayPolitikalari = {'default': 'Platform politikası', 'always': 'Her kampanya onaylı', 'never': 'Onay gerekmez'};

/// Toplu Gönderim (e-posta kampanyaları): kampanyalar, kişi listeleri, şablonlar ve ayarlar.
/// Müşteri yöneticisi kendi kurumunu görür; platform / bayi yöneticisi müşteri seçer (?org=).
class TopluGonderimEkrani extends StatefulWidget {
  const TopluGonderimEkrani({super.key});
  @override
  State<TopluGonderimEkrani> createState() => _TopluGonderimEkraniState();
}

class _TopluGonderimEkraniState extends State<TopluGonderimEkrani> {
  String? _orgId;
  String? _orgAdi;
  Map<String, dynamic>? _ov;
  String? _hata;
  int _surum = 0;

  bool get _ortak => !Uyg.musteri;
  bool get _yetkili => Uyg.yetki('campaigns.manage');

  @override
  void initState() {
    super.initState();
    if (!_ortak && _yetkili) _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final v = harita(await Uyg.api.get('/api/v1/campaigns/overview', q: _orgId == null ? const {} : {'org': _orgId!}));
      if (!mounted) return;
      setState(() {
        _ov = v;
        _orgId ??= metinYa(harita(v['organization'])['id']);
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _musteriSec() async {
    final o = await musteriSec(context);
    if (o == null) return;
    setState(() {
      _orgId = o.id;
      _orgAdi = o.ad;
      _ov = null;
      _surum++;
    });
    _yukle();
  }

  void _hepsiniYenile() {
    setState(() => _surum++);
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    if (!_yetkili) {
      return const Iskelet(
        baslik: 'Toplu Gönderim',
        govde: Kapali('Bu bölüm için kampanya yönetimi yetkisi gerekli.', ikon: Simgeler.lockOutline),
      );
    }
    final ov = _ov;
    final yatay = context.genis ? 16.0 : 12.0;
    Widget govde;
    if (_ortak && _orgId == null) {
      govde = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Kapali('Kampanyaları yönetmek için müşteri seçin.', ikon: Simgeler.campaign),
            FilledButton.icon(onPressed: _musteriSec, icon: const Icon(Simgeler.apartment), label: const Text('Müşteri seçin')),
          ],
        ),
      );
    } else if (ov == null) {
      govde = _hata != null ? Durum.hata(_hata!, tekrar: _yukle) : const Durum.yukleniyor();
    } else {
      final b = KampanyaBaglami(orgId: _orgId ?? '', ov: ov, yenile: _yukle);
      govde = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!b.acik)
            Padding(
              padding: EdgeInsets.fromLTRB(yatay, 8, yatay, 0),
              child: const Bant(
                'Toplu gönderim bu müşterinin paketinde yok. Mevcut kayıtlar görüntülenebilir; yeni kampanya, liste ve şablon oluşturulamaz.',
                renk: Marka.kehribar,
                ikon: Simgeler.infoOutline,
              ),
            ),
          Expanded(
            child: TabBarView(
              children: [
                KampanyalarSekmesi(key: ValueKey('c$_surum'), b: b),
                ListelerSekmesi(key: ValueKey('l$_surum'), b: b),
                SablonlarSekmesi(key: ValueKey('t$_surum'), b: b),
                _AyarlarSekmesi(key: ValueKey('a$_surum-${ov.hashCode}'), b: b),
              ],
            ),
          ),
        ],
      );
    }
    final aktif = tamsayi(ov?['active_campaigns']);
    return DefaultTabController(
      length: 4,
      child: Iskelet(
        baslik: 'Toplu Gönderim',
        alt: _ortak ? (_orgAdi ?? metinYa(harita(ov?['organization'])['name']) ?? 'Müşteri seçilmedi') : 'Onaylı kişi listelerine e-posta kampanyaları',
        yenile: _ortak && _orgId == null ? null : _hepsiniYenile,
        eylemler: [if (_ortak) IconButton(tooltip: 'Müşteri seç', onPressed: _musteriSec, icon: const Icon(Simgeler.apartment))],
        sekmeler: ov == null
            ? null
            : TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Kampanyalar'),
                        if (aktif > 0) ...[const SizedBox(width: 8), Rozet('$aktif', renk: Marka.mavi)],
                      ],
                    ),
                  ),
                  const Tab(text: 'Kişi listeleri'),
                  const Tab(text: 'Şablonlar'),
                  const Tab(text: 'Ayarlar'),
                ],
              ),
        govde: govde,
      ),
    );
  }
}

class _AyarlarSekmesi extends StatefulWidget {
  const _AyarlarSekmesi({super.key, required this.b});
  final KampanyaBaglami b;
  @override
  State<_AyarlarSekmesi> createState() => _AyarlarSekmesiState();
}

class _AyarlarSekmesiState extends State<_AyarlarSekmesi> {
  late final _sirket = TextEditingController(text: metin(widget.b.ayarlar['footer_company']));
  late final _adres = TextEditingController(text: metin(widget.b.ayarlar['footer_address']));
  bool _mesgul = false;

  @override
  void dispose() {
    _sirket.dispose();
    _adres.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() => _mesgul = true);
    final v = await islem(
      () => Uyg.api.put('/api/v1/campaigns/settings', {
        'organization_id': widget.b.orgId,
        'footer_company': _sirket.text.trim(),
        'footer_address': _adres.text.trim(),
      }),
      tamam: 'Alt bilgi kaydedildi',
    );
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (v != null) widget.b.yenile();
  }

  Widget _cubuk(String etiket, int kullanilan, int? toplam, {String? ek}) {
    final r = context.r;
    final oran = toplam == null || toplam <= 0 ? null : (kullanilan / toplam).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(etiket, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(toplam == null ? '${sayiYaz(kullanilan)} · sınırsız' : '${sayiYaz(kullanilan)} / ${sayiYaz(toplam)}', style: TextStyle(color: r.soluk)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: oran ?? 0,
              minHeight: 8,
              backgroundColor: r.ic,
              color: oran != null && oran >= .9 ? Marka.gul : (oran != null && oran >= .75 ? Marka.kehribar : r.birincil),
            ),
          ),
          if (ek != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(ek, style: TextStyle(color: r.silik, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.b;
    final s = b.sinirlar;
    final a = b.ayarlar;
    final r = context.r;
    final bekleyen = tamsayi(s['reserved_pending']);
    return ListView(
      padding: EdgeInsets.all(context.genis ? 16 : 12),
      children: [
        Izgara(
          enAz: 380,
          bosluk: 12,
          children: [
            BolumKarti(
              baslik: 'Zorunlu alt bilgi',
              ikon: Simgeler.business,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Her kampanya iletisinin altına gönderen şirket adı ve adresi eklenir. Boş bırakılırsa müşteri profilindeki bilgiler kullanılır.',
                    style: TextStyle(color: r.soluk, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sirket,
                    maxLength: 200,
                    enabled: b.acik,
                    decoration: InputDecoration(labelText: 'Şirket adı', hintText: metin(a['effective_company']), counterText: ''),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _adres,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    enabled: b.acik,
                    decoration: InputDecoration(labelText: 'Adres', hintText: metin(a['effective_address']), counterText: ''),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Kullanılacak: ${metin(a['effective_company'], '—')} · ${metin(a['effective_address'], 'adres yok')}',
                    style: TextStyle(color: r.silik, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(onPressed: _mesgul || !b.acik ? null : _kaydet, child: const Text('Kaydet')),
                  ),
                ],
              ),
            ),
            BolumKarti(
              baslik: 'Sınırlar ve politika',
              ikon: Simgeler.speed,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cubuk('Kişi sayısı', tamsayi(s['contacts']), tamsayiYa(s['max_contacts'])),
                  _cubuk(
                    'Bu ay gönderilen',
                    tamsayi(s['sent_this_month']),
                    tamsayiYa(s['max_campaign_sends_monthly']),
                    ek: bekleyen > 0 ? 'Bekleyen kampanyalar için ayrılan: ${sayiYaz(bekleyen)}' : null,
                  ),
                  BilgiSatiri('Onay politikası', _onayPolitikalari[metin(a['approval'])] ?? metin(a['approval'], '—')),
                  BilgiSatiri('Saatlik hız üst sınırı', tamsayiYa(a['max_rate_per_hour']) != null ? sayiYaz(tamsayi(a['max_rate_per_hour'])) : 'Otomatik'),
                  BilgiSatiri('Sonraki kampanya onaya düşer', mantik(b.ov['next_campaign_needs_approval']) ? 'Evet' : 'Hayır'),
                  BilgiSatiri('Bastırılmış adres', sayiYaz(tamsayi(b.ov['suppressed']))),
                  const SizedBox(height: 8),
                  Text('Sınırlar ve onay politikası platform yöneticisi tarafından belirlenir.', style: TextStyle(color: r.silik, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
