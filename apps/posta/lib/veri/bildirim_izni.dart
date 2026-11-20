// Bildirim izni: ilk açılışta izin istenmeden önce neden gerektiği anlatılır (iOS, macOS, Android 13+). İzin
// kapalıysa kenar menüsünde ve Ayarlar'da kapatılabilir bir uyarı bandı "Ayarları aç" ile gösterilir; durum her
// öne gelişte yeniden denetlenir. Bildirimler varsayılan olarak açıktır (izin verilirse hemen çalışır).

import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:boga_ortak/boga_ortak.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'arkaplan.dart';
import 'bildirim.dart';

class BildirimIzni {
  BildirimIzni._();

  static const _tanitimAnahtar = 'posta.bildirim.tanitim';

  /// true: izin kapalı (uyarı bandı gösterilir). null: henüz bilinmiyor.
  static final kapali = ValueNotifier<bool?>(null);

  /// Kullanıcı bandı bu oturum için kapattı.
  static final gizlendi = ValueNotifier<bool>(false);

  static bool _tanitimYapildi = false;
  static bool get tanitimYapildi => _tanitimYapildi;

  // Testler için.
  @visibleForTesting
  static bool Function() apple = () => !kIsWeb && (Platform.isIOS || Platform.isMacOS);
  @visibleForTesting
  static bool Function() android = () => Bildirim.android;

  static bool get _gerekli => apple() || android();

  static Future<void> yukle() async {
    try {
      _tanitimYapildi = (await SharedPreferences.getInstance()).getBool(_tanitimAnahtar) ?? false;
    } catch (_) {}
  }

  /// Push kaydı / Android izin denetimi sonucu.
  static void bildir({required bool izinVar}) {
    kapali.value = !izinVar;
    if (izinVar) gizlendi.value = false;
  }

