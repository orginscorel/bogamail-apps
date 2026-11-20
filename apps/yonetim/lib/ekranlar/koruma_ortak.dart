import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../ortak/simgeler.dart';

/// Koruma / trafik ekranlarının ortak küçük parçaları.

/// Küçük bilgi kutusu: etiket, değer, alt satır (ayrıntı panellerinde ızgara hücresi).
class KorumaKutusu extends StatelessWidget {
  const KorumaKutusu({super.key, required this.etiket, required this.deger, this.alt, this.kotu = false, this.renk});
  final String etiket, deger;
  final String? alt;
  final bool kotu;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: r.kart,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: r.kenar),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiket,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            deger,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: kotu ? Marka.gul : (renk ?? r.metin), fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (alt != null && alt!.isNotEmpty)
            Text(
              alt!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: r.silik, fontSize: 11.5),
            ),
        ],
      ),
    );
  }
}

/// Tamsayı form alanı (sınır denetimi çağıran tarafta).
class SayiAlani extends StatelessWidget {
  const SayiAlani({super.key, required this.denetleyici, required this.etiket, this.hata, this.sonEk, this.degisti});
  final TextEditingController denetleyici;
  final String etiket;
  final String? hata, sonEk;
  final ValueChanged<String>? degisti;

  @override
  Widget build(BuildContext context) => TextField(
    controller: denetleyici,
    keyboardType: TextInputType.number,
    onChanged: degisti,
    decoration: InputDecoration(labelText: etiket, errorText: hata, suffixText: sonEk, errorMaxLines: 2),
  );
}

/// Dar ekranda alt alta, geniş ekranda yan yana alanlar.
class YanYana extends StatelessWidget {
  const YanYana({super.key, required this.children, this.esik = 420, this.bosluk = 10});
  final List<Widget> children;
  final double esik, bosluk;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (c, k) {
      if (k.maxWidth < esik) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: bosluk), children[i]],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(width: bosluk), Expanded(child: children[i])],
        ],
      );
    },
  );
}

/// Eşit genişlikte düğme içi yükleniyor göstergesi.
Widget mesgulYazi(bool mesgul, String yazi) =>
    mesgul ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(yazi);

/// Eş aralıklı, seçilebilir metin bloğu (ham MIME, başlıklar).
class KodBlogu extends StatelessWidget {
  const KodBlogu(this.metin, {super.key, this.enFazlaYukseklik = 520});
  final String metin;
  final double enFazlaYukseklik;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      constraints: BoxConstraints(maxHeight: enFazlaYukseklik),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          metin,
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4, color: r.metin),
        ),
      ),
    );
  }
}

/// Sayı metni: tamsayıya çevirir, [enAz]–[enCok] dışındaysa null.
int? aralikta(String s, int enAz, int enCok) {
  final n = int.tryParse(s.trim());
  if (n == null || n < enAz || n > enCok) return null;
  return n;
}

/// Kaydırılan bir içeriğin içinde (yükseklik sınırsız) tek istekle yüklenen bölüm: yükleniyor / hata / içerik.
class GomuluYukleme<T> extends StatefulWidget {
  const GomuluYukleme({super.key, required this.getir, required this.icerik});
  final Future<T> Function() getir;
  final Widget Function(BuildContext context, T veri, Future<void> Function() yenile) icerik;

  @override
  State<GomuluYukleme<T>> createState() => _GomuluYuklemeState<T>();
}

class _GomuluYuklemeState<T> extends State<GomuluYukleme<T>> {
  T? _veri;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yenile();
  }

  Future<void> _yenile() async {
    try {
      final v = await widget.getir();
      if (mounted) {
        setState(() {
          _veri = v;
          _hata = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _veri;
    if (v != null) return widget.icerik(context, v, _yenile);
    if (_hata != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Marka.gul.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Simgeler.errorOutline, color: Marka.gul, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(_hata!)),
            TextButton(onPressed: _yenile, child: const Text('Tekrar dene')),
          ],
        ),
      );
    }
    return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator(minHeight: 2));
  }
}
