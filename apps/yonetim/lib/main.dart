import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'ekranlar/kabuk.dart';
import 'oturum.dart';
import 'veri/tercihler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
  Intl.defaultLocale = 'tr_TR';
  await temaYukle();
  await Uyg.api.baslat();
  Uyg.api.oturumDustu = Uyg.oturumDustu;
  runApp(const YonetimUygulamasi());
}

class YonetimUygulamasi extends StatelessWidget {
  const YonetimUygulamasi({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: temaKipi,
      builder: (_, kip, _) => MaterialApp(
        title: 'BogaMail Yönetim',
        debugShowCheckedModeBanner: false,
        navigatorKey: kokGezgin,
        scaffoldMessengerKey: kokMesaj,
        theme: temaKur(Brightness.light),
        darkTheme: temaKur(Brightness.dark),
        themeMode: kip,
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: AcilisEkrani(alt: 'YÖNETİM', isaret: AcilisIsaret.yonetim, hazirla: () async => await Uyg.yukle() ? const Kabuk() : Uyg.girisEkrani()),
      ),
    );
  }
}
