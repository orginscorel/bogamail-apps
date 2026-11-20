import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/yardimci.dart';

/// Bir alıcı alanının (Kime/Bilgi/Gizli) durumu.
class AliciDenetci extends ChangeNotifier {
  AliciDenetci([List<Adres>? ilk]) : adresler = [...?ilk];
  final List<Adres> adresler;
  final metin = TextEditingController();

  /// Yazılıp henüz eklenmemiş metni de katarak gönderilecek liste. Geçersiz metin varsa [gecersiz] döner.
  ({List<Adres> liste, String? gecersiz}) topla() {
    final t = metin.text.trim();
    if (t.isEmpty) return (liste: adresler, gecersiz: null);
    final ek = adresListesiCoz(t);
    final kotu = ek.where((a) => !gecerliEposta(a.eposta)).map((a) => a.eposta.isEmpty ? a.ad : a.eposta).firstOrNull;
    if (kotu != null) return (liste: adresler, gecersiz: kotu);
    return (liste: [...adresler, ...ek.where((a) => !adresler.contains(a))], gecersiz: null);
  }

  /// Metni ayrıştırıp çiplere çevirir; geçersiz kalan kısmı alanda bırakır.
  bool isle() {
    final t = metin.text.trim();
    if (t.isEmpty) return true;
    final parcalar = adresListesiCoz(t);
    final kalan = <String>[];
    for (final a in parcalar) {
      if (gecerliEposta(a.eposta)) {
        if (!adresler.contains(a)) adresler.add(a);
      } else {
        kalan.add(a.ad.isNotEmpty && a.eposta.isEmpty ? a.ad : adresYaz(a));
      }
    }
    metin.text = kalan.join(', ');
    notifyListeners();
    return kalan.isEmpty;
  }

  void ekle(Adres a) {
    if (!adresler.contains(a)) adresler.add(a);
    metin.clear();
    notifyListeners();
  }

  void cikar(Adres a) {
    adresler.remove(a);
    notifyListeners();
  }

  bool get bos => adresler.isEmpty && metin.text.trim().isEmpty;

  @override
  void dispose() {
    metin.dispose();
    super.dispose();
  }
}

/// Çipli alıcı alanı + kişi önerileri (GET /api/v1/mail/contacts/suggest).
class AdresAlani extends StatefulWidget {
  const AdresAlani({super.key, required this.etiket, required this.denetci, this.sag, this.otomatikOdak = false, this.degisti});
  final String etiket;
  final AliciDenetci denetci;
  final Widget? sag;
  final bool otomatikOdak;
  final VoidCallback? degisti;

  @override
  State<AdresAlani> createState() => _AdresAlaniState();
}

class _AdresAlaniState extends State<AdresAlani> {
  final _odak = FocusNode();
  List<Oneri> _oneriler = const [];
  Timer? _bekle;
  int _istek = 0;
  bool _hata = false;

  @override
  void initState() {
    super.initState();
    widget.denetci.addListener(_yenile);
    _odak.addListener(() {
      if (!_odak.hasFocus) {
        final ok = widget.denetci.isle();
        setState(() {
          _hata = !ok;
          _oneriler = const [];
        });
      }
    });
  }

  @override
  void dispose() {
    widget.denetci.removeListener(_yenile);
    _bekle?.cancel();
    _odak.dispose();
    super.dispose();
  }

  void _yenile() {
    if (mounted) setState(() {});
    widget.degisti?.call();
  }

  void _yazildi(String v) {
    if (_hata) setState(() => _hata = false);
    if (RegExp(r'[,;]\s*$').hasMatch(v) || (v.endsWith(' ') && gecerliEposta(v.trim()))) {
      final ok = widget.denetci.isle();
      setState(() {
        _hata = !ok;
        _oneriler = const [];
      });
      return;
    }
    widget.degisti?.call();
    _bekle?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      if (_oneriler.isNotEmpty) setState(() => _oneriler = const []);
      return;
    }
    _bekle = Timer(const Duration(milliseconds: 220), () async {
      final no = ++_istek;
      try {
        final l = await Posta.oneriler(q);
        if (!mounted || no != _istek || !_odak.hasFocus) return;
        setState(() => _oneriler = l.where((o) => !widget.denetci.adresler.contains(o.adres)).take(6).toList());
      } catch (_) {}
    });
  }

  KeyEventResult _tus(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.backspace && widget.denetci.metin.text.isEmpty && widget.denetci.adresler.isNotEmpty) {
      widget.denetci.cikar(widget.denetci.adresler.last);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = widget.denetci;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _odak.requestFocus(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(widget.etiket, style: TextStyle(color: r.silik, fontSize: 14)),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final a in d.adresler)
                        Tooltip(
                          message: a.eposta,
                          child: InputChip(
                            avatar: Avatar(a.gorunen, boyut: 22, tohum: a.eposta),
                            label: Text(a.gorunen, overflow: TextOverflow.ellipsis),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            deleteButtonTooltipMessage: 'Kaldır',
                            onDeleted: () => d.cikar(a),
                          ),
                        ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 140),
                        child: IntrinsicWidth(
                          child: Focus(
                            onKeyEvent: _tus,
                            child: TextField(
                              controller: d.metin,
                              focusNode: _odak,
                              autofocus: widget.otomatikOdak,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: TextInputAction.next,
                              onChanged: _yazildi,
                              onSubmitted: (_) {
                                if (_oneriler.isNotEmpty && !gecerliEposta(d.metin.text)) {
                                  d.ekle(_oneriler.first.adres);
                                  setState(() => _oneriler = const []);
                                } else {
                                  setState(() => _hata = !d.isle());
                                }
                                _odak.requestFocus();
                              },
                              style: TextStyle(fontSize: 14.5, color: _hata ? Marka.gul : null),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                hintText: d.adresler.isEmpty ? 'Ad veya e-posta adresi' : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ?widget.sag,
              ],
            ),
          ),
        ),
        if (_hata)
          Padding(
            padding: const EdgeInsets.fromLTRB(68, 0, 16, 6),
            child: Text('Geçersiz e-posta adresi', style: TextStyle(color: Marka.gul, fontSize: 12)),
          ),
        if (_oneriler.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(60, 0, 12, 6),
            decoration: BoxDecoration(
              color: r.kart,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: r.kenar),
              boxShadow: r.golge,
            ),
            child: Column(
              children: [
                for (final o in _oneriler)
                  ListTile(
                    dense: true,
                    leading: Avatar(o.ad.isEmpty ? o.eposta : o.ad, boyut: 32, tohum: o.eposta),
                    title: Text(o.ad.isEmpty ? o.eposta : o.ad, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: o.ad.isEmpty ? null : Text(o.eposta, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: o.kaynak == 'colleague' ? Rozet('Kurum', renk: Marka.mavi) : null,
                    onTap: () {
                      d.ekle(o.adres);
                      setState(() => _oneriler = const []);
                      _odak.requestFocus();
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
