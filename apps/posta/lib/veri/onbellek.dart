// Hesap başına kalıcı önbellek: sunucunun JSON yanıtları (klasörler, etiketler, listelerin ilk sayfası, ileti
// ayrıntıları) ve vekil üzerinden alınmış uzak görseller. "Önce önbellek, arkada tazele" (stale-while-revalidate)
// için kullanılır. Düz dosyalar (iOS/macOS/Android/Windows'ta aynı çalışır); boyut sınırı aşılınca en eski
// kullanılanlar silinir (LRU). Hesap cihazdan kaldırılınca o hesabın dizini tümüyle silinir.
// İçerik hiçbir yere loglanmaz; hata ayıklama kipinde yalnız süre/isabet ölçümleri yazılır.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Hata ayıklama kipinde süre ölçümü (içerik yok: yalnız etiket ve milisaniye).
void zamanLogu(String etiket, Stopwatch s) {
  if (kDebugMode) debugPrint('[posta-süre] $etiket: ${s.elapsedMilliseconds} ms');
}

class Onbellek {
  Onbellek._();
  static final ben = Onbellek._();

  /// Hesap başına disk sınırı.
  static int azamiDisk = 200 * 1024 * 1024;

  /// Bellekte tutulan (anında okunabilen) toplam metin sınırı.
  static int azamiBellek = 24 * 1024 * 1024;

  /// Önbellek kök dizini. Testlerde null döndürülürse yalnız bellek kullanılır.
  static Future<Directory?> Function() kok = _varsayilanKok;

  static Future<Directory?> _varsayilanKok() async {
    try {
      final d = await getApplicationSupportDirectory();
      return Directory('${d.path}/onbellek_posta');
    } catch (_) {
      return null;
    }
  }

  String? _hesap;
  Directory? _dizin;
  final _bellek = <String, String>{};
  int _bellekBoyut = 0;

  /// anahtar → (bayt, son kullanım ms). Sıra: en eski başta.
  final _indeks = <String, (int, int)>{};
  int _diskBoyut = 0;
  Timer? _indeksYaz;
  Future<void>? _acilis;

  String? get hesap => _hesap;

  /// Hesabın önbelleğini açar (hesap değişince öncekinin bellek kısmı bırakılır).
  Future<void> hesapAc(String mailboxId) {
    if (mailboxId.isEmpty) return Future.value();
    if (_hesap == mailboxId && _acilis != null) return _acilis!;
    _kapat();
    _hesap = mailboxId;
    return _acilis = _ac(mailboxId);
  }

