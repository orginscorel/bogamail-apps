import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import 'alan_adlari.dart';
import 'alarmlar.dart';
import 'ayarlar.dart';
import 'bastirma.dart';
import 'bayiler.dart';
import 'dahili.dart';
import 'denetim_kayitlari.dart';
import 'depolama.dart';
import 'dlp.dart';
import 'dmarc.dart';
import 'ekip_calismasi.dart';
import 'entegrasyonlar.dart';
import 'gateway.dart';
import 'greylist.dart';
import 'ip_yonetimi.dart';
import 'itibar.dart';
import 'itibar_merkezim.dart';
import 'izleme.dart';
import 'kampanya_izleme.dart';
import 'karantina.dart';
import 'kiraci.dart';
import 'kotuye_kullanim.dart';
import 'kurulum.dart';
import 'kuyruk.dart';
import 'marka.dart';
import 'mesaj_takibi.dart';
import 'mobil_cihazlar.dart';
import 'musteri_detay.dart' show musteriDetayKimlikle;
import 'musteriler.dart';
import 'oltalama.dart';
import 'ozet.dart';
import 'paketim.dart';
import 'paketler.dart';
import 'platform_ayarlari.dart';
import 'posta_kutulari.dart';
import 'saldiri_haritasi.dart';
import 'sandbox.dart';
import 'smtp_trafigi.dart';
import 'spam.dart';
import 'sunucu_erisimi.dart';
import 'sunucular.dart';
import 'takma_adlar.dart';
import 'tehdit.dart';
import 'teslim_teshisi.dart';
import 'teslimat_kontrol.dart';
import 'teslimat_sorunlari.dart';
import 'toplu_gonderim.dart';
import 'yedekleme.dart';
import 'yoneticiler.dart';

/// Menü grubu (web: components/admin/nav.ts navGroups).
enum BolumGrubu {
  genel('Genel', null),
  hizmet('Hizmet', 'Posta Hizmeti'),
  trafik('Posta Trafiği', null),
  guvenlik('Güvenlik', null),
  altyapi('Altyapı', 'Kullanım ve Uyarılar'),
  yonetim('Yönetim', null);

  const BolumGrubu(this._baslik, this._musteriBaslik);
  final String _baslik;
  final String? _musteriBaslik;
  String get baslik => Uyg.musteri && _musteriBaslik != null ? _musteriBaslik : _baslik;
}

const _ortaklar = {'super_admin', 'reseller_admin'};
const _platform = {'super_admin'};
const _posta = {'hosting', 'hybrid'};

/// Uygulamanın bölümleri. Görünürlük web panelindeki menüyle (components/admin/nav.ts navVisible) aynıdır:
/// rol, panel yetkisi (permissions) ve müşteri için paket türü/özellikleri.
enum Bolum {
  ozet('Özet', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, BolumGrubu.genel),
  paketim('Paketim', Icons.verified_outlined, Icons.verified_rounded, BolumGrubu.genel, roller: {'org_admin'}),
  itibarMerkezim('İtibar Merkezim', Icons.trending_up_rounded, Icons.trending_up_rounded, BolumGrubu.genel, roller: {'org_admin'}),

  musteriler('Müşteriler', Icons.apartment_outlined, Icons.apartment_rounded, BolumGrubu.hizmet, roller: _ortaklar),
  dahili('Yönetici Kurumları', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings_rounded, BolumGrubu.hizmet, roller: _platform),
  bayiler('Bayiler', Icons.handshake_outlined, Icons.handshake_rounded, BolumGrubu.hizmet, roller: _platform),
  paketler('Paketler', Icons.inventory_2_outlined, Icons.inventory_2_rounded, BolumGrubu.hizmet, roller: _ortaklar),
  alanlar('Alan Adları', Icons.language_outlined, Icons.language_rounded, BolumGrubu.hizmet),
  kutular('Posta Kutuları', Icons.inbox_outlined, Icons.inbox_rounded, BolumGrubu.hizmet, turler: _posta),
  takmaAdlar('Takma Adlar', Icons.alternate_email_rounded, Icons.alternate_email_rounded, BolumGrubu.hizmet, turler: _posta, ozellikler: {'aliases', 'forwarding', 'distribution_lists'}),
  cihazlar('Mobil Cihazlar', Icons.smartphone_outlined, Icons.smartphone_rounded, BolumGrubu.hizmet, turler: _posta, ozellikler: {'activesync'}),
  ekip('Ekip Çalışması', Icons.groups_outlined, Icons.groups_rounded, BolumGrubu.hizmet, roller: {'org_admin'}, turler: _posta),
  topluGonderim('Toplu Gönderim', Icons.campaign_outlined, Icons.campaign_rounded, BolumGrubu.hizmet, roller: {'org_admin'}, izin: 'campaigns.manage', turler: _posta, ozellikler: {'bulk_sending'}),
  marka('Marka', Icons.palette_outlined, Icons.palette_rounded, BolumGrubu.hizmet, ozellikler: {'branding'}),

