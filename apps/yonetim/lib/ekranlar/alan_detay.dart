import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'alan_adlari.dart';
import 'bolumler.dart';
import 'posta_kutulari.dart';

/// Alan adı ayrıntısı: özet, sahiplik kaydı, canlı DNS denetimi, DKIM, askıya alma ve silme.
class AlanDetay extends StatefulWidget {
  const AlanDetay({super.key, required this.alan, required this.degisti, this.tamSayfa = false});
  final AlanAdi alan;

  /// Alan güncellendi (yeni hali) ya da silindi (null).
  final void Function(AlanAdi?) degisti;

  /// Kendi sayfasında açıldı (silinince sayfa kapanır, başlık AppBar'dadır).
  final bool tamSayfa;

  @override
  State<AlanDetay> createState() => _AlanDetayState();
}

class _AlanDetayState extends State<AlanDetay> {
  late AlanAdi _a = widget.alan;
  DnsRaporu? _rapor;
  bool _raporYuklendi = false;
  int? _takmaAdSayisi;
  bool _denetleniyor = false;
  String? _hata;

  bool get _yonetir => Uyg.yetki('domains.manage');

  @override
  void initState() {
    super.initState();
    _yukle(ilk: true);
  }

  Future<void> _yukle({bool ilk = false}) async {
    final id = _a.id;
    try {
      final sonuc = await Future.wait([
        Uyg.api.get('/api/v1/domains/$id'),
        Uyg.api.get('/api/v1/domains/$id/dns-check'),
        if (_a.hosting) Uyg.api.get('/api/v1/aliases', q: {'domain_id': id}).catchError((_) => null),
      ]);
      if (!mounted) return;
      final yeni = AlanAdi.coz(harita(sonuc[0]));
      setState(() {
        _a = yeni;
        _rapor = DnsRaporu.coz(sonuc[1]);
        _raporYuklendi = true;
        _hata = null;
        if (sonuc.length > 2 && sonuc[2] != null) _takmaAdSayisi = haritalar(harita(sonuc[2])['items']).length;
      });
      if (!ilk) widget.degisti(yeni);
      // Web panelindeki gibi: son denetim 5 dakikadan eskiyse bir kez yeniden denetle.
      final yas = _a.dnsZamani == null ? null : DateTime.now().difference(_a.dnsZamani!);
      if (ilk && _yonetir && (yas == null || yas > const Duration(minutes: 5))) _denetle(sessiz: true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _denetle({bool sessiz = false}) async {
    setState(() => _denetleniyor = true);
    try {
      final v = await Uyg.api.post('/api/v1/domains/${_a.id}/dns-check');
      final r = DnsRaporu.coz(v);
      if (!mounted) return;
      setState(() => _rapor = r);
      if (!sessiz) bildir(r?.dogrulandi == true ? 'Denetim tamamlandı — sahiplik doğrulandı' : 'Denetim tamamlandı', tur: MesajTur.basari);
      final d = await Uyg.api.get('/api/v1/domains/${_a.id}');
      if (!mounted) return;
      setState(() => _a = AlanAdi.coz(harita(d)));
      widget.degisti(_a);
    } catch (e) {
      if (!sessiz) bildir('Denetim başarısız', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _denetleniyor = false);
    }
  }

  Future<void> _durum(String durum) async {
    final askiya = durum == 'suspended';
    if (askiya &&
        !await onayla(context, '${_a.gorunenAd} askıya alınsın mı?', mesaj: 'Bu alan adına posta kabulü durur.', evet: 'Askıya al', tehlikeli: true)) {
      return;
    }
    final v = await islem(
      () => Uyg.api.patch('/api/v1/domains/${_a.id}', {'status': durum}),
      tamam: askiya ? 'Alan adı askıya alındı' : 'Askı kaldırıldı (doğrulama bekliyor)',
    );
    if (v != null && mounted) {
      setState(() => _a = AlanAdi.coz(harita(v)));
      widget.degisti(_a);
    }
  }

  Future<void> _dkimYenile() async {
    if (_a.dkim != null &&
        !await onayla(
          context,
          'DKIM anahtarı yenilensin mi?',
          mesaj: 'Yeni anahtar üretilirse eski DNS kaydı geçersiz olur; yeni kaydı yayınlayana kadar iletiler eşleşmeyen anahtarla imzalanır.',
          evet: 'Yenile',
          tehlikeli: true,
        )) {
      return;
    }
    final v = await islem(() => Uyg.api.post('/api/v1/domains/${_a.id}/dkim'), tamam: 'DKIM anahtarı üretildi');
    if (v != null && mounted) {
      setState(() => _a = AlanAdi.coz(harita(v)));
      widget.degisti(_a);
    }
  }

  Future<void> _sil() async {
    if (_a.kutuSayisi > 0) {
      bildir('Önce posta kutularını silin', mesaj: 'Alan adı yalnızca üzerinde posta kutusu kalmadığında silinebilir.', tur: MesajTur.uyari);
      return;
    }
    final ok = await yazarakOnayla(
      context,
      baslik: '${_a.gorunenAd} silinsin mi?',
      mesaj: 'Alan adı, DKIM anahtarı ve DNS denetim kayıtları kalıcı olarak silinir. Bu işlem geri alınamaz.',
      beklenen: _a.gorunenAd,
    );
    if (!ok) return;
    final v = await islem(() => Uyg.api.delete('/api/v1/domains/${_a.id}').then((_) => true), tamam: 'Alan adı silindi');
    if (v == true && mounted) {
      widget.degisti(null);
      if (widget.tamSayfa) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final a = _a;
    return RefreshIndicator.adaptive(
      onRefresh: _yukle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (!widget.tamSayfa)
            DetayBasligi(
              baslik: a.gorunenAd,
              alt: a.unicodeAd != a.ad && a.unicodeAd.isNotEmpty ? a.ad : null,
              sag: IconButton(tooltip: 'Yenile', onPressed: _yukle, icon: const Icon(Icons.refresh_rounded)),
            ),
          if (_hata != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Bant(_hata!, renk: Marka.gul, ikon: Icons.cloud_off_rounded),
            ),
          Kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    DurumRozeti(a.durum),
                    Rozet(a.hosting ? 'Mail Hosting' : 'MX Gateway', ikon: a.hosting ? Icons.dns_rounded : Icons.alt_route_rounded),
                    DnsRozeti(a.dnsDurumu),
                  ],
                ),
                const SizedBox(height: 10),
                if (!Uyg.musteri) BilgiSatiri('Müşteri', a.orgAdi),
                if (a.unicodeAd != a.ad) BilgiSatiri('Punycode', a.ad, mono: true),
                BilgiSatiri('Eklenme', tamZaman(a.eklenme)),
                BilgiSatiri('Doğrulanma', a.dogrulanma == null ? 'Doğrulanmadı' : tamZaman(a.dogrulanma)),
                if (!a.hosting)
                  BilgiSatiri('Hedef sunucu', a.gatewayHost.isEmpty ? 'Tanımlanmadı' : '${a.gatewayHost}:${a.gatewayPort}', mono: a.gatewayHost.isNotEmpty),
                if (a.hosting) ...[
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _Sayac(etiket: 'Posta kutusu', deger: '${a.kutuSayisi}', onTap: () => _kutular()),
                      ),
                      Expanded(
                        child: _Sayac(etiket: 'Takma ad / liste', deger: _takmaAdSayisi == null ? '—' : '$_takmaAdSayisi'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Baslik('1. Sahiplik doğrulama kaydı'),
          Kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Bu TXT kaydını alan adının DNS bölgesine ekleyin. Kayıt bulunduğunda alan adı etkinleşir.',
                  style: TextStyle(color: r.soluk, fontSize: 13),
                ),
                const SizedBox(height: 6),
                const KopyaKutusu('TXT', etiket: 'Tür'),
                KopyaKutusu(a.ad, etiket: 'Ad (@)'),
                KopyaKutusu(a.dogrulamaTxt, etiket: 'Değer'),
              ],
            ),
          ),
          Baslik(
            '2. Canlı DNS denetimi',
            sag: _yonetir
                ? TextButton.icon(
                    onPressed: _denetleniyor ? null : _denetle,
                    icon: _denetleniyor
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('DNS denetle'),
                  )
                : null,
          ),
          _dnsBolumu(),
          if (a.hosting) ...[
            Baslik(
              '3. DKIM imzalama',
              sag: _yonetir
                  ? TextButton.icon(
                      onPressed: _dkimYenile,
                      icon: const Icon(Icons.vpn_key_rounded, size: 18),
                      label: Text(a.dkim == null ? 'Anahtar üret' : 'Anahtarı yenile'),
                    )
                  : null,
            ),
            Kutu(
              child: a.dkim == null
                  ? Text(
                      'Henüz anahtar yok. Üretilen 2048 bit RSA anahtarın gizli kısmı sunucuda kalır; yalnızca yayınlanacak DNS kaydı gösterilir.',
                      style: TextStyle(color: r.soluk, fontSize: 13),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const KopyaKutusu('TXT', etiket: 'Tür'),
                        KopyaKutusu(a.dkim!.kayitAdi, etiket: 'Ad'),
                        KopyaKutusu(a.dkim!.kayit, etiket: 'Değer'),
                        const SizedBox(height: 6),
                        Text(
                          'Üretildi: ${tamZaman(a.dkim!.olusturma)} · 255 karakterden uzun TXT değerlerini DNS sağlayıcınız otomatik böler.',
                          style: TextStyle(color: r.silik, fontSize: 12),
                        ),
                      ],
                    ),
            ),
          ],
          const Baslik('İşlemler'),
          if (a.hosting && Bolum.kutular.gorunur) ...[
            EylemSatiri(ikon: Icons.inbox_rounded, baslik: 'Posta kutuları', ipucu: 'Bu alan adındaki hesaplar', onTap: _kutular),
            const SizedBox(height: 8),
          ],
          if (Uyg.ortak && Uyg.yetki('domains.manage')) ...[
            if (a.durum != 'suspended')
              EylemSatiri(
                ikon: Icons.pause_circle_outline_rounded,
                baslik: 'Askıya al',
                ipucu: 'Bu alan adına posta kabulünü durdur',
                onTap: () => _durum('suspended'),
              )
            else
              EylemSatiri(
                ikon: Icons.play_circle_outline_rounded,
                baslik: 'Askıyı kaldır',
                ipucu: 'Yeniden doğrulama bekler duruma al',
                onTap: () => _durum('pending'),
              ),
            const SizedBox(height: 8),
          ],
          if (_yonetir)
            EylemSatiri(
              ikon: Icons.delete_outline_rounded,
              baslik: 'Alan adını sil',
              ipucu: 'Yalnızca posta kutusu kalmadığında silinebilir',
              tehlikeli: true,
              onTap: _sil,
            ),
        ],
      ),
    );
  }

  void _kutular() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PostaKutulariEkrani(alanId: _a.id, alanAdi: _a.gorunenAd),
    ),
  );

  Widget _dnsBolumu() {
    final r = context.r;
    if (!_raporYuklendi) {
      return const Kutu(
        child: Center(
          child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator.adaptive()),
        ),
      );
    }
    final rap = _rapor;
    if (rap == null) {
      return Kutu(
        child: Text(
          'Henüz denetlenmedi. Sorgular gerçek DNS çözücüleriyle yapılır; sahiplik kaydı bulunursa alan adı etkinleşir.',
          style: TextStyle(color: r.soluk, fontSize: 13),
        ),
      );
    }
    return Kutu(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Son denetim ${tamZaman(rap.zaman)}', style: TextStyle(color: r.silik, fontSize: 12.5)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (rap.sayi('ok') > 0) Rozet('${rap.sayi('ok')} tamam', renk: Marka.zumrut),
              if (rap.sayi('warn') > 0) Rozet('${rap.sayi('warn')} uyarı', renk: Marka.kehribar),
              if (rap.sayi('fail') > 0) Rozet('${rap.sayi('fail')} hata', renk: Marka.gul),
              if (rap.sayi('info') > 0) Rozet('${rap.sayi('info')} bilgi', renk: r.silik),
            ],
          ),
          const SizedBox(height: 4),
          for (final (i, k) in rap.kontroller.indexed) ...[if (i > 0) const Divider(height: 1), DnsKontrolSatiri(k)],
        ],
      ),
    );
  }
}

