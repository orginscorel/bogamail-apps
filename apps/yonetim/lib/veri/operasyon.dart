// Operasyon nesneleri: özet, trafik, kuyruk, bekletilenler, karantina, alarmlar, sunucu erişimi.

import 'json.dart';

class Ozet {
  Ozet(this.m);
  final Map<String, dynamic> m;

  int get musteriler => tamsayi(m['organizations']);
  int get alanlar => tamsayi(m['domains']);
  int get bekleyenAlanlar => tamsayi(m['domains_pending']);
  int get gatewayAlanlari => tamsayi(m['gateway_domains']);
  int get kutular => tamsayi(m['mailboxes']);
  int get aktifKutular => tamsayi(m['active_mailboxes']);
  int get ayrilan => tamsayi(m['allocated_bytes']);
  int get kullanilan => tamsayi(m['used_bytes']);
  int? get alinan => tamsayiYa(m['messages_received_today']);
  int? get reddedilen => tamsayiYa(m['rejected_messages']);
  int? get teslim => tamsayiYa(m['delivered_today']);
  int? get basarisiz => tamsayiYa(m['failed_today']);
  int? get kuyruk => tamsayiYa(m['queue_depth']);
  int? get gonderilen => tamsayiYa(m['messages_sent_today']);
  int? get gateway => tamsayiYa(m['gateway_relayed_today']);
  int? get spam => tamsayiYa(m['spam_blocked']);
  double? get teslimOrani => ondalikYa(m['delivery_success_rate']);
  Map<String, String> get yok => harita(m['unavailable']).map((k, v) => MapEntry(k, metin(v)));
}

class TrafikDilimi {
  const TrafikDilimi(this.saat, this.kabul, this.ret, this.teslim, this.hata, this.erteleme);
  final DateTime saat;
  final int kabul, ret, teslim, hata, erteleme;

  static List<TrafikDilimi> coz(Object? v) => [
    for (final m in haritalar(harita(v)['items']))
      if (tarihOku(m['hour']) != null)
        TrafikDilimi(
          tarihOku(m['hour'])!,
          tamsayi(m['accepted']),
          tamsayi(m['rejected']),
          tamsayi(m['delivered']),
          tamsayi(m['failed']),
          tamsayi(m['deferred']),
        ),
  ];
}

class KuyrukOgesi {
  const KuyrukOgesi({
    required this.kimlik,
    required this.yon,
    required this.gonderen,
    required this.alicilar,
    required this.alinma,
    required this.boyut,
    required this.durum,
    required this.deneme,
    required this.sonrakiDeneme,
    required this.sonHata,
    required this.orgAdi,
    required this.hataSinifi,
    required this.yasSn,
    required this.sinif,
    required this.frenNedeni,
  });
  final String kimlik, yon, gonderen, durum, sonHata, orgAdi, hataSinifi, sinif, frenNedeni;
  final List<String> alicilar;
  final DateTime? alinma, sonrakiDeneme;
  final int boyut, deneme, yasSn;

  bool get giden => yon == 'outbound';

  factory KuyrukOgesi.coz(Map<String, dynamic> m) => KuyrukOgesi(
    kimlik: metin(m['queue_id']),
    yon: metin(m['direction']),
    gonderen: metin(m['from']),
    alicilar: metinler(m['recipients']),
    alinma: tarihOku(m['received_at']),
    boyut: tamsayi(m['size_bytes']),
    durum: metin(m['status'], 'pending'),
    deneme: tamsayi(m['attempts']),
    sonrakiDeneme: tarihOku(m['next_retry']),
    sonHata: metin(m['last_error']),
    orgAdi: metin(m['organization_name']),
    hataSinifi: metin(m['error_class']),
    yasSn: tamsayi(m['age_seconds']),
    sinif: metin(m['class']),
    frenNedeni: metin(m['hold_reason']),
  );
}