  gateway('Mail Gateway', Icons.alt_route_rounded, Icons.alt_route_rounded, BolumGrubu.trafik, turler: {'gateway', 'hybrid'}, ozellikler: {'gateway'}),
  takip('Mesaj Takibi', Icons.manage_search_rounded, Icons.manage_search_rounded, BolumGrubu.trafik, izin: 'tracking.view'),
  kuyruk('Kuyruk', Icons.format_list_numbered_rounded, Icons.format_list_numbered_rounded, BolumGrubu.trafik, izin: 'tracking.view'),
  teslimatKontrol('Teslimat Kontrol', Icons.bolt_outlined, Icons.bolt_rounded, BolumGrubu.trafik, roller: _platform),
  bastirma('Bastırma Listesi', Icons.block_rounded, Icons.block_rounded, BolumGrubu.trafik, izin: 'tracking.view'),
  teslimatSorunlari('Teslimat Sorunları', Icons.report_problem_outlined, Icons.report_problem_rounded, BolumGrubu.trafik),
  teslimTeshisi('Teslim Teşhisi', Icons.medical_services_outlined, Icons.medical_services_rounded, BolumGrubu.trafik, izin: 'tracking.view'),
  kampanyaIzleme('Toplu Gönderim İzleme', Icons.cell_tower_rounded, Icons.cell_tower_rounded, BolumGrubu.trafik, roller: _ortaklar),
  sandbox('Test Sandbox', Icons.science_outlined, Icons.science_rounded, BolumGrubu.trafik, ozellikler: {'email_sandbox'}),
  dmarc('DMARC Merkezi', Icons.mark_email_read_outlined, Icons.mark_email_read_rounded, BolumGrubu.trafik, ozellikler: {'dmarc_center'}),
  smtpTrafigi('SMTP Trafiği', Icons.show_chart_rounded, Icons.show_chart_rounded, BolumGrubu.trafik, roller: _platform),

  spam('Spam Güvenliği', Icons.gpp_maybe_outlined, Icons.gpp_maybe_rounded, BolumGrubu.guvenlik),
  karantina('Karantina', Icons.shield_outlined, Icons.shield_rounded, BolumGrubu.guvenlik, izin: 'quarantine.view'),
  tehdit('Tehdit Koruması', Icons.security_outlined, Icons.security_rounded, BolumGrubu.guvenlik),
  greylist('Greylisting', Icons.hourglass_empty_rounded, Icons.hourglass_bottom_rounded, BolumGrubu.guvenlik, roller: _ortaklar),
  saldiriHaritasi('Saldırı Haritası', Icons.map_outlined, Icons.map_rounded, BolumGrubu.guvenlik, roller: _ortaklar),
  dlp('Veri Sızıntısı (DLP)', Icons.lock_person_outlined, Icons.lock_person_rounded, BolumGrubu.guvenlik, roller: _platform),
  sunucu('Sunucu Erişimi', Icons.key_outlined, Icons.key_rounded, BolumGrubu.guvenlik, roller: _platform),
  kotuyeKullanim('Kötüye Kullanım', Icons.report_outlined, Icons.report_rounded, BolumGrubu.guvenlik, ozellikler: {'abuse_protection'}),
  oltalama('Oltalama Simülasyonu', Icons.phishing_rounded, Icons.phishing_rounded, BolumGrubu.guvenlik, izin: 'phishing.manage', ozellikler: {'phishing_sim'}),

