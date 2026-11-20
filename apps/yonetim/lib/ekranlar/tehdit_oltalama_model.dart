import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../veri/json.dart';

// Oltalama simülasyonu API modelleri (internal/api/phishing*.go).

/// Huni sayıları (phishFunnel).
class OltaHunisi {
  const OltaHunisi({
    this.hedef = 0,
    this.bekleyen = 0,
    this.teslim = 0,
    this.acilan = 0,
    this.tiklayan = 0,
    this.formGonderen = 0,
    this.bildiren = 0,
    this.atlanan = 0,
  });
  final int hedef, bekleyen, teslim, acilan, tiklayan, formGonderen, bildiren, atlanan;

  factory OltaHunisi.coz(Map<String, dynamic> m) => OltaHunisi(
    hedef: tamsayi(m['targets']),
    bekleyen: tamsayi(m['pending']),
    teslim: tamsayi(m['delivered']),
    acilan: tamsayi(m['opened']),
    tiklayan: tamsayi(m['clicked']),
    formGonderen: tamsayi(m['submitted']),
    bildiren: tamsayi(m['reported']),
    atlanan: tamsayi(m['skipped']),
  );

  /// Teslim edilenlere göre yüzde (web: pct).
  int yuzde(int n) => teslim == 0 ? 0 : (n / teslim * 100).round();
}

class OltaSablon {
  const OltaSablon({
    required this.anahtar,
    required this.hazir,
    required this.ad,
    required this.senaryo,
    required this.gonderenAdi,
    required this.gonderenYerel,
    required this.gonderenAlan,
    required this.konu,
    required this.govde,
    required this.baglantiMetni,
    required this.isaretler,
  });
  final String anahtar, ad, senaryo, gonderenAdi, gonderenYerel, gonderenAlan, konu, govde, baglantiMetni;
  final bool hazir;
  final List<String> isaretler;

  factory OltaSablon.coz(Map<String, dynamic> m) => OltaSablon(
    anahtar: metin(m['key']),
    hazir: mantik(m['builtin']),
    ad: metin(m['name']),
    senaryo: metin(m['scenario']),
    gonderenAdi: metin(m['from_name']),
    gonderenYerel: metin(m['from_local']),
    gonderenAlan: metin(m['from_domain']),
    konu: metin(m['subject']),
    govde: metin(m['body']),
    baglantiMetni: metin(m['link_text']),
    isaretler: metinler(m['signs']),
  );

  String get gonderen => '$gonderenAdi <$gonderenYerel@${gonderenAlan.isEmpty ? 'alıcının alan adı' : gonderenAlan}>';
}

class OltaKampanya {
  const OltaKampanya({
    required this.id,
    required this.ad,
    required this.sablonAdi,
    required this.acilis,
    required this.acilmaIzle,
    required this.hedefKipi,
    required this.baslangic,
    required this.yayma,
    required this.durum,
    required this.olusturan,
    required this.bitis,
    required this.huni,
  });
  final String id, ad, sablonAdi, acilis, hedefKipi, durum, olusturan;
  final bool acilmaIzle;
  final DateTime? baslangic, bitis;
  final int yayma;
  final OltaHunisi huni;

  bool get etkin => durum == 'scheduled' || durum == 'running';

  factory OltaKampanya.coz(Map<String, dynamic> m) => OltaKampanya(
    id: metin(m['id']),
    ad: metin(m['name']),
    sablonAdi: metin(m['template_name']),
    acilis: metin(m['landing']),
    acilmaIzle: mantik(m['track_opens']),
    hedefKipi: metin(m['target_mode']),
    baslangic: tarihOku(m['start_at']),
    yayma: tamsayi(m['spread_hours']),
    durum: metin(m['status']),
    olusturan: metin(m['created_by']),
    bitis: tarihOku(m['finished_at']),
    huni: OltaHunisi.coz(harita(m['funnel'])),
  );
}

