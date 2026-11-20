import '../oturum.dart';
import '../veri/json.dart';

/// Müşteri (GET /organizations ve /organizations/{id}; internal/api/orgs.go Organization).
class Musteri {
  const Musteri({
    required this.id,
    required this.ad,
    required this.durum,
    required this.bayiId,
    required this.bayiAdi,
    required this.paketId,
    required this.paketAdi,
    required this.enFazlaAlan,
    required this.enFazlaKutu,
    required this.toplamKota,
    required this.alanSayisi,
    required this.kutuSayisi,
    required this.ayrilan,
    required this.kullanilan,
    required this.eklenme,
    required this.profil,
    required this.dahili,
  });

  final String id, ad, durum;
  final String? bayiId, bayiAdi, paketId, paketAdi;
  final int? enFazlaAlan, enFazlaKutu, toplamKota;
  final int alanSayisi, kutuSayisi, ayrilan, kullanilan;
  final DateTime? eklenme;
  final Map<String, dynamic> profil;
  final bool dahili;

  bool get aktif => durum == 'active';

  /// Profil alanı (boşsa '').
  String p(String anahtar) => metin(profil[anahtar]).trim();

  factory Musteri.coz(Map<String, dynamic> m) => Musteri(
    id: metin(m['id']),
    ad: metin(m['name']),
    durum: metin(m['status'], 'active'),
    bayiId: metinYa(m['reseller_id']),
    bayiAdi: metinYa(m['reseller_name']),
    paketId: metinYa(m['plan_id']),
    paketAdi: metinYa(m['plan_name']),
    enFazlaAlan: tamsayiYa(m['max_domains']),
    enFazlaKutu: tamsayiYa(m['max_mailboxes']),
    toplamKota: tamsayiYa(m['total_quota_bytes']),
    alanSayisi: tamsayi(m['domain_count']),
    kutuSayisi: tamsayi(m['mailbox_count']),
    ayrilan: tamsayi(m['allocated_bytes']),
    kullanilan: tamsayi(m['used_bytes']),
    eklenme: tarihOku(m['created_at']),
    profil: harita(m['profile']),
    dahili: mantik(m['internal']),
  );
}

/// Sınır yazımı: null ya da 0 → "∞".
String sinirYaz(int? n) => n == null || n <= 0 ? '∞' : '$n';

/// Müşteri ekranındaki yetkiler (web customers-view ve Go handler kuralları).
class MusteriYetki {
  MusteriYetki._();

  /// Müşteri oluşturma / düzenleme / silme / askıya alma (POST/PATCH/DELETE /organizations: organizations.manage, ortak).
  static bool get yonetir => Uyg.ortak && Uyg.yetki('organizations.manage');

  /// Yeni müşteri: görünüm (taklit) içinde sunucu engeller.
  static bool get olusturur => yonetir && Uyg.taklit == null;

  /// Özellik ve limit geçersiz kılma (PATCH /organizations/{id}/entitlements); görünüm içinde kapalı.
  static bool get haklariDuzenler => yonetir && Uyg.taklit == null;

  /// Süper yönetici, görünüm dışında: çıkış IP'si, bayi yapma, Yönetici bölümüne taşıma.
  static bool get platform => Uyg.platformYoneticisi && Uyg.taklit == null;

  /// Tümünü dışa aktar (mailboxes.manage).
  static bool get disaAktarir => Uyg.yetki('mailboxes.manage');

  /// Müşteri paneline gir (POST /organizations/{id}/impersonate: organizations.manage).
  static bool get girer => Uyg.girebilir && Uyg.yetki('organizations.manage');

  /// İki adımlı doğrulama politikası (PATCH /organizations/{id}/mfa-policy: users.manage).
  static bool get mfaDuzenler => Uyg.yetki('users.manage');

  /// Giriş adresi (PUT /organizations/{id}/login-host: branding.manage).
  static bool get girisAdresiDuzenler => Uyg.yetki('branding.manage');

  /// Toplu gönderim ayarları (/admin/campaigns/orgs/{id}/settings: yalnızca ortaklar).
  static bool get topluGonderim => Uyg.ortak;
}

