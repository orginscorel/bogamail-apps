import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../veri/json.dart';

/// Hizmet ekranlarının (Paketim, Paketler, Bayiler, Marka…) ortak küçük parçaları.

/// Sınır değeri (null = sınırsız) → metin.
String sinirYaz(num? n, {bool bayt = false, String sinirsiz = 'Sınırsız'}) {
  if (n == null) return sinirsiz;
  return bayt ? boyutYaz(n) : sayiYaz(n);
}

/// Kullanım sayacı: "x / y", kalan ve çubuk; [sinir] null ise sınırsız.
class KullanimSayaci extends StatelessWidget {
  const KullanimSayaci({super.key, required this.etiket, required this.kullanilan, required this.sinir, this.bayt = false, this.not});
  final String etiket;
  final int kullanilan;
  final int? sinir;
  final bool bayt;
  final String? not;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    String yaz(int n) => bayt ? boyutYaz(n) : sayiYaz(n);
    final s = sinir;
    final oran = s == null || s <= 0 ? null : (kullanilan / s).clamp(0.0, 1.0);
    final renk = oran == null ? r.birincil : (oran >= .9 ? Marka.gul : (oran >= .75 ? Marka.kehribar : r.birincil));
    return Kutu(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(etiket, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 13)),
              ),
              Text(s == null ? 'Sınırsız' : 'Kalan ${yaz((s - kullanilan).clamp(0, s))}', style: TextStyle(color: r.silik, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: yaz(kullanilan), style: gosterim(22, agirlik: FontWeight.w600, renk: r.metin)),
                TextSpan(
                  text: ' / ${s == null ? '∞' : yaz(s)}',
                  style: TextStyle(color: r.silik, fontSize: 14),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: oran ?? 0, minHeight: 6, backgroundColor: r.ic, color: renk),
          ),
          if (not != null && not!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(not!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// Etiket–değer satırı (sağa yaslı değer; kısa listeler).
class DegerSatiri extends StatelessWidget {
  const DegerSatiri(this.etiket, this.deger, {super.key});
  final String etiket, deger;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(etiket, style: TextStyle(color: context.r.soluk, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Text(deger, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

/// /catalog → features öğesi.
class KatalogOzelligi {
  const KatalogOzelligi({required this.anahtar, required this.ad, required this.grup, required this.hazir, this.faz = '', this.kutuBasi = false});
  final String anahtar, ad, grup, faz;
  final bool hazir, kutuBasi;

  factory KatalogOzelligi.coz(Map<String, dynamic> m) => KatalogOzelligi(
    anahtar: metin(m['key']),
    ad: metin(m['name']),
    grup: metin(m['group'], 'Diğer'),
    hazir: mantik(m['available'], true),
    faz: metin(m['phase']),
    kutuBasi: mantik(m['mailbox']),
  );

  /// Gruplara ayrılmış katalog (sıra korunur).
  static Map<String, List<KatalogOzelligi>> grupla(List<KatalogOzelligi> l) {
    final g = <String, List<KatalogOzelligi>>{};
    for (final f in l) {
      g.putIfAbsent(f.grup, () => []).add(f);
    }
    return g;
  }
}

/// GET /api/v1/catalog → özellik listesi.
List<KatalogOzelligi> katalogOzellikleri(Object? v) => haritalar(harita(v)['features']).map(KatalogOzelligi.coz).toList();

/// Form doğrulama yardımcısı: boş = null (sınırsız), sayı değilse hata.
String? sayiDogrula(String? v, {bool bosOlur = true, int enAz = 0}) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return bosOlur ? null : 'Zorunlu';
  final n = num.tryParse(s.replaceAll(',', '.'));
  if (n == null) return 'Sayı girin';
  if (n < enAz) return enAz == 0 ? 'Negatif olamaz' : 'En az $enAz';
  return null;
}
