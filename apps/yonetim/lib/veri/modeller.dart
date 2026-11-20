// Hizmet nesneleri: alan adları, posta kutuları, takma adlar, müşteriler, bayiler, oturumlar, denetim kayıtları.
// Tüm ayrıştırma hoşgörülüdür (eksik alanlar varsayılan değer alır).

import 'json.dart';

class DkimAnahtari {
  const DkimAnahtari({required this.secici, required this.kayitAdi, required this.kayit, this.olusturma});
  final String secici, kayitAdi, kayit;
  final DateTime? olusturma;

  static DkimAnahtari? coz(Object? v) {
    if (v is! Map) return null;
    final m = harita(v);
    return DkimAnahtari(secici: metin(m['selector']), kayitAdi: metin(m['record_name']), kayit: metin(m['record']), olusturma: tarihOku(m['created_at']));
  }
}

class AlanAdi {
  AlanAdi({
    required this.id,
    required this.ad,
    required this.unicodeAd,
    required this.mod,
    required this.durum,
    required this.orgId,
    required this.orgAdi,
    required this.dogrulamaTxt,
    required this.dogrulanma,
    required this.kutuSayisi,
    required this.eklenme,
    required this.dnsDurumu,
    required this.dnsZamani,
    required this.gatewayHost,
    required this.gatewayPort,
    required this.dkim,
  });

  final String id, ad, unicodeAd, mod, durum, orgId, orgAdi, dogrulamaTxt, dnsDurumu, gatewayHost;
  final DateTime? dogrulanma, eklenme, dnsZamani;
  final int kutuSayisi, gatewayPort;
  final DkimAnahtari? dkim;

  bool get hosting => mod != 'gateway';
  String get gorunenAd => unicodeAd.isNotEmpty ? unicodeAd : ad;

  factory AlanAdi.coz(Map<String, dynamic> m) => AlanAdi(
    id: metin(m['id']),
    ad: metin(m['name']),
    unicodeAd: metin(m['unicode_name']),
    mod: metin(m['mode'], 'hosting'),
    durum: metin(m['status'], 'pending'),
    orgId: metin(m['organization_id']),
    orgAdi: metin(m['organization_name']),
    dogrulamaTxt: metin(m['verification_txt']),
    dogrulanma: tarihOku(m['verified_at']),
    kutuSayisi: tamsayi(m['mailbox_count']),
    eklenme: tarihOku(m['created_at']),
    dnsDurumu: metin(m['dns_check'], 'unchecked'),
    dnsZamani: tarihOku(m['dns_checked_at']),
    gatewayHost: metin(m['gateway_host']),
    gatewayPort: tamsayi(m['gateway_port']),
    dkim: DkimAnahtari.coz(m['dkim']),
  );
}

class DnsKontrolu {
  const DnsKontrolu({
    required this.id,
    required this.etiket,
    required this.durum,
    required this.ayrinti,
    required this.beklenen,
    required this.host,
    required this.tur,
    required this.deger,
    required this.bulunan,
    required this.sorunlar,
  });
  final String id, etiket, durum, ayrinti, beklenen, host, tur, deger;
  final List<String> bulunan, sorunlar;

  factory DnsKontrolu.coz(Map<String, dynamic> m) => DnsKontrolu(
    id: metin(m['id']),
    etiket: metin(m['label']),
    durum: metin(m['status'], 'info'),
    ayrinti: metin(m['detail']),
    beklenen: metin(m['expected']),
    host: metin(m['host']),
    tur: metin(m['type']),
    deger: metin(m['value']),
    bulunan: metinler(m['found']),
    sorunlar: metinler(m['problems']),
  );
}

class DnsRaporu {
  const DnsRaporu({required this.zaman, required this.dogrulandi, required this.kontroller});
  final DateTime? zaman;
  final bool dogrulandi;
  final List<DnsKontrolu> kontroller;

