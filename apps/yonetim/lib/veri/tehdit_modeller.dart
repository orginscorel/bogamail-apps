// Tehdit Koruması veri modelleri (internal/api/threat.go, security2.go, clicks.go, spamapi.go).

import 'json.dart';

/// Tespit türleri (threatKinds) ve Türkçe etiketleri.
const tespitTurleri = <String, String>{
  'dmarc': 'DMARC',
  'spoof': 'Sahte gönderen',
  'impersonation': 'Kimlik taklidi',
  'lookalike': 'Benzer alan adı',
  'link': 'Zararlı bağlantı',
  'reputation': 'IP/ASN itibarı',
  'qr': 'QR oltalama',
  'sandbox': 'Ek analizi',
};

String tespitTuru(String k) => tespitTurleri[k] ?? k;

const tespitSonuclari = <String, String>{'inbox': 'Gelen Kutusu', 'junk': 'Önemsiz', 'reject': 'Reddedildi', 'allow': 'İzin listesi'};
String tespitSonucu(String a) => tespitSonuclari[a] ?? a;

/// GET /threat/detections → ThreatDetection.
class Tespit {
  Tespit(this.m);
  final Map<String, dynamic> m;
  factory Tespit.coz(Map<String, dynamic> m) => Tespit(m);

  int get id => tamsayi(m['id']);
  DateTime? get zaman => tarihOku(m['at']);
  String get kuyruk => metin(m['queue_id']);
  String? get orgId => metinYa(m['organization_id']);
  String? get orgAdi => metinYa(m['organization_name']);
  String get tur => metin(m['kind']);
  String get kural => metin(m['rule']);
  double get puan => ondalik(m['score']);
  String get sonuc => metin(m['action']);
  String get ayrinti => metin(m['detail']);
  String get uyari => metin(m['banner']);
  String get zarf => metin(m['mail_from']);
  String get baslikFrom => metin(m['header_from']);
  String? get ip => metinYa(m['remote_ip']);

  /// Görünen gönderen: From başlığı, yoksa zarf, yoksa "<>".
  String get gonderen => baslikFrom.isNotEmpty ? baslikFrom : (zarf.isNotEmpty ? zarf : '<>');
}

/// GET /attachment-reports → AttachmentReport.
class EkRaporu {
  EkRaporu(this.m);
  final Map<String, dynamic> m;
  factory EkRaporu.coz(Map<String, dynamic> m) => EkRaporu(m);

  int get id => tamsayi(m['id']);
  DateTime? get zaman => tarihOku(m['at']);
  String get kuyruk => metin(m['queue_id']);
  String? get orgAdi => metinYa(m['organization_name']);
  String get dosya => metin(m['filename']);
  String get icerikTuru => metin(m['content_type']);
  int get boyut => tamsayi(m['size_bytes']);
  String get sha256 => metin(m['sha256']);
  String get bildirilen => metin(m['declared_type']);
  String get algilanan => metin(m['detected_type']);
  double get puan => ondalik(m['score']);
  String get karar => metin(m['verdict']);
  List<(String, double, String)> get bulgular => [
    for (final f in haritalar(m['findings'])) (metin(f['rule']), ondalik(f['score']), metin(f['detail'])),
  ];
  List<String> get qrAdresleri => metinler(m['qr_urls']);
  String get sonuc => metin(m['action']);
}

const ekKararlari = <String, String>{'clean': 'Temiz', 'suspicious': 'Şüpheli', 'malicious': 'Zararlı'};
const ekSonuclari = <String, String>{'delivered': 'Teslim edildi', 'quarantined': 'Karantinada', 'rejected': 'Reddedildi'};

/// GET /clicks → LinkClick.
class Tiklama {
  Tiklama(this.m);
  final Map<String, dynamic> m;
  factory Tiklama.coz(Map<String, dynamic> m) => Tiklama(m);

  int get id => tamsayi(m['id']);
  DateTime? get zaman => tarihOku(m['at']);
  String? get orgAdi => metinYa(m['organization_name']);
  String get adres => metin(m['address']);
  String get alan => metin(m['host']);
  String get maskeliUrl => metin(m['url_masked']);
  String get karar => metin(m['verdict']);
  List<String> get nedenler => metinler(m['reasons']);
  bool get devamEtti => mantik(m['proceeded']);
}

/// Liste kaydı: GET /clicks/blocklist (ClickBlock) ve GET /spam/lists (SpamListEntry) için ortak.
class ListeKaydi {
  ListeKaydi(this.m);
  final Map<String, dynamic> m;
  factory ListeKaydi.coz(Map<String, dynamic> m) => ListeKaydi(m);

  String get id => metin(m['id']);
  String? get orgId => metinYa(m['organization_id']);
  String? get orgAdi => metinYa(m['organization_name']);

  /// allow | block (yalnızca spam listelerinde).
  String get tur => metin(m['kind']);

  /// sender | domain | ip | asn | link (yalnızca spam listelerinde).
  String get tip => metin(m['type']);
  String get deger => metin(m['value']);
  String get not => metin(m['note']);
  String get ekleyen => metin(m['created_by']);
  DateTime? get eklenme => tarihOku(m['created_at']);
}

/// GET /threat/people → ProtectedPerson.
class KorunanKisi {
  KorunanKisi(this.m);
  final Map<String, dynamic> m;
  factory KorunanKisi.coz(Map<String, dynamic> m) => KorunanKisi(m);

  String get id => metin(m['id']);
  String get orgId => metin(m['organization_id']);
  String get orgAdi => metin(m['organization_name']);
  String get ad => metin(m['name']);
  String get unvan => metin(m['title']);
  List<String> get adresler => metinler(m['emails']);
  DateTime? get eklenme => tarihOku(m['created_at']);
}

/// GET /threat/asn → ASNStat.
class AsnIstatistigi {
  AsnIstatistigi(this.m);
  final Map<String, dynamic> m;
  factory AsnIstatistigi.coz(Map<String, dynamic> m) => AsnIstatistigi(m);

  int get asn => tamsayi(m['asn']);
  String get ad => metin(m['name']);
  String get ulke => metin(m['country']);
  int get ileti => tamsayi(m['messages']);
  int get spam => tamsayi(m['spam']);
  int get ret => tamsayi(m['rejected']);
  double get kotuOran => ondalik(m['bad_ratio']);
  DateTime? get ilk => tarihOku(m['first_seen']);
  DateTime? get son => tarihOku(m['last_seen']);

  /// allow | block | null.
  String? get liste => metinYa(m['listed']);
}

/// GET /threat/ips → IPRep.
class IpItibari {
  IpItibari(this.m);
  final Map<String, dynamic> m;
  factory IpItibari.coz(Map<String, dynamic> m) => IpItibari(m);

  String get ip => metin(m['ip']);
  int? get asn => tamsayiYa(m['asn']);
  String? get asAdi => metinYa(m['as_name']);
  int get ileti => tamsayi(m['messages']);
  int get spam => tamsayi(m['spam']);
  int get ret => tamsayi(m['rejected']);
  double get puan => ondalik(m['score']);
  DateTime? get son => tarihOku(m['last_seen']);
}

/// Oran (0..1) → "%42".
String oranYaz(double v) => '%${(v * 100).toStringAsFixed(0)}';

/// Ondalık puanı Türkçe yazar (ör. 2,5).
String puanYaz(double v, {int basamak = 1}) => v.toStringAsFixed(basamak).replaceAll('.', ',');
