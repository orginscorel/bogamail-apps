// Ayarlar → Genel (web GeneralSection + UndoSendCard): görünen ad, sayfa başına ileti, yazma biçimi, gönderimi geri al.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../oturum.dart';
import '../../veri/ayar_servisi.dart';
import 'ayar_ortak.dart';

class GenelAyari extends StatelessWidget {
  const GenelAyari({super.key});

  @override
  Widget build(BuildContext context) => SunucuAyarGovdesi(
    olustur: (context, a, kaydet) => [
      _GenelForm(key: ValueKey('genel-${a.gorunenAd}|${a.sayfaBoyutu}|${a.yazmaHtml}'), a: a, kaydet: kaydet),
      IkiSutun(
        children: [
          _GeriAlKarti(a: a, kaydet: kaydet),
          AyarKarti(
            ikon: Icons.dns_outlined,
            baslik: 'Sunucu',
            aciklama: 'Bu uygulamanın bağlandığı BogaMail sunucusu.',
            child: InkWell(
              onTap: () => kopyala(Uyg.api.sunucu, mesaj: 'Sunucu adresi kopyalandı'),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(Uyg.api.sunucu, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  ),
                  const Icon(Icons.copy_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _GenelForm extends StatefulWidget {
  const _GenelForm({super.key, required this.a, required this.kaydet});
  final SunucuAyarlari a;
  final AyarKaydedici kaydet;
  @override
  State<_GenelForm> createState() => _GenelFormState();
}

class _GenelFormState extends State<_GenelForm> {
  late final _ad = TextEditingController(text: widget.a.gorunenAd);
  late final _sayfa = TextEditingController(text: '${widget.a.sayfaBoyutu}');
  late bool _html = widget.a.yazmaHtml;
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _ad.addListener(() => setState(() {}));
    _sayfa.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ad.dispose();
    _sayfa.dispose();
    super.dispose();
  }

  int? get _ps {
    final n = int.tryParse(_sayfa.text.trim());
    return n != null && n >= 10 && n <= 200 ? n : null;
  }

  bool get _adGecerli => _ad.text.trim().length <= 100 && !RegExp(r'[\r\n<>"]').hasMatch(_ad.text);

  bool get _kirli => _ad.text.trim() != widget.a.gorunenAd || _ps != widget.a.sayfaBoyutu || _html != widget.a.yazmaHtml;

  Future<void> _gonder() async {
    final ps = _ps;
    if (ps == null || !_adGecerli) return;
    setState(() => _mesgul = true);
    final d = <String, dynamic>{
      if (_ad.text.trim() != widget.a.gorunenAd) 'display_name': _ad.text.trim(),
      if (ps != widget.a.sayfaBoyutu) 'page_size': ps,
      if (_html != widget.a.yazmaHtml) 'compose_html': _html,
    };
    final ok = await widget.kaydet(d, tamam: 'Genel ayarlar kaydedildi');
    if (ok && d.containsKey('display_name')) {
      final k = Uyg.kutu.value;
      if (k != null) Uyg.kutu.value = {...k, 'display_name': d['display_name']};
    }
    if (mounted) setState(() => _mesgul = false);
  }

  @override
  Widget build(BuildContext context) {
    final ps = _ps;
    return AyarKarti(
      ikon: Icons.tune_rounded,
      baslik: 'Genel',
      aciklama: 'Adınızın nasıl görüneceği ve ileti listesinin düzeni.',
      alt: KaydetDugmesi(key: const ValueKey('genel-kaydet'), etkin: _kirli && ps != null && _adGecerli, mesgul: _mesgul, basildi: _gonder),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AyarAlani(
            etiket: 'Görünen ad',
            ipucu: 'Gönderdiğiniz postalarda adresinizin yanında bu ad görünür. Örnek: Ayşe Yılmaz',
            child: TextField(
              key: const ValueKey('genel-ad'),
              controller: _ad,
              maxLength: 100,
              decoration: InputDecoration(
                hintText: 'Adınız Soyadınız',
                counterText: '',
                errorText: _adGecerli ? null : 'En fazla 100 karakter; < > " işaretleri kullanılamaz.',
              ),
            ),
          ),
          AyarAlani(
            etiket: 'Sayfa başına ileti',
            ipucu: 'Listede bir seferde gösterilecek ileti sayısı (10–200).',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: const ValueKey('genel-sayfa'),
                    controller: _sayfa,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                    decoration: InputDecoration(isDense: true, errorText: ps == null ? '10–200' : null),
                  ),
                ),
                for (final n in const [25, 50, 100]) ChoiceChip(label: Text('$n'), selected: ps == n, onSelected: (_) => _sayfa.text = '$n'),
              ],
            ),
          ),
          AyarAlani(
            etiket: 'Yazma biçimi',
            ipucu:
                'Webmail\'de yeni iletiler hangi düzenleyiciyle açılsın? HTML; kalın, renk, bağlantı gibi biçimlendirmeye izin verir. '
                'Bu uygulamada iletiler düz metin olarak yazılır; imzanız biçimiyle eklenir.',
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('HTML (biçimli)')),
                ButtonSegment(value: false, label: Text('Düz metin')),
              ],
              selected: {_html},
              onSelectionChanged: (s) => setState(() => _html = s.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _GeriAlKarti extends StatefulWidget {
  const _GeriAlKarti({required this.a, required this.kaydet});
  final SunucuAyarlari a;
  final AyarKaydedici kaydet;
  @override
  State<_GeriAlKarti> createState() => _GeriAlKartiState();
}

class _GeriAlKartiState extends State<_GeriAlKarti> {
  bool _mesgul = false;
  @override
  Widget build(BuildContext context) => AyarKarti(
    ikon: Icons.undo_rounded,
    baslik: 'Gönderimi geri al',
    aciklama: 'Gönder\'e bastıktan sonra ileti bu süre boyunca sunucuda bekletilir; "Geri al" ile taslağa döner.',
    child: SecimCipleri<int>(
      etkin: !_mesgul,
      secenekler: const {0: 'Kapalı', 5: '5 saniye', 10: '10 saniye', 20: '20 saniye', 30: '30 saniye'},
      deger: widget.a.geriAlmaSaniye,
      degisti: (n) async {
        if (n == widget.a.geriAlmaSaniye) return;
        setState(() => _mesgul = true);
        await widget.kaydet({'undo_send_seconds': n}, tamam: n == 0 ? 'Gönderimi geri alma kapatıldı' : 'Geri alma süresi $n saniye');
        if (mounted) setState(() => _mesgul = false);
      },
    ),
  );
}
