// Masaüstünde iletileri kenar menüsündeki klasör/etiketlere sürükleyip bırakma (web: application/x-bogamail-ids).

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../veri/durum.dart';

/// Sürüklenen iletiler. [birak] listeyi sahiplenen ekran tarafından verilir (taşıma/etiketleme, geri bildirim, hata).
class IletiSurukleme {
  const IletiSurukleme(this.idler, {required this.birak, this.kaynak});
  final List<String> idler;

  /// İletilerin bulunduğu konum (aynı klasöre bırakma yok sayılır).
  final Konum? kaynak;
  final Future<void> Function(Konum hedef) birak;
}

/// Fareyle sürükleme yalnız masaüstü uygulamada (dokunmatikte uzun basma seçimdir, kaydırma ile çakışmaz).
bool get masaustuPlatformu => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
