// Denetim kayıtlarının Türkçe okunuşu (web: lib/audit-labels.ts). Tablolar denetim_tablolari.dart dosyasında.

import 'package:boga_ortak/boga_ortak.dart' show boyutYaz, tamZaman;

import 'bicim.dart';
import 'denetim_tablolari.dart';

export 'denetim_tablolari.dart' show denetimGruplari;

/// Web panelinin tablosunda olmayan ama sunucunun yazdığı eylemler.
const _ekEylemler = <String, (String, String, String)>{
  'host.ssh_allow': ('security', 'Sunucuya SSH izni verildi', 'warning'),
  'host.ssh_remove': ('security', 'Sunucu SSH izni kaldırıldı', 'warning'),
  'host.ban': ('security', 'IP adresi yasaklandı', 'warning'),
  'host.unban': ('security', 'IP adresi yasağı kaldırıldı', ''),
  'host.unban_expired': ('security', 'Süresi dolan IP yasağı kaldırıldı', ''),
  'host.autoban': ('security', 'SSH otomatik yasaklama ayarı değiştirildi', ''),
  'host.drop_log': ('security', 'Engellenen SSH denemelerinin kaydı değiştirildi', ''),
  'alias.create': ('mailbox', 'Takma ad oluşturuldu', ''),
  'alias.update': ('mailbox', 'Takma ad güncellendi', ''),
  'alias.delete': ('mailbox', 'Takma ad silindi', 'danger'),
  'mailbox.forwarding': ('mailbox', 'Posta kutusu yönlendirmesi değiştirildi', ''),
  'auth.session_revoke': ('auth', 'Bir oturum kapatıldı', ''),
  'auth.session_revoke_others': ('auth', 'Diğer tüm oturumlar kapatıldı', ''),
};

class DenetimEylemi {
  const DenetimEylemi(this.etiket, this.grup, this.ton);
  final String etiket;
  final String grup;

  /// '' | 'danger' | 'warning'
  final String ton;
}

/// "mailbox.password_reset" → "Mailbox password reset" (bilinmeyen kodlar boş görünmesin).
String koduOkunur(String kod) {
  final s = kod.replaceAll(RegExp(r'[._]+'), ' ').trim();
  if (s.isEmpty) return kod;
  final ilk = s[0] == 'i' ? 'İ' : s[0].toUpperCase();
  return ilk + s.substring(1);
}

DenetimEylemi denetimEylemi(String kod) {
  final b = denetimEylemleri[kod] ?? _ekEylemler[kod];
  if (b != null) return DenetimEylemi(b.$2, b.$1, b.$3);
  final basarisiz = RegExp(r'(^|[._])failed$').hasMatch(kod);
  return DenetimEylemi(koduOkunur(kod), 'other', basarisiz ? 'danger' : '');
}

/// Arama metniyle Türkçe etiketi eşleşen eylem kodları (sunucuya q_actions olarak gider).
List<String> eylemAra(String q, {int enFazla = 100}) {
  final s = trKucuk(q.trim());
  if (s.length < 2) return const [];
  final out = <String>[];
  for (final e in {...denetimEylemleri, ..._ekEylemler}.entries) {
    if (trKucuk(e.value.$2).contains(s) || trKucuk(denetimGruplari[e.value.$1] ?? '').contains(s)) out.add(e.key);
    if (out.length >= enFazla) break;
  }
  return out;
}

