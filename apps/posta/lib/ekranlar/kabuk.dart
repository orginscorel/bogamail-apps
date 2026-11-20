import 'dart:async';
import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../oturum.dart';
import '../ortak/html_govde.dart';
import '../veri/bildirim.dart';
import '../veri/birlesik.dart';
import '../veri/canli.dart';
import '../veri/durum.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/sohbet_servisi.dart';
import '../veri/yazma_hazirla.dart';
import 'ileti_listesi.dart';
import 'ayarlar.dart';
import 'birlesik_ekrani.dart';
import 'gorevler/gorevler_ekrani.dart';
import 'sohbet/sohbet_ekrani.dart';
import 'sohbet/sohbet_odasi.dart';
import 'takvim/takvim_ekrani.dart';
import 'okuyucu.dart';
import 'yan_menu.dart';
import 'yazma.dart';

bool get _mobil => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Uygulama bölümleri (alt çubuk / kenar rayı).
enum Modul {
  posta('Posta', Icons.mail_outline_rounded, Icons.mail_rounded),
  sohbet('Sohbet', Icons.forum_outlined, Icons.forum_rounded),
  takvim('Takvim', Icons.calendar_month_outlined, Icons.calendar_month_rounded),
  gorevler('Görevler', Icons.task_alt_outlined, Icons.task_alt_rounded),
  ayarlar('Ayarlar', Icons.settings_outlined, Icons.settings_rounded);

  const Modul(this.ad, this.ikon, this.seciliIkon);
  final String ad;
  final IconData ikon;
  final IconData seciliIkon;
}

/// Ana kabuk. Telefonda alt çubuk: Posta · Sohbet · Takvim · Görevler · Ayarlar (paketinde kapalı bölümler gizlenir).
/// Posta sekmesinin başlığında klasör değiştirici (çekmece) ve arama vardır; ileti ayrı sayfada açılır.
/// Geniş ekranda (iPad, Mac, Windows): bölüm rayı | klasör kenar çubuğu | ileti listesi | okuyucu.
class Kabuk extends StatefulWidget {
  const Kabuk({super.key});
  @override
  State<Kabuk> createState() => _KabukState();
}

class _KabukState extends State<Kabuk> with WidgetsBindingObserver {
  final _durum = PostaDurum.ben;
  final _okuyucu = GlobalKey<OkuyucuState>();
  final _abonelikler = <StreamSubscription<dynamic>>[];
  final _iskele = GlobalKey<ScaffoldState>();
  String? _secili;

  /// Etkin bölüm; açılmış bölümler canlı tutulur (IndexedStack).
  Modul _modul = Modul.posta;
  final _acilanlar = <Modul>{Modul.posta};

  /// Geniş ekranda sohbet bölmesinde açık oda.
  String? _seciliOda;