const sektorler = <String, String>{
  'bilisim': 'Bilişim ve yazılım',
  'finans': 'Finans, banka, sigorta',
  'saglik': 'Sağlık',
  'egitim': 'Eğitim',
  'kamu': 'Kamu kurumu',
  'uretim': 'Üretim ve sanayi',
  'perakende': 'Perakende',
  'eticaret': 'E-ticaret',
  'insaat': 'İnşaat ve gayrimenkul',
  'lojistik': 'Lojistik ve taşımacılık',
  'turizm': 'Turizm ve otelcilik',
  'hukuk': 'Hukuk',
  'muhasebe': 'Muhasebe ve mali müşavirlik',
  'medya': 'Medya ve reklam',
  'enerji': 'Enerji',
  'tarim': 'Tarım',
  'gida': 'Gıda ve restoran',
  'otomotiv': 'Otomotiv',
  'danismanlik': 'Danışmanlık',
  'stk': 'Dernek, vakıf, STK',
  'diger': 'Diğer',
};

const musteriTurleri = <String, String>{'corporate': 'Kurumsal', 'individual': 'Bireysel', 'public': 'Kamu'};

const calisanSayilari = ['1-10', '11-50', '51-200', '201-500', '501-1000', '1000+'];

const iller = [
  'Adana', 'Adıyaman', 'Afyonkarahisar', 'Ağrı', 'Aksaray', 'Amasya', 'Ankara', 'Antalya', 'Ardahan', 'Artvin', 'Aydın', 'Balıkesir', //
  'Bartın', 'Batman', 'Bayburt', 'Bilecik', 'Bingöl', 'Bitlis', 'Bolu', 'Burdur', 'Bursa', 'Çanakkale', 'Çankırı', 'Çorum', 'Denizli', //
  'Diyarbakır', 'Düzce', 'Edirne', 'Elazığ', 'Erzincan', 'Erzurum', 'Eskişehir', 'Gaziantep', 'Giresun', 'Gümüşhane', 'Hakkâri', //
  'Hatay', 'Iğdır', 'Isparta', 'İstanbul', 'İzmir', 'Kahramanmaraş', 'Karabük', 'Karaman', 'Kars', 'Kastamonu', 'Kayseri', 'Kilis', //
  'Kırıkkale', 'Kırklareli', 'Kırşehir', 'Kocaeli', 'Konya', 'Kütahya', 'Malatya', 'Manisa', 'Mardin', 'Mersin', 'Muğla', 'Muş', //
  'Nevşehir', 'Niğde', 'Ordu', 'Osmaniye', 'Rize', 'Sakarya', 'Samsun', 'Şanlıurfa', 'Siirt', 'Sinop', 'Şırnak', 'Sivas', 'Tekirdağ', //
  'Tokat', 'Trabzon', 'Tunceli', 'Uşak', 'Van', 'Yalova', 'Yozgat', 'Zonguldak',
];

/// Müşteri dışa aktarma işi (GET /organizations/{id}/exports → items).
class MusteriDisaAktarma {
  const MusteriDisaAktarma({
    required this.id,
    required this.durum,
    required this.isteyen,
    required this.olusturma,
    required this.bitis,
    required this.silinme,
    required this.kutu,
    required this.ileti,
    required this.kisi,
    required this.etkinlik,
    required this.boyut,
    required this.indirme,
    required this.hata,
    required this.ozet,
  });
  final String id, durum, isteyen, hata, ozet;
  final DateTime? olusturma, bitis, silinme;
  final int kutu, ileti, kisi, etkinlik, boyut, indirme;

  bool get suruyor => durum == 'queued' || durum == 'running';

  factory MusteriDisaAktarma.coz(Map<String, dynamic> m) => MusteriDisaAktarma(
    id: metin(m['id']),
    durum: metin(m['status']),
    isteyen: metin(m['requested_by']),
    olusturma: tarihOku(m['created_at']),
    bitis: tarihOku(m['finished_at']),
    silinme: tarihOku(m['expires_at']),
    kutu: tamsayi(m['mailboxes']),
    ileti: tamsayi(m['messages']),
    kisi: tamsayi(m['contacts']),
    etkinlik: tamsayi(m['events']),
    boyut: tamsayi(m['size_bytes']),
    indirme: tamsayi(m['downloads']),
    hata: metin(m['error']),
    ozet: metin(m['sha256']),
  );
}

const disaAktarmaDurumlari = {'queued': 'Sırada', 'running': 'Hazırlanıyor', 'ready': 'Hazır', 'failed': 'Başarısız', 'expired': 'Süresi doldu'};
