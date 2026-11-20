import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cihazda saklanan kullanıcı tercihleri (sunucu ayarlarından bağımsız).
class Tercihler {
  Tercihler._();
  static const _tema = 'posta.tema';
  static const _gorsel = 'posta.uzakGorseller';

  /// Uzak görselleri sunucu vekili üzerinden kendiliğinden yükle (gereksiz ve uyarılı iletiler hariç).
  static final uzakGorseller = ValueNotifier<bool>(false);

  static Future<void> yukle() async {
    try {
      final p = await SharedPreferences.getInstance();
      temaKipi.value = switch (p.getString(_tema)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      uzakGorseller.value = p.getBool(_gorsel) ?? false;
    } catch (_) {}
  }

  static Future<void> temaAyarla(ThemeMode m) async {
    temaKipi.value = m;
    final p = await SharedPreferences.getInstance();
    await p.setString(_tema, switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  static Future<void> uzakGorselAyarla(bool v) async {
    uzakGorseller.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_gorsel, v);
  }
}
