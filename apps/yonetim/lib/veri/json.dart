// Hoşgörülü JSON okuma yardımcıları: eksik ya da beklenmeyen türde alanlar asla çökme yaratmaz.

/// Metin değeri (null / sayı / bool → metin, yoksa [d]).
String metin(Object? v, [String d = '']) {
  if (v == null) return d;
  if (v is String) return v;
  if (v is num || v is bool) return '$v';
  return d;
}

/// Boş değilse metin, değilse null.
String? metinYa(Object? v) {
  final s = metin(v).trim();
  return s.isEmpty ? null : s;
}

int tamsayi(Object? v, [int d = 0]) {
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.toInt() : d;
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt() ?? d;
  return d;
}

int? tamsayiYa(Object? v) {
  if (v is num) return v.isFinite ? v.toInt() : null;
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double ondalik(Object? v, [double d = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.')) ?? d;
  return d;
}

double? ondalikYa(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);

bool mantik(Object? v, [bool d = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return d;
}

DateTime? tarihOku(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

Map<String, dynamic> harita(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, x) => MapEntry('$k', x));
  return <String, dynamic>{};
}

List<Map<String, dynamic>> haritalar(Object? v) => v is List
    ? [
        for (final x in v)
          if (x is Map) harita(x),
      ]
    : <Map<String, dynamic>>[];

List<String> metinler(Object? v) => v is List
    ? [
        for (final x in v)
          if (x != null) metin(x),
      ]
    : <String>[];

/// Sayfalı API yanıtı: {items, total, page, page_size}.
class Sayfa<T> {
  const Sayfa(this.ogeler, this.toplam);
  final List<T> ogeler;
  final int toplam;

  factory Sayfa.coz(Object? v, T Function(Map<String, dynamic>) yap) {
    final m = harita(v);
    final l = haritalar(m['items']).map(yap).toList();
    return Sayfa(l, m.containsKey('total') ? tamsayi(m['total'], l.length) : l.length);
  }
}