class KuyrukYaniti {
  KuyrukYaniti(this.m)
    : ogeler = haritalar(m['items']).map(KuyrukOgesi.coz).toList(),
      hataSiniflari = {for (final c in haritalar(m['error_class_labels'])) metin(c['key']): metin(c['label'])};
  final Map<String, dynamic> m;
  final List<KuyrukOgesi> ogeler;
  final Map<String, String> hataSiniflari;

  bool get etkin => mantik(m['enabled'], true);
  bool get kapsamli => mantik(m['scoped']);
  bool get yonetebilir => mantik(m['can_manage']);
  int get eslesen => tamsayi(m['matched'], ogeler.length);
  Map<String, dynamic> get istatistik => harita(m['stats']);
  bool get istatistikVar => m['stats'] is Map;
  List<(String, String, int)> get hataSayilari => [
    for (final c in haritalar(istatistik['error_classes'])) (metin(c['key']), metin(c['label']), tamsayi(c['count'])),
  ];
}

class Bekletilen {
  const Bekletilen({
    required this.id,
    required this.kaynak,
    required this.orgAdi,
    required this.gonderen,
    required this.aliciSayisi,
    required this.disSayisi,
    required this.konu,
    required this.boyut,
    required this.puan,
    required this.neden,
    required this.koken,
    required this.durum,
    required this.olusturma,
    required this.bitis,
    required this.kararVeren,
  });
  final String id, kaynak, orgAdi, gonderen, konu, neden, koken, durum;
  final int aliciSayisi, disSayisi, boyut;
  final double puan;
  final DateTime? olusturma, bitis;
  final String? kararVeren;

  factory Bekletilen.coz(Map<String, dynamic> m) => Bekletilen(
    id: metin(m['id']),
    kaynak: metin(m['source'], 'abuse'),
    orgAdi: metin(m['organization_name']),
    gonderen: metin(m['from']),
    aliciSayisi: tamsayi(m['to_count']),
    disSayisi: tamsayi(m['external_count']),
    konu: metin(m['subject_preview']),
    boyut: tamsayi(m['size_bytes']),
    puan: ondalik(m['score']),
    neden: metin(m['reason']),
    koken: metin(m['origin']),
    durum: metin(m['status'], 'held'),
    olusturma: tarihOku(m['created_at']),
    bitis: tarihOku(m['expires_at']),
    kararVeren: metinYa(m['decided_by']),
  );
}

class Bulgu {
  const Bulgu(this.tur, this.ad, this.dosya, this.ayrinti);
  final String tur, ad, dosya, ayrinti;
}

class KarantinaOgesi {
  const KarantinaOgesi({
    required this.id,
    required this.kuyrukKimligi,
    required this.yon,
    required this.orgAdi,
    required this.zarfGonderen,
    required this.alicilar,
    required this.konu,
    required this.kimden,
    required this.neden,
    required this.bulgular,
    required this.spamPuani,
    required this.boyut,
    required this.durum,
    required this.olusturma,
    required this.bitis,
    required this.kararVeren,
    required this.kararZamani,
  });
  final String id, kuyrukKimligi, yon, zarfGonderen, konu, kimden, neden, durum;
  final String? orgAdi, kararVeren;
  final List<String> alicilar;
  final List<Bulgu> bulgular;
  final double? spamPuani;
  final int boyut;
  final DateTime? olusturma, bitis, kararZamani;

  factory KarantinaOgesi.coz(Map<String, dynamic> m) {
    final f = m['findings'];
    final liste = f is List ? f : harita(f)['findings'];
    return KarantinaOgesi(
      id: metin(m['id']),
      kuyrukKimligi: metin(m['queue_id']),
      yon: metin(m['direction']),
      orgAdi: metinYa(m['organization_name']),
      zarfGonderen: metin(m['mail_from']),
      alicilar: metinler(m['recipients']),
      konu: metin(m['subject']),
      kimden: metin(m['from_header']),
      neden: metin(m['reason']),
      bulgular: [for (final b in haritalar(liste)) Bulgu(metin(b['kind']), metin(b['name']), metin(b['file']), metin(b['detail']))],
      spamPuani: ondalikYa(m['spam_score']),
      boyut: tamsayi(m['size_bytes']),
      durum: metin(m['status'], 'held'),
      olusturma: tarihOku(m['created_at']),
      bitis: tarihOku(m['expires_at']),
      kararVeren: metinYa(m['decided_by']),
      kararZamani: tarihOku(m['decided_at']),
    );
  }
}

