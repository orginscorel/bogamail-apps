import 'package:flutter/material.dart';

import '../../veri/modeller.dart';

/// Ayarlar'da bir kategori (masaüstünde sol listede bir satır + sağ bölme; telefonda listede bir satır → sayfa).
///
/// [olustur] içeriği döndürür. [tamSayfa] false ise içerik kendi kaydırmasını yapan bir gövdedir (ör. ListView);
/// kabuk onu başlıklı bir sayfaya (masaüstünde okunabilir genişlikte, en çok 860 px) koyar. true ise kendi
/// Scaffold/AppBar'ı olan tam sayfadır ve olduğu gibi gösterilir. Alt sayfalar Navigator.of(context).push ile açılır:
/// masaüstünde sağ bölmenin kendi gezgini olduğundan bölmenin içinde kalırlar.
@immutable
class AyarBolumu {
  const AyarBolumu({
    required this.id,
    required this.ikon,
    required this.baslik,
    required this.olustur,
    this.sira = 500,
    this.aciklama = '',
    this.tamSayfa = false,
    this.gorunur,
  });

  /// Benzersiz kimlik. Yerleşik bir kategoriyle aynı kimlik verilirse onun yerine geçer.
  final String id;
  final IconData ikon;
  final String baslik;

  /// Telefon listesinde alt satır.
  final String aciklama;

  /// Sıralama: küçük önce. Yerleşikler: hesaplar 10, genel 20, gorunum 30, imza 40, profil 50, bildirimler 60,
  /// guvenlik 70, suzgecler 80, otomatik 90, kisiler 100, yonlendirme 110, posta 120, uygulama 900.
  final int sira;
  final bool tamSayfa;

  /// Paket özelliğine göre gizlemek için (ör. (a) => a.ozellik('forwarding')).
  final bool Function(PostaAyarlari ayarlar)? gorunur;
  final WidgetBuilder olustur;
}
