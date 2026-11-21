// Ayarlar'a eklenen bölümler. Yeni bir ayar sayfası: lib/ekranlar/ayarlar/<ad>.dart dosyasına yazın ve buraya bir
// AyarBolumu ekleyin; masaüstünde sol listede, telefonda Ayarlar listesinde kendiliğinden görünür. Aynı id ile
// yerleşik bir kategorinin (bkz. AyarBolumu.sira belgesi) yerine geçebilirsiniz.

import 'package:boga_ortak/boga_ortak.dart';

import '../hesap/posta_yonetimi.dart';
import 'arkaplan_ayari.dart';
import 'bildirimler.dart';
import 'bolum.dart';
import 'genel.dart';
import 'gorunum.dart';
import 'klasorler.dart';
import 'kurulum.dart';
import 'okuma_alani_ayari.dart';
import 'otomatik.dart';
import 'tasima.dart';

final ekAyarBolumleri = <AyarBolumu>[
  AyarBolumu(
    id: 'kurulum',
    ikon: Simge.kurulum,
    baslik: 'Bağlantı ve kurulum',
    aciklama: 'Paket özellikleri, IMAP/SMTP/POP3, Apple profili, CalDAV/CardDAV',
    sira: 15,
    olustur: (_) => const KurulumAyari(),
  ),
  AyarBolumu(
    id: 'genel',
    ikon: Simge.ayarlarInce,
    baslik: 'Genel',
    aciklama: 'Görünen ad, sayfa başına ileti, yazma biçimi, gönderimi geri al',
    sira: 20,
    olustur: (_) => const GenelAyari(),
  ),
  AyarBolumu(id: 'gorunum', ikon: Simge.palet, baslik: 'Görünüm', aciklama: 'Tema, uzak görseller', sira: 30, olustur: (_) => const GorunumAyari()),
  AyarBolumu(
    id: 'okuma-alani',
    ikon: Simge.katmanlar,
    baslik: 'Okuma alanı',
    aciklama: 'Sağda / Altta / Kapalı (web ile ortak)',
    sira: 31,
    olustur: (_) => const OkumaAlaniAyari(),
  ),
  AyarBolumu(
    id: 'bildirimler',
    ikon: Simge.bildirim,
    baslik: 'Bildirimler',
    aciklama: 'Bu cihaz, ses, eşitleme, anlık bağlantı, sohbet gizliliği',
    sira: 60,
    olustur: (_) => const BildirimlerAyari(),
  ),
  AyarBolumu(
    id: 'arkaplan',
    ikon: Simge.pil,
    baslik: 'Arka planda çalışma',
    aciklama: 'Sürekli bağlı kal, pil kısıtlaması, oturum açılınca başlat',
    sira: 62,
    grup: AyarGrubu.uygulama,
    gorunur: (_) => ArkaplanAyari.gerekli,
    olustur: (_) => const ArkaplanAyari(),
  ),
  AyarBolumu(
    id: 'otomatik',
    ikon: Simge.tatil,
    baslik: 'Otomatik yanıt',
    aciklama: 'İzin/tatil yanıtı ve kurallar',
    sira: 90,
    olustur: (_) => const OtomatikYanitAyari(),
  ),
  AyarBolumu(
    id: 'etiketler',
    ikon: Simge.etiket,
    baslik: 'Etiketler',
    aciklama: 'Oluştur, yeniden adlandır, renk, sil',
    sira: 114,
    tamSayfa: true,
    olustur: (_) => const EtiketlerEkrani(),
  ),
  AyarBolumu(
    id: 'klasorler',
    ikon: Simge.klasor,
    baslik: 'Klasörler',
    aciklama: 'Oluştur, yeniden adlandır, sil; Çöp/Gereksiz\'i boşalt',
    sira: 115,
    tamSayfa: true,
    olustur: (_) => const KlasorlerEkrani(),
  ),
  AyarBolumu(
    id: 'tasima',
    ikon: Simge.aktar,
    baslik: 'Taşıma (IMAP)',
    aciklama: 'Eski sağlayıcıdaki postaları bu kutuya aktarın',
    sira: 125,
    olustur: (_) => const TasimaAyari(),
  ),
];