class EtkinAlarm {
  const EtkinAlarm({
    required this.kuralId,
    required this.ad,
    required this.tur,
    required this.onem,
    required this.konu,
    required this.etiket,
    required this.deger,
    required this.esik,
    required this.ayrinti,
    required this.baslangic,
  });
  final String kuralId, ad, tur, onem, konu, etiket, ayrinti;
  final double deger, esik;
  final DateTime? baslangic;

  bool get kritik => onem == 'critical';

  factory EtkinAlarm.coz(Map<String, dynamic> m) => EtkinAlarm(
    kuralId: metin(m['rule_id']),
    ad: metin(m['name']),
    tur: metin(m['kind']),
    onem: metin(m['severity'], 'warning'),
    konu: metin(m['subject']),
    etiket: metin(m['label']),
    deger: ondalik(m['value']),
    esik: ondalik(m['threshold']),
    ayrinti: metin(m['detail']),
    baslangic: tarihOku(m['since']),
  );
}

class AlarmOlayi {
  const AlarmOlayi({
    required this.id,
    required this.zaman,
    required this.orgAdi,
    required this.kuralAdi,
    required this.tur,
    required this.onem,
    required this.durum,
    required this.etiket,
    required this.deger,
    required this.esik,
    required this.ayrinti,
    required this.teslimler,
  });
  final int id;
  final DateTime? zaman;
  final String orgAdi, kuralAdi, tur, onem, durum, etiket, ayrinti;
  final double deger, esik;

  /// (kanal adı, başarılı mı, hata)
  final List<(String, bool, String)> teslimler;

  factory AlarmOlayi.coz(Map<String, dynamic> m) => AlarmOlayi(
    id: tamsayi(m['id']),
    zaman: tarihOku(m['at']),
    orgAdi: metin(m['organization_name']),
    kuralAdi: metin(m['rule_name']),
    tur: metin(m['kind']),
    onem: metin(m['severity'], 'warning'),
    durum: metin(m['status']),
    etiket: metin(m['label']),
    deger: ondalik(m['value']),
    esik: ondalik(m['threshold']),
    ayrinti: metin(m['detail']),
    teslimler: [for (final d in haritalar(m['deliveries'])) (metin(d['channel']), mantik(d['ok']), metin(d['error']))],
  );
}

class OtomatikYasak {
  const OtomatikYasak({required this.etkin, required this.esik, required this.pencereDk, required this.yasakSaat});
  final bool etkin;
  final int esik, pencereDk, yasakSaat;

  factory OtomatikYasak.coz(Object? v) {
    final m = harita(v);
    return OtomatikYasak(
      etkin: mantik(m['enabled']),
      esik: tamsayi(m['threshold'], 20),
      pencereDk: tamsayi(m['window_minutes'], 60),
      yasakSaat: tamsayi(m['ban_hours'], 24),
    );
  }

  Map<String, dynamic> json() => {'enabled': etkin, 'threshold': esik, 'window_minutes': pencereDk, 'ban_hours': yasakSaat};

  OtomatikYasak kopya({bool? etkin, int? esik, int? pencereDk, int? yasakSaat}) =>
      OtomatikYasak(etkin: etkin ?? this.etkin, esik: esik ?? this.esik, pencereDk: pencereDk ?? this.pencereDk, yasakSaat: yasakSaat ?? this.yasakSaat);
}

class IpYasagi {
  const IpYasagi({
    required this.ip,
    required this.neden,
    required this.otomatik,
    required this.yasaklayan,
    required this.olusturma,
    required this.bitis,
    required this.panelden,
  });
  final String ip, neden, yasaklayan;
  final bool otomatik, panelden;
  final DateTime? olusturma, bitis;