  kurulum('Kurulum', Icons.checklist_rounded, Icons.checklist_rounded, BolumGrubu.altyapi, roller: _platform),
  itibar('İtibar', Icons.star_outline_rounded, Icons.star_rounded, BolumGrubu.altyapi, roller: _ortaklar),
  ipYonetimi('IP Yönetimi', Icons.lan_outlined, Icons.lan_rounded, BolumGrubu.altyapi, roller: _platform),
  kiraci('Kiracı İzolasyonu', Icons.shield_moon_outlined, Icons.shield_moon_rounded, BolumGrubu.altyapi, roller: _platform),
  depolama('Depolama', Icons.storage_outlined, Icons.storage_rounded, BolumGrubu.altyapi),
  yedekleme('Yedekleme', Icons.backup_outlined, Icons.backup_rounded, BolumGrubu.altyapi, roller: _platform),
  izleme('İzleme', Icons.monitor_heart_outlined, Icons.monitor_heart_rounded, BolumGrubu.altyapi, roller: _platform),
  alarmlar('Uyarılar', Icons.notifications_outlined, Icons.notifications_rounded, BolumGrubu.altyapi),
  sunucular('Sunucular', Icons.dns_outlined, Icons.dns_rounded, BolumGrubu.altyapi, roller: _platform),

  yoneticiler('Yöneticiler', Icons.manage_accounts_outlined, Icons.manage_accounts_rounded, BolumGrubu.yonetim),
  denetim('Denetim Kayıtları', Icons.receipt_long_outlined, Icons.receipt_long_rounded, BolumGrubu.yonetim, izin: 'audit.view'),
  entegrasyonlar('Entegrasyonlar', Icons.extension_outlined, Icons.extension_rounded, BolumGrubu.yonetim, roller: _platform),
  platformAyarlari('Platform Ayarları', Icons.tune_rounded, Icons.tune_rounded, BolumGrubu.yonetim, roller: _platform),
  ayarlar('Ayarlar ve Profil', Icons.settings_outlined, Icons.settings_rounded, BolumGrubu.yonetim);

  const Bolum(this.baslik, this.ikon, this.secikIkon, this.grup, {this.roller, this.izin, this.turler, this.ozellikler});
  final String baslik;
  final IconData ikon, secikIkon;
  final BolumGrubu grup;

  /// Bölümü gören roller (null = tüm panel rolleri).
  final Set<String>? roller;

  /// API'nin istediği panel yetkisi.
  final String? izin;

  /// Müşteri için paket türleri (hosting | gateway | hybrid).
  final Set<String>? turler;

  /// Müşteri için paket özellikleri (biri yeterli).
  final Set<String>? ozellikler;

  /// Rol, yetki ve (müşteri için) paket türü/özelliklerine göre görünür mü (web: navVisible).
  bool get gorunur {
    if (roller != null && !roller!.contains(Uyg.rol)) return false;
    if (izin != null && !Uyg.yetki(izin!)) return false;
    return pakette;
  }

  /// Müşterinin paketi bölümü kapsıyor mu (web: navInPackage). Ortaklar her modülü yönetir.
  bool get pakette {
    if (!Uyg.musteri || Uyg.baglam['organization'] is! Map) return true;
    final tur = Uyg.paketTuru.isEmpty ? 'hosting' : Uyg.paketTuru;
    final turUygun = turler == null || turler!.contains(tur);
    final ozellikUygun = ozellikler == null || ozellikler!.any(Uyg.ozellik);
    if (this == Bolum.gateway) return turUygun || ozellikUygun;
    return turUygun && ozellikUygun;
  }

  /// Telefon alt çubuğuna aday bölümler (görünür olanlardan ilk dördü kullanılır).
  static const anaBolumler = [Bolum.ozet, Bolum.alanlar, Bolum.kutular, Bolum.kuyruk, Bolum.alarmlar, Bolum.musteriler];

  static List<Bolum> get gorunenler => [
    for (final b in values)
      if (b.gorunur) b,
  ];

  /// Görünür bölümler, gruplarına göre (boş gruplar çıkarılır).
  static List<(BolumGrubu, List<Bolum>)> get gruplar {
    final g = gorunenler;
    return [
      for (final grup in BolumGrubu.values)
        if (g.any((b) => b.grup == grup)) (grup, g.where((b) => b.grup == grup).toList()),
    ];
  }

