// Okuyucu parçaları: güvenlik bantları, alıcı çipleri, konuşma şeridi ve yanıt çubuğu.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/yardimci.dart';

enum BantTuru { tehlike, uyari, bilgi }

/// Güvenlik / bilgi bandı: renkli sol şerit, simge, başlık ve açıklama.
class GuvenlikBandi extends StatelessWidget {
  const GuvenlikBandi({super.key, required this.tur, required this.baslik, this.metin, this.ikon});
  final BantTuru tur;
  final String baslik;
  final String? metin;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final renk = switch (tur) {
      BantTuru.tehlike => Marka.gul,
      BantTuru.uyari => Marka.kehribar,
      BantTuru.bilgi => r.vurgu,
    };
    final simge =
        ikon ??
        switch (tur) {
          BantTuru.tehlike => Simge.tehlike,
          BantTuru.uyari => Simge.uyari,
          BantTuru.bilgi => Simge.bilgi,
        };
    return Semantics(
      container: true,
      label: '${tur == BantTuru.tehlike ? 'Güvenlik uyarısı' : 'Uyarı'}: $baslik',
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: r.koyu ? .16 : .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: renk.withValues(alpha: .35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: renk),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(simge, color: renk, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              baslik,
                              style: TextStyle(fontWeight: FontWeight.w600, color: r.metin, fontSize: 13.5),
                            ),
                            if (metin != null && metin!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(metin!, style: TextStyle(color: r.soluk, fontSize: 12.5, height: 1.35)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// İstemci tarafı sezgiler: yürütülebilir/makrolu ekler ve görünen adında başka adres taşıyan gönderen.
List<GuvenlikBandi> sezgiselUyarilar(IletiDetay d) {
  final out = <GuvenlikBandi>[];
  final riskli = d.gorunum.dosyaEkleri.where((e) => ekRiskli(e.ad)).map((e) => e.ad).toList();
  if (riskli.isNotEmpty) {
    out.add(
      GuvenlikBandi(
        tur: BantTuru.tehlike,
        baslik: 'Riskli ek',
        metin: '${riskli.join(', ')} çalıştırılabilir kod veya makro içerebilir. Göndereni tanımıyorsanız açmayın.',
        ikon: Simge.tehlikeli,
      ),
    );
  }
  final g = d.gorunum.kimden.isNotEmpty ? d.gorunum.kimden.first : null;
  if (g != null && g.ad.contains('@')) {
    final adDaki = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+').firstMatch(g.ad)?.group(0)?.toLowerCase();
    if (adDaki != null && adDaki != g.eposta.toLowerCase()) {
      out.add(
        GuvenlikBandi(
          tur: BantTuru.uyari,
          baslik: 'Gönderen adresi farklı',
          metin: 'Görünen ad "$adDaki" diyor ama ileti ${g.eposta} adresinden geldi. Kimlik avı olabilir.',
          ikon: Simge.kisiYok,
        ),
      );
    }
  }
  return out;
}

bool ekRiskli(String ad) {
  final a = ad.toLowerCase();
  return RegExp(r'\.(exe|scr|bat|cmd|com|pif|vbs|vbe|js|jse|wsf|wsh|hta|msi|ps1|jar|lnk|iso|img|docm|xlsm|pptm|dotm|xlam)$').hasMatch(a);
}

/// "Kime" satırı: alıcılar çip olarak; siz vurgulanır, fazlası "+N".
class AliciCipleri extends StatelessWidget {
  const AliciCipleri({super.key, required this.etiket, required this.adresler, this.azami = 3});
  final String etiket;
  final List<Adres> adresler;
  final int azami;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (adresler.isEmpty) return const SizedBox.shrink();
    final ben = Uyg.adres.toLowerCase();
    final gorunen = adresler.take(azami).toList();
    Widget cip(String t, {bool vurgu = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: vurgu ? r.vurguYumusak : r.ic, borderRadius: BorderRadius.circular(20)),
      child: Text(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, fontWeight: vurgu ? FontWeight.w600 : FontWeight.w500, color: vurgu ? r.vurgu : r.soluk),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$etiket ',
            style: TextStyle(fontSize: 12, color: r.silik, fontWeight: FontWeight.w600),
          ),
          for (final a in gorunen) Tooltip(message: a.eposta, child: a.eposta.toLowerCase() == ben ? cip('siz', vurgu: true) : cip(a.gorunen)),
          if (adresler.length > azami) cip('+${adresler.length - azami}'),
        ],
      ),
    );
  }
}

/// Konuşma şeridi: aynı konudaki diğer iletiler (yanıtlar, iletmeler) katlanabilir bir kartta.
class KonusmaSeridi extends StatefulWidget {
  const KonusmaSeridi({super.key, required this.iletiId, required this.konu, required this.ac});
  final String iletiId;
  final String konu;
  final ValueChanged<IletiOzet> ac;

