// Altyapı ekranlarının (izleme, yedekleme, itibar, IP, kiracı, depolama) ortak parçaları.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../veri/json.dart';

/// Bütünlük taraması (GET /backup/integrity → last / running).
class ButunlukTaramasi {
  ButunlukTaramasi(this.m);
  final Map<String, dynamic> m;

  String get kimlik => metin(m['id']);
  String get tetik => metin(m['trigger']);
  String get durum => metin(m['status']);
  DateTime? get baslangic => tarihOku(m['started_at']);
  DateTime? get bitis => tarihOku(m['finished_at']);
  String get isteyen => metin(m['requested_by']);
  int get iletiler => tamsayi(m['messages_checked']);
  int get baytlar => tamsayi(m['bytes_checked']);
  int get dosyalar => tamsayi(m['blob_files']);
  int get eksik => tamsayi(m['missing_blobs']);
  int get bozuk => tamsayi(m['hash_mismatches']);
  int get boyutHatasi => tamsayi(m['size_mismatches']);
  int get sahipsiz => tamsayi(m['orphan_blobs']);
  String get manifestCalistirma => metin(m['manifest_run']);
  String get manifestDurumu => metin(m['manifest_status'], 'none');
  int get manifestDosyalari => tamsayi(m['manifest_files']);
  int get manifestSorunlari => tamsayi(m['manifest_problems']);
  List<Map<String, dynamic>> get sorunlar => haritalar(m['problems']);
  bool get kesik => mantik(m['problems_truncated']);
  String get hata => metin(m['error']);
  double get sure => ondalik(m['duration_seconds']);

  bool get sorunlu => durum == 'problems' || durum == 'failed';

  /// web: integritySummary
  String get ozet {
    if (durum == 'failed') return 'Tarama tamamlanamadı: ${hata.isEmpty ? 'bilinmeyen hata' : hata}';
    final p = <String>[
      if (eksik > 0) '$eksik eksik dosya',
      if (bozuk > 0) '$bozuk bozuk (SHA-256)',
      if (boyutHatasi > 0) '$boyutHatasi boyut uyuşmazlığı',
      if (sahipsiz > 0) '$sahipsiz sahipsiz dosya',
      if (manifestSorunlari > 0) '$manifestSorunlari yedek dosyası sorunu',
    ];
    return p.isEmpty ? 'Sorun bulunmadı' : p.join(' · ');
  }

  static ButunlukTaramasi? coz(Object? v) => v is Map ? ButunlukTaramasi(harita(v)) : null;
}

/// Bütünlük sorun türleri (web: problemLabel).
const butunlukSorunEtiketleri = {
  'missing_blob': 'Dosya eksik',
  'hash_mismatch': 'SHA-256 uyuşmuyor',
  'size_mismatch': 'Boyut uyuşmuyor',
  'orphan_blob': 'Sahipsiz dosya',
  'manifest_missing': 'Manifest eksik',
  'manifest_hash_mismatch': 'Manifest değişmiş',
  'manifest_invalid': 'Manifest geçersiz',
  'backup_file_missing': 'Yedek dosyası eksik',
  'backup_file_size_mismatch': 'Yedek dosyası boyutu',
  'backup_file_hash_mismatch': 'Yedek dosyası SHA-256',
};

/// Son bütünlük taraması sorunluysa kırmızı uyarı (web: IntegrityAlert). Yalnız süper yönetici.
class ButunlukUyarisi extends StatefulWidget {
  const ButunlukUyarisi({super.key, this.ayrintilar});

  /// Verilirse "Ayrıntılar" bağlantısı.
  final VoidCallback? ayrintilar;

  @override
  State<ButunlukUyarisi> createState() => _ButunlukUyarisiState();
}

class _ButunlukUyarisiState extends State<ButunlukUyarisi> {
  ButunlukTaramasi? _son;

  @override
  void initState() {
    super.initState();
    if (Uyg.platformYoneticisi) _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = await Uyg.api.get('/api/v1/backup/integrity');
      if (mounted) setState(() => _son = ButunlukTaramasi.coz(harita(v)['last']));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _son;
    if (s == null || !s.sorunlu) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ButunlukBandi(tarama: s, ayrintilar: widget.ayrintilar),
    );
  }
}

/// Sorunlu bütünlük taraması bandı.
class ButunlukBandi extends StatelessWidget {
  const ButunlukBandi({super.key, required this.tarama, this.ayrintilar});
  final ButunlukTaramasi tarama;
  final VoidCallback? ayrintilar;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final s = tarama;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Marka.gul.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Marka.gul.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gpp_maybe_rounded, color: Marka.gul, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: s.durum == 'failed' ? 'Bütünlük taraması başarısız' : 'Bütünlük taraması sorun buldu',
                    style: const TextStyle(color: Marka.gul, fontWeight: FontWeight.w700),
                    children: [
                      TextSpan(
                        text: '  (${goreliZaman(s.bitis ?? s.baslangic)})',
                        style: TextStyle(color: r.silik, fontWeight: FontWeight.w400, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text('${s.ozet}. Tarama hiçbir şeyi silmez veya onarmaz.', style: TextStyle(color: r.soluk, fontSize: 13)),
                if (ayrintilar != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                      onPressed: ayrintilar,
                      child: const Text('Ayrıntılar'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Monitor denetim durumu rozeti (web: MonBadge).
class MonRozeti extends StatelessWidget {
  const MonRozeti(this.durum, {super.key});
  final String durum;

  static const etiketler = {'ok': 'Sorunsuz', 'warn': 'Uyarı', 'fail': 'Sorun', 'unknown': 'Belirsiz', 'info': 'Bilgi', 'unchecked': 'Denetlenmedi'};

  static Color renk(BuildContext c, String d) => switch (d) {
    'ok' => Marka.zumrut,
    'warn' => Marka.kehribar,
    'fail' => Marka.gul,
    'info' => Marka.mavi,
    _ => c.r.silik,
  };

  @override
  Widget build(BuildContext context) => Rozet(etiketler[durum] ?? durum, renk: renk(context, durum));
}

/// Küçük sayaç kutusu (etiket altında büyük sayı).
class SayacKutusu extends StatelessWidget {
  const SayacKutusu({super.key, required this.etiket, required this.deger, this.ipucu, this.kotu = false});
  final String etiket, deger;
  final String? ipucu;
  final bool kotu;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: r.kenar),
      ),
      child: Column(
        children: [
          Text(
            deger,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: gosterim(18, agirlik: FontWeight.w700, renk: kotu ? Marka.gul : r.metin),
          ),
          const SizedBox(height: 2),
          Text(
            etiket,
            textAlign: TextAlign.center,
            style: TextStyle(color: r.soluk, fontSize: 12),
          ),
          if (ipucu != null)
            Text(
              ipucu!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: r.silik, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

/// Ayrıntı yoksa "—".
String tire(String s) => s.trim().isEmpty ? '—' : s;
