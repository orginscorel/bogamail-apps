import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/modeller.dart';
import 'guvenlik.dart';
import 'otomatik_yanit.dart';
import 'posta_yonetimi.dart';
import 'profil.dart';
import 'suzgecler.dart';

/// Ayarlar'daki "Posta yönetimi", "Güvenlik" ve "Profil" bölümleri: her satır ilgili sayfayı açar.
class AraclarBolumleri extends StatelessWidget {
  const AraclarBolumleri({super.key, required this.ayarlar, this.bolumler = const {'posta', 'guvenlik', 'profil'}});
  final PostaAyarlari ayarlar;

  /// Gösterilecek bölümler: posta, guvenlik, profil (masaüstü Ayarlar'da her kategori kendi bölümünü gösterir).
  final Set<String> bolumler;

  @override
  Widget build(BuildContext context) {
    Widget oge(IconData i, String baslik, String alt, Widget Function() sayfa, {Color? renk}) => ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: (renk ?? context.r.vurgu).withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
        child: Icon(i, size: 21, color: renk ?? context.r.vurgu),
      ),
      title: Text(baslik, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(alt, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(Simge.ileri, color: context.r.silik),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => sayfa())),
    );
    Widget grup(List<Widget> l) => Kutu(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < l.length; i++) ...[if (i > 0) const Divider(indent: 68), l[i]],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bolumler.contains('posta')) ...[
          const Baslik('Posta yönetimi'),
          grup([
            oge(Simge.kisiler, 'Kişiler', 'Adres defteri, favoriler', KisilerEkrani.new),
            oge(Simge.suzgec, 'Süzgeçler (kurallar)', 'Gelen iletileri otomatik taşı, etiketle, işaretle', SuzgeclerEkrani.new),
            oge(Simge.planliGonder, 'Planlanan gönderimler', 'Zamanlanmış iletileri gör, ertele, iptal et', PlanlananlarEkrani.new),
            oge(Simge.kalkan, 'Güvenilir ve engelli gönderenler', 'Engelle veya her zaman Gelen Kutusu\'na al', GondericiListeleriEkrani.new),
            if (ayarlar.ozellik('autoresponder'))
              oge(Simge.otomatik, 'Otomatik yanıt kuralları', 'Mesai dışı, belirli günler, iç/dış gönderen', OtomatikYanitKurallariEkrani.new),
            if (ayarlar.ozellik('forwarding')) oge(Simge.yonlendir, 'Yönlendirme', 'Gelen postaları başka adrese ilet', YonlendirmeEkrani.new),
            oge(Simge.kargo, 'Gönderim durumu', 'İletileriniz teslim edildi mi?', GonderimDurumuEkrani.new),
            oge(Simge.gereksiz, 'Karantina', 'Güvenlik taramasında tutulan iletiler', KarantinaEkrani.new, renk: Marka.kehribar),
            if (ayarlar.ozellik('backup')) oge(Simge.yedek, 'Yedekler', 'Silinen iletileri yedekten geri yükle', YedeklerEkrani.new),
          ]),
        ],
        if (bolumler.contains('guvenlik')) ...[
          const Baslik('Güvenlik'),
          grup([
            oge(Simge.sifre, 'Şifre değiştir', 'Posta kutusu şifreniz', SifreEkrani.new),
            oge(Simge.guvenli, 'İki adımlı doğrulama', 'Girişte telefon kodu iste', IkiAdimliEkrani.new, renk: Marka.zumrut),
            oge(Simge.anahtar, 'Uygulama şifreleri', 'Outlook, Apple Mail, Thunderbird için', UygulamaSifreleriEkrani.new),
            oge(Simge.cihazlar, 'Kayıtlı cihazlar', 'Şifresiz girişe kayıtlı tarayıcı ve uygulamalar', KayitliCihazlarEkrani.new),
            oge(Simge.telefon, 'Bağlı cihazlar', 'ActiveSync telefonlar: engelle, uzaktan temizle', CihazlarEkrani.new),
            oge(Simge.yonetim, 'Yönetici erişim kaydı', 'Kutunuza kim, ne zaman erişti', YoneticiErisimiEkrani.new),
          ]),
        ],
        if (bolumler.contains('profil')) ...[
          const Baslik('Profil'),
          grup([oge(Simge.kimlik, 'Profil resmi ve bilgileri', 'Unvan, telefon, sosyal bağlantılar (imzada kullanılır)', ImzaProfiliEkrani.new)]),
        ],
      ],
    );
  }
}
