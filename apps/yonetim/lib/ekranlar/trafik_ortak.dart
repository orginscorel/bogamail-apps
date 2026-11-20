// Posta trafiği ekranlarının ortak modelleri ve parçaları (Mesaj Takibi, Teslimat Sorunları, Teslim Teşhisi...).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../veri/json.dart';
import '../ortak/simgeler.dart';

/// Sunucunun olay açıklaması (explain.go Explanation): kısa etiket, ton, özet ve öneri.
class Aciklama {
  const Aciklama({this.durum = '', this.etiket = '', this.ton = 'info', this.ozet = '', this.oneri = ''});
  final String durum, etiket, ton, ozet, oneri;

  factory Aciklama.coz(Object? v) {
    final m = harita(v);
    return Aciklama(durum: metin(m['status']), etiket: metin(m['label']), ton: metin(m['tone'], 'info'), ozet: metin(m['summary']), oneri: metin(m['fix']));
  }
}

/// ok | warn | bad | info tonunun rengi.
Color tonRengi(String ton) => switch (ton) {
  'ok' => Marka.zumrut,
  'warn' => Marka.kehribar,
  'bad' => Marka.gul,
  _ => Marka.mavi,
};

/// İzleme durumu (ok | warn | fail | unknown | info | unchecked) rengi ve etiketi.
Color izlemeRengi(String d) => switch (d) {
  'ok' => Marka.zumrut,
  'warn' => Marka.kehribar,
  'fail' => Marka.gul,
  'info' => Marka.mavi,
  _ => const Color(0xFF94A3B8),
};

String izlemeEtiketi(String d) => switch (d) {
  'ok' => 'Sorunsuz',
  'warn' => 'Uyarı',
  'fail' => 'Sorun',
  'unknown' => 'Belirsiz',
  'info' => 'Bilgi',
  'unchecked' => 'Denetlenmedi',
  _ => d,
};

class IzlemeRozeti extends StatelessWidget {
  const IzlemeRozeti(this.durum, {super.key});
  final String durum;
  @override
  Widget build(BuildContext context) => Rozet(izlemeEtiketi(durum), renk: izlemeRengi(durum));
}

/// Kısa renkli açıklama etiketi ("Teslim edildi", "Reddedildi (spam)").
class AciklamaRozeti extends StatelessWidget {
  const AciklamaRozeti(this.a, {super.key});
  final Aciklama a;
  @override
  Widget build(BuildContext context) {
    final renk = tonRengi(a.ton);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: renk.withValues(alpha: .13), borderRadius: BorderRadius.circular(8)),
      child: Text(
        a.etiket.isEmpty ? (a.durum.isEmpty ? '—' : a.durum) : a.etiket,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: renk, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Açıklamanın tamamı: ne oldu ve varsa ne yapılmalı.
class AciklamaMetni extends StatelessWidget {
  const AciklamaMetni(this.a, {super.key});
  final Aciklama a;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (a.ozet.isNotEmpty) SelectableText(a.ozet, style: const TextStyle(fontSize: 13.5, height: 1.35)),
        if (a.oneri.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(SimgelerKalin.lightbulbOutline, size: 15, color: Marka.kehribar),
                const SizedBox(width: 8),
                Expanded(child: Text(a.oneri, style: TextStyle(color: r.soluk, fontSize: 12.5, height: 1.35))),
              ],
            ),
          ),
      ],
    );
  }
}

/// Milisaniyeyi okunur yazar ("850 ms", "4,2 sn", "3 dk", "1,5 sa").
String msYaz(num? ms) {
  if (ms == null) return '—';
  String bir(double v) {
    final s = v.toStringAsFixed(1);
    return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s).replaceAll('.', ',');
  }

  if (ms < 1000) return '${ms.round()} ms';
  if (ms < 60000) return '${bir(ms / 1000)} sn';
  if (ms < 3600000) return '${(ms / 60000).round()} dk';
  return '${bir(ms / 3600000)} sa';
}

/// Mesaj takibi olayı (ops.go MailEvent).
class PostaOlayi {
  const PostaOlayi({
    required this.id,
    this.zaman,
    this.kuyrukId = '',
    this.yon = '',
    this.olay = '',
    this.asama = '',
    this.uzakIp,
    this.gonderen = '',
    this.alici = '',
    this.kurum,
    this.smtpKodu,
    this.genisKod = '',
    this.neden = '',
    this.boyut,
    this.spamPuani,
    this.spamEylemi,
    this.spamKurallari = const [],
    this.toplu = false,
    this.mxSunucu,
    this.aciklama = const Aciklama(),
  });
  final int id;
  final DateTime? zaman;
  final String kuyrukId, yon, olay, asama, gonderen, alici, genisKod, neden;
  final String? uzakIp, kurum, spamEylemi, mxSunucu;
  final int? smtpKodu, boyut;
  final double? spamPuani;
  final List<String> spamKurallari;
  final bool toplu;
  final Aciklama aciklama;

  factory PostaOlayi.coz(Map<String, dynamic> m) => PostaOlayi(
    id: tamsayi(m['id']),
    zaman: tarihOku(m['at']),
    kuyrukId: metin(m['queue_id']),
    yon: metin(m['direction']),
    olay: metin(m['event']),
    asama: metin(m['stage']),
    uzakIp: metinYa(m['remote_ip']),
    gonderen: metin(m['mail_from']),
    alici: metin(m['rcpt']),
    kurum: metinYa(m['organization_name']),
    smtpKodu: tamsayiYa(m['smtp_code']),
    genisKod: metin(m['enhanced_code']),
    neden: metin(m['reason']),
    boyut: tamsayiYa(m['size_bytes']),
    spamPuani: ondalikYa(m['spam_score']),
    spamEylemi: metinYa(m['spam_action']),
    spamKurallari: metinler(m['spam_rules']),
    toplu: mantik(m['bulk']),
    mxSunucu: metinYa(m['mx_host']),
    aciklama: Aciklama.coz(m['explain']),
  );

  bool get giden => yon == 'outbound';
  bool get spamli => spamEylemi != null && spamEylemi != 'inbox';
}

/// Küçük başlıklı bölüm başlığı (kart dışındaki alt bölümler).
class AltBaslik extends StatelessWidget {
  const AltBaslik(this.metin, {super.key, this.alt});
  final String metin;
  final String? alt;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metin, style: gosterim(17, agirlik: FontWeight.w600)),
        if (alt != null) Text(alt!, style: TextStyle(color: context.r.silik, fontSize: 12.5)),
      ],
    ),
  );
}
