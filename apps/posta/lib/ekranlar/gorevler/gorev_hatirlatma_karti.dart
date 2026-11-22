// Görev hatırlatmaları kartı (Ayarlar › Bildirimler ve Görevler › Hatırlatıcılar):
// - iPhone/iPad/Mac: "Apple Hatırlatıcılar ile eşitle" — kurulum profili CalDAV hesabını ekler, Hatırlatıcılar
//   uygulamasında "Görevler" listesi iki yönlü eşitlenir; sunucu son tarihli görevlere alarm koyar.
// - Android / Windows: "Görev hatırlatmaları" anahtarı (cihazın bildirim zamanlayıcısı, gorev_hatirlatma.dart);
//   Android 12+'da tam zamanlı alarm izni yoksa uyarı.

import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../oturum.dart';
import '../../veri/ayar_servisi.dart';
import '../../veri/bildirim.dart';
import '../../veri/gorev_hatirlatma.dart';
import '../ayarlar/ayar_ortak.dart';

enum HatirlatmaPlatformu { apple, yerel, yok }

/// Apple kurulum profilini indirip açar (Ayarlar › Posta programına kur ile aynı akış).
Future<void> appleProfiliniAc() async {
  try {
    final v = await Ayar.appleProfili();
    final d = await getTemporaryDirectory();
    final f = File('${d.path}/BogaMail.mobileconfig');
    await f.writeAsBytes(v, flush: true);
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/x-apple-aspen-config')]));
    } else {
      await OpenFilex.open(f.path);
    }
  } catch (e) {
    bildir('Kurulum profili alınamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
  }
}

class GorevHatirlatmaKarti extends StatefulWidget {
  const GorevHatirlatmaKarti({super.key, this.ozellikler, this.imap = true, this.sunucu = ''});

  /// Paket özellikleri (bilinmiyorsa null: gösterilir).
  final Map<String, bool>? ozellikler;

  /// Posta programı erişimi (IMAP) açık mı; kurulum profili onu gerektirir. Bilinmiyorsa true.
  final bool imap;

  /// Sunucu adı (elle CalDAV kurulumu notu için).
  final String sunucu;

  @visibleForTesting
  static HatirlatmaPlatformu? platformZorla;

  /// Testlerde profil indirme.
  @visibleForTesting
  static Future<void> Function() profilAc = appleProfiliniAc;

  static HatirlatmaPlatformu get platform {
    final z = platformZorla;
    if (z != null) return z;
    if (kIsWeb) return HatirlatmaPlatformu.yok;
    if (Platform.isIOS || Platform.isMacOS) return HatirlatmaPlatformu.apple;
    if (Platform.isAndroid || Platform.isWindows) return HatirlatmaPlatformu.yerel;
    return HatirlatmaPlatformu.yok;
  }

  /// Bu hesapta ve platformda gösterilir mi (görevler paketi; Apple'da CalDAV da gerekir).
  static bool gosterilir(Map<String, bool>? a) {
    if (a != null && a.isEmpty) a = null; // özellikler henüz bilinmiyor
    if (a != null && !(a['tasks'] ?? false)) return false;
    return switch (platform) {
      HatirlatmaPlatformu.apple => a == null || (a['caldav'] ?? false),
      HatirlatmaPlatformu.yerel => true,
      HatirlatmaPlatformu.yok => false,
    };
  }

  @override
  State<GorevHatirlatmaKarti> createState() => _GorevHatirlatmaKartiState();
}

class _GorevHatirlatmaKartiState extends State<GorevHatirlatmaKarti> {
  bool? _acik;
  bool _tamZamanli = true;

  @override
  void initState() {
    super.initState();
    if (GorevHatirlatmaKarti.platform == HatirlatmaPlatformu.yerel) _durum();
  }

  Future<void> _durum() async {
    final a = await GorevHatirlatma.acik();
    final t = await Bildirim.tamZamanliAlarm();
    if (mounted) {
      setState(() {
        _acik = a;
        _tamZamanli = t;
      });
    }
  }

  Future<void> _degistir(bool v) async {
    setState(() => _acik = v);
    await GorevHatirlatma.ayarla(v, kutu: Uyg.kutuId);
    bildir(v ? 'Görev hatırlatmaları açıldı' : 'Görev hatırlatmaları kapatıldı', tur: MesajTur.basari);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (GorevHatirlatmaKarti.platform == HatirlatmaPlatformu.apple) {
      final imap = widget.imap;
      final sunucu = widget.sunucu;
      return AyarKarti(
        key: const ValueKey('gorev-hatirlatma-karti'),
        ikon: Simge.hatirlatma,
        baslik: 'Apple Hatırlatıcılar ile eşitle',
        aciklama: 'Görevleriniz iPhone, iPad ve Mac\'teki Hatırlatıcılar uygulamasında "Görevler" listesi olarak görünür.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kurulum profili hesabınızı (posta, takvim, kişiler ve hatırlatıcılar) bu cihaza ekler. Eşitleme iki yönlüdür: '
              'Hatırlatıcılar\'da tamamladığınız ya da eklediğiniz görev BogaMail\'e de yansır. Son tarihi olan görevler için '
              'Hatırlatıcılar son tarih saatinde uyarır. Şifreniz dosyada yer almaz, kurulum sırasında sorulur.',
              style: TextStyle(color: r.soluk, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 10),
            if (imap)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('apple-hatirlaticilar'),
                  onPressed: () => GorevHatirlatmaKarti.profilAc(),
                  icon: const Icon(Simge.indir, size: 18),
                  label: const Text('Kurulum profilini indir'),
                ),
              )
            else
              AyarNotu(
                'Kurulum profili için posta programı erişimi gerekir. Elle ekleyin: Ayarlar › Hatırlatıcılar (Mac\'te '
                'İnternet Hesapları) › Hesap ekle › Diğer › CalDAV hesabı; sunucu ${sunucu.isEmpty ? 'posta sunucunuz' : sunucu}, '
                'kullanıcı adı ${Uyg.adres}, şifre webmail şifreniz.',
              ),
          ],
        ),
      );
    }
    final acik = _acik;
    return AyarKarti(
      key: const ValueKey('gorev-hatirlatma-karti'),
      ikon: Simge.hatirlatma,
      baslik: 'Görev hatırlatmaları',
      aciklama: 'Size atanan (ya da oluşturup kimseye atamadığınız) görevlerin son tarihinden 15 dakika önce bu cihazda bildirim.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            key: const ValueKey('gorev-hatirlatma'),
            contentPadding: EdgeInsets.zero,
            value: acik ?? true,
            onChanged: acik == null ? null : _degistir,
            title: const Text('Görev hatırlatmaları'),
            subtitle: const Text(
              'Uygulama kapalıyken de cihazın bildirim zamanlayıcısıyla gelir. Görevi takvime eklemek için görevin ayrıntısındaki "Takvime ekle"yi kullanın.',
            ),
          ),
          if (acik == true && !_tamZamanli)
            AyarNotu(
              'Tam zamanlı alarm izni kapalı: Android hatırlatmayı birkaç dakika geciktirebilir.',
              ton: NotTonu.uyari,
              alt: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () async {
                    await Bildirim.tamZamanliAlarmIste();
                    await _durum();
                  },
                  child: const Text('Alarmlar ve hatırlatıcılar iznini ver'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
