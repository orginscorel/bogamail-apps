import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'kutu_formlari.dart';

/// Posta kutusu ayrıntısı: kota, durum, son giriş, yönlendirme, güvenlik, takma adlar ve işlemler.
class KutuDetay extends StatefulWidget {
  const KutuDetay({super.key, required this.kutu, required this.degisti, this.tamSayfa = false});
  final PostaKutusu kutu;
  final void Function(PostaKutusu?) degisti;
  final bool tamSayfa;
  @override
  State<KutuDetay> createState() => _KutuDetayState();
}

class _KutuDetayState extends State<KutuDetay> {
  late PostaKutusu _k = widget.kutu;
  Yonlendirme? _yon;
  Map<String, dynamic>? _guvenlik;
  List<TakmaAd>? _takmaAdlar;
  String? _hata;

  bool get _yonetir => Uyg.yetki('mailboxes.manage');

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final id = _k.id;
    Future<Object?> dene(Future<Object?> f) => f.catchError((_) => null);
    try {
      final s = await Future.wait<Object?>([
        Uyg.api.get('/api/v1/mailboxes/$id'),
        dene(Uyg.api.get('/api/v1/mailboxes/$id/forwarding')),
        dene(Uyg.api.get('/api/v1/mailboxes/$id/security')),
        dene(Uyg.api.get('/api/v1/aliases', q: {'q': _k.adresAscii, 'domain_id': _k.alanId})),
      ]);
      if (!mounted) return;
      final yeni = PostaKutusu.coz(harita(s[0]));
      final adres = yeni.adresAscii.toLowerCase();
      setState(() {
        _k = yeni;
        _hata = null;
        _yon = s[1] == null ? null : Yonlendirme.coz(s[1]);
        _guvenlik = s[2] == null ? null : harita(s[2]);
        _takmaAdlar = s[3] == null
            ? null
            : haritalar(harita(s[3])['items']).map(TakmaAd.coz).where((t) => t.hedefler.any((h) => h.toLowerCase() == adres)).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  void _guncelle(PostaKutusu y) {
    setState(() => _k = y);
    widget.degisti(y);
  }

  Future<void> _duzenle() async {
    final y = await showDialog<PostaKutusu>(
      context: context,
      builder: (_) => KutuDuzenleDialog(kutu: _k),
    );
    if (y != null && mounted) _guncelle(y);
  }

  Future<void> _durum() async {
    final askiya = _k.aktif;
    if (askiya &&
        !await onayla(
          context,
          '${_k.adres} askıya alınsın mı?',
          mesaj: 'Kullanıcı giriş yapamaz ve posta gönderemez. Gelen posta kabul edilmeye devam eder.',
          evet: 'Askıya al',
          tehlikeli: true,
        )) {
      return;
    }
    final v = await islem(
      () => Uyg.api.patch('/api/v1/mailboxes/${_k.id}', {'status': askiya ? 'suspended' : 'active'}),
      tamam: askiya ? 'Posta kutusu askıya alındı' : 'Posta kutusu etkinleştirildi',
    );
    if (v != null && mounted) _guncelle(PostaKutusu.coz(harita(v)));
  }

  Future<void> _sil() async {
    final ok = await yazarakOnayla(
      context,
      baslik: '${_k.adres} silinsin mi?',
      mesaj: 'Hesap kalıcı olarak silinir ve bu adrese gelen posta reddedilir. İçinde ileti bulunan kutular silinemez. Bu işlem geri alınamaz.',
      beklenen: _k.adres,
    );
    if (!ok) return;
    final v = await islem(() => Uyg.api.delete('/api/v1/mailboxes/${_k.id}').then((_) => true), tamam: 'Posta kutusu silindi');
    if (v == true && mounted) {
      widget.degisti(null);
      if (widget.tamSayfa) Navigator.of(context).maybePop();
    }
  }

  Future<void> _yonlendirme() async {
    final y = _yon;
    if (y == null) return;
    final yeni = await yonlendirmeDuzenle(context, _k, y);
    if (yeni != null && mounted) setState(() => _yon = yeni);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final k = _k;
    final mfa = harita(_guvenlik?['mfa']);
    final uygSifre = _guvenlik?['app_passwords'] is List ? (_guvenlik!['app_passwords'] as List).length : null;
    return RefreshIndicator.adaptive(
      onRefresh: _yukle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Avatar(k.gorunenAd.isEmpty ? k.adres : k.gorunenAd, tohum: k.adres, boyut: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(k.adres, style: gosterim(17, agirlik: FontWeight.w700)),
                          if (k.gorunenAd.isNotEmpty) Text(k.gorunenAd, style: TextStyle(color: r.soluk)),
                        ],
                      ),
                    ),
                    DurumRozeti(k.durum),
                    if (!widget.tamSayfa) IconButton(tooltip: 'Yenile', onPressed: _yukle, icon: const Icon(Icons.refresh_rounded)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Kota',
                  style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                KullanimCubugu(kullanilan: k.kullanilan, toplam: k.kota),
              ],
            ),
          ),
          if (_hata != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Bant(_hata!, renk: Marka.gul, ikon: Icons.cloud_off_rounded),
            ),
          const Baslik('Bilgiler'),
          Kutu(
            child: Column(
              children: [
                if (!Uyg.musteri) BilgiSatiri('Müşteri', k.orgAdi),
                BilgiSatiri('Alan adı', k.alanAdi),
                if (k.adres != k.adresAscii) BilgiSatiri('ASCII adres', k.adresAscii, mono: true, kopyalanabilir: true),
                BilgiSatiri('Kota', sinirsizMi(k.kota) ? 'Sınırsız' : boyutYaz(k.kota)),
                BilgiSatiri('Gönderim sınırı', '${sayiYaz(k.saatlikSinir)} ileti / saat'),
                BilgiSatiri('Son giriş', k.sonGiris == null ? 'Hiç giriş yapılmadı' : '${tamZaman(k.sonGiris)} (${goreliZaman(k.sonGiris)})'),
                BilgiSatiri('Oluşturulma', tamZaman(k.eklenme)),
              ],
            ),
          ),
          if (_guvenlik != null) ...[
            const Baslik('Güvenlik'),
            Kutu(
              child: Column(
                children: [
                  BilgiSatiri(
                    'İki adımlı doğrulama',
                    mantik(mfa['enabled'])
                        ? 'Açık${mfa['enabled_at'] != null ? ' · ${kisaZaman(tarihOku(mfa['enabled_at']))}' : ''}'
                        : (mantik(mfa['required']) ? 'Kapalı (politika zorunlu kılıyor)' : 'Kapalı'),
                  ),
                  if (uygSifre != null) BilgiSatiri('Uygulama şifreleri', uygSifre == 0 ? 'Yok' : '$uygSifre etkin şifre'),
                ],
              ),
            ),
          ],
          if (_yon != null) ...[
            Baslik(
              'Yönlendirme',
              sag: _yonetir && (_yon!.izinli || _yon!.hedef.isNotEmpty) ? TextButton(onPressed: _yonlendirme, child: const Text('Düzenle')) : null,
            ),
            Kutu(
              child: _yon!.hedef.isEmpty
                  ? Text(
                      _yon!.izinli ? 'Yönlendirme kapalı.' : 'Yönlendirme bu posta kutusu için kapalı (paket veya kutu ayarı).',
                      style: TextStyle(color: r.soluk),
                    )
                  : Column(
                      children: [
                        BilgiSatiri('Hedef', _yon!.hedef, kopyalanabilir: true),
                        BilgiSatiri('Kopya', _yon!.kopyaKalsin ? 'Bu kutuda da kalır' : 'Kutuda kalmaz'),
                        if (_yon!.ayarlayan.isNotEmpty)
                          BilgiSatiri('Ayarlayan', _yon!.ayarlayan.startsWith('admin:') ? 'Yönetici (${_yon!.ayarlayan.substring(6)})' : 'Kullanıcı'),
                      ],
                    ),
            ),
          ],
          if (_takmaAdlar != null && _takmaAdlar!.isNotEmpty) ...[
            const Baslik('Bu kutuya yönlenen takma adlar'),
            Kutu(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  for (final t in _takmaAdlar!)
                    BilgiSatiri(
                      t.liste ? 'Dağıtım listesi' : 'Takma ad',
                      t.adres,
                      mono: true,
                      sag: t.etkin ? null : const Rozet('kapalı', renk: Marka.kehribar),
                    ),
                ],
              ),
            ),
          ],
          if (_yonetir) ...[
            const Baslik('İşlemler'),
            EylemSatiri(ikon: Icons.edit_rounded, baslik: 'Düzenle', ipucu: 'Görünen ad, kota, gönderim sınırı', onTap: _duzenle),
            const SizedBox(height: 8),
            EylemSatiri(ikon: Icons.key_rounded, baslik: 'Şifreyi sıfırla', ipucu: 'Güçlü şifre üret, oturumları kapat', onTap: () => sifreSifirla(context, k)),
            const SizedBox(height: 8),
            EylemSatiri(
              ikon: k.aktif ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
              baslik: k.aktif ? 'Askıya al' : 'Etkinleştir',
              ipucu: k.aktif ? 'Giriş ve gönderimi durdur' : 'Hesabı yeniden kullanıma aç',
              onTap: _durum,
            ),
            const SizedBox(height: 8),
            EylemSatiri(ikon: Icons.delete_outline_rounded, baslik: 'Posta kutusunu sil', ipucu: 'Geri alınamaz', tehlikeli: true, onTap: _sil),
          ],
        ],
      ),
    );
  }
}