  /// {report: {...} | null}
  static DnsRaporu? coz(Object? yanit) {
    final r = harita(yanit)['report'];
    if (r is! Map) return null;
    final m = harita(r);
    return DnsRaporu(zaman: tarihOku(m['checked_at']), dogrulandi: mantik(m['verified']), kontroller: haritalar(m['checks']).map(DnsKontrolu.coz).toList());
  }

  int sayi(String durum) => kontroller.where((k) => k.durum == durum).length;
}

class PostaKutusu {
  PostaKutusu({
    required this.id,
    required this.adres,
    required this.adresAscii,
    required this.gorunenAd,
    required this.alanId,
    required this.alanAdi,
    required this.orgId,
    required this.orgAdi,
    required this.kota,
    required this.kullanilan,
    required this.saatlikSinir,
    required this.durum,
    required this.sonGiris,
    required this.eklenme,
  });

  final String id, adres, adresAscii, gorunenAd, alanId, alanAdi, orgId, orgAdi, durum;
  final int kota, kullanilan, saatlikSinir;
  final DateTime? sonGiris, eklenme;

  bool get aktif => durum == 'active';

  factory PostaKutusu.coz(Map<String, dynamic> m) {
    final ascii = metin(m['address']);
    return PostaKutusu(
      id: metin(m['id']),
      adres: metinYa(m['address_unicode']) ?? ascii,
      adresAscii: ascii,
      gorunenAd: metin(m['display_name']),
      alanId: metin(m['domain_id']),
      alanAdi: metinYa(m['domain_unicode']) ?? metin(m['domain_name']),
      orgId: metin(m['organization_id']),
      orgAdi: metin(m['organization_name']),
      kota: tamsayi(m['quota_bytes']),
      kullanilan: tamsayi(m['used_bytes']),
      saatlikSinir: tamsayi(m['send_limit_per_hour']),
      durum: metin(m['status'], 'active'),
      sonGiris: tarihOku(m['last_login_at']),
      eklenme: tarihOku(m['created_at']),
    );
  }
}

class Yonlendirme {
  const Yonlendirme({required this.hedef, required this.kopyaKalsin, required this.ayarlayan, required this.izinli, required this.disIzinli});
  final String hedef, ayarlayan;
  final bool kopyaKalsin, izinli, disIzinli;

  factory Yonlendirme.coz(Object? v) {
    final m = harita(v);
    return Yonlendirme(
      hedef: metin(m['forward_to']),
      kopyaKalsin: mantik(m['keep_copy'], true),
      ayarlayan: metin(m['set_by']),
      izinli: mantik(m['allowed']),
      disIzinli: mantik(m['external_allowed']),
    );
  }
}

class TakmaAd {
  const TakmaAd({
    required this.id,
    required this.adres,
    required this.alanId,
    required this.orgAdi,
    required this.tur,
    required this.ad,
    required this.hedefler,
    required this.gonderimIzni,
    required this.etkin,
    required this.eklenme,
  });
  final String id, adres, alanId, orgAdi, tur, ad, gonderimIzni;
  final List<String> hedefler;
  final bool etkin;
  final DateTime? eklenme;

  bool get liste => tur == 'list';

  factory TakmaAd.coz(Map<String, dynamic> m) => TakmaAd(
    id: metin(m['id']),
    adres: metin(m['address']),
    alanId: metin(m['domain_id']),
    orgAdi: metin(m['organization_name']),
    tur: metin(m['kind'], 'alias'),
    ad: metin(m['name']),
    hedefler: metinler(m['destinations']),
    gonderimIzni: metin(m['send_policy'], 'anyone'),
    etkin: mantik(m['enabled'], true),
    eklenme: tarihOku(m['created_at']),
  );
}

const gonderimIzinleri = {'anyone': 'Herkes', 'members': 'Yalnızca üyeler', 'internal': 'Yalnızca kurum içi'};