  /// İlk kez: açıklama sayfası. Dönüş: izin istensin mi (kullanıcı "İzin ver" dedi ya da tanıtım önceden yapıldı).
  static Future<bool> tanitimGerekirse(BuildContext context) async {
    if (!_gerekli) return true;
    await yukle();
    if (_tanitimYapildi) return true;
    if (!context.mounted) return false;
    final evet = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const BildirimTanitimi(),
    );
    _tanitimYapildi = true;
    try {
      await (await SharedPreferences.getInstance()).setBool(_tanitimAnahtar, true);
    } catch (_) {}
    if (evet != true) kapali.value = true;
    return evet == true;
  }

  /// Android: pil kısıtlaması açık (arka planda bildirimler gecikebilir). Bantta "Muaf tut" ile gösterilir.
  static final pilKisitli = ValueNotifier<bool>(false);

  /// Öne gelişte: izin durumu (Android: bildirim izni + pil kısıtlaması; Apple: sistem izin durumu).
  static Future<void> denetle() async {
    if (!_tanitimYapildi) return;
    if (android()) {
      bildir(izinVar: await Bildirim.izinVar());
      pilKisitli.value = Arkaplan.surekliBagli.value && !await Arkaplan.platform.pilMuaf();
    } else if (apple()) {
      final d = await Push.izin();
      if (d != null) bildir(izinVar: d == 'verildi');
    }
  }

  static const _pilSoruldu = 'posta.pil.soruldu';
  static const _oemSoruldu = 'posta.oem.soruldu';

  /// Otomatik başlatmayı ayrıca kısıtlayan üreticiler (uygulama ayarlarında "Otomatik başlatma" vb.).
  static const _oemYollari = {
    'xiaomi': 'Ayarlar › Uygulamalar › BogaMail › Otomatik başlatma: açık; Pil tasarrufu: Kısıtlama yok',
    'redmi': 'Ayarlar › Uygulamalar › BogaMail › Otomatik başlatma: açık; Pil tasarrufu: Kısıtlama yok',
    'poco': 'Ayarlar › Uygulamalar › BogaMail › Otomatik başlatma: açık; Pil tasarrufu: Kısıtlama yok',
    'huawei': 'Ayarlar › Pil › Uygulama başlatma › BogaMail: "Manuel yönet", üç seçeneği de açın',
    'honor': 'Ayarlar › Pil › Uygulama başlatma › BogaMail: "Manuel yönet", üç seçeneği de açın',
    'oppo': 'Ayarlar › Pil › BogaMail: "Arka planda etkinliğe izin ver" ve "Otomatik başlat" açık',
    'realme': 'Ayarlar › Pil › BogaMail: "Arka planda etkinliğe izin ver" ve "Otomatik başlat" açık',
    'oneplus': 'Ayarlar › Pil › Pil optimizasyonu › BogaMail: "Optimize etme"',
    'vivo': 'Ayarlar › Pil › Arka planda yüksek güç tüketimi › BogaMail: açık',
    'samsung': 'Ayarlar › Pil › Arka plan kullanım sınırları › BogaMail\'i "Hiç uyumayan uygulamalar"a ekleyin',
    'meizu': 'Ayarlar › Uygulamalar › BogaMail › Arka planda çalışmaya izin ver',
    'asus': 'Ayarlar › Pil › Otomatik başlatma yöneticisi › BogaMail: açık',
  };

  /// Bildirim izni verildikten sonra (bir kez): pil kısıtlaması muafiyeti, gerekiyorsa üretici yardımı.
  static Future<void> pilVeOtomatikBaslatma(BuildContext context) async {
    if (!android()) return;
    final p = await SharedPreferences.getInstance();
    if (!await Arkaplan.platform.pilMuaf() && !(p.getBool(_pilSoruldu) ?? false)) {
      await p.setBool(_pilSoruldu, true);
      if (!context.mounted) return;
      if (await pilMuafiyetiSor(context)) await Arkaplan.platform.pilMuafiyetiIste();
    }
    pilKisitli.value = Arkaplan.surekliBagli.value && !await Arkaplan.platform.pilMuaf();
    if (p.getBool(_oemSoruldu) ?? false) return;
    final yol = _oemYollari[await _uretici()];
    if (yol == null) return;
    await p.setBool(_oemSoruldu, true);
    if (context.mounted) await otomatikBaslatmaYardimi(context, yol: yol);
  }

  static Future<String> _uretici() async {
    try {
      return (await DeviceInfoPlugin().androidInfo).manufacturer.toLowerCase().trim();
    } catch (_) {
      return '';
    }
  }

  /// Ayarlar'dan da açılabilir: üretici yolu yoksa genel açıklama.
  static Future<void> otomatikBaslatmaYardimiAc(BuildContext context) async {
    final yol = _oemYollari[await _uretici()] ?? 'Ayarlar › Uygulamalar › BogaMail › Pil: "Kısıtlama yok"';
    if (context.mounted) await otomatikBaslatmaYardimi(context, yol: yol);
  }

  /// Pil kısıtlaması açıklaması. Dönüş: kullanıcı "Muaf tut" dedi mi.
  static Future<bool> pilMuafiyetiSor(BuildContext context) async {
    final v = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Simge.pil),
        title: const Text('Arka planda bağlı kalın'),
        content: const Text(
          'Android\'in pil tasarrufu uygulamayı uyutabilir ve yeni e-posta bildirimleri gecikebilir. BogaMail\'i pil kısıtlamasından muaf tutun.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Şimdi değil')),
          FilledButton(key: const ValueKey('pil-muaf-tut'), onPressed: () => Navigator.pop(c, true), child: const Text('Muaf tut')),
        ],
      ),
    );
    return v == true;
  }

  /// Üreticiye özel otomatik başlatma yardımı.
  static Future<void> otomatikBaslatmaYardimi(BuildContext context, {required String yol}) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Telefonunuz uygulamaları kapatabilir', style: gosterim(18)),
            const SizedBox(height: 10),
            Text(
              'Bu telefonun üreticisi arka plandaki uygulamaları ayrıca durdurur. Yeni e-posta bildirimlerini kaçırmamak için şunu açın:',
              style: TextStyle(fontSize: 14, color: c.r.soluk),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.r.ic, borderRadius: BorderRadius.circular(10)),
              child: Text(yol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                unawaited(AppSettings.openAppSettings());
              },
              child: const Text('Uygulama ayarlarını aç'),
            ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam')),
          ],
        ),
      ),
    ),
  );

  /// Sistem bildirim ayarlarını açar.
  static Future<void> ayarlariAc() async {
    if (android()) {
      // Android: önce izin yeniden istenir (kalıcı reddedilmişse sistem göstermez; yol tarif edilir).
      final ok = await Bildirim.izinIste();
      bildir(izinVar: ok);
      if (!ok) {
        try {
          await AppSettings.openAppSettings(type: AppSettingsType.notification);
        } catch (_) {
          bildir_('Ayarlar › Uygulamalar › BogaMail › Bildirimler yolundan açın.');
        }
      }
      return;
    }
    final mac = !kIsWeb && Platform.isMacOS;
    final u = Uri.parse(mac ? 'x-apple.systempreferences:com.apple.preference.notifications' : 'app-settings:');
    final ok = await launchUrl(u, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok) bildir_(mac ? 'Sistem Ayarları › Bildirimler › BogaMail yolundan açın.' : 'Ayarlar › BogaMail › Bildirimler yolundan açın.');
  }

  static void bildir_(String yol) => bildirGoster('Bildirim ayarları açılamadı', mesaj: yol);
}

