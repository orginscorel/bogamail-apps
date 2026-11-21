import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cihazda saklanan kullanıcı tercihleri (sunucu ayarlarından bağımsız).
class Tercihler {
  Tercihler._();
  static const _tema = 'posta.tema';
  static const _gorsel = 'posta.uzakGorseller';
  static const _imzaYeni = 'posta.imza.yeni';
  static const _imzaYanit = 'posta.imza.yanit';
  static const _listeOrani = 'posta.listeOrani';
  static const _listeYOrani = 'posta.listeYOrani';
  static const _kenar = 'posta.kenarCubugu';

  /// Masaüstü yerleşimi (web mail-layout.ts gibi): liste genişliğinin / yüksekliğinin alana oranı (null: varsayılan
  /// %36 / %45) ve klasör sütunu tercihi (auto: 1400 px altında daralt | collapsed | expanded).
  static final listeOrani = ValueNotifier<double?>(null);
  static final listeYOrani = ValueNotifier<double?>(null);
  static final kenarCubugu = ValueNotifier<String>('auto');

  /// İmza varsayılan olarak yeni iletilere / yanıt ve iletmelere eklensin mi (yazarken tek tıkla değiştirilebilir).
  static final imzaYeni = ValueNotifier<bool>(true);
  static final imzaYanit = ValueNotifier<bool>(true);

  /// Uzak görselleri sunucu vekili üzerinden kendiliğinden yükle (gereksiz ve uyarılı iletiler hariç).
  static final uzakGorseller = ValueNotifier<bool>(false);

  static Future<void> yukle() async {
    try {
      final p = await SharedPreferences.getInstance();
      temaKipi.value = switch (p.getString(_tema)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
      uzakGorseller.value = p.getBool(_gorsel) ?? false;
      imzaYeni.value = p.getBool(_imzaYeni) ?? true;
      imzaYanit.value = p.getBool(_imzaYanit) ?? true;
      listeOrani.value = p.getDouble(_listeOrani);
      listeYOrani.value = p.getDouble(_listeYOrani);
      kenarCubugu.value = p.getString(_kenar) ?? 'auto';
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

  static Future<void> imzaVarsayilanAyarla({bool? yeni, bool? yanit}) async {
    final p = await SharedPreferences.getInstance();
    if (yeni != null) {
      imzaYeni.value = yeni;
      await p.setBool(_imzaYeni, yeni);
    }
    if (yanit != null) {
      imzaYanit.value = yanit;
      await p.setBool(_imzaYanit, yanit);
    }
  }

  static Future<void> _yaz(String k, double? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null) {
      await p.remove(k);
    } else {
      await p.setDouble(k, v);
    }
  }

  static Future<void> listeOraniAyarla(double? v) async {
    listeOrani.value = v;
    await _yaz(_listeOrani, v);
  }

  static Future<void> listeYOraniAyarla(double? v) async {
    listeYOrani.value = v;
    await _yaz(_listeYOrani, v);
  }

  static Future<void> kenarCubuguAyarla(String v) async {
    kenarCubugu.value = v;
    await (await SharedPreferences.getInstance()).setString(_kenar, v);
  }
}
