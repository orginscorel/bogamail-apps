import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/json.dart';
import '../veri/taklit.dart';
import '../ortak/simgeler.dart';

/// Dış tarayıcıda adres açar (testlerde değiştirilir).
Future<bool> Function(Uri) adresAc = (u) => launchUrl(u, mode: LaunchMode.externalApplication);

/// Ana kabuğu kuran fonksiyon; kabuk ilk açıldığında kaydeder (bu dosya kabuğa bağımlı olmasın diye).
Widget Function()? kabukKurucu;

/// Görünüm değişince kullanıcıyı yeniden yükler ve kabuğu baştan kurar (testlerde değiştirilir).
Future<void> Function() kabuguYenile = () async {
  final ok = await Uyg.yukle();
  final kur = kabukKurucu;
  kokGezgin.currentState?.pushAndRemoveUntil(HizliRota(builder: (_) => ok && kur != null ? kur() : Uyg.girisEkrani()), (_) => false);
};

Widget _madde(BuildContext c, IconData i, String m) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(i, size: 18, color: c.r.soluk),
      const SizedBox(width: 8),
      Expanded(child: Text(m, style: const TextStyle(fontSize: 13.5, height: 1.35))),
    ],
  ),
);

/// "Posta kutusuna gir": onay → tek kullanımlık webmail adresi → dış tarayıcı. Jeton 60 sn geçerli olduğu için
/// adres alınır alınmaz açılır; açılamazsa kopyalanabilir olarak gösterilir.
Future<void> postaKutusunaGir(BuildContext context, {required String id, required String adres}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      scrollable: true,
      icon: Icon(Simgeler.markEmailUnread, color: c.r.vurgu, size: 30),
      title: Text('Posta kutusuna gir', style: gosterim(19, agirlik: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(adres, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Kutu, şifresi sorulmadan webmail\'de açılır.', style: TextStyle(color: c.r.soluk, fontSize: 13)),
            const SizedBox(height: 16),
            _madde(c, Simgeler.timer, 'Oturum 30 dakika sürer; giriş bağlantısı tek kullanımlıktır ve 60 saniye içinde açılmalıdır.'),
            _madde(c, Simgeler.password, 'Bu oturumda kutunun şifresi değiştirilemez; gönderilen her ileti "yönetici adına gönderim" olarak kaydedilir.'),
            _madde(c, Simgeler.visibility, 'Kutu sahibi bu erişimi Ayarlar → Güvenlik bölümündeki güvenlik kaydında görür.'),
            _madde(c, Simgeler.receiptLong, 'Erişim; adınız, IP adresiniz ve zamanla denetim kayıtlarına yazılır.'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Simgeler.openInNew, size: 18), label: const Text('Webmail\'i aç')),
      ],
    ),
  );
  if (ok != true) return;
  final Uri u;
  try {
    u = await Taklit.webmailAdresi(Uyg.api, id);
  } catch (e) {
    bildir('Webmail açılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    return;
  }
  var acildi = false;
  try {
    acildi = await adresAc(u);
  } catch (_) {}
  if (acildi) {
    bildir('Webmail tarayıcıda açıldı', mesaj: adres, tur: MesajTur.basari);
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      scrollable: true,
      title: Text('Tarayıcı açılamadı', style: gosterim(19, agirlik: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Bağlantıyı kopyalayıp 60 saniye içinde bir tarayıcıda açın. Bağlantı yalnızca bir kez kullanılabilir.'),
          KopyaKutusu(u.toString(), mesaj: 'Bağlantı kopyalandı'),
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
    ),
  );
}

/// "Müşteri paneline gir": gerekçe (en az 5 karakter) → panel o müşterinin yöneticisi olarak yeniden açılır.
Future<void> musteriPanelineGir(BuildContext context, {required String id, required String ad}) async {
  final k = TextEditingController();
  String? hata;
  var mesgul = false;
  final girildi = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, yenile) {
        Future<void> gonder() async {
          yenile(() {
            mesgul = true;
            hata = null;
          });
          try {
            await Taklit.musteriyeGir(Uyg.api, id, k.text);
            if (c.mounted) Navigator.pop(c, true);
          } catch (e) {
            yenile(() {
              mesgul = false;
              hata = hataMetni(e);
            });
          }
        }

        return AlertDialog(
          scrollable: true,
          icon: Icon(Simgeler.switchAccount, color: c.r.vurgu, size: 30),
          title: Text('Müşteri paneline gir', style: gosterim(19, agirlik: FontWeight.w600)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Paneli '),
                  TextSpan(text: ad, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const TextSpan(text: ' yöneticisi olarak görüntüleyeceksiniz.'),
                ])),
                const SizedBox(height: 12),
                _madde(c, Simgeler.timer, 'Görünüm 30 dakika sonra kendiliğinden kapanır; üstteki banttan istediğiniz an çıkabilirsiniz.'),
                _madde(c, Simgeler.block, 'Panel kullanıcıları, paketler, bayiler, IP havuzu, kuyruk ve platform ayarları bu görünümde değiştirilemez.'),
                _madde(c, Simgeler.receiptLong, 'Gerekçe, oturum ve IP adresiniz denetim kaydına yazılır.'),
                const SizedBox(height: 8),
                TextField(
                  controller: k,
                  autofocus: true,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => yenile(() {}),
                  decoration: InputDecoration(labelText: 'Gerekçe', hintText: 'Örn. Destek talebi #1234 — gönderim sorunu', errorText: hata),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: mesgul ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: mesgul || k.text.trim().length < 5 ? null : gonder,
              child: mesgul ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Müşteri paneline gir'),
            ),
          ],
        );
      },
    ),
  );
  if (girildi == true) {
    bildir('Müşteri panelindesiniz', mesaj: ad, tur: MesajTur.basari);
    await kabuguYenile();
  }
}

