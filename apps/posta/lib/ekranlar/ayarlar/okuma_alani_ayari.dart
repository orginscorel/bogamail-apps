// Ayarlar › Okuma alanı: Sağda / Altta / Kapalı (sunucu ayarı reading_pane; web postasıyla ortak). Yalnız geniş
// ekranda anlamlıdır; telefonda ileti her zaman tam ekran açılır.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/durum.dart';
import 'ayar_ortak.dart';

const okumaAlaniSecenekleri = {'right': 'Sağda', 'bottom': 'Altta', 'off': 'Kapalı'};

class OkumaAlaniAyari extends StatelessWidget {
  const OkumaAlaniAyari({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: PostaDurum.ben.okumaAlani,
    builder: (context, v, _) => ListView(
      padding: EdgeInsets.zero,
      children: [
        AyarAlani(
          etiket: 'Okuma alanı',
          ipucu:
              'Sağda: liste ile ileti yan yana. Altta: liste üstte, ileti altta. Kapalı: ileti açılınca tüm alanı kaplar; '
              'geri okuyla ya da Esc ile listeye dönersiniz. Web postasıyla ortak ayardır.',
          child: SecimCipleri<String>(
            key: const ValueKey('okuma-alani'),
            secenekler: okumaAlaniSecenekleri,
            deger: v,
            degisti: (x) => islem(() => PostaDurum.ben.okumaAlaniAyarla(x), tamam: 'Okuma alanı: ${okumaAlaniSecenekleri[x]}'),
          ),
        ),
      ],
    ),
  );
}
