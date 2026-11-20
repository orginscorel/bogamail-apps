// Ayarlar'a eklenen bölümler. Yeni bir ayar sayfası: lib/ekranlar/ayarlar/<ad>.dart dosyasına yazın ve buraya bir
// AyarBolumu ekleyin; masaüstünde sol listede, telefonda Ayarlar listesinde kendiliğinden görünür. Aynı id ile
// yerleşik bir kategorinin (bkz. AyarBolumu.sira belgesi) yerine geçebilirsiniz.

import 'package:flutter/material.dart';

import '../hesap/posta_yonetimi.dart';
import 'bildirimler.dart';
import 'bolum.dart';
import 'genel.dart';
import 'gorunum.dart';
import 'klasorler.dart';
import 'kurulum.dart';
import 'otomatik.dart';
import 'tasima.dart';

final ekAyarBolumleri = <AyarBolumu>[
  AyarBolumu(
    id: 'kurulum',
    ikon: Icons.settings_ethernet_rounded,
    baslik: 'Bağlantı ve kurulum',
    aciklama: 'Paket özellikleri, IMAP/SMTP/POP3, Apple profili, CalDAV/CardDAV',
    sira: 15,
    olustur: (_) => const KurulumAyari(),
  ),
  AyarBolumu(
    id: 'genel',
    ikon: Icons.tune_rounded,
    baslik: 'Genel',
    aciklama: 'Görünen ad, sayfa başına ileti, yazma biçimi, gönderimi geri al',
    sira: 20,
    olustur: (_) => const GenelAyari(),
  ),
  AyarBolumu(id: 'gorunum', ikon: Icons.palette_outlined, baslik: 'Görünüm', aciklama: 'Tema, uzak görseller', sira: 30, olustur: (_) => const GorunumAyari()),
  AyarBolumu(
    id: 'bildirimler',
    ikon: Icons.notifications_none_rounded,
    baslik: 'Bildirimler',
    aciklama: 'Bu cihaz, ses, eşitleme, anlık bağlantı, sohbet gizliliği',
    sira: 60,
    olustur: (_) => const BildirimlerAyari(),
  ),
  AyarBolumu(
    id: 'otomatik',
    ikon: Icons.beach_access_outlined,
    baslik: 'Otomatik yanıt',
    aciklama: 'İzin/tatil yanıtı ve kurallar',
    sira: 90,
    olustur: (_) => const OtomatikYanitAyari(),
  ),
  AyarBolumu(
    id: 'etiketler',
    ikon: Icons.label_outline_rounded,
    baslik: 'Etiketler',
    aciklama: 'Oluştur, yeniden adlandır, renk, sil',
    sira: 114,
    tamSayfa: true,
    olustur: (_) => const EtiketlerEkrani(),
  ),
  AyarBolumu(
    id: 'klasorler',
    ikon: Icons.folder_outlined,
    baslik: 'Klasörler',
    aciklama: 'Oluştur, yeniden adlandır, sil; Çöp/Gereksiz\'i boşalt',
    sira: 115,
    tamSayfa: true,
    olustur: (_) => const KlasorlerEkrani(),
  ),
  AyarBolumu(
    id: 'tasima',
    ikon: Icons.move_down_rounded,
    baslik: 'Taşıma (IMAP)',
    aciklama: 'Eski sağlayıcıdaki postaları bu kutuya aktarın',
    sira: 125,
    olustur: (_) => const TasimaAyari(),
  ),
];
