import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import 'bolumler.dart';

/// Ana kabuk: telefonda alt gezinme çubuğu (Özet, Alan Adları, Posta Kutuları, Kuyruk, Daha Fazla), geniş ekranda
/// tüm bölümleri gösteren yan menü. Bildirime dokunulunca ilgili alarmı açar.
class Kabuk extends StatefulWidget {
  const Kabuk({super.key});
  @override
  State<Kabuk> createState() => _KabukState();
}

class _KabukState extends State<Kabuk> {
  Bolum _bolum = Bolum.ozet;
  bool _dahaFazla = false;
  final _acilan = <Bolum>{Bolum.ozet};
  StreamSubscription<Map<String, dynamic>>? _push;

  @override
  void initState() {
    super.initState();
    bolumIstegi.addListener(_istek);
    _pushHazirla();
  }

  @override
  void dispose() {
    bolumIstegi.removeListener(_istek);
    _push?.cancel();
    super.dispose();
  }

  Future<void> _pushHazirla() async {
    if (!Push.destekli) return;
    _push = Push.acildi.listen(_bildirimAcildi);
    final ilk = await Push.baslangic();
    if (ilk != null) _bildirimAcildi(ilk);
    // Kabuk açıldıktan sonra cihaz bir kez kaydedilir (izin daha önce sorulmadıysa sistem sorar).
    await Push.kaydet(Uyg.api, yol: Uyg.pushYolu, konu: Uyg.pushKonu);
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

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder(valueListenable: Uyg.ben, builder: (context, _, _) => context.genis ? _genis(context) : _dar(context));

  Widget _dar(BuildContext context) {
    final alt = _altCubuk;
    if (!alt.contains(_bolum)) _bolum = alt.first;
    final secili = _dahaFazla ? alt.length : alt.indexOf(_bolum);
    return Scaffold(
      body: _dahaFazla
          ? DahaFazlaEkrani(
              haric: alt,
              ac: (b) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => b.ekran())),
            )
          : _govde(alt),
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
          for (final b in alt) NavigationDestination(icon: Icon(b.ikon), selectedIcon: Icon(b.secikIkon), label: _kisa(b), tooltip: b.baslik),
          const NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'Daha Fazla', tooltip: 'Diğer bölümler ve ayarlar'),
        ],
      ),
    );
  }

  String _kisa(Bolum b) => b == Bolum.kutular ? 'Kutular' : b.baslik;

  Widget _genis(BuildContext context) {
    final hepsi = Bolum.gorunenler;
    if (!hepsi.contains(_bolum)) _bolum = Bolum.ozet;
    final r = context.r;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 268,
            child: NavigationDrawer(
              elevation: 0,
              backgroundColor: r.kart,
              selectedIndex: hepsi.indexOf(_bolum),
              onDestinationSelected: (i) => _ac(hepsi[i]),
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                const PanelBasligi(),
                const SizedBox(height: 8),
                for (final b in hepsi) NavigationDrawerDestination(icon: Icon(b.ikon), selectedIcon: Icon(b.secikIkon), label: Text(b.baslik)),
                const SizedBox(height: 12),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: r.kenar),
          Expanded(child: _govde(hepsi)),
        ],
      ),
    );
  }
}

/// Panel bağlamı: kimin paneli, kullanıcı adı ve rolü.
class PanelBasligi extends StatelessWidget {
  const PanelBasligi({super.key, this.dolgu = const EdgeInsets.fromLTRB(20, 18, 16, 6)});
  final EdgeInsets dolgu;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ad = Uyg.ad.isNotEmpty ? Uyg.ad : Uyg.adres;
    final taklit = Uyg.ben.value?['impersonation'] != null;
    return Padding(
      padding: dolgu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BogaIsaret(boyut: 34, isaret: AcilisIsaret.yonetim),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BogaMail', style: gosterim(16, agirlik: FontWeight.w800)),
                    Text(
                      'YÖNETİM',
                      style: TextStyle(color: r.silik, fontSize: 10.5, letterSpacing: 2, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Uyg.panelAdi,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (Uyg.panelAlt.isNotEmpty)
                  Text(
                    Uyg.panelAlt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: r.silik, fontSize: 12),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Avatar(ad, boyut: 30, tohum: Uyg.adres),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ad,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            rolEtiketi(Uyg.rol),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: r.silik, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (taklit) ...[const SizedBox(height: 8), const Rozet('Müşteri görünümü', renk: Marka.kehribar, ikon: Icons.visibility_rounded)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Telefon: alt çubukta olmayan bölümler ve hesap.
class DahaFazlaEkrani extends StatelessWidget {
  const DahaFazlaEkrani({super.key, required this.haric, required this.ac});
  final List<Bolum> haric;
  final void Function(Bolum) ac;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final liste = [
      for (final b in Bolum.gorunenler)
        if (!haric.contains(b) && b != Bolum.ayarlar) b,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Daha Fazla')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          const PanelBasligi(dolgu: EdgeInsets.fromLTRB(4, 0, 4, 8)),
          if (liste.isNotEmpty) ...[
            const Baslik('Bölümler'),
            Kutu(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, b) in liste.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(b.ikon, color: r.birincil),
                      title: Text(b.baslik),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => ac(b),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const Baslik('Hesap'),
          Kutu(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Bolum.ayarlar.ikon, color: r.birincil),
                  title: const Text('Ayarlar ve profil'),
                  subtitle: const Text('Tema, bildirimler, oturumlar'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => ac(Bolum.ayarlar),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Marka.gul),
                  title: const Text('Çıkış yap', style: TextStyle(color: Marka.gul)),
                  onTap: () => cikisOnayi(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> cikisOnayi(BuildContext context) async {
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
