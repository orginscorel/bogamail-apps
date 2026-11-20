import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../veri/json.dart';
import 'bolumler.dart';
import 'bildirim_izni.dart';
import 'hesap_blogu.dart';
import 'taklit_islemleri.dart';
import '../ortak/simgeler.dart';
import '../veri/arkaplan.dart';
import '../veri/bildirim.dart';
import '../ortak/tablo.dart' show trBuyuk;

/// Ana kabuk: geniş ekranda gruplu yan menü (rozetler, sürüm, çıkış), telefonda alt gezinme çubuğu (ilk dört bölüm)
/// ve gruplu "Daha fazla" ekranı. Gövdenin üstünde müşteri görünümü ve güncelleme bantları yer alır.
/// Açılışta ve uygulama öne geldiğinde güncelleme denetlenir, rozet sayaçları yenilenir.
class Kabuk extends StatefulWidget {
  const Kabuk({super.key});
  @override
  State<Kabuk> createState() => _KabukState();
}

class _KabukState extends State<Kabuk> with WidgetsBindingObserver {
  Bolum _bolum = Bolum.ozet;
  bool _dahaFazla = false;
  final _acilan = <Bolum>{Bolum.ozet};
  StreamSubscription<Map<String, dynamic>>? _push;
  StreamSubscription<String>? _yerelBildirim;
  Timer? _rozetSayaci;
  final _izleyici = UygulamaIzleyici();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    kabukKurucu ??= () => const Kabuk();
    bolumIstegi.addListener(_istek);
    _pushHazirla();
    _arkaplanHazirla();
    Guncelleme.denetle(Uyg.api);
    _rozetleriYenile();
    _rozetSayaci = Timer.periodic(const Duration(minutes: 2), (_) => _rozetleriYenile());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    bolumIstegi.removeListener(_istek);
    _push?.cancel();
    _yerelBildirim?.cancel();
    _izleyici.durdur();
    _rozetSayaci?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Guncelleme.denetle(Uyg.api);
      _rozetleriYenile();
      Bildirim.yenile(); // kullanıcı sistem ayarlarından izni açmış olabilir
    }
  }

  /// Menü rozetleri: etkin alarm sayısı, kuyruk derinliği, karantinada bekleyen ileti.
  Future<void> _rozetleriYenile() async {
    Future<Object?> dene(Future<dynamic> Function() f) async {
      try {
        return await f();
      } catch (_) {
        return null;
      }
    }

    final s = await Future.wait<Object?>([
      dene(() => Uyg.api.get('/api/v1/alerts/active')),
      Bolum.kuyruk.gorunur ? dene(() => Uyg.api.get('/api/v1/stats/overview')) : Future.value(null),
      Bolum.karantina.gorunur ? dene(() => Uyg.api.get('/api/v1/quarantine', q: {'status': 'held'})) : Future.value(null),
    ]);
    if (!mounted) return;
    final m = <Bolum, int>{};
    if (s[0] != null) m[Bolum.alarmlar] = haritalar(harita(s[0])['items']).length;
    if (s[1] != null) m[Bolum.kuyruk] = tamsayi(harita(s[1])['queue_depth']);
    if (s[2] != null) m[Bolum.karantina] = tamsayi(harita(harita(s[2])['summary'])['held']);
    bolumRozetleri.value = m;
  }

  Future<void> _pushHazirla() async {
    if (!Push.destekli) return;
    _push = Push.acildi.listen(_bildirimAcildi);
    final ilk = await Push.baslangic();
    if (ilk != null) _bildirimAcildi(ilk);
    // Kabuk açıldıktan sonra cihaz bir kez kaydedilir (izin daha önce sorulmadıysa sistem sorar).
    await Push.kaydet(Uyg.api, yol: Uyg.pushYolu, konu: Uyg.pushKonu);
  }

  /// Bildirim izni tanıtımı, Android ön plan hizmeti / girişte başlat, uygulama içi alarm yoklaması.
  Future<void> _arkaplanHazirla() async {
    _yerelBildirim = Bildirim.platform.acildi.listen(_yerelAcildi);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await bildirimTanitimi(context);
      await Arkaplan.oturumAcildi();
      if (mounted) _izleyici.baslat();
    });
    final ilk = await Bildirim.platform.baslangic();
    if (ilk != null) _yerelAcildi(ilk);
  }

  void _yerelAcildi(String yuk) {
    if (!mounted || !yuk.startsWith(alarmYukOneki)) return;
    Arkaplan.platform.pencereyiGoster();
    bolumeGit(Bolum.alarmlar);
  }

  void _bildirimAcildi(Map<String, dynamic> v) {
    if (!mounted) return;
    if (metin(v['kind']) == 'alert') {
      Uyg.vurguluAlarm.value = tamsayiYa(v['event_id']);
      bolumeGit(Bolum.alarmlar);
    }
  }

  void _istek() {
    final b = bolumIstegi.value;
    if (b == null || !mounted) return;
    bolumIstegi.value = null;
    _ac(b);
  }

  List<Bolum> get _altCubuk => [
    for (final b in Bolum.anaBolumler)
      if (b.gorunur) b,
  ].take(4).toList();

  void _ac(Bolum b) {
    if (!b.gorunur) return;
    // Açık alt sayfaları kapat (kök kabuğa dön).
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (!context.genis && !_altCubuk.contains(b)) {
      setState(() => _dahaFazla = true);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => b.ekran()));
      return;
    }
    setState(() {
      _bolum = b;
      _dahaFazla = false;
      _acilan.add(b);
    });
  }

  /// Açılmış bölümleri canlı tutar (geri dönünce liste ve kaydırma yeri korunur); açılmamışlar hiç yüklenmez.
  Widget _govde(List<Bolum> bolumler) => IndexedStack(
    index: bolumler.indexOf(_bolum).clamp(0, bolumler.length - 1),
    children: [for (final b in bolumler) _acilan.contains(b) ? KeyedSubtree(key: ValueKey(b), child: b.ekran()) : const SizedBox.shrink()],
  );

  /// Bantlar (müşteri görünümü, güncelleme) + gövde.
  Widget _bantli(Widget govde) => Column(
    children: [
      const TaklitBandi(),
      const BildirimBandi(),
      GuncellemeBandi(api: Uyg.api),
      Expanded(child: govde),
    ],
  );

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder(valueListenable: Uyg.ben, builder: (context, _, _) => context.genis ? _genis(context) : _dar(context));

  Widget _dar(BuildContext context) {
    final alt = _altCubuk;
    if (!alt.contains(_bolum)) _bolum = alt.first;
    final secili = _dahaFazla ? alt.length : alt.indexOf(_bolum);
    return ValueListenableBuilder<Map<Bolum, int>>(
      valueListenable: bolumRozetleri,
      builder: (context, rozet, _) {
        final digerRozet = [
          for (final e in rozet.entries)
            if (!alt.contains(e.key) && e.key.gorunur && e.key != Bolum.kuyruk) e.value,
        ].fold(0, (a, b) => a + b);
        Widget ikon(Bolum b, IconData i) {
          final n = b == Bolum.kuyruk ? 0 : (rozet[b] ?? 0);
          return n > 0 ? Badge(label: Text(n > 99 ? '99+' : '$n'), child: Icon(i)) : Icon(i);
        }

        return Scaffold(
          body: _bantli(
            _dahaFazla
                ? DahaFazlaEkrani(
                    haric: alt,
                    ac: (b) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => b.ekran())),
                  )
                : _govde(alt),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: secili,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) => setState(() {
              if (i == alt.length) {
                _dahaFazla = true;
              } else {
                _dahaFazla = false;
                _bolum = alt[i];
                _acilan.add(_bolum);
              }
            }),
            destinations: [
              for (final b in alt) NavigationDestination(icon: ikon(b, b.ikon), selectedIcon: ikon(b, b.secikIkon), label: _kisa(b), tooltip: b.baslik),
              NavigationDestination(
                icon: digerRozet > 0 ? const Badge(smallSize: 8, child: Icon(Simgeler.menu)) : const Icon(Simgeler.menu),
                label: 'Daha fazla',
                tooltip: 'Diğer bölümler ve ayarlar',
              ),
            ],
          ),
        );
      },
    );
  }

  String _kisa(Bolum b) => switch (b) {
    Bolum.kutular => 'Kutular',
    Bolum.alanlar => 'Alan adları',
    _ => b.baslik,
  };

  Widget _genis(BuildContext context) {
    final hepsi = Bolum.gorunenler;
    if (!hepsi.contains(_bolum)) _bolum = Bolum.ozet;
    final r = context.r;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 272,
            child: YanMenu(secili: _bolum, ac: _ac),
          ),
          VerticalDivider(width: 1, color: r.kenar.withValues(alpha: .6)),
          Expanded(child: _bantli(_govde(hepsi))),
        ],
      ),
    );
  }
}