/// "Bayi paneline gir" (yalnızca süper yönetici; gerekçe sorulmaz, varsayılanı kaydedilir).
Future<void> bayiPanelineGir(BuildContext context, {required String id, required String ad}) async {
  if (!await onayla(
    context,
    'Bayi paneline gir',
    mesaj: 'Panel "$ad" bayisinin yöneticisi olarak açılır. Görünüm 30 dakika sürer, denetim kaydına yazılır; kullanıcı, paket ve platform ayarları bu görünümde değiştirilemez.',
    evet: 'Bayi paneline gir',
  )) {
    return;
  }
  final v = await islem(() => Taklit.bayiyeGir(Uyg.api, id));
  if (v == null) return;
  bildir('Bayi panelindesiniz', mesaj: v.isEmpty ? ad : v, tur: MesajTur.basari);
  await kabuguYenile();
}

/// Görünümden çıkar ve asıl yönetici paneline döner.
Future<void> gorunumdenCik({bool sureDoldu = false}) async {
  try {
    final geri = await Taklit.cik(Uyg.api);
    bildir(sureDoldu ? 'Görünüm süresi doldu' : 'Görünümden çıkıldı', mesaj: geri ? 'Yönetici paneline dönüldü.' : 'Yeniden giriş yapın.', tur: geri ? MesajTur.basari : MesajTur.uyari);
  } catch (e) {
    bildir('Görünümden çıkılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
  }
  await kabuguYenile();
}

/// Kabuğun üstündeki kalıcı bant: "Müşteri panelindesiniz: `<ad>` · Çık". Süre dolmadan kendiliğinden çıkar
/// (süre dolarsa sunucu oturumu düşürür ve asıl oturum da kaybolurdu).
class TaklitBandi extends StatefulWidget {
  const TaklitBandi({super.key});
  @override
  State<TaklitBandi> createState() => _TaklitBandiState();
}

class _TaklitBandiState extends State<TaklitBandi> {
  Timer? _sayac, _bitis;
  bool _cikiyor = false;

  @override
  void initState() {
    super.initState();
    Uyg.ben.addListener(_kur);
    _kur();
  }

  @override
  void dispose() {
    Uyg.ben.removeListener(_kur);
    _sayac?.cancel();
    _bitis?.cancel();
    super.dispose();
  }

  void _kur() {
    _sayac?.cancel();
    _bitis?.cancel();
    final t = Uyg.taklit;
    final son = tarihOku(t?['expires_at']);
    if (t == null || son == null) return;
    _sayac = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    final kalan = son.difference(DateTime.now()) - const Duration(seconds: 20);
    _bitis = Timer(kalan.isNegative ? Duration.zero : kalan, () => _cik(sureDoldu: true));
  }

  Future<void> _cik({bool sureDoldu = false}) async {
    if (_cikiyor) return;
    setState(() => _cikiyor = true);
    await gorunumdenCik(sureDoldu: sureDoldu);
    if (mounted) setState(() => _cikiyor = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Uyg.taklit;
    if (t == null) return const SizedBox.shrink();
    final bayi = metin(t['kind']) == 'reseller';
    final son = tarihOku(t['expires_at']);
    final dk = son?.difference(DateTime.now()).inMinutes.clamp(0, 999);
    return Material(
      color: Marka.kehribar,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Simgeler.visibility, size: 18, color: Color(0xFF3B2600)),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: bayi ? 'Bayi panelindesiniz: ' : 'Müşteri panelindesiniz: '),
                    TextSpan(text: taklitAdi(t), style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (dk != null) TextSpan(text: ' · $dk dk kaldı'),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF3B2600), fontSize: 13),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF3B2600), visualDensity: VisualDensity.compact),
                onPressed: _cikiyor ? null : _cik,
                icon: _cikiyor
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B2600)))
                    : const Icon(Simgeler.logout, size: 18),
                label: const Text('Çık', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// İşlem görünüm içinde engellendiyse anlaşılır mesaj gösterir; true döner.
bool taklitEngeliniBildir(Object e) {
  if (!taklitEngeli(e)) return false;
  bildir('Müşteri görünümünde yapılamaz', mesaj: 'Bu işlem için görünümden çıkıp kendi panelinize dönün.', tur: MesajTur.uyari);
  return true;
}