  /// "Re: Fwd: YNT: Konu" → "Konu".
  static String yalinKonu(String k) {
    var s = k.trim();
    final on = RegExp(r'^(re|fw|fwd|ynt|ilt|cvp|yanıt|ilet|aw|wg|sv|tr)\s*(\[\d+\])?\s*:\s*', caseSensitive: false);
    while (on.hasMatch(s)) {
      s = s.replaceFirst(on, '').trim();
    }
    return s;
  }

  @override
  State<KonusmaSeridi> createState() => _KonusmaSeridiState();
}

class _KonusmaSeridiState extends State<KonusmaSeridi> {
  List<IletiOzet>? _l;
  bool _acik = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final k = KonusmaSeridi.yalinKonu(widget.konu);
    if (k.length < 3) return;
    try {
      final s = await Posta.liste(gorunum: 'all', arama: k, alan: 'subject', boyut: 25);
      final l = s.ogeler.where((m) => m.id != widget.iletiId && KonusmaSeridi.yalinKonu(m.konu).toLowerCase() == k.toLowerCase()).toList();
      if (mounted) setState(() => _l = l);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    if (l == null || l.isEmpty) return const SizedBox.shrink();
    final r = context.r;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: r.kart,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: r.kenar),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            key: const ValueKey('konusma-ac'),
            onTap: () => setState(() => _acik = !_acik),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Icon(Simge.sohbet, size: 18, color: r.vurgu),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu konuşmada ${l.length} ileti daha',
                      style: TextStyle(fontWeight: FontWeight.w600, color: r.metin, fontSize: 13.5),
                    ),
                  ),
                  Icon(_acik ? Simge.yukari : Simge.asagi, color: r.silik),
                ],
              ),
            ),
          ),
          if (_acik)
            for (final m in l)
              InkWell(
                onTap: () => widget.ac(m),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: r.kenar.withValues(alpha: .7))),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      Avatar(adresCoz(m.kimden).gorunen, boyut: 30, tohum: adresCoz(m.kimden).eposta),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    adresCoz(m.kimden).gorunen,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: m.okundu ? FontWeight.w500 : FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                                Text(kisaZaman(m.tarih), style: TextStyle(fontSize: 11.5, color: r.silik)),
                              ],
                            ),
                            Text(
                              m.onizleme.isNotEmpty ? m.onizleme : m.konu,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: r.soluk),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Alt yanıt çubuğu: Yanıtla (birincil), Tümünü yanıtla, İlet.
class YanitCubugu extends StatelessWidget {
  const YanitCubugu({super.key, required this.yanitla, required this.tumunu, required this.ilet, this.tumuGoster = true});
  final VoidCallback yanitla;
  final VoidCallback tumunu;
  final VoidCallback ilet;
  final bool tumuGoster;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    const boyut = Size(0, 46);
    return Container(
      decoration: BoxDecoration(
        color: r.kart,
        border: Border(top: BorderSide(color: r.kenar)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: FilledButton.icon(
                key: const ValueKey('yanitla'),
                style: FilledButton.styleFrom(minimumSize: boyut, backgroundColor: r.vurgu, foregroundColor: Colors.white),
                onPressed: yanitla,
                icon: const Icon(Simge.yanitla, size: 19),
                label: const Text('Yanıtla', maxLines: 1),
              ),
            ),
            if (tumuGoster) ...[
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: boyut, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: tumunu,
                  icon: const Icon(Simge.tumuneYanitla, size: 19),
                  label: const Text('Tümünü', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: boyut, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: ilet,
                icon: const Icon(Simge.ilet, size: 19),
                label: const Text('İlet', maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Web reader: temiz iletide "Spam denetimi: puan -0.7 (temiz)" — dokununca eşleşen kurallar (eş aralıklı haplar).
class SpamDenetimi extends StatefulWidget {
  const SpamDenetimi({super.key, required this.puan, required this.kurallar});
  final double puan;
  final List<String> kurallar;

  @override
  State<SpamDenetimi> createState() => _SpamDenetimiState();
}

class _SpamDenetimiState extends State<SpamDenetimi> {
  bool _acik = false;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Column(
      key: const ValueKey('spam-denetimi'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _acik = !_acik),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: _acik ? .25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Simge.ileri, size: 12, color: r.silik),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('Spam denetimi: puan ${widget.puan.toStringAsFixed(1)} (temiz)', style: TextStyle(fontSize: 12, color: r.silik)),
                ),
              ],
            ),
          ),
        ),
        if (_acik)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final k in widget.kurallar)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      k,
                      style: TextStyle(fontSize: 11.5, color: r.silik, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