/// Geniş ekran yan menüsü: panel başlığı, gruplu bölümler (uzun gruplar katlanır), rozetler, sürüm ve çıkış.
class YanMenu extends StatefulWidget {
  const YanMenu({super.key, required this.secili, required this.ac});
  final Bolum secili;
  final void Function(Bolum) ac;
  @override
  State<YanMenu> createState() => _YanMenuState();
}

class _YanMenuState extends State<YanMenu> {
  /// Kullanıcının kapattığı gruplar (seçili bölümün grubu her zaman açıktır).
  final _kapali = <BolumGrubu>{};

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return ColoredBox(
      color: r.kart,
      child: Column(
        children: [
          const PanelBasligi(dolgu: EdgeInsets.fromLTRB(16, 16, 16, 8)),
          Expanded(
            child: ValueListenableBuilder<Map<Bolum, int>>(
              valueListenable: bolumRozetleri,
              builder: (context, rozet, _) => ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                children: [
                  for (final (grup, bolumler) in Bolum.gruplar) ...[
                    _grupBasligi(context, grup, bolumler),
                    if (!_kapali.contains(grup) || bolumler.contains(widget.secili))
                      for (final b in bolumler) _oge(context, b, rozet[b] ?? 0),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
          HesapBlogu(ac: widget.ac, dolgu: const EdgeInsets.fromLTRB(8, 8, 8, 0)),
          const Padding(padding: EdgeInsets.fromLTRB(24, 0, 16, 8), child: SurumEtiketi()),
        ],
      ),
    );
  }

  Widget _grupBasligi(BuildContext context, BolumGrubu g, List<Bolum> bolumler) {
    final r = context.r;
    final katlanir = bolumler.length > 4 && !bolumler.contains(widget.secili);
    final kapali = _kapali.contains(g) && katlanir;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: katlanir ? () => setState(() => kapali ? _kapali.remove(g) : _kapali.add(g)) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                trBuyuk(g.baslik),
                style: TextStyle(color: r.silik, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.2),
              ),
            ),
            if (katlanir) Icon(kapali ? SimgelerKalin.expandMore : SimgelerKalin.expandLess, size: 16, color: r.silik),
          ],
        ),
      ),
    );
  }

  Widget _oge(BuildContext context, Bolum b, int rozet) {
    final r = context.r;
    final secili = b == widget.secili;
    final kritik = b == Bolum.alarmlar || b == Bolum.karantina;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: secili ? r.vurguYumusak : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.ac(b),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(secili ? b.secikIkon : b.ikon, size: 20, color: secili ? r.vurgu : r.soluk),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    b.baslik,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: secili ? FontWeight.w600 : FontWeight.w500, color: secili ? r.metin : r.soluk),
                  ),
                ),
                if (rozet > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: kritik ? Marka.gul : r.ic, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      rozet > 999 ? '999+' : sayiYaz(rozet),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kritik ? Colors.white : r.soluk),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel bağlamı: kimin paneli, kullanıcı adı ve rolü.