  Future<void> _ac(String id) async {
    final k = await kok();
    if (k == null || _hesap != id) return;
    final d = Directory('${k.path}/${_ad(id)}');
    try {
      await d.create(recursive: true);
      final f = File('${d.path}/_indeks.json');
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString());
        if (m is Map) {
          final l = m.entries.where((e) => e.value is List && (e.value as List).length == 2).toList()
            ..sort((a, b) => ((a.value as List)[1] as num).compareTo((b.value as List)[1] as num));
          for (final e in l) {
            final v = e.value as List;
            _indeks['${e.key}'] = ((v[0] as num).toInt(), (v[1] as num).toInt());
            _diskBoyut += (v[0] as num).toInt();
          }
        }
      }
    } catch (_) {
      _indeks.clear();
      _diskBoyut = 0;
    }
    if (_hesap == id) _dizin = d;
  }

  void _kapat() {
    _indeksiYaz(hemen: true);
    _hesap = null;
    _dizin = null;
    _acilis = null;
    _bellek.clear();
    _bellekBoyut = 0;
    _indeks.clear();
    _diskBoyut = 0;
  }

  /// Bellekteki kaydı eşzamanlı döndürür (yoksa null). İlk karede gösterim için.
  Object? hemen(String anahtar) {
    final s = _bellek.remove(anahtar);
    if (s == null) return null;
    _bellek[anahtar] = s;
    _dokun(anahtar);
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  bool bellekte(String anahtar) => _bellek.containsKey(anahtar);
  bool var_(String anahtar) => _bellek.containsKey(anahtar) || _indeks.containsKey(anahtar);

  /// Bellekten, yoksa diskten okur.
  Future<Object?> oku(String anahtar) async {
    final h = hemen(anahtar);
    if (h != null) return h;
    await _acilis;
    final d = _dizin;
    if (d == null || !_indeks.containsKey(anahtar)) return null;
    try {
      final s = await File('${d.path}/${_ad(anahtar)}').readAsString();
      if (_dizin != d) return null;
      _bellegeKoy(anahtar, s);
      _dokun(anahtar);
      return jsonDecode(s);
    } catch (_) {
      _indeks.remove(anahtar);
      return null;
    }
  }

  /// Yazar; içerik aynıysa false döner (arayüz güncellemesi gerekmez).
  Future<bool> yaz(String anahtar, Object? deger) async {
    final String s;
    try {
      s = jsonEncode(deger);
    } catch (_) {
      return false;
    }
    if (_bellek[anahtar] == s) {
      _dokun(anahtar);
      return false;
    }
    _bellegeKoy(anahtar, s);
    final hesap = _hesap;
    await _acilis;
    final d = _dizin;
    if (d == null || _hesap != hesap) return true;
    try {
      final b = utf8.encode(s).length;
      await File('${d.path}/${_ad(anahtar)}').writeAsString(s, flush: false);
      if (_dizin != d) return true;
      _diskBoyut -= _indeks.remove(anahtar)?.$1 ?? 0;
      _indeks[anahtar] = (b, DateTime.now().millisecondsSinceEpoch);
      _diskBoyut += b;
      await _sinirla(d);
      _indeksiYaz();
    } catch (_) {}
    return true;
  }

  Future<void> sil(String anahtar) async {
    final s = _bellek.remove(anahtar);
    if (s != null) _bellekBoyut -= s.length;
    final d = _dizin;
    final i = _indeks.remove(anahtar);
    if (i == null || d == null) return;
    _diskBoyut -= i.$1;
    try {
      await File('${d.path}/${_ad(anahtar)}').delete();
    } catch (_) {}
    _indeksiYaz();
  }

  /// Bellekteki JSON nesnesini yerinde değiştirip geri yazar (ör. okundu işareti).
  Future<void> degistir(String anahtar, void Function(Map<String, dynamic>) f) async {
    final v = await oku(anahtar);
    if (v is! Map) return;
    final m = Map<String, dynamic>.from(v);
    f(m);
    await yaz(anahtar, m);
  }

  /// Bir hesabın tüm önbelleğini siler (hesap cihazdan kaldırıldı / unutuldu).
  Future<void> hesabiSil(String mailboxId) async {
    if (mailboxId.isEmpty) return;
    if (_hesap == mailboxId) {
      _indeksYaz?.cancel();
      _indeksYaz = null;
      _indeks.clear();
      _kapat();
    }
    final k = await kok();
    if (k == null) return;
    try {
      final d = Directory('${k.path}/${_ad(mailboxId)}');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  void _bellegeKoy(String anahtar, String s) {
    final eski = _bellek.remove(anahtar);
    if (eski != null) _bellekBoyut -= eski.length;
    _bellek[anahtar] = s;
    _bellekBoyut += s.length;
    while (_bellekBoyut > azamiBellek && _bellek.length > 1) {
      final ilk = _bellek.keys.first;
      _bellekBoyut -= _bellek.remove(ilk)!.length;
    }
  }

  void _dokun(String anahtar) {
    final i = _indeks.remove(anahtar);
    if (i != null) _indeks[anahtar] = (i.$1, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _sinirla(Directory d) async {
    while (_diskBoyut > azamiDisk && _indeks.length > 1) {
      final ilk = _indeks.keys.first;
      _diskBoyut -= _indeks.remove(ilk)!.$1;
      final s = _bellek.remove(ilk);
      if (s != null) _bellekBoyut -= s.length;
      try {
        await File('${d.path}/${_ad(ilk)}').delete();
      } catch (_) {}
    }
  }

  void _indeksiYaz({bool hemen = false}) {
    final d = _dizin;
    if (d == null) return;
    _indeksYaz?.cancel();
    void yaz() {
      try {
        File('${d.path}/_indeks.json').writeAsStringSync(
          jsonEncode({
            for (final e in _indeks.entries) e.key: [e.value.$1, e.value.$2],
          }),
        );
      } catch (_) {}
    }

    if (hemen) {
      if (_indeksYaz != null || _indeks.isNotEmpty) yaz();
      _indeksYaz = null;
    } else {
      _indeksYaz = Timer(const Duration(milliseconds: 500), () {
        _indeksYaz = null;
        if (_dizin == d) yaz();
      });
    }
  }

  /// Dosya adı: anahtarın 64 bit FNV-1a özeti (adres/konu gibi içerik dosya adına sızmaz).
  static String _ad(String s) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h = h * 0x100000001b3; // 64 bit taşma = mod 2^64
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  @visibleForTesting
  void testSifirla() {
    _indeksiYaz(hemen: true);
    _indeksYaz?.cancel();
    _indeksYaz = null;
    _hesap = null;
    _dizin = null;
    _acilis = null;
    _bellek.clear();
    _bellekBoyut = 0;
    _indeks.clear();
    _diskBoyut = 0;
  }

  @visibleForTesting
  int get diskBoyut => _diskBoyut;
}
