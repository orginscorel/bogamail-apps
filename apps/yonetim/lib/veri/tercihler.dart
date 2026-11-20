import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _temaAnahtari = 'yonetim.tema';

ThemeMode temaCoz(String? s) => switch (s) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  'system' => ThemeMode.system,
  _ => ThemeMode.light,
};

String temaAdi(ThemeMode m) => switch (m) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

/// Kayıtlı tema seçimini [temaKipi]'ne yükler (açılışta, runApp öncesi).
Future<void> temaYukle() async {
  try {
    final p = await SharedPreferences.getInstance();
    temaKipi.value = temaCoz(p.getString(_temaAnahtari));
  } catch (_) {}
}

Future<void> temaKaydet(ThemeMode m) async {
  temaKipi.value = m;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_temaAnahtari, temaAdi(m));
  } catch (_) {}
}