class _Sayac extends StatelessWidget {
  const _Sayac({required this.etiket, required this.deger, this.onTap});
  final String etiket, deger;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Text(deger, style: gosterim(20)),
          Text(etiket, style: TextStyle(color: context.r.silik, fontSize: 12)),
        ],
      ),
    ),
  );
}

(IconData, Color) dnsDurumGorunumu(String durum, Renkler r) => switch (durum) {
  'ok' => (Icons.check_circle_rounded, Marka.zumrut),
  'warn' => (Icons.warning_amber_rounded, Marka.kehribar),
  'fail' => (Icons.cancel_rounded, Marka.gul),
  'error' => (Icons.error_outline_rounded, r.silik),
  'not_built' => (Icons.radio_button_unchecked_rounded, r.silik),
  _ => (Icons.info_outline_rounded, Marka.mavi),
};

/// Tek DNS denetimi: durum, açıklama, olması gereken kayıt (kopyalanabilir), DNS'te bulunan ve teşhis edilen hatalar.
class DnsKontrolSatiri extends StatelessWidget {
  const DnsKontrolSatiri(this.k, {super.key});
  final DnsKontrolu k;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final (ikon, renk) = dnsDurumGorunumu(k.durum, r);
    final yapisal = k.host.isNotEmpty && k.deger.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(ikon, color: renk, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(k.etiket, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (k.durum == 'not_built') Rozet('Henüz yok', renk: r.silik),
            ],
          ),
          if (k.ayrinti.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 27, top: 3),
              child: Text(k.ayrinti, style: TextStyle(color: r.soluk, fontSize: 12.5)),
            ),
          if (yapisal)
            Padding(
              padding: const EdgeInsets.only(left: 27, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Olması gereken kayıt',
                    style: TextStyle(color: r.soluk, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  KopyaKutusu(k.host, etiket: 'Ad'),
                  KopyaKutusu(k.tur, etiket: 'Tür'),
                  KopyaKutusu(k.deger, etiket: 'Değer'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (k.durum == 'ok' ? Marka.zumrut : Marka.gul).withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: (k.durum == 'ok' ? Marka.zumrut : Marka.gul).withValues(alpha: .3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "DNS'te şu an bulunan",
                          style: TextStyle(color: r.soluk, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        if (k.bulunan.isEmpty)
                          Text('Bu adda kayıt bulunamadı.', style: TextStyle(color: r.silik, fontSize: 12))
                        else
                          for (final f in k.bulunan) SelectableText(f, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (k.beklenen.isNotEmpty)
            Padding(padding: const EdgeInsets.only(left: 27), child: KopyaKutusu(k.beklenen)),
          if (k.sorunlar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 27, top: 8),
              child: Bant(k.sorunlar.join('\n'), renk: Marka.kehribar, ikon: Icons.warning_amber_rounded),
            ),
        ],
      ),
    );
  }
}
