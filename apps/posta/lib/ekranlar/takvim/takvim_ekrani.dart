import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../veri/canli.dart';
import '../../veri/modeller.dart';
import '../../veri/takvim_servisi.dart';
import 'etkinlik_duzenleyici.dart';

enum TakvimGorunumu {
  ay('Ay', Simge.ay),
  hafta('Hafta', Simge.hafta),
  ajanda('Ajanda', Simge.ajanda);

  const TakvimGorunumu(this.ad, this.ikon);
  final String ad;
  final IconData ikon;
}

Color takvimRengi(String hex, Color yedek) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'ff$h' : h, radix: 16);
  return v == null ? yedek : Color(v);
}

DateTime _gun(DateTime d) => DateTime(d.year, d.month, d.day);
bool _ayniGun(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Takvim: ay / hafta / ajanda görünümleri, etkinlik oluşturma ve düzenleme, takvim yönetimi.
class TakvimEkrani extends StatefulWidget {
  const TakvimEkrani({super.key});
  @override
  State<TakvimEkrani> createState() => _TakvimEkraniState();
}

class _TakvimEkraniState extends State<TakvimEkrani> {
  TakvimGorunumu _gorunum = TakvimGorunumu.ay;
  DateTime _odak = _gun(DateTime.now());
  DateTime _secili = _gun(DateTime.now());
  List<Etkinlik> _etkinlikler = [];
  List<Takvim> _takvimler = [];
  final _gizli = <String>{};
  bool _yukleniyor = true;
  String? _hata;
  bool _kapali = false;
  StreamSubscription<CanliOlay>? _abone;
  int _istek = 0;

  @override
  void initState() {
    super.initState();
    _abone = Canli.ben.olaylar.listen((o) {
      if (o.tur == 'calendar') _yukle(sessiz: true);
    });
    _yukle();
  }

  @override
  void dispose() {
    _abone?.cancel();
    super.dispose();
  }

  (DateTime, DateTime) get _aralik {
    switch (_gorunum) {
      case TakvimGorunumu.ay:
        final ilk = DateTime(_odak.year, _odak.month, 1);
        final bas = ilk.subtract(Duration(days: ilk.weekday - 1));
        return (bas, bas.add(const Duration(days: 42)));
      case TakvimGorunumu.hafta:
        final bas = _odak.subtract(Duration(days: _odak.weekday - 1));
        return (bas, bas.add(const Duration(days: 7)));
      case TakvimGorunumu.ajanda:
        return (_odak, _odak.add(const Duration(days: 60)));
    }
  }

  Future<void> _yukle({bool sessiz = false}) async {
    final no = ++_istek;
    if (!sessiz) {
      setState(() {
        _yukleniyor = true;
        _hata = null;
      });
    }
    final (bas, son) = _aralik;
    try {
      // Önce yerel: ay / hafta önbellekten hemen çizilir, ağ yanıtı yerine konur.
      final sonuc = await Future.wait([
        TakvimApi.etkinlikler(
          bas,
          son,
          yerel: (o) {
            if (mounted && no == _istek) {
              setState(() {
                _etkinlikler = o;
                _yukleniyor = false;
              });
            }
          },
        ),
        if (_takvimler.isEmpty || !sessiz)
          TakvimApi.takvimler(
            yerel: (o) {
              if (mounted && no == _istek && _takvimler.isEmpty) setState(() => _takvimler = o);
            },
          ),
      ]);
      if (!mounted || no != _istek) return;
      setState(() {
        _etkinlikler = sonuc[0] as List<Etkinlik>;
        if (sonuc.length > 1) _takvimler = sonuc[1] as List<Takvim>;
        _yukleniyor = false;
        _kapali = false;
      });
    } catch (e) {
      if (!mounted || no != _istek) return;
      setState(() {
        _kapali = ozellikKapali(e);
        _hata = hataMetni(e);
        _yukleniyor = false;
      });
    }
  }

  List<Etkinlik> get _gorunen => _etkinlikler.where((e) => !_gizli.contains(e.takvimId)).toList();
  List<Etkinlik> _gunun(DateTime g) => _gorunen.where((e) => e.gununde(g)).toList()
    ..sort((a, b) {
      if (a.tumGun != b.tumGun) return a.tumGun ? -1 : 1;
      return a.baslangic.compareTo(b.baslangic);
    });

  void _kaydir(int yon) {
    setState(() {
      switch (_gorunum) {
        case TakvimGorunumu.ay:
          _odak = DateTime(_odak.year, _odak.month + yon, 1);
          _secili = _odak;
        case TakvimGorunumu.hafta:
          _odak = _odak.add(Duration(days: 7 * yon));
          _secili = _odak;
        case TakvimGorunumu.ajanda:
          _odak = _odak.add(Duration(days: 30 * yon));
          _secili = _odak;
      }
    });
    _yukle();
  }

  void _bugun() {
    setState(() {
      _odak = _gun(DateTime.now());
      _secili = _odak;
    });
    _yukle();
  }

  String get _baslik {
    switch (_gorunum) {
      case TakvimGorunumu.ay:
        return DateFormat('MMMM y', 'tr_TR').format(_odak);
      case TakvimGorunumu.hafta:
        final (bas, son) = _aralik;
        final s = son.subtract(const Duration(days: 1));
        return bas.month == s.month
            ? '${bas.day}–${DateFormat('d MMMM y', 'tr_TR').format(s)}'
            : '${DateFormat('d MMM', 'tr_TR').format(bas)} – ${DateFormat('d MMM y', 'tr_TR').format(s)}';
      case TakvimGorunumu.ajanda:
        return 'Yaklaşanlar';
    }
  }

  Future<void> _yeni([DateTime? gun]) async {
    final g = gun ?? _secili;
    final n = DateTime.now();
    final bas = DateTime(g.year, g.month, g.day, _ayniGun(g, n) ? (n.hour + 1).clamp(0, 23) : 9);
    final ok = await EtkinlikDuzenleyici.ac(context, takvimler: _takvimler, baslangic: bas);
    if (ok == true) _yukle(sessiz: true);
  }

  Future<void> _ac(Etkinlik e) async {
    final degisti = await EtkinlikAyrinti.ac(context, etkinlik: e, takvimler: _takvimler);
    if (degisti == true) _yukle(sessiz: true);
  }

  Future<void> _takvimleriYonet() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TakvimlerEkrani(
          gizli: _gizli,
          degisti: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    _takvimler = [];
    _yukle(sessiz: true);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    Widget govde;
    if (_kapali) {
      govde = Durum.bos(_hata ?? 'Takvim paketinizde kapalı.', ikon: Simge.etkinlikIptal);
    } else if (_hata != null && _etkinlikler.isEmpty) {
      govde = Durum.hata(_hata!, tekrar: _yukle);
    } else {
      govde = switch (_gorunum) {
        TakvimGorunumu.ay => _ayGorunumu(),
        TakvimGorunumu.hafta => _haftaGorunumu(),
        TakvimGorunumu.ajanda => _ajanda(),
      };
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Takvim'),
        actions: [
          TextButton(onPressed: _bugun, child: const Text('Bugün')),
          PopupMenuButton<TakvimGorunumu>(
            tooltip: 'Görünüm',
            icon: Icon(_gorunum.ikon),
            initialValue: _gorunum,
            onSelected: (v) {
              setState(() => _gorunum = v);
              _yukle();
            },
            itemBuilder: (_) => [
              for (final g in TakvimGorunumu.values)
                PopupMenuItem(
                  value: g,
                  child: ListTile(leading: Icon(g.ikon), title: Text(g.ad)),
                ),
            ],
          ),
          IconButton(tooltip: 'Takvimlerim', icon: const Icon(Simge.ayarlarInce), onPressed: _kapali ? null : _takvimleriYonet),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                IconButton(tooltip: 'Önceki', icon: const Icon(Simge.geriOk), onPressed: () => _kaydir(-1)),
                Expanded(
                  child: Text(
                    _baslik,
                    key: const ValueKey('takvim-baslik'),
                    textAlign: TextAlign.center,
                    style: gosterim(17, agirlik: FontWeight.w600),
                  ),
                ),
                IconButton(tooltip: 'Sonraki', icon: const Icon(Simge.ileri), onPressed: () => _kaydir(1)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _kapali
          ? null
          : FloatingActionButton.extended(onPressed: () => _yeni(), icon: const Icon(Simge.ekle), label: const Text('Etkinlik')),
      body: Column(
        children: [
          if (_yukleniyor) LinearProgressIndicator(minHeight: 2, color: r.vurgu) else const SizedBox(height: 2),
          Expanded(child: govde),
        ],
      ),
    );
  }

  Widget _ayGorunumu() {
    final r = context.r;
    final (bas, _) = _aralik;
    final bugun = _gun(DateTime.now());
    final gunler = [for (var i = 0; i < 42; i++) DateTime(bas.year, bas.month, bas.day + i)];
    final secilenler = _gunun(_secili);
    return LayoutBuilder(
      builder: (context, c) {
        final genis = c.maxWidth >= 700;
        final hucreY = genis ? 96.0 : 52.0;
        final izgara = Column(
          children: [
            Row(
              children: [
                for (final g in const ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        g,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: r.silik),
                      ),
                    ),
                  ),
              ],
            ),
            for (var h = 0; h < 6; h++)
              Row(
                children: [
                  for (var d = 0; d < 7; d++)
                    Expanded(
                      child: Builder(
                        builder: (_) {
                          final g = gunler[h * 7 + d];
                          final buAy = g.month == _odak.month;
                          final secili = _ayniGun(g, _secili);
                          final bugunMu = _ayniGun(g, bugun);
                          final olaylar = _gunun(g);
                          return InkWell(
                            key: ValueKey('gun-${g.year}-${g.month}-${g.day}'),
                            onTap: () => setState(() => _secili = g),
                            onDoubleTap: () => _yeni(g),
                            child: Container(
                              height: hucreY,
                              margin: const EdgeInsets.all(1.5),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: secili ? r.vurguYumusak : (buAy ? r.kart : r.zemin),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: secili ? r.vurgu : r.kenar.withValues(alpha: .6), width: secili ? 1.5 : 1),
                              ),
                              child: Column(
                                crossAxisAlignment: genis ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: bugunMu ? BoxDecoration(color: r.vurgu, shape: BoxShape.circle) : null,
                                    child: Text(
                                      '${g.day}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: bugunMu || secili ? FontWeight.w600 : FontWeight.w500,
                                        color: bugunMu ? Colors.white : (buAy ? r.metin : r.silik),
                                      ),
                                    ),
                                  ),
                                  if (genis)
                                    for (final e in olaylar.take(3))
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: takvimRengi(e.renk, r.vurgu).withValues(alpha: .16),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          e.baslik,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 11, color: r.metin, fontWeight: FontWeight.w600),
                                        ),
                                      )
                                  else if (olaylar.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          for (final e in olaylar.take(3))
                                            Container(
                                              width: 6,
                                              height: 6,
                                              margin: const EdgeInsets.symmetric(horizontal: 1),
                                              decoration: BoxDecoration(color: takvimRengi(e.renk, r.vurgu), shape: BoxShape.circle),
                                            ),
                                        ],
                                      ),
                                    ),
                                  if (genis && olaylar.length > 3) Text('+${olaylar.length - 3} daha', style: TextStyle(fontSize: 10.5, color: r.silik)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
          ],
        );
        return RefreshIndicator(
          onRefresh: _yukle,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
            children: [
              izgara,
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                child: Text(DateFormat('d MMMM EEEE', 'tr_TR').format(_secili), style: gosterim(16, agirlik: FontWeight.w600)),
              ),
              if (secilenler.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Bu gün için etkinlik yok.', style: TextStyle(color: r.silik)),
                )
              else
                for (final e in secilenler) EtkinlikKarti(etkinlik: e, gun: _secili, ac: () => _ac(e)),
            ],
          ),
        );
      },
    );
  }

  Widget _haftaGorunumu() {
    final r = context.r;
    final (bas, _) = _aralik;
    final bugun = _gun(DateTime.now());
    return RefreshIndicator(
      onRefresh: _yukle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (_) {
                final g = DateTime(bas.year, bas.month, bas.day + i);
                final l = _gunun(g);
                final bugunMu = _ayniGun(g, bugun);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 54,
                        child: Column(
                          children: [
                            Text(
                              DateFormat('EEE', 'tr_TR').format(g),
                              style: TextStyle(fontSize: 12, color: bugunMu ? r.vurgu : r.silik, fontWeight: FontWeight.w600),
                            ),
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: bugunMu ? BoxDecoration(color: r.vurgu, shape: BoxShape.circle) : null,
                              child: Text(
                                '${g.day}',
                                style: gosterim(18, agirlik: FontWeight.w600, renk: bugunMu ? Colors.white : r.metin),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: l.isEmpty
                            ? InkWell(
                                onTap: () => _yeni(g),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  height: 48,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: r.kenar.withValues(alpha: .7)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('Boş · eklemek için dokunun', style: TextStyle(color: r.silik, fontSize: 13)),
                                ),
                              )
                            : Column(
                                children: [for (final e in l) EtkinlikKarti(etkinlik: e, gun: g, ac: () => _ac(e))],
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _ajanda() {
    final r = context.r;
    final l = [..._gorunen]..sort((a, b) => a.baslangic.compareTo(b.baslangic));
    final simdi = DateTime.now();
    final gelecek = l.where((e) => e.bitis.isAfter(simdi) || _ayniGun(e.baslangic, simdi)).toList();
    if (gelecek.isEmpty && !_yukleniyor) {
      return RefreshIndicator(
        onRefresh: _yukle,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            Durum.bos('Önümüzdeki 60 günde etkinlik yok.', ikon: Simge.etkinlikOnay),
          ],
        ),
      );
    }
    final gruplar = <DateTime, List<Etkinlik>>{};
    for (final e in gelecek) {
      gruplar.putIfAbsent(_gun(e.baslangic.isBefore(_odak) ? _odak : e.baslangic), () => []).add(e);
    }
    return RefreshIndicator(
      onRefresh: _yukle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          for (final g in gruplar.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text(
                _ayniGun(g.key, simdi) ? 'Bugün · ${DateFormat('d MMMM', 'tr_TR').format(g.key)}' : DateFormat('d MMMM EEEE', 'tr_TR').format(g.key),
                style: TextStyle(fontWeight: FontWeight.w600, color: _ayniGun(g.key, simdi) ? r.vurgu : r.soluk),
              ),
            ),
            for (final e in g.value) EtkinlikKarti(etkinlik: e, gun: g.key, ac: () => _ac(e)),
          ],
        ],
      ),
    );
  }
}