class PanelBasligi extends StatelessWidget {
  const PanelBasligi({super.key, this.dolgu = const EdgeInsets.fromLTRB(20, 16, 16, 8)});
  final EdgeInsets dolgu;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final taklit = Uyg.taklit != null;
    return Padding(
      padding: dolgu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BogaIsaret(boyut: 34, isaret: AcilisIsaret.yonetim),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BogaMail', style: gosterim(16, agirlik: FontWeight.w600)),
                    Text(
                      'YÖNETİM',
                      style: TextStyle(color: r.vurgu, fontSize: 10.5, letterSpacing: 2, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Uyg.panelAdi,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                ),
                if (Uyg.panelAlt.isNotEmpty)
                  Text(
                    Uyg.panelAlt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                if (taklit) ...[const SizedBox(height: 8), const Rozet('Müşteri görünümü', renk: Marka.kehribar, ikon: Simgeler.visibility)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Telefon: alt çubukta olmayan bölümler (gruplu, rozetli) ve hesap.
class DahaFazlaEkrani extends StatelessWidget {
  const DahaFazlaEkrani({super.key, required this.haric, required this.ac});
  final List<Bolum> haric;
  final void Function(Bolum) ac;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    bool uygun(Bolum b) => !haric.contains(b) && b != Bolum.ayarlar;
    final gruplar = [
      for (final (g, l) in Bolum.gruplar)
        if (l.any(uygun)) (g, l.where(uygun).toList()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Daha fazla')),
      body: ValueListenableBuilder<Map<Bolum, int>>(
        valueListenable: bolumRozetleri,
        builder: (context, rozet, _) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            const PanelBasligi(dolgu: EdgeInsets.fromLTRB(4, 0, 4, 8)),
            for (final (g, liste) in gruplar) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text(trBuyuk(g.baslik),
                    style: TextStyle(color: r.silik, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1)),
              ),
              Kutu(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, b) in liste.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(b.ikon, color: r.birincil),
                        title: Text(b.baslik),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((rozet[b] ?? 0) > 0)
                              Badge(
                                backgroundColor: b == Bolum.kuyruk ? r.ic : Marka.gul,
                                textColor: b == Bolum.kuyruk ? r.soluk : Colors.white,
                                label: Text(sayiYaz(rozet[b])),
                              ),
                            const SizedBox(width: 4),
                            const Icon(Simgeler.chevronRight),
                          ],
                        ),
                        onTap: () => ac(b),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const Baslik('Hesap'),
            Kutu(padding: EdgeInsets.zero, child: HesapBlogu(ac: ac, dolgu: const EdgeInsets.all(4))),
            const SizedBox(height: 16),
            const SurumEtiketi(ortala: true),
          ],
        ),
      ),
    );
  }
}

Future<void> cikisOnayi(BuildContext context) async {
  if (Uyg.taklit != null) {
    if (await onayla(context, 'Görünümden çıkılsın mı?', mesaj: 'Kendi yönetici panelinize dönersiniz.', evet: 'Görünümden çık')) {
      await gorunumdenCik();
    }
    return;
  }
  if (await onayla(
    context,
    'Çıkış yapılsın mı?',
    mesaj: 'Bu cihazdaki oturum kapatılır ve bu cihaza alarm bildirimi gelmez.',
    evet: 'Çıkış yap',
    tehlikeli: true,
  )) {
    await Uyg.cikis();
  }
}
