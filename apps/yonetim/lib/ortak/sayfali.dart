import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../veri/json.dart';

/// Sayfalı liste yükleyicisi: ilk sayfa, sonsuz kaydırma, yenileme. Hatalar [hata] alanında tutulur.
class SayfaYukleyici<T> extends ChangeNotifier {
  SayfaYukleyici(this._getir, {this.sayfaBoyu = 25});

  final Future<Sayfa<T>> Function(int sayfa, int boy) _getir;
  final int sayfaBoyu;

  final List<T> ogeler = [];
  int toplam = 0;
  int _sayfa = 0;
  bool yukleniyor = false;
  bool ilkYukleme = true;
  String? hata;
  int _nesil = 0;
  bool _kapandi = false;

  bool get dahaVar => ogeler.length < toplam;

  Future<void> yenile() async {
    final n = ++_nesil;
    yukleniyor = true;
    hata = null;
    _bildir();
    try {
      final s = await _getir(1, sayfaBoyu);
      if (n != _nesil) return;
      ogeler
        ..clear()
        ..addAll(s.ogeler);
      toplam = s.toplam;
      _sayfa = 1;
    } catch (e) {
      if (n != _nesil) return;
      hata = hataMetni(e);
    } finally {
      if (n == _nesil) {
        yukleniyor = false;
        ilkYukleme = false;
        _bildir();
      }
    }
  }

  Future<void> devam() async {
    if (yukleniyor || !dahaVar || hata != null) return;
    final n = _nesil;
    yukleniyor = true;
    _bildir();
    try {
      final s = await _getir(_sayfa + 1, sayfaBoyu);
      if (n != _nesil) return;
      ogeler.addAll(s.ogeler);
      toplam = s.toplam;
      _sayfa++;
      if (s.ogeler.isEmpty) toplam = ogeler.length;
    } catch (e) {
      if (n != _nesil) return;
      bildir('Devamı yüklenemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (n == _nesil) {
        yukleniyor = false;
        _bildir();
      }
    }
  }

  /// Bir öğeyi yerinde değiştirir ya da kaldırır (sunucudan yeniden yüklemeden).
  void degistir(bool Function(T) eslesir, T? yeni) {
    final i = ogeler.indexWhere(eslesir);
    if (i < 0) return;
    if (yeni == null) {
      ogeler.removeAt(i);
      toplam = toplam > 0 ? toplam - 1 : 0;
    } else {
      ogeler[i] = yeni;
    }
    _bildir();
  }

  void _bildir() {
    if (!_kapandi) notifyListeners();
  }

  @override
  void dispose() {
    _kapandi = true;
    super.dispose();
  }
}

/// [SayfaYukleyici] için çekerek yenilenen, sonuna gelince devamını yükleyen liste.
class SayfaliListe<T> extends StatefulWidget {
  const SayfaliListe({
    super.key,
    required this.yukleyici,
    required this.oge,
    required this.bosMetin,
    this.bosIkon = Icons.inbox_rounded,
    this.ust,
    this.ayrac = true,
    this.dolgu = const EdgeInsets.fromLTRB(12, 4, 12, 24),
  });

  final SayfaYukleyici<T> yukleyici;
  final Widget Function(BuildContext, T) oge;
  final String bosMetin;
  final IconData bosIkon;

  /// Listenin üstünde kayan başlık (özet kutuları, uyarılar).
  final Widget? ust;
  final bool ayrac;
  final EdgeInsets dolgu;

  @override
  State<SayfaliListe<T>> createState() => _SayfaliListeState<T>();
}

class _SayfaliListeState<T> extends State<SayfaliListe<T>> {
  final _kaydirma = ScrollController();

  @override
  void initState() {
    super.initState();
    _kaydirma.addListener(() {
      if (_kaydirma.position.extentAfter < 600) widget.yukleyici.devam();
    });
  }

  @override
  void dispose() {
    _kaydirma.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.yukleyici,
      builder: (context, _) {
        final y = widget.yukleyici;
        Widget? durum;
        if (y.ogeler.isEmpty) {
          if (y.hata != null) {
            durum = Durum.hata(y.hata!, tekrar: y.yenile);
          } else if (y.yukleniyor || y.ilkYukleme) {
            durum = const Durum.yukleniyor();
          } else {
            durum = Durum.bos(widget.bosMetin, ikon: widget.bosIkon);
          }
        }
        final n = y.ogeler.length;
        return RefreshIndicator.adaptive(
          onRefresh: y.yenile,
          child: CustomScrollView(
            controller: _kaydirma,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (widget.ust != null) SliverToBoxAdapter(child: widget.ust),
              if (durum != null)
                SliverFillRemaining(hasScrollBody: false, child: durum)
              else
                SliverPadding(
                  padding: widget.dolgu,
                  sliver: SliverList.separated(
                    itemCount: n + 1,
                    separatorBuilder: (_, i) => widget.ayrac && i < n - 1 ? const Divider(height: 1, indent: 16, endIndent: 16) : const SizedBox.shrink(),
                    itemBuilder: (c, i) {
                      if (i == n) {
                        return Padding(
                          padding: const EdgeInsets.all(18),
                          child: Center(
                            child: y.dahaVar
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                                : Text('${sayiYaz(y.toplam)} kayıt', style: TextStyle(color: context.r.silik, fontSize: 12.5)),
                          ),
                        );
                      }
                      return widget.oge(c, y.ogeler[i]);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