class Organizasyon {
  Organizasyon({
    required this.id,
    required this.ad,
    required this.durum,
    required this.bayiAdi,
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
  final String? bayiAdi, paketAdi;
  final int? enFazlaAlan, enFazlaKutu, toplamKota;
  final int alanSayisi, kutuSayisi, ayrilan, kullanilan;
  final DateTime? eklenme;
  final Map<String, dynamic> profil;
  final bool dahili;

  factory Organizasyon.coz(Map<String, dynamic> m) => Organizasyon(
    id: metin(m['id']),
    ad: metin(m['name']),
    durum: metin(m['status'], 'active'),
    bayiAdi: metinYa(m['reseller_name']),
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

/// Müşteri profili alanlarının Türkçe adları (gösterim sırası).
const profilAlanlari = <String, String>{
  'legal_name': 'Ticari unvan',
  'sector': 'Sektör',
  'website': 'Web sitesi',
  'contact_name': 'Yetkili',
  'contact_title': 'Yetkili unvanı',
  'contact_email': 'Yetkili e-postası',
  'contact_phone': 'Telefon',
  'contact_mobile': 'Cep telefonu',
  'tech_name': 'Teknik sorumlu',
  'tech_email': 'Teknik e-posta',
  'tech_phone': 'Teknik telefon',
  'billing_email': 'Fatura e-postası',
  'tax_office': 'Vergi dairesi',
  'tax_number': 'Vergi / TC kimlik no',
  'notes': 'Notlar',
};

class Bayi {
  const Bayi({required this.id, required this.ad, required this.durum, required this.musteriSayisi, required this.eklenme});
  final String id, ad, durum;
  final int musteriSayisi;
  final DateTime? eklenme;

  factory Bayi.coz(Map<String, dynamic> m) => Bayi(
    id: metin(m['id']),
    ad: metin(m['name']),
    durum: metin(m['status'], 'active'),
    musteriSayisi: tamsayi(m['organization_count']),
    eklenme: tarihOku(m['created_at']),
  );
}

class PanelOturumu {
  const PanelOturumu({
    required this.id,
    required this.ip,
    required this.tarayici,
    required this.olusturma,
    required this.sonGorulme,
    required this.gecerli,
    required this.musteriGorunumu,
  });
  final String id, tarayici;
  final String? ip, musteriGorunumu;
  final DateTime? olusturma, sonGorulme;
  final bool gecerli;

  factory PanelOturumu.coz(Map<String, dynamic> m) => PanelOturumu(
    id: metin(m['id']),
    ip: metinYa(m['ip']),
    tarayici: metin(m['user_agent']),
    olusturma: tarihOku(m['created_at']),
    sonGorulme: tarihOku(m['last_seen_at']),
    gecerli: mantik(m['current']),
    musteriGorunumu: metinYa(m['customer_view']),
  );
}

class DenetimKaydi {
  const DenetimKaydi({
    required this.id,
    required this.zaman,
    required this.aktor,
    required this.eylem,
    required this.hedefTuru,
    required this.hedefId,
    required this.orgAdi,
    required this.ip,
    required this.ayrintilar,
    required this.taklitci,
  });
  final int id;
  final DateTime? zaman;
  final String aktor, eylem, hedefTuru, hedefId;
  final String? orgAdi, ip, taklitci;
  final Map<String, dynamic> ayrintilar;

  factory DenetimKaydi.coz(Map<String, dynamic> m) => DenetimKaydi(
    id: tamsayi(m['id']),
    zaman: tarihOku(m['at']),
    aktor: metin(m['actor_email']),
    eylem: metin(m['action']),
    hedefTuru: metin(m['target_type']),
    hedefId: metin(m['target_id']),
    orgAdi: metinYa(m['organization_name']),
    ip: metinYa(m['ip']),
    ayrintilar: harita(m['details']),
    taklitci: metinYa(m['impersonator_email']),
  );
}
