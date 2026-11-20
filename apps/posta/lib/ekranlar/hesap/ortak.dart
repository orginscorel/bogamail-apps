import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

/// Veri yükleyen yönetim sayfası iskeleti: yükleniyor / hata / içerik, aşağı çekerek yenileme, en fazla 760 px genişlik.
class YukleyiciSayfa<T> extends StatefulWidget {
  const YukleyiciSayfa({super.key, required this.baslik, required this.yukle, required this.govde, this.eylemler, this.fab, this.altBaslik});
  final String baslik;
  final String? altBaslik;
  final Future<T> Function() yukle;

  /// [yenile]: veriyi yeniden alır.
  final List<Widget> Function(BuildContext context, T veri, Future<void> Function() yenile) govde;
  final List<Widget> Function(BuildContext context, Future<void> Function() yenile)? eylemler;
  final Widget Function(BuildContext context, Future<void> Function() yenile)? fab;

  @override
  State<YukleyiciSayfa<T>> createState() => _YukleyiciSayfaState<T>();
}

class _YukleyiciSayfaState<T> extends State<YukleyiciSayfa<T>> {
  T? _veri;
  String? _hata;
  bool _yuklendi = false;

  @override
  void initState() {
    super.initState();
    _yenile();
  }

  Future<void> _yenile() async {
    try {
      final v = await widget.yukle();
      if (!mounted) return;
      setState(() {
        _veri = v;
        _hata = null;
        _yuklendi = true;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    Widget govde;
    if (_hata != null && !_yuklendi) {
      govde = Durum.hata(
        _hata!,
        tekrar: () {
          setState(() => _hata = null);
          _yenile();
        },
      );
    } else if (!_yuklendi) {
      govde = const Durum.yukleniyor();
    } else {
      govde = RefreshIndicator(
        onRefresh: _yenile,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (widget.altBaslik != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(widget.altBaslik!, style: TextStyle(color: r.soluk, fontSize: 13.5, height: 1.4)),
                  ),
                ...widget.govde(context, _veri as T, _yenile),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.baslik), actions: widget.eylemler?.call(context, _yenile)),
      floatingActionButton: _yuklendi ? widget.fab?.call(context, _yenile) : null,
      body: govde,
    );
  }
}

/// Listenin boş olduğu durumda kart içinde açıklama.
class BosKart extends StatelessWidget {
  const BosKart(this.metin, {super.key, this.ikon = Simge.gelen});
  final String metin;
  final IconData ikon;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Kutu(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: r.vurguYumusak, shape: BoxShape.circle),
            child: Icon(ikon, color: r.vurgu, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            metin,
            textAlign: TextAlign.center,
            style: TextStyle(color: r.soluk, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Kart içinde satırlar arası ayırıcıyla liste.
class KartListe extends StatelessWidget {
  const KartListe({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Kutu(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(indent: 16, endIndent: 16), children[i]],
      ],
    ),
  );
}

/// Bir kez gösterilen gizli değer (uygulama şifresi, kurtarma kodları) için kopyalanabilir kutu.
Future<void> gizliGoster(BuildContext context, String baslik, String aciklama, String deger) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text(baslik, style: gosterim(19, agirlik: FontWeight.w600)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(aciklama),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.r.ic, borderRadius: BorderRadius.circular(12)),
          child: SelectableText(
            deger,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
    actions: [
      TextButton.icon(onPressed: () => kopyala(deger), icon: const Icon(Simge.kopyala, size: 18), label: const Text('Kopyala')),
      FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam')),
    ],
  ),
);