  Widget ekran() => switch (this) {
    Bolum.ozet => const OzetEkrani(),
    Bolum.paketim => const PaketimEkrani(),
    Bolum.itibarMerkezim => const ItibarMerkezimEkrani(),
    Bolum.musteriler => const MusterilerEkrani(),
    Bolum.dahili => const DahiliKurumlarEkrani(),
    Bolum.bayiler => const BayilerEkrani(),
    Bolum.paketler => const PaketlerEkrani(),
    Bolum.alanlar => const AlanAdlariEkrani(),
    Bolum.kutular => const PostaKutulariEkrani(),
    Bolum.takmaAdlar => const TakmaAdlarEkrani(),
    Bolum.cihazlar => const MobilCihazlarEkrani(),
    Bolum.ekip => const EkipCalismasiEkrani(),
    Bolum.topluGonderim => const TopluGonderimEkrani(),
    Bolum.marka => const MarkaEkrani(),
    Bolum.gateway => const GatewayEkrani(),
    Bolum.takip => const MesajTakibiEkrani(),
    Bolum.kuyruk => const KuyrukEkrani(),
    Bolum.teslimatKontrol => const TeslimatKontrolEkrani(),
    Bolum.bastirma => const BastirmaListesiEkrani(),
    Bolum.teslimatSorunlari => const TeslimatSorunlariEkrani(),
    Bolum.teslimTeshisi => const TeslimTeshisiEkrani(),
    Bolum.kampanyaIzleme => const KampanyaIzlemeEkrani(),
    Bolum.sandbox => const SandboxEkrani(),
    Bolum.dmarc => const DmarcEkrani(),
    Bolum.smtpTrafigi => const SmtpTrafigiEkrani(),
    Bolum.spam => const SpamEkrani(),
    Bolum.karantina => const KarantinaEkrani(),
    Bolum.tehdit => const TehditEkrani(),
    Bolum.greylist => const GreylistEkrani(),
    Bolum.saldiriHaritasi => const SaldiriHaritasiEkrani(),
    Bolum.dlp => const DlpEkrani(),
    Bolum.sunucu => const SunucuErisimiEkrani(),
    Bolum.kotuyeKullanim => const KotuyeKullanimEkrani(),
    Bolum.oltalama => const OltalamaEkrani(),
    Bolum.kurulum => const KurulumEkrani(),
    Bolum.itibar => const ItibarEkrani(),
    Bolum.ipYonetimi => const IpYonetimiEkrani(),
    Bolum.kiraci => const KiraciIzolasyonuEkrani(),
    Bolum.depolama => const DepolamaEkrani(),
    Bolum.yedekleme => const YedeklemeEkrani(),
    Bolum.izleme => const IzlemeEkrani(),
    Bolum.alarmlar => const AlarmlarEkrani(),
    Bolum.sunucular => const SunucularEkrani(),
    Bolum.yoneticiler => const YoneticilerEkrani(),
    Bolum.denetim => const DenetimKayitlariEkrani(),
    Bolum.entegrasyonlar => const EntegrasyonlarEkrani(),
    Bolum.platformAyarlari => const PlatformAyarlariEkrani(),
    Bolum.ayarlar => const AyarlarEkrani(),
  };
}

/// Ekranların kabuktan bölüm açma isteği (özet kartları, push bildirimleri).
final bolumIstegi = ValueNotifier<Bolum?>(null);

/// Bir bölüme geçer. İsteğe bağlı hedefle o bölümdeki kaydı da açar:
/// - [musteriId]: Müşteriler → müşteri ayrıntısı (GET /organizations/{id}),
/// - [alanId] (+ [alanAdi]): DMARC → alan adı ayrıntısı,
/// - [kuyrukId]: Mesaj Takibi → iletinin yolculuğu.
void bolumeGit(Bolum b, {String? musteriId, String? alanId, String? alanAdi, String? kuyrukId}) {
  bolumIstegi.value = null;
  bolumIstegi.value = b;
  if (musteriId == null && alanId == null && kuyrukId == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final c = kokGezgin.currentContext;
    if (c == null || !c.mounted) return;
    if (kuyrukId != null && kuyrukId.isNotEmpty) {
      await iletiYolculugunuAc(c, kuyrukId);
    } else if (alanId != null && alanId.isNotEmpty) {
      await Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => DmarcAlanDetay(id: alanId, ad: alanAdi ?? 'Alan adı')));
    } else if (musteriId != null && musteriId.isNotEmpty) {
      await musteriDetayKimlikle(c, musteriId);
    }
  });
}

/// Kabukta gösterilen sayaçlar (etkin alarm, kuyruk, bekleyen karantina); kabuk ve özet günceller.
final bolumRozetleri = ValueNotifier<Map<Bolum, int>>(const {});
