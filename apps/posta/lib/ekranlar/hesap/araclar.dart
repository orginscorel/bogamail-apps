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
  const AraclarBolumleri({super.key, required this.ayarlar});
  final PostaAyarlari ayarlar;

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
      trailing: Icon(Icons.chevron_right_rounded, color: context.r.silik),
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
        const Baslik('Posta yönetimi'),
        grup([
          oge(Icons.contacts_outlined, 'Kişiler', 'Adres defteri, favoriler', KisilerEkrani.new),
          oge(Icons.filter_alt_outlined, 'Süzgeçler (kurallar)', 'Gelen iletileri otomatik taşı, etiketle, işaretle', SuzgeclerEkrani.new),
          oge(Icons.label_outline_rounded, 'Etiketler', 'Ad, renk, silme', EtiketlerEkrani.new),
          oge(Icons.schedule_send_outlined, 'Planlanan gönderimler', 'Zamanlanmış iletileri gör, ertele, iptal et', PlanlananlarEkrani.new),
          oge(Icons.shield_outlined, 'Güvenilir ve engelli gönderenler', 'Engelle veya her zaman Gelen Kutusu\'na al', GondericiListeleriEkrani.new),
          if (ayarlar.ozellik('autoresponder'))
            oge(Icons.auto_mode_rounded, 'Otomatik yanıt kuralları', 'Mesai dışı, belirli günler, iç/dış gönderen', OtomatikYanitKurallariEkrani.new),
          if (ayarlar.ozellik('forwarding')) oge(Icons.forward_to_inbox_outlined, 'Yönlendirme', 'Gelen postaları başka adrese ilet', YonlendirmeEkrani.new),
          oge(Icons.local_shipping_outlined, 'Gönderim durumu', 'İletileriniz teslim edildi mi?', GonderimDurumuEkrani.new),
          oge(Icons.gpp_maybe_outlined, 'Karantina', 'Güvenlik taramasında tutulan iletiler', KarantinaEkrani.new, renk: Marka.kehribar),
          if (ayarlar.ozellik('backup')) oge(Icons.backup_outlined, 'Yedekler', 'Silinen iletileri yedekten geri yükle', YedeklerEkrani.new),
        ]),
        const Baslik('Güvenlik'),
        grup([
          oge(Icons.password_rounded, 'Şifre değiştir', 'Posta kutusu şifreniz', SifreEkrani.new),
          oge(Icons.verified_user_outlined, 'İki adımlı doğrulama', 'Girişte telefon kodu iste', IkiAdimliEkrani.new, renk: Marka.zumrut),
          oge(Icons.key_outlined, 'Uygulama şifreleri', 'Outlook, Apple Mail, Thunderbird için', UygulamaSifreleriEkrani.new),
          oge(Icons.smartphone_outlined, 'Bağlı cihazlar', 'ActiveSync telefonlar: engelle, uzaktan temizle', CihazlarEkrani.new),
          oge(Icons.admin_panel_settings_outlined, 'Yönetici erişim kaydı', 'Kutunuza kim, ne zaman erişti', YoneticiErisimiEkrani.new),
        ]),
        const Baslik('Profil'),
        grup([oge(Icons.badge_outlined, 'Profil resmi ve bilgileri', 'Unvan, telefon, sosyal bağlantılar (imzada kullanılır)', ImzaProfiliEkrani.new)]),
      ],
    );
  }
}
