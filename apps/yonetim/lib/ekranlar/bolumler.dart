import 'package:flutter/material.dart';

import '../oturum.dart';
import 'alan_adlari.dart';
import 'alarmlar.dart';
import 'ayarlar.dart';
import 'denetim_kayitlari.dart';
import 'karantina.dart';
import 'kuyruk.dart';
import 'musteriler.dart';
import 'ozet.dart';
import 'posta_kutulari.dart';
import 'sunucu_erisimi.dart';

/// Uygulamanın bölümleri. Görünürlük web panelindeki menüyle (components/admin/nav.ts) ve API yetkileriyle aynıdır.
enum Bolum {
  ozet('Özet', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  alanlar('Alan Adları', Icons.language_outlined, Icons.language_rounded),
  kutular('Posta Kutuları', Icons.inbox_outlined, Icons.inbox_rounded),
  kuyruk('Kuyruk', Icons.format_list_numbered_rounded, Icons.format_list_numbered_rounded),
  karantina('Karantina', Icons.shield_outlined, Icons.shield_rounded),
  alarmlar('Alarmlar', Icons.notifications_outlined, Icons.notifications_rounded),
  sunucu('Sunucu Erişimi', Icons.key_outlined, Icons.key_rounded),
  musteriler('Müşteriler', Icons.apartment_outlined, Icons.apartment_rounded),
  denetim('Denetim Kayıtları', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  ayarlar('Ayarlar', Icons.settings_outlined, Icons.settings_rounded);

  const Bolum(this.baslik, this.ikon, this.secikIkon);
  final String baslik;
  final IconData ikon, secikIkon;

  /// Rol, yetki ve (müşteri için) paket türüne göre görünür mü.
  bool get gorunur => switch (this) {
    Bolum.kutular => !(Uyg.musteri && Uyg.paketTuru == 'gateway'),
    Bolum.kuyruk => Uyg.yetki('tracking.view'),
    Bolum.karantina => Uyg.yetki('quarantine.view'),
    Bolum.sunucu => Uyg.platformYoneticisi,
    Bolum.musteriler => Uyg.ortak,
    Bolum.denetim => Uyg.yetki('audit.view'),
    _ => true,
  };

  /// Telefon alt çubuğunda yer alabilecek bölümler (görünür olanlardan ilk dördü).
  static const anaBolumler = [Bolum.ozet, Bolum.alanlar, Bolum.kutular, Bolum.kuyruk, Bolum.alarmlar];

  static List<Bolum> get gorunenler => [
    for (final b in values)
      if (b.gorunur) b,
  ];

  Widget ekran() => switch (this) {
    Bolum.ozet => const OzetEkrani(),
    Bolum.alanlar => const AlanAdlariEkrani(),
    Bolum.kutular => const PostaKutulariEkrani(),
    Bolum.kuyruk => const KuyrukEkrani(),
    Bolum.karantina => const KarantinaEkrani(),
    Bolum.alarmlar => const AlarmlarEkrani(),
    Bolum.sunucu => const SunucuErisimiEkrani(),
    Bolum.musteriler => const MusterilerEkrani(),
    Bolum.denetim => const DenetimKayitlariEkrani(),
    Bolum.ayarlar => const AyarlarEkrani(),
  };
}

/// Ekranların kabuktan bölüm açma isteği (özet kartları, push bildirimleri).
final bolumIstegi = ValueNotifier<Bolum?>(null);

void bolumeGit(Bolum b) {
  bolumIstegi.value = null;
  bolumIstegi.value = b;
}
