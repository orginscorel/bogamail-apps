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
import '../ortak/simgeler.dart';

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
  ozet('Özet', Simgeler.spaceDashboard, SimgelerDolu.spaceDashboard, BolumGrubu.genel),
  paketim('Paketim', Simgeler.verified, SimgelerDolu.verified, BolumGrubu.genel, roller: {'org_admin'}),
  itibarMerkezim('İtibar Merkezim', Simgeler.trendingUp, SimgelerDolu.trendingUp, BolumGrubu.genel, roller: {'org_admin'}),

  musteriler('Müşteriler', Simgeler.apartment, SimgelerDolu.apartment, BolumGrubu.hizmet, roller: _ortaklar),
  dahili('Yönetici Kurumları', Simgeler.adminPanelSettings, SimgelerDolu.adminPanelSettings, BolumGrubu.hizmet, roller: _platform),
  bayiler('Bayiler', Simgeler.handshake, SimgelerDolu.handshake, BolumGrubu.hizmet, roller: _platform),
  paketler('Paketler', Simgeler.inventory2, SimgelerDolu.inventory2, BolumGrubu.hizmet, roller: _ortaklar),
  alanlar('Alan Adları', Simgeler.language, SimgelerDolu.language, BolumGrubu.hizmet),
  kutular('Posta Kutuları', Simgeler.inbox, SimgelerDolu.inbox, BolumGrubu.hizmet, turler: _posta),
  takmaAdlar('Takma Adlar', Simgeler.alternateEmail, SimgelerDolu.alternateEmail, BolumGrubu.hizmet, turler: _posta, ozellikler: {'aliases', 'forwarding', 'distribution_lists'}),
  cihazlar('Mobil Cihazlar', Simgeler.smartphone, SimgelerDolu.smartphone, BolumGrubu.hizmet, turler: _posta, ozellikler: {'activesync'}),
  ekip('Ekip Çalışması', Simgeler.groups, SimgelerDolu.groups, BolumGrubu.hizmet, roller: {'org_admin'}, turler: _posta),
  topluGonderim('Toplu Gönderim', Simgeler.campaign, SimgelerDolu.campaign, BolumGrubu.hizmet, roller: {'org_admin'}, izin: 'campaigns.manage', turler: _posta, ozellikler: {'bulk_sending'}),
  marka('Marka', Simgeler.palette, SimgelerDolu.palette, BolumGrubu.hizmet, ozellikler: {'branding'}),

  gateway('Mail Gateway', Simgeler.altRoute, SimgelerDolu.altRoute, BolumGrubu.trafik, turler: {'gateway', 'hybrid'}, ozellikler: {'gateway'}),
  takip('Mesaj Takibi', Simgeler.manageSearch, SimgelerDolu.manageSearch, BolumGrubu.trafik, izin: 'tracking.view'),
  kuyruk('Kuyruk', Simgeler.formatListNumbered, SimgelerDolu.formatListNumbered, BolumGrubu.trafik, izin: 'tracking.view'),
  teslimatKontrol('Teslimat Kontrol', Simgeler.bolt, SimgelerDolu.bolt, BolumGrubu.trafik, roller: _platform),
  bastirma('Bastırma Listesi', Simgeler.block, SimgelerDolu.block, BolumGrubu.trafik, izin: 'tracking.view'),
  teslimatSorunlari('Teslimat Sorunları', Simgeler.reportProblem, SimgelerDolu.reportProblem, BolumGrubu.trafik),
  teslimTeshisi('Teslim Teşhisi', Simgeler.medicalServices, SimgelerDolu.medicalServices, BolumGrubu.trafik, izin: 'tracking.view'),
  kampanyaIzleme('Toplu Gönderim İzleme', Simgeler.cellTower, SimgelerDolu.cellTower, BolumGrubu.trafik, roller: _ortaklar),
  sandbox('Test Sandbox', Simgeler.science, SimgelerDolu.science, BolumGrubu.trafik, ozellikler: {'email_sandbox'}),
  dmarc('DMARC Merkezi', Simgeler.markEmailRead, SimgelerDolu.markEmailRead, BolumGrubu.trafik, ozellikler: {'dmarc_center'}),
  smtpTrafigi('SMTP Trafiği', Simgeler.showChart, SimgelerDolu.showChart, BolumGrubu.trafik, roller: _platform),

  spam('Spam Güvenliği', Simgeler.gppMaybe, SimgelerDolu.gppMaybe, BolumGrubu.guvenlik),
  karantina('Karantina', Simgeler.shield, SimgelerDolu.shield, BolumGrubu.guvenlik, izin: 'quarantine.view'),
  tehdit('Tehdit Koruması', Simgeler.security, SimgelerDolu.security, BolumGrubu.guvenlik),
  greylist('Greylisting', Simgeler.hourglassEmpty, SimgelerDolu.hourglassBottom, BolumGrubu.guvenlik, roller: _ortaklar),
  saldiriHaritasi('Saldırı Haritası', Simgeler.map, SimgelerDolu.map, BolumGrubu.guvenlik, roller: _ortaklar),
  dlp('Veri Sızıntısı (DLP)', Simgeler.lockPerson, SimgelerDolu.lockPerson, BolumGrubu.guvenlik, roller: _platform),
  sunucu('Sunucu Erişimi', Simgeler.key, SimgelerDolu.key, BolumGrubu.guvenlik, roller: _platform),
  kotuyeKullanim('Kötüye Kullanım', Simgeler.report, SimgelerDolu.report, BolumGrubu.guvenlik, ozellikler: {'abuse_protection'}),
  oltalama('Oltalama Simülasyonu', Simgeler.phishing, SimgelerDolu.phishing, BolumGrubu.guvenlik, izin: 'phishing.manage', ozellikler: {'phishing_sim'}),

  kurulum('Kurulum', Simgeler.checklist, SimgelerDolu.checklist, BolumGrubu.altyapi, roller: _platform),
  itibar('İtibar', Simgeler.starOutline, SimgelerDolu.star, BolumGrubu.altyapi, roller: _ortaklar),
  ipYonetimi('IP Yönetimi', Simgeler.lan, SimgelerDolu.lan, BolumGrubu.altyapi, roller: _platform),
  kiraci('Kiracı İzolasyonu', Simgeler.shieldMoon, SimgelerDolu.shieldMoon, BolumGrubu.altyapi, roller: _platform),
  depolama('Depolama', Simgeler.storage, SimgelerDolu.storage, BolumGrubu.altyapi),
  yedekleme('Yedekleme', Simgeler.backup, SimgelerDolu.backup, BolumGrubu.altyapi, roller: _platform),
  izleme('İzleme', Simgeler.monitorHeart, SimgelerDolu.monitorHeart, BolumGrubu.altyapi, roller: _platform),
  alarmlar('Uyarılar', Simgeler.notifications, SimgelerDolu.notifications, BolumGrubu.altyapi),
  sunucular('Sunucular', Simgeler.dns, SimgelerDolu.dns, BolumGrubu.altyapi, roller: _platform),

  yoneticiler('Yöneticiler', Simgeler.manageAccounts, SimgelerDolu.manageAccounts, BolumGrubu.yonetim),
  denetim('Denetim Kayıtları', Simgeler.receiptLong, SimgelerDolu.receiptLong, BolumGrubu.yonetim, izin: 'audit.view'),
  entegrasyonlar('Entegrasyonlar', Simgeler.extension, SimgelerDolu.extension, BolumGrubu.yonetim, roller: _platform),
  platformAyarlari('Platform Ayarları', Simgeler.tune, SimgelerDolu.tune, BolumGrubu.yonetim, roller: _platform),
  ayarlar('Ayarlar ve Profil', Simgeler.settings, SimgelerDolu.settings, BolumGrubu.yonetim);

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
