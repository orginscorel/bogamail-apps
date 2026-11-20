import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'alan_adlari.dart';
import 'bolumler.dart';
import 'posta_kutulari.dart';
import '../ortak/simgeler.dart';

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
              sag: IconButton(tooltip: 'Yenile', onPressed: _yukle, icon: const Icon(Simgeler.refresh)),
            ),
          if (_hata != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Bant(_hata!, renk: Marka.gul, ikon: Simgeler.cloudOff),
            ),
          Kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DurumRozeti(a.durum),
                    Rozet(a.hosting ? 'Mail Hosting' : 'MX Gateway', ikon: a.hosting ? Simgeler.dns : Simgeler.altRoute),
                    DnsRozeti(a.dnsDurumu),
                  ],
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 8),
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
                        : const Icon(Simgeler.refresh, size: 18),
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
                      icon: const Icon(Simgeler.vpnKey, size: 18),
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
                        const SizedBox(height: 8),
                        Text(
                          'Üretildi: ${tamZaman(a.dkim!.olusturma)} · 255 karakterden uzun TXT değerlerini DNS sağlayıcınız otomatik böler.',
                          style: TextStyle(color: r.silik, fontSize: 12),
                        ),
                      ],
                    ),
            ),
          ],
          if (!a.hosting) ...[
            const Baslik('3. Teslim hedefi (gateway)'),
            _GatewayHedefi(
              alan: a,
              yonetir: _yonetir,
              kaydedildi: (y) {
                setState(() => _a = y);
                widget.degisti(y);
              },
            ),
          ],
          if (a.hosting) ...[const Baslik('Posta programı ayarları'), PostaProgramiAyarlari(alanAdi: a.gorunenAd)],
          const Baslik('İşlemler'),
          if (a.hosting && Bolum.kutular.gorunur) ...[
            EylemSatiri(ikon: Simgeler.inbox, baslik: 'Posta kutuları', ipucu: 'Bu alan adındaki hesaplar', onTap: _kutular),
            const SizedBox(height: 8),
          ],
          if (Uyg.ortak && Uyg.yetki('domains.manage')) ...[
            if (a.durum != 'suspended')
              EylemSatiri(
                ikon: Simgeler.pauseCircleOutline,
                baslik: 'Askıya al',
                ipucu: 'Bu alan adına posta kabulünü durdur',
                onTap: () => _durum('suspended'),
              )
            else
              EylemSatiri(
                ikon: Simgeler.playCircleOutline,
                baslik: 'Askıyı kaldır',
                ipucu: 'Yeniden doğrulama bekler duruma al',
                onTap: () => _durum('pending'),
              ),
            const SizedBox(height: 8),
          ],
          if (_yonetir)
            EylemSatiri(
              ikon: Simgeler.deleteOutline,
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
          Text(deger, style: gosterim(20, agirlik: FontWeight.w600)),
          Text(etiket, style: TextStyle(color: context.r.silik, fontSize: 12)),
        ],
      ),
    ),
  );
}

(IconData, Color) dnsDurumGorunumu(String durum, Renkler r) => switch (durum) {
  'ok' => (Simgeler.checkCircle, Marka.zumrut),
  'warn' => (Simgeler.warningAmber, Marka.kehribar),
  'fail' => (Simgeler.cancel, Marka.gul),
  'error' => (Simgeler.errorOutline, r.silik),
  'not_built' => (Simgeler.radioButtonUnchecked, r.silik),
  _ => (Simgeler.infoOutline, Marka.mavi),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
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
              padding: const EdgeInsets.only(left: 27, top: 8),
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
                    padding: const EdgeInsets.all(8),
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
              child: Bant(k.sorunlar.join('\n'), renk: Marka.kehribar, ikon: Simgeler.warningAmber),
            ),
        ],
      ),
    );
  }
}

/// Gateway alan adının birincil teslim hedefi (PATCH /domains/{id} gateway_host, gateway_port).
class _GatewayHedefi extends StatefulWidget {
  const _GatewayHedefi({required this.alan, required this.yonetir, required this.kaydedildi});
  final AlanAdi alan;
  final bool yonetir;
  final ValueChanged<AlanAdi> kaydedildi;
  @override
  State<_GatewayHedefi> createState() => _GatewayHedefiState();
}

