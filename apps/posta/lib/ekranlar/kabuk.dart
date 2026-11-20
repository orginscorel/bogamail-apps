import 'dart:async';
import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../oturum.dart';
import '../veri/bildirim.dart';
import '../veri/canli.dart';
import '../veri/durum.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/yazma_hazirla.dart';
import 'ileti_listesi.dart';
import 'okuyucu.dart';
import 'yan_menu.dart';
import 'yazma.dart';

bool get _mobil => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Ana kabuk. Telefonda: çekmece (klasörler) + ileti listesi, ileti ayrı sayfada açılır.
/// Geniş ekranda (iPad, Mac, Windows): klasör menüsü | ileti listesi | okuyucu.
class Kabuk extends StatefulWidget {
  const Kabuk({super.key});
  @override
  State<Kabuk> createState() => _KabukState();
}

class _KabukState extends State<Kabuk> with WidgetsBindingObserver {
  final _durum = PostaDurum.ben;
  final _okuyucu = GlobalKey<OkuyucuState>();
  final _abonelikler = <StreamSubscription<dynamic>>[];
  String? _secili;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _durum.sifirla();
    _durum.addListener(_degisti);
    _durum.yukle();
    _abonelikler.add(Canli.ben.olaylar.listen(_canliOlay));
    Canli.ben.baslat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bildirimleriKur());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durum.removeListener(_degisti);
    for (final a in _abonelikler) {
      a.cancel();
    }
    Canli.ben.durdur();
    super.dispose();
  }

  void _degisti() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Masaüstünde pencere arka plandayken de bağlı kalınır (Windows bildirimleri için).
    if (!_mobil) return;
    if (s == AppLifecycleState.resumed) {
      Canli.ben.baslat();
      _durum.sayilariYenile();
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      Canli.ben.durdur();
    }
  }

  void _canliOlay(CanliOlay o) {
    if (o.tur == 'new_mail' || o.tur == 'changed' || o.tur == 'scheduled') {
      _durum.sayilariYenile();
    }
    if (o.tur == 'new_mail') unawaited(Bildirim.canliOlay(o));
  }

  Future<void> _bildirimleriKur() async {
    if (Push.destekli) {
      _abonelikler.add(Push.acildi.listen(_bildirimAcildi));
      final ilk = await Push.baslangic();
      if (ilk != null) _bildirimAcildi(ilk);
      unawaited(Push.kaydet(Uyg.api, yol: Uyg.pushYolu, konu: Uyg.pushKonu));
    }
    if (Bildirim.yerel) {
      await Bildirim.hazirla();
      _abonelikler.add(Bildirim.acildi.listen(_iletiAc));
      final ilk = await Bildirim.baslangic();
      if (ilk != null) _iletiAc(ilk);
      if (Bildirim.android) {
        await Bildirim.izinIste();
        await Bildirim.arkaPlanAyarla(await Bildirim.arkaPlanAcik());
      }
    }
  }

  void _bildirimAcildi(Map<String, dynamic> v) {
    final id = '${v['message_id'] ?? ''}';
    if ((v['kind'] == null || v['kind'] == 'mail') && id.isNotEmpty) _iletiAc(id);
  }

  /// Bildirimden gelen ileti kimliğini açar.
  void _iletiAc(String id) {
    if (id.isEmpty || !mounted) return;
    if (context.genis) {
      setState(() => _secili = id);
    } else {
      kokGezgin.currentState?.popUntil((r) => r.isFirst);
      final c = kokGezgin.currentContext;
      if (c != null) okuyucuAc(c, id);
    }
  }

  Future<void> _ac(IletiOzet m) async {
    if (m.klasorRolu == 'drafts') {
      try {
        final d = await Posta.ileti(m.id);
        if (mounted) await yazmaAc(context, taslakHazirla(d));
      } catch (e) {
        bildir('Taslak açılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
      }
      return;
    }
    if (context.genis) {
      setState(() => _secili = m.id);
    } else {
      await okuyucuAc(context, m.id);
    }
  }

  void _yeni([YazmaBaslangic? b]) => yazmaAc(context, b);

  void _sec(Konum k) {
    _durum.git(k);
    setState(() => _secili = null);
  }

  /// Klavye kısayolu yalnızca bir metin alanına yazılmıyorken çalışır.
  VoidCallback _kisayol(VoidCallback f) => () {
    final odak = FocusManager.instance.primaryFocus?.context;
    if (odak != null && (odak.widget is EditableText || odak.findAncestorStateOfType<EditableTextState>() != null)) return;
    f();
  };

  @override
  Widget build(BuildContext context) {
    final genis = context.genis;
    final konum = _durum.konum;
    final kisayollar = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyC): _kisayol(_yeni),
      const SingleActivator(LogicalKeyboardKey.keyR): _kisayol(() => _okuyucu.currentState?.yanitla()),
      const SingleActivator(LogicalKeyboardKey.keyA): _kisayol(() => _okuyucu.currentState?.yanitla(tumu: true)),
      const SingleActivator(LogicalKeyboardKey.keyF): _kisayol(() => _okuyucu.currentState?.ilet()),
      const SingleActivator(LogicalKeyboardKey.keyE): _kisayol(() => _okuyucu.currentState?.arsivle()),
      const SingleActivator(LogicalKeyboardKey.delete): _kisayol(() => _okuyucu.currentState?.sil()),
      const SingleActivator(LogicalKeyboardKey.backspace, meta: true): _kisayol(() => _okuyucu.currentState?.sil()),
    };

    Widget icerik;
    if (konum == null) {
      icerik = Scaffold(
        drawer: genis ? null : Drawer(child: YanMenu(sec: _sec, cekmecede: true)),
        appBar: AppBar(title: const Text('BogaMail')),
        body: _durum.hata != null ? Durum.hata(_durum.hata!, tekrar: _durum.yukle) : const Center(child: CircularProgressIndicator.adaptive()),
      );
    } else {
      final liste = IletiListesi(
        konum: konum,
        ac: _ac,
        seciliId: genis ? _secili : null,
        cekmece: genis ? null : Drawer(width: 320, child: YanMenu(sec: _sec, cekmecede: true)),
        fab: genis
            ? null
            : FloatingActionButton.extended(onPressed: _yeni, tooltip: 'Yeni ileti (C)', icon: const Icon(Icons.edit_rounded), label: const Text('Yeni ileti')),
        kaldirildi: (s) {
          if (_secili != null && s.contains(_secili)) setState(() => _secili = null);
        },
      );
      if (!genis) {
        icerik = liste;
      } else {
        final r = context.r;
        final en = MediaQuery.sizeOf(context).width;
        icerik = Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                SizedBox(
                  width: en >= 1250 ? 280 : 250,
                  child: YanMenu(sec: _sec, yeniIleti: _yeni),
                ),
                VerticalDivider(width: 1, color: r.kenar),
                SizedBox(width: en >= 1400 ? 440 : 380, child: liste),
                VerticalDivider(width: 1, color: r.kenar),
                Expanded(
                  child: _secili == null
                      ? ColoredBox(
                          color: r.kart,
                          child: const Durum.bos('Okumak için bir ileti seçin', ikon: Icons.mark_email_read_outlined),
                        )
                      : Okuyucu(key: _okuyucu, id: _secili!, kaldirildi: () => setState(() => _secili = null)),
                ),
              ],
            ),
          ),
        );
      }
    }
    return CallbackShortcuts(
      bindings: kisayollar,
      child: Focus(autofocus: true, child: icerik),
    );
  }
}