/// boga_ortak `bildir` (adı [BildirimIzni.bildir] ile çakışmasın).
void bildirGoster(String baslik, {String? mesaj}) => bildir(baslik, mesaj: mesaj, tur: MesajTur.uyari);

/// İzin istemeden önceki açıklama.
class BildirimTanitimi extends StatelessWidget {
  const BildirimTanitimi({super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    Widget madde(IconData i, String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(i, size: 20, color: r.vurgu),
          const SizedBox(width: 12),
          Expanded(
            child: Text(t, style: TextStyle(fontSize: 14, color: r.metin)),
          ),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Simge.bildirim, size: 36, color: r.vurgu),
            const SizedBox(height: 12),
            Text('Yeni postadan anında haberdar olun', textAlign: TextAlign.center, style: gosterim(19)),
            const SizedBox(height: 12),
            madde(Simge.posta, 'Yeni e-posta ve sohbet iletileri geldiğinde bildirim alırsınız.'),
            madde(Simge.kalkan, 'Bildirimde yalnız gönderen ve konu görünür; içerik cihazınızda kalır.'),
            madde(Simge.ayarlarInce, 'İstediğiniz zaman Ayarlar › Bildirimler\'den kapatabilirsiniz.'),
            const SizedBox(height: 16),
            FilledButton(key: const ValueKey('bildirim-izin-ver'), onPressed: () => Navigator.pop(context, true), child: const Text('Bildirimlere izin ver')),
            const SizedBox(height: 4),
            TextButton(key: const ValueKey('bildirim-simdi-degil'), onPressed: () => Navigator.pop(context, false), child: const Text('Şimdi değil')),
          ],
        ),
      ),
    );
  }
}

/// İzin kapalıyken uyarı bandı (kenar menüsü, Ayarlar). Kapatılabilir; izin açılınca kendiliğinden gider.
class BildirimIzniBandi extends StatelessWidget {
  const BildirimIzniBandi({super.key, this.kenar = const EdgeInsets.fromLTRB(12, 0, 12, 8)});
  final EdgeInsets kenar;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([BildirimIzni.kapali, BildirimIzni.gizlendi, BildirimIzni.pilKisitli]),
      builder: (context, _) {
        final izinYok = BildirimIzni.kapali.value == true;
        final pil = !izinYok && BildirimIzni.pilKisitli.value;
        if ((!izinYok && !pil) || BildirimIzni.gizlendi.value) return const SizedBox.shrink();
        final r = context.r;
        return Container(
          key: const ValueKey('bildirim-izni-bandi'),
          margin: kenar,
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
          decoration: BoxDecoration(color: Marka.kehribar.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Simge.bildirimKapali, size: 18, color: Marka.kehribar),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pil ? 'Pil kısıtlaması açık: arka planda bildirimler gecikebilir.' : 'Bildirimler kapalı. Yeni postayı kaçırmamak için izin verin.',
                      style: TextStyle(fontSize: 12.5, color: r.metin, height: 1.3),
                    ),
                  ),
                  InkResponse(
                    key: const ValueKey('bildirim-bandi-kapat'),
                    radius: 16,
                    onTap: () => BildirimIzni.gizlendi.value = true,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Simge.kapat, size: 16, color: r.soluk),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('bildirim-ayarlari-ac'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 18)),
                  onPressed: pil
                      ? () async {
                          await Arkaplan.platform.pilMuafiyetiIste();
                          BildirimIzni.pilKisitli.value = !await Arkaplan.platform.pilMuaf();
                        }
                      : BildirimIzni.ayarlariAc,
                  child: Text(pil ? 'Muaf tut' : 'Ayarları aç'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