  factory IpYasagi.coz(Map<String, dynamic> m) => IpYasagi(
    ip: metin(m['ip']),
    neden: metin(m['reason']),
    otomatik: mantik(m['auto']),
    yasaklayan: metin(m['created_by']),
    olusturma: tarihOku(m['created_at']),
    bitis: tarihOku(m['expires_at']),
    panelden: mantik(m['managed'], true),
  );
}

class SshKaynagi {
  const SshKaynagi({
    required this.ip,
    required this.engellenen,
    required this.hatali,
    required this.olmayanKullanici,
    required this.basarili,
    required this.kullanicilar,
    required this.sonGorulme,
    required this.yasakli,
    required this.izinli,
  });
  final String ip;
  final int engellenen, hatali, olmayanKullanici, basarili;
  final List<String> kullanicilar;
  final DateTime? sonGorulme;
  final bool yasakli, izinli;

  int get toplamHatali => hatali + olmayanKullanici;
  int get dusmanca => engellenen + hatali + olmayanKullanici;

  factory SshKaynagi.coz(Map<String, dynamic> m) => SshKaynagi(
    ip: metin(m['ip']),
    engellenen: tamsayi(m['dropped']),
    hatali: tamsayi(m['failed']),
    olmayanKullanici: tamsayi(m['invalid_user']),
    basarili: tamsayi(m['accepted']),
    kullanicilar: metinler(m['users']),
    sonGorulme: tarihOku(m['last_seen']),
    yasakli: mantik(m['banned']),
    izinli: mantik(m['ssh_allowed']),
  );
}

/// SSH kaynak sıralaması: en çok düşmanca deneme yapan üstte, eşitlikte en yeni.
List<SshKaynagi> kaynaklariSirala(List<SshKaynagi> l) => [...l]
  ..sort((a, b) {
    final c = b.dusmanca.compareTo(a.dusmanca);
    if (c != 0) return c;
    final ta = a.sonGorulme?.millisecondsSinceEpoch ?? 0, tb = b.sonGorulme?.millisecondsSinceEpoch ?? 0;
    return tb.compareTo(ta);
  });

class SunucuErisimi {
  SunucuErisimi(Map<String, dynamic> m)
    : benimIp = metin(m['my_ip']),
      benimIpIzinli = mantik(m['my_ip_ssh_allowed']),
      sshIzinleri = [for (final a in haritalar(m['ssh_allow'])) metin(a['ip'])],
      yasaklar = haritalar(m['bans']).map(IpYasagi.coz).toList(),
      dusurmeKaydi = mantik(m['drop_log']),
      otomatik = OtomatikYasak.coz(m['autoban']),
      kaynaklar = kaynaklariSirala(haritalar(m['sources']).map(SshKaynagi.coz).toList()),
      toplamlar = harita(m['totals']).map((k, v) => MapEntry(k, tamsayi(v))),
      gun = tamsayi(m['window_days'], 7),
      duvarHatasi = metinYa(m['firewall_error']),
      kayitHatasi = metinYa(m['log_error']);

  final String benimIp;
  final bool benimIpIzinli, dusurmeKaydi;
  final List<String> sshIzinleri;
  final List<IpYasagi> yasaklar;
  final OtomatikYasak otomatik;
  final List<SshKaynagi> kaynaklar;
  final Map<String, int> toplamlar;
  final int gun;
  final String? duvarHatasi, kayitHatasi;
}

class SshOlayi {
  const SshOlayi(this.zaman, this.tur, this.kullanici, this.yontem, this.satir);
  final DateTime? zaman;
  final String tur, kullanici, yontem, satir;

  factory SshOlayi.coz(Map<String, dynamic> m) => SshOlayi(tarihOku(m['time']), metin(m['kind']), metin(m['user']), metin(m['method']), metin(m['line']));
}