class _GatewayHedefiState extends State<_GatewayHedefi> {
  late final _host = TextEditingController(text: widget.alan.gatewayHost);
  late final _port = TextEditingController(text: '${widget.alan.gatewayPort == 0 ? 25 : widget.alan.gatewayPort}');
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _hata = 'Port 1-65535 arasında olmalı.');
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final v = await Uyg.api.patch('/api/v1/domains/${widget.alan.id}', {'gateway_host': _host.text.trim(), 'gateway_port': port});
      bildir('Teslim hedefi kaydedildi', tur: MesajTur.basari);
      widget.kaydedildi(AlanAdi.coz(harita(v)));
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Spam taramasından geçen iletiler bu sunucuya iletilir (müşterinin kendi posta sunucusu). Yerel ve özel ağ adresleri güvenlik nedeniyle kabul edilmez.',
            style: TextStyle(color: r.soluk, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _host,
                  enabled: widget.yonetir,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(labelText: 'Sunucu', hintText: 'mail.musteri.com', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _port,
                  enabled: widget.yonetir,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port', isDense: true),
                ),
              ),
            ],
          ),
          if (_hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 12.5))),
          if (widget.yonetir) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _mesgul ? null : _kaydet,
                child: _mesgul ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Kaydet'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (widget.alan.gatewayHost.isEmpty)
            const Bant(
              'Hedef tanımlanmadan bu alan adına gelen iletiler geçici hatayla (451) geri çevrilir; gönderen sunucu daha sonra tekrar dener.',
              renk: Marka.kehribar,
              ikon: Simgeler.warningAmber,
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Yedek hedefler, TLS politikası, devre kesici ve kesinti modu Mail Gateway bölümünden yönetilir.',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Posta programı ayarları (GET /mail-client-settings): sunucu, gelen / giden portlar, güvenlik, kullanıcı adı biçimi.
class PostaProgramiAyarlari extends StatefulWidget {
  const PostaProgramiAyarlari({super.key, required this.alanAdi});
  final String alanAdi;
  @override
  State<PostaProgramiAyarlari> createState() => _PostaProgramiAyarlariState();
}

class _PostaProgramiAyarlariState extends State<PostaProgramiAyarlari> {
  late final Future<dynamic> _getir = Uyg.api.get('/api/v1/mail-client-settings');

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: _getir,
    builder: (c, s) {
      final r = c.r;
      if (s.hasError) return Kutu(child: Text(hataMetni(s.error!), style: TextStyle(color: r.silik, fontSize: 13)));
      if (!s.hasData) {
        return const Kutu(child: Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator.adaptive())));
      }
      final m = harita(s.data);
      final host = metin(m['host']);
      Widget uclar(String baslik, IconData ikon, List<Map<String, dynamic>> l) => Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: r.kenar)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Icon(ikon, size: 16, color: r.birincil),
                  const SizedBox(width: 8),
                  Text(baslik, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
            Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
            if (l.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('Açık değil', style: TextStyle(color: r.silik, fontSize: 13))),
            for (final e in l)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  children: [
                    Expanded(child: Text(metin(e['protocol']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    Text('${tamsayi(e['port'])}', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                    const SizedBox(width: 8),
                    Text(metin(e['security']), style: TextStyle(color: r.soluk, fontSize: 12.5)),
                    if (!mantik(e['enabled'], true)) ...[const SizedBox(width: 8), Rozet('kapalı', renk: r.silik)],
                  ],
                ),
              ),
          ],
        ),
      );
      final gelen = uclar('Gelen posta', Simgeler.mailOutline, haritalar(m['incoming']));
      final giden = uclar('Giden posta (SMTP)', Simgeler.send, haritalar(m['outgoing']));
      final notlar = [
        'SMTP için kimlik doğrulama açık olmalı (gelen sunucuyla aynı kullanıcı adı ve şifre).',
        if (mantik(m['restricted'])) 'Şu an posta programı bağlantıları yalnızca izin verilen IP adreslerinden kabul ediliyor.',
        if (metin(m['host_note']).isNotEmpty) metin(m['host_note']),
      ].join(' ');
      return Kutu(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BilgiSatiri('Sunucu', host, mono: true, kopyalanabilir: host.isNotEmpty),
            BilgiSatiri('Kullanıcı adı', 'ad@${widget.alanAdi}', mono: true),
            const BilgiSatiri('Şifre', 'Posta kutusunun şifresi'),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (c, k) => k.maxWidth >= 460
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: gelen),
                        const SizedBox(width: 8),
                        Expanded(child: giden),
                      ],
                    )
                  : Column(children: [gelen, const SizedBox(height: 8), giden]),
            ),
            const SizedBox(height: 8),
            Text(notlar, style: TextStyle(color: r.silik, fontSize: 12)),
          ],
        ),
      );
    },
  );
}
