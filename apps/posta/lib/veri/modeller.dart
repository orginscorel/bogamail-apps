// Sunucunun JSON yanıtları için tipli modeller. Hepsi hoşgörülü: eksik/yanlış tipli alanlar çökmeye yol açmaz.

import 'yardimci.dart';

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
bool _b(Object? v) => v == true;
DateTime? _t(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _l(Object? v) => v is List ? v : const [];

/// GET /api/v1/mail/folders → items[]
class Klasor {
  Klasor({required this.id, required this.ad, this.rol, this.toplam = 0, this.okunmamis = 0});
  final String id;
  final String ad;
  final String? rol; // inbox snoozed drafts sent archive templates junk trash | null (kullanıcı klasörü)
  final int toplam;
  final int okunmamis;

  factory Klasor.json(Object? v) {
    final m = _m(v);
    final rol = m['role'];
    return Klasor(id: _s(m['id']), ad: _s(m['name']), rol: rol is String && rol.isNotEmpty ? rol : null, toplam: _i(m['total']), okunmamis: _i(m['unseen']));
  }

  bool get sistem => rol != null;
  String get gorunenAd => klasorAdi(rol, ad);
}

/// GET /api/v1/mail/labels → items[]
class Etiket {
  Etiket({required this.id, required this.ad, this.renk = 'gray', this.toplam = 0, this.okunmamis = 0});
  final String id;
  final String ad;
  final String renk; // blue green purple orange red yellow teal gray
  final int toplam;
  final int okunmamis;

  factory Etiket.json(Object? v) {
    final m = _m(v);
    return Etiket(
      id: _s(m['id']),
      ad: _s(m['name']),
      renk: _s(m['color']).isEmpty ? 'gray' : _s(m['color']),
      toplam: _i(m['total']),
      okunmamis: _i(m['unseen']),
    );
  }
}

/// Liste satırı (mailSummary).
class IletiOzet {
  IletiOzet({
    required this.id,
    this.klasorId = '',
    this.konu = '',
    this.kimden = '',
    this.kime = '',
    this.tarih,
    this.boyut = 0,
    this.okundu = false,
    this.yildizli = false,
    this.onemli = false,
    this.yanitlandi = false,
    this.iletildi = false,
    this.onizleme = '',
    this.ekVar = false,
    this.etiketler = const [],
    this.ertelemeBitis,
    this.klasorRolu,
    this.takip = false,
  });

  final String id;
  final String klasorId;
  final String konu;
  final String kimden;
  final String kime;
  final DateTime? tarih;
  final int boyut;
  bool okundu;
  bool yildizli;
  bool onemli;
  final bool yanitlandi;
  final bool iletildi;
  final String onizleme;
  final bool ekVar;
  List<String> etiketler;
  final DateTime? ertelemeBitis;
  final String? klasorRolu;
  final bool takip;

  factory IletiOzet.json(Object? v) {
    final m = _m(v);
    final rol = m['folder_role'];
    return IletiOzet(
      id: _s(m['id']),
      klasorId: _s(m['folder_id']),
      konu: _s(m['subject']),
      kimden: _s(m['from']),
      kime: _s(m['to']),
      tarih: _t(m['date']),
      boyut: _i(m['size']),
      okundu: _b(m['seen']),
      yildizli: _b(m['flagged']),
      onemli: _b(m['important']),
      yanitlandi: _b(m['answered']),
      iletildi: _b(m['forwarded']),
      onizleme: _s(m['preview']),
      ekVar: _b(m['has_attachments']),
      etiketler: _l(m['labels']).map(_s).toList(),
      ertelemeBitis: _t(m['snoozed_until']),
      klasorRolu: rol is String && rol.isNotEmpty ? rol : null,
      takip: _b(m['followup']),
    );
  }

  /// Gönderilenler/Taslaklar'da karşı taraf alıcıdır.
  bool get gidenMi => klasorRolu == 'sent' || klasorRolu == 'drafts' || klasorRolu == 'templates';
}

/// Sayfalı liste yanıtı.
class Sayfa {
  Sayfa(this.ogeler, this.toplam, this.sayfa, this.boyut);
  final List<IletiOzet> ogeler;
  final int toplam;
  final int sayfa;
  final int boyut;

  factory Sayfa.json(Object? v) {
    final m = _m(v);
    return Sayfa(_l(m['items']).map(IletiOzet.json).toList(), _i(m['total']), _i(m['page']), _i(m['page_size']));
  }
}

class Adres {
  const Adres(this.ad, this.eposta);
  final String ad;
  final String eposta;

  factory Adres.json(Object? v) {
    final m = _m(v);
    return Adres(_s(m['name']), _s(m['email']));
  }

  String get gorunen => ad.isNotEmpty ? ad : eposta;
  String get bicimli => adresYaz(this);

  @override
  bool operator ==(Object other) => other is Adres && other.eposta.toLowerCase() == eposta.toLowerCase();
  @override
  int get hashCode => eposta.toLowerCase().hashCode;
}

class Ek {
  Ek({required this.sira, this.dosyaAdi = '', this.tur = '', this.boyut = 0, this.satirIci = false, this.icerikId = ''});
  final int sira;
  final String dosyaAdi;
  final String tur;
  final int boyut;
  final bool satirIci;
  final String icerikId;

  factory Ek.json(Object? v) {
    final m = _m(v);
    return Ek(
      sira: _i(m['index']),
      dosyaAdi: _s(m['filename']),
      tur: _s(m['content_type']),
      boyut: _i(m['size']),
      satirIci: _b(m['inline']),
      icerikId: _s(m['content_id']),
    );
  }

  String get ad => dosyaAdi.isNotEmpty ? dosyaAdi : 'ek-$sira';
  bool get davetiye => RegExp(r'^(text/calendar|application/ics)', caseSensitive: false).hasMatch(tur) || ad.toLowerCase().endsWith('.ics');
}

/// İletinin ayrıştırılmış hâli (mailview.View).
class IletiGorunum {
  IletiGorunum({
    this.konu = '',
    this.kimden = const [],
    this.kime = const [],
    this.bilgi = const [],
    this.yanitAdresi = const [],
    this.tarih,
    this.mesajKimligi = '',
    this.metin = '',
    this.html = '',
    this.kesik = false,
    this.ekler = const [],
  });

  final String konu;
  final List<Adres> kimden;
  final List<Adres> kime;
  final List<Adres> bilgi;
  final List<Adres> yanitAdresi;
  final DateTime? tarih;
  final String mesajKimligi;
  final String metin;
  final String html;
  final bool kesik;
  final List<Ek> ekler;

  factory IletiGorunum.json(Object? v) {
    final m = _m(v);
    List<Adres> a(Object? x) => _l(x).map(Adres.json).where((e) => e.eposta.isNotEmpty || e.ad.isNotEmpty).toList();
    return IletiGorunum(
      konu: _s(m['subject']),
      kimden: a(m['from']),
      kime: a(m['to']),
      bilgi: a(m['cc']),
      yanitAdresi: a(m['reply_to']),
      tarih: _t(m['date']),
      mesajKimligi: _s(m['message_id']),
      metin: _s(m['text']),
      html: _s(m['html']),
      kesik: _b(m['truncated']),
      ekler: _l(m['attachments']).map(Ek.json).toList(),
    );
  }

  List<Ek> get dosyaEkleri => ekler.where((e) => !e.satirIci).toList();
}

/// GET /api/v1/mail/messages/{id}
class IletiDetay {
  IletiDetay({required this.ozet, required this.gorunum, this.tehditler = const [], this.baglantilar = const {}});
  final IletiOzet ozet;
  final IletiGorunum gorunum;

  /// Gelen tarama uyarıları (banner metinleri).
  final List<String> tehditler;

  /// Özgün bağlantı → imzalı tıklama bağlantısı (gelişmiş tehdit koruması açıksa).
  final Map<String, String> baglantilar;

  factory IletiDetay.json(Object? v) {
    final m = _m(v);
    final b = _m(m['links']);
    return IletiDetay(
      ozet: IletiOzet.json(m['message']),
      gorunum: IletiGorunum.json(m['view']),
      tehditler: _l(m['threats']).map((t) => _s(_m(t)['banner'])).where((s) => s.isNotEmpty).toList(),
      baglantilar: b.map((k, v) => MapEntry(k, _s(v))),
    );
  }
}

/// GET /api/v1/mail/settings
class PostaAyarlari {
  PostaAyarlari({
    this.gorunenAd = '',
    this.imza = '',
    this.imzaHtml = '',
    this.sayfaBoyutu = 50,
    this.tatilAcik = false,
    this.tatilKonu = '',
    this.tatilMetin = '',
    this.tatilBaslangic,
    this.tatilBitis,
    this.geriAlmaSaniye = 0,
    this.ozellikler = const {},
    this.azamiEk = 0,
    this.azamiIleti = 0,
    this.azamiImza = 0,
    this.etkinImzaHtml = '',
    this.imzaKilitli = false,
    this.imzaKurumdan = false,
    this.sunucu = '',
    this.bildirimMasaustu = true,
    this.bildirimSes = true,
    this.bicimliYazma = true,
    this.okumaAlani = 'right',
  });

  /// reading_pane: okuma alanının yeri — right (Sağda, varsayılan) | bottom (Altta) | off (Kapalı). Web ile ortak.
  final String okumaAlani;

  /// compose_html: yeni iletiler biçimli (HTML) düzenleyicide mi başlar (web ile ortak ayar).
  final bool bicimliYazma;

  /// notify_desktop / notify_sound (webmail ile ortak; yerel bildirimler de uyar).
  final bool bildirimMasaustu;
  final bool bildirimSes;

  final String gorunenAd;
  final String imza;
  final String imzaHtml;
  final int sayfaBoyutu;
  final bool tatilAcik;
  final String tatilKonu;
  final String tatilMetin;
  final String? tatilBaslangic; // YYYY-AA-GG
  final String? tatilBitis;
  final int geriAlmaSaniye;
  final Map<String, bool> ozellikler;
  final int azamiEk;
  final int azamiIleti;

  /// Biçimli imzanın (görseller dahil) azami boyutu.
  final int azamiImza;

  /// Etkin imza (kurum şablonu veya kendi imzası, değişkenler doldurulmuş).
  final String etkinImzaHtml;
  final bool imzaKilitli;
  final bool imzaKurumdan;

  /// İstemci bağlantı sunucusu (IMAP/SMTP ana makinesi).
  final String sunucu;

  factory PostaAyarlari.json(Object? v) {
    final m = _m(v);
    final s = _m(m['settings']);
    final f = _m(m['features']);
    final l = _m(m['limits']);
    final g = m['signature'] is Map ? _m(m['signature']) : null;
    final baglanti = _m(m['connection']);
    String? tarih(Object? x) => x is String && x.isNotEmpty ? x : null;
    // Eski sunucularda etkin imza yok: kendi imzasından türetilir (web ile aynı).
    var etkin = '';
    if (g != null) {
      etkin = _s(g['html']).trim();
    } else if (_s(s['signature_html']).trim().isNotEmpty) {
      etkin = _s(s['signature_html']).trim();
    } else if (_s(s['signature']).trim().isNotEmpty) {
      etkin = metindenHtml(_s(s['signature']).trim());
    }
    return PostaAyarlari(
      gorunenAd: _s(s['display_name']),
      imza: _s(s['signature']),
      imzaHtml: _s(s['signature_html']),
      sayfaBoyutu: _i(s['page_size']) > 0 ? _i(s['page_size']) : 50,
      tatilAcik: _b(s['vacation_enabled']),
      tatilKonu: _s(s['vacation_subject']),
      tatilMetin: _s(s['vacation_body']),
      tatilBaslangic: tarih(s['vacation_start']),
      tatilBitis: tarih(s['vacation_end']),
      geriAlmaSaniye: _i(s['undo_send_seconds']),
      ozellikler: f.map((k, v) => MapEntry(k, v == true)),
      azamiEk: _i(_m(l['max_attachment_bytes'])['bytes']),
      azamiIleti: _i(_m(l['max_message_bytes'])['bytes']),
      azamiImza: _i(_m(l['max_signature_bytes'])['bytes']),
      etkinImzaHtml: etkin,
      imzaKilitli: g != null && _b(g['locked']),
      imzaKurumdan: g != null && _b(g['from_org']),
      sunucu: _s(baglanti['host']),
      bildirimMasaustu: s['notify_desktop'] == null || _b(s['notify_desktop']),
      bildirimSes: s['notify_sound'] == null || _b(s['notify_sound']),
      bicimliYazma: s['compose_html'] == null || _b(s['compose_html']),
      okumaAlani: const {'right', 'bottom', 'off'}.contains(s['reading_pane']) ? s['reading_pane'] as String : 'right',
    );
  }

  bool ozellik(String ad) => ozellikler[ad] ?? true;
}

/// GET /api/v1/mail/contacts/suggest → items[]
class Oneri {
  const Oneri(this.ad, this.eposta, this.kaynak);
  final String ad;
  final String eposta;
  final String kaynak; // contact | recent | colleague

  factory Oneri.json(Object? v) {
    final m = _m(v);
    return Oneri(_s(m['name']), _s(m['email']), _s(m['source']));
  }

  Adres get adres => Adres(ad, eposta);
}

/// Canlı olay (GET /api/v1/mail/stream, "mail" olayı).
class CanliOlay {
  CanliOlay(this.tur, this.veri);
  final String tur; // new_mail | changed | scheduled | ...
  final Map<String, dynamic> veri;

  factory CanliOlay.json(Object? v) {
    final m = _m(v);
    return CanliOlay(_s(m['kind']), _m(m['data']));
  }
}

/// DLP ayrıntısı (422 dlp_warning | dlp_blocked).
class DlpRapor {
  DlpRapor({required this.engel, required this.mesaj, this.politikalar = const [], this.eslesmeler = const [], this.taranamayan = const []});
  final bool engel;
  final String mesaj;
  final List<String> politikalar;
  final List<DlpEslesme> eslesmeler;
  final List<String> taranamayan;

  factory DlpRapor.json(Map<String, dynamic> e) {
    return DlpRapor(
      engel: _s(e['code']) == 'dlp_blocked',
      mesaj: _s(e['message']),
      politikalar: _l(e['policies']).map((p) => _s(_m(p)['name'])).where((s) => s.isNotEmpty).toList(),
      eslesmeler: _l(e['matches']).map(DlpEslesme.json).toList(),
      taranamayan: _l(e['unscanned']).map((u) {
        final m = _m(u);
        return '${_s(m['name'])}: ${_s(m['reason'])}';
      }).toList(),
    );
  }
}

class DlpEslesme {
  DlpEslesme(this.dedektor, this.kural, this.adet, this.ornekler);
  final String dedektor;
  final String kural;
  final int adet;
  final List<String> ornekler;

  factory DlpEslesme.json(Object? v) {
    final m = _m(v);
    return DlpEslesme(_s(m['detector']), _s(m['rule']), _i(m['count']), _l(m['samples']).map(_s).toList());
  }

  static const _adlar = {
    'tckn': 'T.C. kimlik no',
    'card': 'Kart numarası',
    'iban': 'IBAN',
    'phone_tr': 'Cep telefonu',
    'email_list': 'E-posta adresi listesi',
    'custom': 'Özel kural',
  };

  String get baslik => kural.isNotEmpty ? 'Özel kural: $kural' : (_adlar[dedektor] ?? dedektor);
}

/// POST /api/v1/mail/send yanıtı.
class GonderimSonucu {
  GonderimSonucu({this.planId, this.geriAlinabilir = false, this.geriAlmaSaniye = 0, this.planZamani, this.bekletme});
  final String? planId;
  final bool geriAlinabilir;
  final int geriAlmaSaniye;
  final DateTime? planZamani;
  final String? bekletme; // abuse/DLP onayı bekleniyor bildirimi

  factory GonderimSonucu.json(Object? v) {
    final m = _m(v);
    final h = m['held'] is Map ? _m(m['held']) : null;
    final sid = _s(m['scheduled_id']);
    return GonderimSonucu(
      planId: sid.isEmpty ? null : sid,
      geriAlinabilir: _b(m['undo']),
      geriAlmaSaniye: _i(m['undo_seconds']),
      planZamani: _t(m['send_at']),
      bekletme: h == null ? null : _s(h['notice']),
    );
  }
}

/// GET /api/v1/mail/search/operators
class AramaIsleci {
  const AramaIsleci(this.anahtar, this.ornek, this.ipucu);
  final String anahtar;
  final String ornek;
  final String ipucu;

  factory AramaIsleci.json(Object? v) {
    final m = _m(v);
    return AramaIsleci(_s(m['Key'] ?? m['key']), _s(m['Example'] ?? m['example']), _s(m['Hint'] ?? m['hint']));
  }
}
