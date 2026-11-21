// Sunucuya ulaşılabilirlik ve son eşitleme zamanı. Her API isteği sonucunu bildirir (BogaApi.ulasilabilirlik):
// ulaşılamazsa "çevrimdışı", bir yanıt gelince yeniden "çevrimiçi" olunur ve bekleyen işlemler sırayla gönderilir.
// Son eşitleme zamanı hesap başına kalıcıdır ("Çevrimdışı — son eşitleme 14:32").

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Baglanti {
  Baglanti._();
  static final ben = Baglanti._();

  /// Son istek sunucuya ulaşamadı.
  final cevrimdisi = ValueNotifier<bool>(false);

  /// Son başarılı tam eşitleme (klasörler + gelen kutusu).
  final sonEsitleme = ValueNotifier<DateTime?>(null);

  /// Çevrimdışından çevrimiçine geçince çağrılır (kuyruk yeniden oynatma, eşitleme).
  final _geriGeldi = <VoidCallback>[];
  void geriGelince(VoidCallback f) {
    if (!_geriGeldi.contains(f)) _geriGeldi.add(f);
  }

  String _hesap = '';

  void bildir(bool ulasildi) {
    if (ulasildi == !cevrimdisi.value) return;
    cevrimdisi.value = !ulasildi;
    if (ulasildi) {
      // Dinleyiciler bu isteğin akışını beklemeden çalışsın.
      scheduleMicrotask(() {
        for (final f in List.of(_geriGeldi)) {
          f();
        }
      });
    }
  }

  /// Hesap açılınca son eşitleme zamanı yüklenir.
  Future<void> hesapAc(String id) async {
    _hesap = id;
    try {
      final p = await SharedPreferences.getInstance();
      final ms = p.getInt('posta.son_esitleme.$id');
      if (_hesap == id) sonEsitleme.value = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {}
  }

  Future<void> esitlendi([DateTime? t]) async {
    final z = t ?? DateTime.now();
    sonEsitleme.value = z;
    if (_hesap.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('posta.son_esitleme.$_hesap', z.millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> hesabiSil(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('posta.son_esitleme.$id');
    } catch (_) {}
    if (_hesap == id) sonEsitleme.value = null;
  }

  @visibleForTesting
  void testSifirla() {
    cevrimdisi.value = false;
    sonEsitleme.value = null;
    _hesap = '';
  }
}
