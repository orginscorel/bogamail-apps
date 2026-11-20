import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Kamera/fotoğraf izni reddedildi: neden gerektiğini açıklar ve ayarlara yönlendirir.
Future<void> izinReddedildi(BuildContext context, {required bool kamera}) async {
  final ios = !kIsWeb && Platform.isIOS;
  final ne = kamera ? 'kameraya' : 'fotoğraflarınıza';
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(kamera ? Icons.no_photography_outlined : Icons.hide_image_outlined),
      title: Text(kamera ? 'Kamera izni gerekli' : 'Fotoğraf izni gerekli'),
      content: Text(
        'BogaMail\'in $ne erişim izni kapalı. İletiye ${kamera ? 'çektiğiniz fotoğraf ve videoları' : 'galerinizden fotoğraf ve video'} '
        'ekleyebilmek için izni ayarlardan açın.\n\n'
        '${ios ? 'Ayarlar › BogaMail › ${kamera ? 'Kamera (video için Mikrofon da)' : 'Fotoğraflar'}' : 'Ayarlar › Uygulamalar › BogaMail › İzinler'}',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(ios ? 'Vazgeç' : 'Tamam')),
        // iOS uygulamanın ayar sayfasını doğrudan açabilir; Android'de yol tarif edilir.
        if (ios)
          FilledButton(
            onPressed: () async {
              Navigator.pop(c);
              final ok = await launchUrl(Uri.parse('app-settings:'), mode: LaunchMode.externalApplication).catchError((_) => false);
              if (!ok) bildir('Ayarlar açılamadı', mesaj: 'Telefonunuzun Ayarlar uygulamasından BogaMail izinlerini açın.', tur: MesajTur.uyari);
            },
            child: const Text('Ayarları aç'),
          ),
      ],
    ),
  );
}
