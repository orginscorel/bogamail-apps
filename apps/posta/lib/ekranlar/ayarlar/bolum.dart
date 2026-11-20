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
    this.grup,
  });

  /// Benzersiz kimlik. Yerleşik bir kategoriyle aynı kimlik verilirse onun yerine geçer.
  final String id;
  final IconData ikon;
  final String baslik;

  /// Telefon listesinde alt satır.
  final String aciklama;

  /// Sıralama (grup içinde): küçük önce. Yerleşikler — Profil ve hesap: profil 5, guvenlik 70, cihazlar 72,
  /// hesaplar 74, depolama 76; Posta: genel 20, imza 40, suzgecler 80, otomatik 90, kisiler 100, yonlendirme 110,
  /// engelli 112, posta 120; Uygulama: gorunum 30, bildirimler 60, uygulama 900, hakkinda 950.
  final int sira;
  final bool tamSayfa;

  /// Paket özelliğine göre gizlemek için (ör. (a) => a.ozellik('forwarding')).
  final bool Function(PostaAyarlari ayarlar)? gorunur;
  final WidgetBuilder olustur;

  /// Listede hangi başlık altında: verilmezse kimliğe göre ([varsayilanGruplar]), bilinmeyenler Posta'ya.
  final AyarGrubu? grup;

  AyarGrubu get etkinGrup => grup ?? varsayilanGruplar[id] ?? AyarGrubu.posta;
}

/// Ayarlar listesinin başlıkları: profil/hesap, postaya özgü ayarlar, uygulama.
enum AyarGrubu {
  profil('Profil ve hesap'),
  posta('Posta'),
  uygulama('Uygulama');

  const AyarGrubu(this.baslik);
  final String baslik;
}

const varsayilanGruplar = <String, AyarGrubu>{
  'profil': AyarGrubu.profil,
  'guvenlik': AyarGrubu.profil,
  'cihazlar': AyarGrubu.profil,
  'hesaplar': AyarGrubu.profil,
  'depolama': AyarGrubu.profil,
  'gorunum': AyarGrubu.uygulama,
  'bildirimler': AyarGrubu.uygulama,
  'uygulama': AyarGrubu.uygulama,
  'hakkinda': AyarGrubu.uygulama,
};
