// Ayarlar → Görünüm: tema (cihazda uygulanır, webmail ile aynı olsun diye sunucuya da yazılır) ve uzak görseller.
// Web'de yoğunluk/okuma bölmesi/yazı boyutu ayarı yoktur; burada da eklenmedi.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/ayar_servisi.dart';
import '../../veri/tercihler.dart';
import 'ayar_ortak.dart';

class GorunumAyari extends StatelessWidget {
  const GorunumAyari({super.key});

  static String _ad(ThemeMode m) => switch (m) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  /// Temayı cihazda uygular ve sunucudaki tercihi de günceller (webmail aynı temayı kullanır). Sunucuya
  /// yazılamazsa cihazdaki seçim yine geçerlidir.
  static Future<void> temaSec(ThemeMode m) async {
    await Tercihler.temaAyarla(m);
    try {
      await Ayar.kaydet({'theme': _ad(m)});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => AyarListesi(
    children: [
      AyarKarti(
        ikon: Icons.palette_outlined,
        baslik: 'Tema',
        aciklama: '"Sistem" seçilirse cihazınızın açık/koyu ayarına uyulur. Seçim webmail\'e de uygulanır.',
        child: Align(
          alignment: Alignment.centerLeft,
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: temaKipi,
            builder: (_, k, _) => SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto_outlined)),
                ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {k},
              onSelectionChanged: (s) => temaSec(s.first),
            ),
          ),
        ),
      ),
      AyarKarti(
        ikon: Icons.image_outlined,
        baslik: 'Uzak görseller',
        aciklama: 'İletilerdeki internetten yüklenen görseller.',
        child: ValueListenableBuilder<bool>(
          valueListenable: Tercihler.uzakGorseller,
          builder: (_, v, _) => SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: v,
            onChanged: Tercihler.uzakGorselAyarla,
            title: const Text('Uzak görselleri otomatik göster'),
            subtitle: const Text(
              'Görseller sunucu üzerinden alınır; gönderen IP adresinizi görmez. Gereksiz ve uyarılı iletilerde yine sorulur. Bu tercih bu cihazda saklanır.',
            ),
          ),
        ),
      ),
    ],
  );
}
