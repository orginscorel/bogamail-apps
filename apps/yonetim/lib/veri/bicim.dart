// Saf biçimlendirme ve yardımcı işlevler (birim testleri test/bicim_test.dart).

import 'dart:math';

const mib = 1 << 20;
const gib = 1 << 30;

/// Sunucunun izin verdiği en büyük kota (1 PiB) = "Sınırsız".
const sinirsizKota = 1 << 50;

/// Sunucunun izin verdiği en küçük kota (10 MiB).
const enKucukKota = 10 * mib;

/// Kota ön ayarları (etiket, bayt).
const kotaOnAyarlari = <(String, int)>[
  ('1 GB', 1 * gib),
  ('5 GB', 5 * gib),
  ('10 GB', 10 * gib),
  ('25 GB', 25 * gib),
  ('50 GB', 50 * gib),
  ('Sınırsız', sinirsizKota),
];

bool sinirsizMi(int bayt) => bayt >= sinirsizKota;

/// "2,5" / "10" GB metnini bayta çevirir; geçersizse null.
int? gbdenBayt(String gbMetni) {
  final v = double.tryParse(gbMetni.trim().replaceAll(',', '.'));
  if (v == null || v.isNaN || v <= 0) return null;
  final b = (v * gib).round();
  return b > sinirsizKota ? sinirsizKota : b;
}

/// Bayt → düzenleme alanı için GB metni ("5", "2,5").
String baytGbMetni(int bayt) {
  final g = bayt / gib;
  final s = g == g.roundToDouble() ? g.toStringAsFixed(0) : g.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  return s.replaceAll('.', ',');
}

/// Kullanım oranı 0..1 (sınırsız ya da kota yoksa null).
double? kullanimOrani(int kullanilan, int kota) {
  if (kota <= 0 || sinirsizMi(kota)) return null;
  return (kullanilan / kota).clamp(0.0, 1.0);
}

/// Kuyruk yaşı: "45 sn", "12 dk", "3 sa 5 dk", "2 gün 4 sa".
String yasYaz(int? sn) {
  if (sn == null || sn < 0) return '—';
  if (sn < 60) return '$sn sn';
  if (sn < 3600) return '${sn ~/ 60} dk';
  if (sn < 86400) return '${sn ~/ 3600} sa ${(sn % 3600) ~/ 60} dk';
  return '${sn ~/ 86400} gün ${(sn % 86400) ~/ 3600} sa';
}

/// "3 saattir" tarzı süre (etkin alarmlar için).
String suredir(DateTime? since, {DateTime? simdi}) {
  if (since == null) return '';
  final m = max(0, ((simdi ?? DateTime.now()).difference(since).inSeconds / 60).round());
  if (m < 60) return '$m dakikadır';
  if (m < 1440) return '${(m / 60).round()} saattir';
  return '${(m / 1440).round()} gündür';
}

/// Saniye cinsinden süreyi kısa yazar ("3 gün 4 sa", "5 sa 2 dk").
String sureYaz(num? sn) {
  if (sn == null || sn <= 0) return '—';
  final s = sn.round();
  if (s < 3600) return '${s ~/ 60} dk';
  if (s < 86400) return '${s ~/ 3600} sa ${(s % 3600) ~/ 60} dk';
  return '${s ~/ 86400} gün ${(s % 86400) ~/ 3600} sa';
}

String yuzdeYaz(double v, {int basamak = 1}) => '%${v.toStringAsFixed(basamak).replaceAll('.', ',')}';

const _sifreAlfabesi = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789-_.!@#';

/// Güçlü rastgele şifre (web panelindeki generatePassword ile aynı alfabe; karışık harf ve rakam garanti).
String sifreUret({int uzunluk = 20, Random? rastgele}) {
  final r = rastgele ?? Random.secure();
  final n = max(uzunluk, 12);
  while (true) {
    final s = String.fromCharCodes(List.generate(n, (_) => _sifreAlfabesi.codeUnitAt(r.nextInt(_sifreAlfabesi.length))));
    if (s.contains(RegExp(r'[A-Z]')) && s.contains(RegExp(r'[a-z]')) && s.contains(RegExp(r'[0-9]'))) return s;
  }
}

const rolEtiketleri = {'super_admin': 'Süper Yönetici', 'reseller_admin': 'Bayi Yöneticisi', 'org_admin': 'Müşteri Yöneticisi'};

String rolEtiketi(String rol) => rolEtiketleri[rol] ?? rol;