  /// Hesap değiştirince yeni kabuk eskisi kapanmadan kurulur; yalnızca etkin olan akışı durdurur.
  static _KabukState? _etkin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _durum.sifirla();
    _durum.addListener(_degisti);
    _durum.yukle();
    _etkin = this;
    _abonelikler.add(Canli.ben.olaylar.listen(_canliOlay));
    Canli.ben.durdur(); // hesap değiştiyse yeni oturumla yeniden bağlan
    Canli.ben.baslat();
    SohbetDurum.ben.sifirla();
    SohbetDurum.ben.addListener(_degisti);
    SohbetDurum.ben.baslat();
    BirlesikDurum.ben.addListener(_degisti);
    unawaited(BirlesikDurum.ben.baslat());
    WidgetsBinding.instance.addPostFrameCallback((_) => _bildirimleriKur());
    unawaited(Guncelleme.denetle(Uyg.api));
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) Timer(const Duration(seconds: 1), () => unawaited(webGorunumunuIsit()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durum.removeListener(_degisti);
    SohbetDurum.ben.removeListener(_degisti);
    BirlesikDurum.ben.removeListener(_degisti);
    for (final a in _abonelikler) {
      a.cancel();
    }
    if (_etkin == this) {
      _etkin = null;
      Canli.ben.durdur();
      SohbetDurum.ben.durdur();
      BirlesikDurum.ben.durdur();
    }
    super.dispose();
  }

  void _degisti() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) unawaited(Guncelleme.denetle(Uyg.api));
    // Masaüstünde pencere arka plandayken de bağlı kalınır (Windows bildirimleri için).
    if (!_mobil) return;
    if (s == AppLifecycleState.resumed) {
      Canli.ben.baslat();
      _durum.sayilariYenile();
      SohbetDurum.ben.etkin(true);
      SohbetDurum.ben.yenile();
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      Canli.ben.durdur();
      SohbetDurum.ben.etkin(false);
    }
  }

  void _canliOlay(CanliOlay o) {
    _durum.canliOlay(o);
    if (o.tur == 'new_mail') unawaited(Bildirim.canliOlay(o));
    if (o.tur == 'chat_message' && '${o.veri['sender_id'] ?? ''}' != SohbetDurum.benId) unawaited(Bildirim.sohbetOlayi(o));
  }

  Future<void> _bildirimleriKur() async {
    final yazma = Uyg.bekleyenYazma;
    if (yazma != null) {
      // Birleşik görünümden yanıt/iletme için bu hesaba geçildi: yazma penceresi şimdi açılır.
      Uyg.bekleyenYazma = null;
      unawaited(bekleyenYazmayiAc(context, yazma.$1, yazma.$2));
    }
    final bekleyen = Uyg.bekleyenBildirim;
    if (bekleyen != null) {
      Uyg.bekleyenBildirim = null;
      unawaited(_bildirimAcildi(bekleyen));
    }
    if (Push.destekli) {
      _abonelikler.add(Push.acildi.listen(_bildirimAcildi));
      final ilk = await Push.baslangic();
      if (ilk != null) _bildirimAcildi(ilk);
      unawaited(Push.kaydet(Uyg.api, yol: Uyg.pushYolu, konu: Uyg.pushKonu));
    }
    if (Bildirim.yerel) {
      await Bildirim.hazirla();
      _abonelikler.add(Bildirim.acildi.listen(_yerelAcildi));
      final ilk = await Bildirim.baslangic();
      if (ilk != null) _yerelAcildi(ilk);
      if (Bildirim.android) {
        await Bildirim.izinIste();
        await Bildirim.arkaPlanAyarla(await Bildirim.arkaPlanAcik());
      }
    }
  }

  void _yerelAcildi(String yuk) {
    if (yuk.startsWith(Bildirim.sohbetOneki)) {
      odaAc(yuk.substring(Bildirim.sohbetOneki.length));
    } else {
      _iletiAc(yuk);
    }
  }

  /// APNs bildirimine dokunuldu: başka hesaba aitse önce o hesaba geçilir (yeni kabuk açılışta yeniden işler).
  Future<void> _bildirimAcildi(Map<String, dynamic> v) async {
    final hesap = '${v['account'] ?? ''}'.trim().toLowerCase();
    if (hesap.isNotEmpty && hesap != Uyg.adres.toLowerCase()) {
      Uyg.bekleyenBildirim = v;
      await Uyg.hesabaGec(adres: hesap);
      return;
    }
    final tur = '${v['kind'] ?? 'mail'}';
    if (tur == 'chat') {
      final oda = '${v['room_id'] ?? ''}';
      if (oda.isNotEmpty) odaAc(oda);
      return;
    }
    final id = '${v['message_id'] ?? ''}';
    if (tur == 'mail' && id.isNotEmpty) _iletiAc(id);
  }

  /// Bir sohbet odasını açar (bildirimden ya da başka bir ekrandan).
  void odaAc(String oda) {
    if (oda.isEmpty || !mounted) return;
    kokGezgin.currentState?.popUntil((r) => r.isFirst);
    setState(() => _modulSec(Modul.sohbet));
    if (context.genis) {
      setState(() => _seciliOda = oda);
    } else {
      final c = kokGezgin.currentContext;
      if (c != null) sohbetOdasiAc(c, oda);
    }
  }

  /// Bildirimden gelen ileti kimliğini açar.
  void _iletiAc(String id) {
    if (id.isEmpty || !mounted) return;
    if (context.genis) {
      setState(() {
        _modulSec(Modul.posta);
        _secili = id;
      });
    } else {
      kokGezgin.currentState?.popUntil((r) => r.isFirst);
      setState(() => _modulSec(Modul.posta));
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

  void _modulSec(Modul m) {
    _modul = m;
    _acilanlar.add(m);
  }

  /// Paket özelliğine göre görünen bölümler. Sohbet, sunucu 403 feature_disabled döndürünce de gizlenir.
  List<Modul> get _moduller {
    final a = _durum.ayarlar;
    bool acik(String o) => a == null || a.ozellik(o);
    return [
      Modul.posta,
      if (acik('chat') && !SohbetDurum.ben.kapali) Modul.sohbet,
      if (acik('calendar')) Modul.takvim,
      if (acik('tasks')) Modul.gorevler,
      Modul.ayarlar,
    ];
  }

  Konum? get _gelenKonumu {
    final g = _durum.rolu('inbox');
    return g == null ? null : Konum.klasor(g.id);
  }

  /// Telefonda çekmeceden bir yer seçildi: Posta sekmesindeki liste o konuma geçer.
  void _telefondaSec(Konum k) {
    _durum.git(k);
    setState(() => _modulSec(Modul.posta));
  }

  Widget _yeniDugmesi() =>
      FloatingActionButton.extended(onPressed: _yeni, tooltip: 'Yeni ileti (C)', icon: const Icon(Icons.edit_rounded), label: const Text('Yeni ileti'));

  /// Gelen Kutusu dışındaki klasörlerdeki okunmamışlar (kullanıcı klasörleri + Arşiv).
  int get _digerOkunmamis => _durum.klasorler.where((k) => k.rol == null || k.rol == 'archive').fold(0, (t, k) => t + k.okunmamis);

  Widget _rozetli(IconData ikon, int sayi) =>
      Badge(isLabelVisible: sayi > 0, backgroundColor: context.r.vurgu, textColor: Colors.white, label: Text(sayi > 999 ? '999+' : '$sayi'), child: Icon(ikon));

  int _rozet(Modul m) => switch (m) {
    Modul.posta => _durum.rolu('inbox')?.okunmamis ?? 0,
    Modul.sohbet => SohbetDurum.ben.okunmamis.value,
    _ => 0,
  };

  String _ipucu(Modul m) {
    final n = _rozet(m);
    return n > 0 ? '${m.ad}, $n okunmamış' : m.ad;
  }

  /// Bir bölümün ekranı. [genis]: geniş düzende posta ve sohbet çok bölmeli gösterilir.
  Widget _modulEkrani(Modul m, {required bool genis}) {
    if (!_acilanlar.contains(m)) return const SizedBox.shrink();
    switch (m) {
      case Modul.posta:
        return genis ? _genisPosta() : _telefonPosta();
      case Modul.sohbet:
        if (!genis) return const SohbetEkrani();
        return Row(
          children: [
            SizedBox(
              width: 380,
              child: SohbetEkrani(seciliOda: _seciliOda, odaAc: (o) => setState(() => _seciliOda = o)),
            ),
            VerticalDivider(width: 1, color: context.r.kenar),
            Expanded(
              child: _seciliOda == null
                  ? ColoredBox(
                      color: context.r.kart,
                      child: const Durum.bos('Bir sohbet seçin ya da yeni sohbet başlatın', ikon: Icons.forum_outlined),
                    )
                  : SohbetOdasiEkrani(key: ValueKey(_seciliOda), odaId: _seciliOda!, sayfa: false, kapat: () => setState(() => _seciliOda = null)),
            ),
          ],
        );
      case Modul.takvim:
        return const TakvimEkrani();
      case Modul.gorevler:
        return const GorevlerEkrani();
      case Modul.ayarlar:
        return const AyarlarEkrani();
    }
  }

  Widget _telefonPosta() {
    final konum = _durum.konum ?? _gelenKonumu;
    if (konum == null) return const Durum.yukleniyor();
    if (konum.tur == KonumTur.birlesik) {
      return BirlesikListe(
        key: const ValueKey('birlesik-liste'),
        ac: (o, h) => birlesikOkuyucuAc(context, o, hesap: h),
        fab: _yeniDugmesi(),
        klasorler: () => _iskele.currentState?.openDrawer(),
      );
    }
    return IletiListesi(
      key: ValueKey('liste-${konum.tur.name}-${konum.id}'),
      konum: konum,
      ac: _ac,
      fab: _yeniDugmesi(),
      klasorler: () => _iskele.currentState?.openDrawer(),
      klasorRozeti: konum == _gelenKonumu ? _digerOkunmamis : 0,
    );
  }

  Widget _telefon() {
    final moduller = _moduller;
    if (!moduller.contains(_modul)) _modul = Modul.posta;
    return Scaffold(
      key: _iskele,
      drawer: Drawer(width: 320, child: YanMenu(sec: _telefondaSec, cekmecede: true)),
      drawerEnableOpenDragGesture: _modul == Modul.posta,
      // Güncelleme şeridi varken üst güvenli alanı şerit kullanır; alttaki sayfalar yeniden boşluk bırakmaz.
      body: ValueListenableBuilder<SurumBilgisi?>(
        valueListenable: Guncelleme.yeni,
        builder: (context, yeni, _) => Column(
          children: [
            if (yeni != null) SafeArea(bottom: false, child: GuncellemeBandi(api: Uyg.api)),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: yeni != null,
                child: IndexedStack(index: moduller.indexOf(_modul), children: [for (final m in moduller) _modulEkrani(m, genis: false)]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: moduller.indexOf(_modul),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => setState(() => _modulSec(moduller[i])),
        destinations: [
          for (final m in moduller)
            NavigationDestination(
              key: ValueKey('modul-${m.name}'),
              icon: _rozetli(m.ikon, _rozet(m)),
              selectedIcon: _rozetli(m.seciliIkon, _rozet(m)),
              label: m.ad,
              tooltip: _ipucu(m),
            ),
        ],
      ),
    );
  }

  final _listeAnahtari = GlobalKey<IletiListesiState>();

  /// J / K: okuma bölmesinde sonraki / önceki ileti.
  void _gez(int yon) {
    final s = _secili;
    if (s == null) return;
    final m = _listeAnahtari.currentState?.komsu(s, yon);
    if (m != null) setState(() => _secili = m.id);
  }

  BirlesikOge? _birlesikSecili;
  BirlesikHesap? _birlesikHesap;

  Widget _genisPosta() {
    final konum = _durum.konum!;
    final r = context.r;
    final en = MediaQuery.sizeOf(context).width;
    final birlesik = konum.tur == KonumTur.birlesik;
    final seciliB = _birlesikSecili;
    final onceki = _secili == null ? null : _listeAnahtari.currentState?.komsu(_secili!, -1);
    final sonraki = _secili == null ? null : _listeAnahtari.currentState?.komsu(_secili!, 1);
    final liste = birlesik
        ? BirlesikListe(
            key: const ValueKey('birlesik-liste'),
            seciliAnahtar: seciliB?.anahtar,
            ac: (o, h) => setState(() {
              _birlesikSecili = o;
              _birlesikHesap = h;
            }),
            kaldirildi: (s) {
              if (seciliB != null && s.contains(seciliB.anahtar)) setState(() => _birlesikSecili = null);
            },
          )
        : IletiListesi(
            key: _listeAnahtari,
            konum: konum,
            ac: _ac,
            seciliId: _secili,
            kaldirildi: (s) {
              if (_secili != null && s.contains(_secili)) setState(() => _secili = null);
            },
          );
    return Row(
      children: [
        SizedBox(
          width: en >= 1250 ? 280 : 250,
          child: YanMenu(sec: _sec, yeniIleti: _yeni),
        ),
        VerticalDivider(width: 1, color: r.kenar),
        SizedBox(width: en >= 1400 ? 440 : 380, child: liste),
        VerticalDivider(width: 1, color: r.kenar),
        Expanded(
          child: birlesik
              ? (seciliB == null
                    ? ColoredBox(
                        color: r.kart,
                        child: const Durum.bos('Okumak için soldaki listeden bir ileti seçin', ikon: Icons.layers_outlined),
                      )
                    : BirlesikOkuyucu(oge: seciliB, hesap: _birlesikHesap, kaldirildi: () => setState(() => _birlesikSecili = null)))
              : _secili == null
              ? ColoredBox(
                  color: r.kart,
                  child: const Durum.bos('Okumak için soldaki listeden bir ileti seçin', ikon: Icons.mark_email_read_outlined),
                )
              : Okuyucu(
                  key: _okuyucu,
                  id: _secili!,
                  kaldirildi: () => setState(() => _secili = null),
                  onceki: onceki == null ? null : () => _gez(-1),
                  sonraki: sonraki == null ? null : () => _gez(1),
                ),
        ),
      ],
    );
  }

  Widget _genis() {
    final r = context.r;
    final moduller = _moduller;
    if (!moduller.contains(_modul)) _modul = Modul.posta;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GuncellemeBandi(api: Uyg.api),
            Expanded(
              child: Row(
                children: [
                  NavigationRail(
                    backgroundColor: r.zemin,
                    selectedIndex: moduller.indexOf(_modul),
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: -0.9,
                    indicatorColor: r.vurguYumusak,
                    onDestinationSelected: (i) => setState(() => _modulSec(moduller[i])),
                    destinations: [
                      for (final m in moduller)
                        NavigationRailDestination(
                          icon: Tooltip(message: _ipucu(m), child: _rozetli(m.ikon, _rozet(m))),
                          selectedIcon: _rozetli(m.seciliIkon, _rozet(m)),
                          label: Text(m.ad),
                        ),
                    ],
                  ),
                  VerticalDivider(width: 1, color: r.kenar),
                  Expanded(
                    child: IndexedStack(index: moduller.indexOf(_modul), children: [for (final m in moduller) _modulEkrani(m, genis: true)]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Klavye kısayolu yalnızca bir metin alanına yazılmıyorken çalışır.
  VoidCallback _kisayol(VoidCallback f) => () {
    if (!_metinYaziliyor()) f();
  };

  bool _metinYaziliyor() {
    final odak = FocusManager.instance.primaryFocus?.context;
    return odak != null && (odak.widget is EditableText || odak.findAncestorStateOfType<EditableTextState>() != null);
  }

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
      const SingleActivator(LogicalKeyboardKey.keyJ): _kisayol(() => _gez(1)),
      const SingleActivator(LogicalKeyboardKey.keyK): _kisayol(() => _gez(-1)),
      const SingleActivator(LogicalKeyboardKey.delete): _kisayol(() => _okuyucu.currentState?.sil()),
      const SingleActivator(LogicalKeyboardKey.backspace, meta: true): _kisayol(() => _okuyucu.currentState?.sil()),
    };

    Widget icerik;
    if (konum == null) {
      icerik = Scaffold(
        appBar: AppBar(title: const Text('BogaMail')),
        body: _durum.hata != null ? Durum.hata(_durum.hata!, tekrar: _durum.yukle) : const Center(child: CircularProgressIndicator.adaptive()),
      );
    } else {
      icerik = genis ? _genis() : _telefon();
    }
    // CallbackShortcuts tuşu her durumda yutar (yazarken "selam" → "slm" olurdu); metin alanı odaktayken tuşlar
    // hiç ele alınmadan metin alanına bırakılır.
    return Focus(
      autofocus: true,
      onKeyEvent: (node, olay) {
        if (olay is! KeyDownEvent && olay is! KeyRepeatEvent) return KeyEventResult.ignored;
        if (_metinYaziliyor()) return KeyEventResult.ignored;
        for (final e in kisayollar.entries) {
          if (e.key.accepts(olay, HardwareKeyboard.instance)) {
            e.value();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: icerik,
    );
  }
}
