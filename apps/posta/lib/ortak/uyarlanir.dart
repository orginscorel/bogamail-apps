import 'dart:math';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

/// Telefonda tam ekran sayfa; geniş pencerede (masaüstü/tablet) ortada okunabilir genişlikte bir pencere. Böylece
/// düzenleyici ve ayrıntı ekranları masaüstünde tüm pencereye yayılmaz ya da dar telefon görünümünde kalmaz.
Future<T?> uyarlanirAc<T>(BuildContext context, WidgetBuilder builder, {double genislik = 760, double yukseklik = 860, bool tamEkran = false}) {
  if (context.genis) {
    final b = MediaQuery.sizeOf(context);
    return showDialog<T>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(width: min(genislik, b.width - 48), height: min(yukseklik, b.height - 48), child: builder(c)),
      ),
    );
  }
  return Navigator.of(context).push<T>(MaterialPageRoute(fullscreenDialog: tamEkran, builder: builder));
}