/// Türkçe küçük harf (İ → i, I → ı).
String trKucuk(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// "Posta kutusu: ali@firma.com" — hedefin türü ve ayrıntılardaki en anlamlı ad.
String? denetimHedefi(String tur, String hedefId, String? orgAdi, Map<String, dynamic> d) {
  if (tur.isEmpty) return null;
  final ad =
      denetimHedefleri[tur] ??
      (tur == 'host'
          ? 'Sunucu'
          : tur == 'alias'
          ? 'Takma ad'
          : koduOkunur(tur));
  Object? isim = d['address'] ?? d['email'] ?? d['name'] ?? d['value'] ?? d['domain'] ?? d['organization_name'];
  if (isim == null && tur == 'organization') isim = orgAdi;
  if (isim == null && (tur == 'queue' || tur == 'host') && hedefId.isNotEmpty) isim = hedefId;
  if (isim == null && tur == 'settings' && hedefId.isNotEmpty) isim = denetimAyarHedefleri[hedefId] ?? koduOkunur(hedefId);
  return isim is String && isim.isNotEmpty ? '$ad: $isim' : ad;
}

const _gizliAnahtarlar = {'organization_id', 'mailbox_id', 'domain_id', 'export_id', 'job_id', 'plan_id', 'id', 'user_id'};
const _gunler = ['Pazar', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi'];

String denetimAnahtari(String k) => denetimAnahtarlari[k] ?? (k == 'hours' ? 'Süre' : koduOkunur(k));

final _tarihDeseni = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');

String? _deger(String k, Object? v) {
  if (v == null || v == '') return null;
  if (v is bool) {
    if (k == 'enabled') return v ? 'Açık' : 'Kapalı';
    if (k == 'ok') return v ? 'Başarılı' : 'Başarısız';
    return v ? 'Evet' : 'Hayır';
  }
  if (v is num) {
    if (k.endsWith('_bytes') || k == 'bytes') return boyutYaz(v);
    if (k == 'weekday') return v >= 0 && v < 7 ? _gunler[v.toInt()] : '$v';
    if (k == 'hours') return yasakSuresiEtiketi(v.toInt());
    return sayiMetni(v);
  }
  if (v is String) {
    if (k == 'status') return denetimDurumlari[v] ?? koduOkunur(v);
    if (k == 'role' && rolEtiketleri.containsKey(v)) return rolEtiketleri[v];
    final l = denetimDegerleri[k]?[v];
    if (l != null) return l;
    if (_tarihDeseni.hasMatch(v)) {
      final t = DateTime.tryParse(v)?.toLocal();
      if (t != null) return tamZaman(t);
    }
    return v;
  }
  if (v is List) {
    if (v.isEmpty) return k == 'permissions' ? 'Tam yetki' : '—';
    if (v.every((x) => x is! Map && x is! List)) return v.map((x) => _deger(k, x) ?? '—').join(', ');
    return '${v.length} kayıt';
  }
  if (v is Map) {
    final m = v.map((a, b) => MapEntry('$a', b));
    if (m.isNotEmpty && m.values.every((x) => x is bool)) {
      final acik = [
        for (final e in m.entries)
          if (e.value == true) denetimAnahtari(e.key),
      ];
      final kapali = [
        for (final e in m.entries)
          if (e.value == false) denetimAnahtari(e.key),
      ];
      return [if (acik.isNotEmpty) 'Açık: ${acik.join(', ')}', if (kapali.isNotEmpty) 'Kapalı: ${kapali.join(', ')}'].join(' · ');
    }
    final rows = denetimAyrintilari(m);
    return rows.isEmpty ? null : rows.map((r) => '${r.$1}: ${r.$2}').join(' · ');
  }
  return '$v';
}

/// Sayıyı Türkçe binlik ayırıcıyla yazar (intl yerel verisi gerektirmez).
String sayiMetni(num v) {
  if (v is double && v != v.roundToDouble()) return v.toStringAsFixed(2).replaceAll('.', ',');
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Ayrıntı JSON'unu okunur (etiket, değer) satırlarına çevirir; kimlikler ve boş değerler gizlenir.
List<(String, String)> denetimAyrintilari(Map<String, dynamic>? d) {
  if (d == null) return const [];
  final out = <(String, String)>[];
  for (final e in d.entries) {
    final k = e.key;
    if (_gizliAnahtarlar.contains(k) || (k.endsWith('_id') && k != 'queue_id' && k != 'report_id')) continue;
    final v = _deger(k, e.value);
    if (v == null) continue;
    out.add((denetimAnahtari(k), v));
  }
  return out;
}

String denetimOzeti(Map<String, dynamic>? d, {int enFazla = 3}) {
  final r = denetimAyrintilari(d);
  final bas = [for (final x in r.take(enFazla)) '${x.$1}: ${x.$2}'];
  if (r.length > enFazla) bas.add('+${r.length - enFazla}');
  return bas.join(' · ');
}