const durumEtiketleri = {'active': 'Aktif', 'pending': 'Doğrulama bekliyor', 'suspended': 'Askıda', 'disabled': 'Devre dışı'};

String durumEtiketi(String d) => durumEtiketleri[d] ?? d;

/// /health bileşenlerinin okunur adları (web: healthLabels).
const saglikEtiketleri = {
  'api': "Yönetim API'si",
  'postgresql': 'Veritabanı (PostgreSQL)',
  'redis': 'Önbellek (Redis)',
  'smtp-inbound': 'Gelen posta (SMTP 25)',
  'smtp-submission': 'Gönderim (SMTP 587/465)',
  'outbound': 'Giden teslimat',
  'imap': 'IMAP',
  'pop3': 'POP3',
  'antivirus': 'Antivirüs (ClamAV)',
  'delivery-queue': 'Teslim kuyruğu',
};

/// SSH olay türleri (Sunucu Erişimi).
const sshOlayEtiketleri = {
  'accepted': 'Başarılı giriş',
  'failed': 'Hatalı şifre',
  'invalid_user': 'Olmayan kullanıcı',
  'preauth': 'Girişsiz kopma',
  'dropped': 'Güvenlik duvarı engelledi',
};

/// IP yasak süreleri (saat; 0 = süresiz).
const yasakSureleri = <(int, String)>[(1, '1 saat'), (24, '24 saat'), (168, '7 gün'), (720, '30 gün'), (0, 'Süresiz')];

String yasakSuresiEtiketi(int saat) {
  for (final (s, e) in yasakSureleri) {
    if (s == saat) return e;
  }
  return saat % 24 == 0 ? '${saat ~/ 24} gün' : '$saat saat';
}

const karantinaNedenleri = {'virus': 'Virüs bulundu', 'blocked_attachment': 'Engellenen dosya eki', 'spam': 'Spam (istenmeyen posta)'};

const karantinaDurumlari = {'held': 'Bekletiliyor', 'released': 'Serbest bırakıldı', 'deleted': 'Silindi'};

const alarmDurumlari = {'firing': 'Tetiklendi', 'repeat': 'Hatırlatma', 'resolved': 'Düzeldi', 'test': 'Test'};
const onemEtiketleri = {'warning': 'Uyarı', 'critical': 'Kritik'};

/// HTML'den kaba düz metin (karantina önizlemesi için; HTML hiçbir zaman çizilmez).
String htmldenMetin(String html) {
  var s = html.replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</tr>|</li>|</h[1-6]>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  const ad = {'&nbsp;': ' ', '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&apos;': "'"};
  ad.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ').split('\n').map((l) => l.trim()).join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// Kullanıcı aracısından kısa cihaz adı ("Chrome · macOS", "BogaMail Yönetim · iOS").
String cihazAdi(String ua) {
  if (ua.isEmpty) return 'Bilinmeyen cihaz';
  final app = RegExp(r'BogaMail-(Posta|Yonetim)/.*\(([^()]+)\)\s*$').firstMatch(ua);
  if (app != null) return 'BogaMail ${app.group(1) == 'Yonetim' ? 'Yönetim' : 'Posta'} · ${app.group(2)}';
  String tarayici = 'Tarayıcı';
  if (ua.contains('Edg/')) {
    tarayici = 'Edge';
  } else if (ua.contains('OPR/')) {
    tarayici = 'Opera';
  } else if (ua.contains('Firefox/')) {
    tarayici = 'Firefox';
  } else if (ua.contains('Chrome/')) {
    tarayici = 'Chrome';
  } else if (ua.contains('Safari/')) {
    tarayici = 'Safari';
  } else if (ua.startsWith('curl')) {
    tarayici = 'curl';
  }
  String isletim = '';
  if (ua.contains('iPhone') || ua.contains('iPad')) {
    isletim = 'iOS';
  } else if (ua.contains('Android')) {
    isletim = 'Android';
  } else if (ua.contains('Mac OS X') || ua.contains('Macintosh')) {
    isletim = 'macOS';
  } else if (ua.contains('Windows')) {
    isletim = 'Windows';
  } else if (ua.contains('Linux')) {
    isletim = 'Linux';
  }
  return isletim.isEmpty ? tarayici : '$tarayici · $isletim';
}

/// Alıcı / hedef listesini virgül, noktalı virgül, boşluk ya da satırlardan ayırır.
List<String> adresleriAyir(String s) => s.split(RegExp(r'[\s,;]+')).map((x) => x.trim().toLowerCase()).where((x) => x.isNotEmpty).toSet().toList();