class OltaHedef {
  const OltaHedef({
    required this.id,
    required this.adres,
    required this.ad,
    required this.durum,
    required this.tiklama,
    required this.tiklamaSayisi,
    required this.formGonderdi,
    required this.bildirim,
    required this.sonHata,
  });
  final String id, adres, ad, durum;
  final DateTime? tiklama, bildirim;
  final int tiklamaSayisi;
  final bool formGonderdi;
  final String? sonHata;

  factory OltaHedef.coz(Map<String, dynamic> m) => OltaHedef(
    id: metin(m['id']),
    adres: metin(m['address']),
    ad: metin(m['display_name']),
    durum: metin(m['status']),
    tiklama: tarihOku(m['clicked_at']),
    tiklamaSayisi: tamsayi(m['click_count']),
    formGonderdi: mantik(m['credential_submitted']),
    bildirim: tarihOku(m['reported_at']),
    sonHata: metinYa(m['last_error']),
  );
}

class OltaBildirim {
  const OltaBildirim({required this.id, required this.bildiren, required this.gonderen, required this.konu, required this.spam, required this.durum, required this.zaman, required this.inceleyen});
  final String id, bildiren, gonderen, konu, durum;
  final double? spam;
  final DateTime? zaman;
  final String? inceleyen;

  factory OltaBildirim.coz(Map<String, dynamic> m) => OltaBildirim(
    id: metin(m['id']),
    bildiren: metin(m['reporter']),
    gonderen: metin(m['from']),
    konu: metin(m['subject']),
    spam: ondalikYa(m['spam_score']),
    durum: metin(m['status']),
    zaman: tarihOku(m['created_at']),
    inceleyen: metinYa(m['reviewed_by']),
  );
}

const kampanyaDurumEtiketi = {'scheduled': 'Planlandı', 'running': 'Sürüyor', 'completed': 'Tamamlandı', 'cancelled': 'İptal edildi'};
const hedefDurumEtiketi = {'pending': 'Bekliyor', 'delivered': 'Teslim edildi', 'skipped': 'Atlandı', 'cancelled': 'İptal', 'failed': 'Başarısız'};

Color kampanyaDurumRengi(String d) => switch (d) {
  'running' => Marka.mor,
  'completed' => Marka.zumrut,
  'cancelled' => Colors.blueGrey,
  _ => Marka.kehribar,
};

/// Medyan dakika → okunur süre (web: minutes).
String dakikaYaz(double? v) {
  if (v == null) return '—';
  if (v < 60) return '${v.round().clamp(0, 59)} dk';
  if (v < 48 * 60) return '${(v / 60).toStringAsFixed(1).replaceAll('.', ',')} sa';
  return '${(v / 1440).round()} gün';
}

/// Huni çubukları: teslim, açılma, tıklama, form, bildirim (teslim edilenlere oranla).
class HuniCubuklari extends StatelessWidget {
  const HuniCubuklari(this.f, {super.key});
  final OltaHunisi f;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final satirlar = [
      ('Teslim edildi', f.teslim, r.silik),
      ('Açıldı (yaklaşık)', f.acilan, Marka.morAcik),
      ('Bağlantıya tıkladı', f.tiklayan, Marka.kehribar),
      ('Formu gönderdi', f.formGonderen, Marka.gul),
      ('Bildirdi', f.bildiren, Marka.zumrut),
    ];
    return Column(
      children: [
        for (final (e, n, renk) in satirlar)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 13)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: f.teslim == 0 ? 0 : (n / f.teslim).clamp(0, 1).toDouble(),
                      minHeight: 9,
                      backgroundColor: r.ic,
                      color: renk,
                    ),
                  ),
                ),
                SizedBox(
                  width: 78,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$n ', style: const TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(text: '%${f.yuzde(n)}', style: TextStyle(color: r.silik, fontSize: 11.5)),
                      ],
                    ),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
