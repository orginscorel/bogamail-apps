import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'simgeler.dart';

/// Aranabilir seçim alt sayfası: arama metniyle sunucudan yükler.
Future<T?> araVeSec<T>(
  BuildContext context, {
  required String baslik,
  required String ipucu,
  required Future<List<T>> Function(String q) yukle,
  required String Function(T) ad,
  String? Function(T)? alt,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  builder: (c) => _AraSec<T>(baslik: baslik, ipucu: ipucu, yukle: yukle, ad: ad, alt: alt),
);

class _AraSec<T> extends StatefulWidget {
  const _AraSec({super.key, required this.baslik, required this.ipucu, required this.yukle, required this.ad, this.alt});
  final String baslik, ipucu;
  final Future<List<T>> Function(String q) yukle;
  final String Function(T) ad;
  final String? Function(T)? alt;
  @override
  State<_AraSec<T>> createState() => _AraSecState<T>();
}

class _AraSecState<T> extends State<_AraSec<T>> {
  List<T>? _liste;
  String? _hata;
  int _nesil = 0;

  @override
  void initState() {
    super.initState();
    _ara('');
  }

  Future<void> _ara(String q) async {
    final n = ++_nesil;
    try {
      final l = await widget.yukle(q);
      if (mounted && n == _nesil) {
        setState(() {
          _liste = l;
          _hata = null;
        });
      }
    } catch (e) {
      if (mounted && n == _nesil) setState(() => _hata = hataMetni(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(widget.baslik, style: gosterim(17, agirlik: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(hintText: widget.ipucu, prefixIcon: const Icon(Simgeler.search), isDense: true),
                  onChanged: _ara,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _hata != null
                    ? Durum.hata(_hata!)
                    : _liste == null
                    ? const Durum.yukleniyor()
                    : _liste!.isEmpty
                    ? const Durum.bos('Eşleşen kayıt yok.')
                    : ListView.builder(
                        itemCount: _liste!.length,
                        itemBuilder: (c, i) {
                          final x = _liste![i];
                          final a = widget.alt?.call(x);
                          return ListTile(title: Text(widget.ad(x)), subtitle: a == null || a.isEmpty ? null : Text(a), onTap: () => Navigator.pop(c, x));
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Organizasyon?> musteriSec(BuildContext context) => araVeSec<Organizasyon>(
  context,
  baslik: 'Müşteri seçin',
  ipucu: 'Müşteri ara…',
  yukle: (q) async => Sayfa.coz(
    await Uyg.api.get('/api/v1/organizations', q: {'page_size': '100', 'sort': 'name', 'order': 'asc', if (q.isNotEmpty) 'q': q}),
    Organizasyon.coz,
  ).ogeler,
  ad: (o) => o.ad,
  alt: (o) => [?o.paketAdi, if (o.durum != 'active') 'askıda'].join(' · '),
);

Future<AlanAdi?> alanSec(BuildContext context, {String? orgId, bool yalnizHosting = true}) => araVeSec<AlanAdi>(
  context,
  baslik: 'Alan adı seçin',
  ipucu: 'Alan adı ara…',
  yukle: (q) async => Sayfa.coz(
    await Uyg.api.get(
      '/api/v1/domains',
      q: {'page_size': '100', 'sort': 'name', 'order': 'asc', if (yalnizHosting) 'mode': 'hosting', 'organization_id': ?orgId, if (q.isNotEmpty) 'q': q},
    ),
    AlanAdi.coz,
  ).ogeler,
  ad: (d) => d.gorunenAd,
  alt: (d) => Uyg.musteri ? null : d.orgAdi,
);

/// Form içinde seçim alanı görünümü (dokununca seçim açılır).
class SecimAlani extends StatelessWidget {
  const SecimAlani({super.key, required this.etiket, required this.deger, required this.onTap, this.hata});
  final String etiket;
  final String? deger, hata;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(labelText: etiket, errorText: hata, suffixIcon: const Icon(Simgeler.unfoldMore)),
      isEmpty: deger == null,
      child: Text(deger ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}