String etkinlikSaati(Etkinlik e, [DateTime? gun]) {
  if (e.tumGun) return 'Tüm gün';
  final f = DateFormat('HH:mm');
  if (_ayniGun(e.baslangic, e.bitis)) return '${f.format(e.baslangic)} – ${f.format(e.bitis)}';
  final g = DateFormat('d MMM HH:mm', 'tr_TR');
  return '${g.format(e.baslangic)} – ${g.format(e.bitis)}';
}

/// Etkinlik satırı: renk şeridi, saat, başlık, yer.
class EtkinlikKarti extends StatelessWidget {
  const EtkinlikKarti({super.key, required this.etkinlik, this.gun, this.ac});
  final Etkinlik etkinlik;
  final DateTime? gun;
  final VoidCallback? ac;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final e = etkinlik;
    final renk = takvimRengi(e.renk, r.vurgu);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: r.kart,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: ac,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: r.kenar),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: renk,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.baslik,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: r.metin),
                          ),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _bilgi(context, Simge.saat, etkinlikSaati(e, gun)),
                              if (e.yer.isNotEmpty) _bilgi(context, Simge.konum, e.yer),
                              if (e.tekrar.isNotEmpty) _bilgi(context, Simge.tekrar, tekrarAdlari[e.tekrar] ?? ''),
                              if (e.katilimcilar.isNotEmpty) _bilgi(context, Simge.kisilerGrup, '${e.katilimcilar.length} katılımcı'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bilgi(BuildContext context, IconData i, String t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(i, size: 14, color: context.r.silik),
      const SizedBox(width: 3),
      Flexible(
        child: Text(
          t,
          style: TextStyle(fontSize: 12.5, color: context.r.soluk),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// Takvimlerim: görünürlük, yeni takvim, silme.
class TakvimlerEkrani extends StatefulWidget {
  const TakvimlerEkrani({super.key, required this.gizli, required this.degisti});
  final Set<String> gizli;
  final VoidCallback degisti;
  @override
  State<TakvimlerEkrani> createState() => _TakvimlerEkraniState();
}

class _TakvimlerEkraniState extends State<TakvimlerEkrani> {
  List<Takvim>? _l;
  String? _hata;
  static const _renkler = ['#2563eb', '#16a34a', '#dc2626', '#9333ea', '#ea580c', '#0891b2', '#db2777', '#64748b'];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final l = await TakvimApi.takvimler();
      if (mounted) setState(() => _l = l);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _yeni() async {
    final ad = TextEditingController();
    var renk = _renkler.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => AlertDialog(
          title: Text('Yeni takvim', style: gosterim(19, agirlik: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ad,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Takvim adı'),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in _renkler)
                    InkWell(
                      onTap: () => yenile(() => renk = k),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: takvimRengi(k, Colors.blue),
                          shape: BoxShape.circle,
                          border: renk == k ? Border.all(color: c.r.metin, width: 3) : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oluştur')),
          ],
        ),
      ),
    );
    final a = ad.text.trim();
    ad.dispose();
    if (ok != true || a.isEmpty) return;
    await islem(() => TakvimApi.takvimOlustur(a, renk), tamam: 'Takvim oluşturuldu');
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    return Scaffold(
      appBar: AppBar(title: const Text('Takvimlerim')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _yeni, icon: const Icon(Simge.ekle), label: const Text('Yeni takvim')),
      body: l == null
          ? (_hata != null ? Durum.hata(_hata!, tekrar: _yukle) : const Durum.yukleniyor())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                Kutu(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final t in l)
                        CheckboxListTile(
                          value: !widget.gizli.contains(t.id),
                          activeColor: takvimRengi(t.renk, context.r.vurgu),
                          onChanged: (v) {
                            setState(() => v == true ? widget.gizli.remove(t.id) : widget.gizli.add(t.id));
                            widget.degisti();
                          },
                          title: Text(t.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: t.varsayilan ? const Text('Varsayılan takvim') : null,
                          secondary: t.varsayilan
                              ? Icon(Simge.nokta, color: takvimRengi(t.renk, context.r.vurgu))
                              : IconButton(
                                  tooltip: 'Takvimi sil',
                                  icon: const Icon(Simge.sil),
                                  onPressed: () async {
                                    if (!await onayla(
                                      context,
                                      '"${t.ad}" silinsin mi?',
                                      mesaj: 'Takvimdeki tüm etkinlikler de silinir.',
                                      evet: 'Sil',
                                      tehlikeli: true,
                                    )) {
                                      return;
                                    }
                                    await islem(() => TakvimApi.takvimSil(t.id), tamam: 'Takvim silindi');
                                    _yukle();
                                  },
                                ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('İşareti kaldırdığınız takvimlerin etkinlikleri gizlenir.', style: TextStyle(color: context.r.silik, fontSize: 12.5)),
                ),
              ],
            ),
    );
  }
}
