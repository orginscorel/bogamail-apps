import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../veri/canli.dart';
import '../../veri/modeller.dart';
import '../../veri/takvim_servisi.dart';
import '../../ortak/uyarlanir.dart';

enum GorevKapsami {
  hepsi('', 'Tümü'),
  bana('assigned', 'Bana atanan'),
  benim('created', 'Oluşturduğum');

  const GorevKapsami(this.deger, this.ad);
  final String deger;
  final String ad;
}

Color oncelikRengi(String o, BuildContext c) => switch (o) {
  'high' => Marka.gul,
  'low' => c.r.silik,
  _ => Marka.kehribar,
};

String bitisMetni(DateTime d) {
  final n = DateTime.now();
  final bugun = DateTime(n.year, n.month, n.day);
  final g = DateTime(d.year, d.month, d.day);
  final fark = g.difference(bugun).inDays;
  final saat = d.hour == 0 && d.minute == 0 ? '' : ' ${DateFormat('HH:mm').format(d)}';
  if (fark == 0) return 'Bugün$saat';
  if (fark == 1) return 'Yarın$saat';
  if (fark == -1) return 'Dün$saat';
  return '${DateFormat(g.year == bugun.year ? 'd MMM' : 'd MMM y', 'tr_TR').format(d)}$saat';
}

/// Görevler: bana atanan / oluşturduğum, açık / tamamlanan, arama; hızlı tamamlama; ayrıntı ve yorumlar.
class GorevlerEkrani extends StatefulWidget {
  const GorevlerEkrani({super.key});
  @override
  State<GorevlerEkrani> createState() => _GorevlerEkraniState();
}

class _GorevlerEkraniState extends State<GorevlerEkrani> {
  GorevKapsami _kapsam = GorevKapsami.hepsi;
  bool _tamamlananlar = false;
  final _ara = TextEditingController();
  List<Gorev>? _l;
  String? _hata;
  bool _kapali = false;
  Timer? _gecikme;
  StreamSubscription<CanliOlay>? _abone;
  int _no = 0;

  @override
  void initState() {
    super.initState();
    _abone = Canli.ben.olaylar.listen((o) {
      if (o.tur == 'task') _yukle();
    });
    _yukle();
  }

  @override
  void dispose() {
    _abone?.cancel();
    _gecikme?.cancel();
    _ara.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    final no = ++_no;
    try {
      final l = await GorevApi.liste(
        kapsam: _kapsam.deger,
        durum: _tamamlananlar ? 'done' : 'open',
        q: _ara.text,
        yerel: (o) {
          if (mounted && no == _no) setState(() => _l = o);
        },
      );
      if (!mounted || no != _no) return;
      setState(() {
        _l = l;
        _hata = null;
        _kapali = false;
      });
    } catch (e) {
      if (!mounted || no != _no) return;
      setState(() {
        _hata = hataMetni(e);
        _kapali = ozellikKapali(e);
      });
    }
  }

  Future<void> _durum(Gorev g, String d) async {
    setState(() {
      _l = (_l ?? <Gorev>[]).where((x) => x.id != g.id || (d == 'done') == _tamamlananlar).toList();
    });
    await islem(() => GorevApi.durumDegistir(g.id, d), tamam: d == 'done' ? 'Görev tamamlandı' : 'Görev yeniden açıldı');
    _yukle();
  }

  Future<void> _yeni() async {
    final ok = await GorevDuzenleyici.ac(context);
    if (ok == true) _yukle();
  }

  Future<void> _ac(Gorev g) async {
    await uyarlanirAc<void>(context, (_) => GorevAyrinti(gorevId: g.id, ilk: g));
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = _l;
    Widget govde;
    if (_kapali) {
      govde = Durum.bos(_hata ?? 'Görevler paketinizde kapalı.', ikon: Simge.gorev);
    } else if (l == null) {
      govde = _hata != null ? Durum.hata(_hata!, tekrar: _yukle) : const Durum.yukleniyor();
    } else {
      final geciken = l.where((g) => g.gecikti).toList();
      final diger = l.where((g) => !g.gecikti).toList();
      govde = RefreshIndicator(
        onRefresh: _yukle,
        child: l.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 60),
                  Durum.bos(
                    _ara.text.isNotEmpty
                        ? 'Aramanızla eşleşen görev yok.'
                        : _tamamlananlar
                        ? 'Tamamlanan görev yok.'
                        : 'Açık görev yok. Harika!\nYeni görev ekleyip kendinize ya da bir iş arkadaşınıza atayabilirsiniz.',
                    ikon: Simge.gorev,
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                children: [
                  if (geciken.isNotEmpty) ...[_bolum('Geciken (${geciken.length})', renk: Marka.gul), for (final g in geciken) _satir(g)],
                  if (diger.isNotEmpty) ...[if (geciken.isNotEmpty) _bolum(_tamamlananlar ? 'Tamamlanan' : 'Diğer'), for (final g in diger) _satir(g)],
                ],
              ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Görevler'),
        bottom: _kapali
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(104),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Column(
                    children: [
                      TextField(
                        controller: _ara,
                        decoration: InputDecoration(
                          hintText: 'Görevlerde ara',
                          isDense: true,
                          prefixIcon: const Icon(Simge.ara, size: 20),
                          suffixIcon: _ara.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Temizle',
                                  icon: const Icon(Simge.kapat, size: 18),
                                  onPressed: () {
                                    _ara.clear();
                                    _yukle();
                                  },
                                ),
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _gecikme?.cancel();
                          _gecikme = Timer(const Duration(milliseconds: 300), _yukle);
                        },
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final k in GorevKapsami.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(k.ad),
                                  selected: _kapsam == k,
                                  onSelected: (_) {
                                    setState(() => _kapsam = k);
                                    _yukle();
                                  },
                                ),
                              ),
                            Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), color: r.kenar),
                            FilterChip(
                              label: const Text('Tamamlananlar'),
                              avatar: const Icon(Simge.hepsiOkundu, size: 16),
                              selected: _tamamlananlar,
                              onSelected: (v) {
                                setState(() => _tamamlananlar = v);
                                _yukle();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      floatingActionButton: _kapali
          ? null
          : FloatingActionButton.extended(onPressed: _yeni, icon: const Icon(Simge.gorevEkle), label: const Text('Yeni görev')),
      body: govde,
    );
  }

  Widget _bolum(String t, {Color? renk}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
    child: Text(
      t,
      style: TextStyle(fontWeight: FontWeight.w600, color: renk ?? context.r.soluk),
    ),
  );

  Widget _satir(Gorev g) {
    final r = context.r;
    final kime = g.atanan?.gorunen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: r.kart,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _ac(g),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: g.gecikti ? Marka.gul.withValues(alpha: .4) : r.kenar),
            ),
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            child: Row(
              children: [
                Semantics(
                  label: g.bitti ? 'Yeniden aç' : 'Tamamlandı olarak işaretle',
                  child: Checkbox(
                    key: ValueKey('gorev-tamam-${g.id}'),
                    value: g.bitti,
                    shape: const CircleBorder(),
                    onChanged: (v) => _durum(g, v == true ? 'done' : 'todo'),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.baslik,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: g.bitti ? r.silik : r.metin,
                          decoration: g.bitti ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (g.durum == 'doing') const Rozet('Sürüyor', renk: Marka.zumrut),
                          if (g.oncelik != 'normal') Rozet(gorevOncelikAdlari[g.oncelik] ?? g.oncelik, renk: oncelikRengi(g.oncelik, context)),
                          if (g.bitis != null) _ufak(Simge.etkinlik, bitisMetni(g.bitis!), renk: g.gecikti ? Marka.gul : null),
                          if (kime != null) _ufak(Simge.kisi, kime),
                          if (g.yorumSayisi > 0) _ufak(Simge.mesaj, '${g.yorumSayisi}'),
                          if (g.iletiKonu.isNotEmpty) _ufak(Simge.posta, g.iletiKonu),
                        ],
                      ),
                    ],
                  ),
                ),
                if (g.atanan != null) Avatar(g.atanan!.gorunen, boyut: 28, tohum: g.atanan!.adres),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ufak(IconData i, String t, {Color? renk}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(i, size: 14, color: renk ?? context.r.silik),
      const SizedBox(width: 3),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          t,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: renk ?? context.r.soluk, fontWeight: renk != null ? FontWeight.w600 : null),
        ),
      ),
    ],
  );
}

/// Görev ayrıntısı: durum, alanlar, yorumlar.
class GorevAyrinti extends StatefulWidget {
  const GorevAyrinti({super.key, required this.gorevId, this.ilk});
  final String gorevId;
  final Gorev? ilk;
  @override
  State<GorevAyrinti> createState() => _GorevAyrintiState();
}

class _GorevAyrintiState extends State<GorevAyrinti> {
  Gorev? _g;
  List<GorevYorumu> _yorumlar = [];
  String? _hata;
  final _yorum = TextEditingController();
  bool _gonderiyor = false;

  @override
  void initState() {
    super.initState();
    _g = widget.ilk;
    _yukle();
  }

  @override
  void dispose() {
    _yorum.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final v = await GorevApi.getir(widget.gorevId);
      if (!mounted) return;
      setState(() {
        _g = v.gorev;
        _yorumlar = v.yorumlar;
        _hata = null;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _yorumGonder() async {
    final t = _yorum.text.trim();
    if (t.isEmpty || _gonderiyor) return;
    setState(() => _gonderiyor = true);
    try {
      final y = await GorevApi.yorumla(widget.gorevId, t);
      _yorum.clear();
      if (mounted) setState(() => _yorumlar = [..._yorumlar, y]);
    } catch (e) {
      bildir('Yorum gönderilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _gonderiyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final g = _g;
    if (g == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Görev')),
        body: _hata != null ? Durum.hata(_hata!, tekrar: _yukle) : const Durum.yukleniyor(),
      );
    }
    Widget alan(IconData i, String etiket, String deger, {Color? renk}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(i, size: 20, color: r.silik),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Text(etiket, style: TextStyle(color: r.soluk)),
          ),
          Expanded(
            child: Text(
              deger,
              style: TextStyle(fontWeight: FontWeight.w600, color: renk ?? r.metin),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Görev'),
        actions: [
          if (g.duzenleyebilir) ...[
            IconButton(
              tooltip: 'Düzenle',
              icon: const Icon(Simge.duzenle),
              onPressed: () async {
                if (await GorevDuzenleyici.ac(context, gorev: g) == true) _yukle();
              },
            ),
            IconButton(
              tooltip: 'Sil',
              icon: const Icon(Simge.sil),
              onPressed: () async {
                if (!await onayla(context, 'Görev silinsin mi?', mesaj: 'Yorumlarıyla birlikte kalıcı olarak silinir.', evet: 'Sil', tehlikeli: true)) return;
                final ok = await islem(() async {
                  await GorevApi.sil(g.id);
                  return true;
                }, tamam: 'Görev silindi');
                if (ok == true && context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _yukle,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    g.baslik,
                    style: gosterim(22, agirlik: FontWeight.w600).copyWith(decoration: g.bitti ? TextDecoration.lineThrough : null),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [for (final e in gorevDurumAdlari.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                    selected: {g.durum},
                    onSelectionChanged: (v) async {
                      await islem(() => GorevApi.durumDegistir(g.id, v.first), tamam: 'Durum güncellendi');
                      _yukle();
                    },
                  ),
                  const SizedBox(height: 12),
                  Kutu(
                    child: Column(
                      children: [
                        alan(Simge.bayrak, 'Öncelik', gorevOncelikAdlari[g.oncelik] ?? g.oncelik, renk: oncelikRengi(g.oncelik, context)),
                        alan(
                          Simge.etkinlik,
                          'Bitiş',
                          g.bitis == null ? 'Yok' : DateFormat('d MMMM y EEEE, HH:mm', 'tr_TR').format(g.bitis!),
                          renk: g.gecikti ? Marka.gul : null,
                        ),
                        alan(Simge.kisi, 'Atanan', g.atanan?.gorunen ?? 'Atanmadı'),
                        alan(Simge.taslak, 'Oluşturan', g.olusturan?.gorunen ?? ''),
                        if (g.tamamlanma != null) alan(Simge.hepsiOkundu, 'Tamamlandı', DateFormat('d MMM y HH:mm', 'tr_TR').format(g.tamamlanma!)),
                        if (g.iletiKonu.isNotEmpty) alan(Simge.posta, 'İleti', '${g.iletiKonu}${g.iletiKimden.isNotEmpty ? ' · ${g.iletiKimden}' : ''}'),
                      ],
                    ),
                  ),
                  if (g.notlar.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Kutu(
                      child: SelectableText(g.notlar.trim(), style: TextStyle(color: r.metin, height: 1.4)),
                    ),
                  ],
                  if (!g.duzenleyebilir)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Bu görev size atandı; yalnızca durumunu değiştirebilir ve yorum yazabilirsiniz.',
                        style: TextStyle(color: r.silik, fontSize: 12.5),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    'Yorumlar (${_yorumlar.length})',
                    style: TextStyle(fontWeight: FontWeight.w600, color: r.soluk),
                  ),
                  const SizedBox(height: 8),
                  if (_yorumlar.isEmpty)
                    Text('Henüz yorum yok.', style: TextStyle(color: r.silik))
                  else
                    for (final y in _yorumlar)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Avatar(y.yazar?.gorunen ?? '?', boyut: 32, tohum: y.yazar?.adres),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(y.yazar?.gorunen ?? 'Silinmiş kullanıcı', style: const TextStyle(fontWeight: FontWeight.w600)),
                                        ),
                                        if (y.tarih != null) Text(goreliZaman(y.tarih), style: TextStyle(color: r.silik, fontSize: 11.5)),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    SelectableText(y.metin),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: r.kart,
              border: Border(top: BorderSide(color: r.kenar)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _yorum,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'Yorum yazın', isDense: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Gönder',
                    icon: const Icon(Simge.gonder),
                    color: r.vurgu,
                    onPressed: _yorum.text.trim().isEmpty || _gonderiyor ? null : _yorumGonder,
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

/// Görev oluştur / düzenle. [iletiId] verilirse görev o iletiye bağlanır.
class GorevDuzenleyici extends StatefulWidget {
  const GorevDuzenleyici({super.key, this.gorev, this.iletiId, this.ilkBaslik});
  final Gorev? gorev;
  final String? iletiId;
  final String? ilkBaslik;

  static Future<bool?> ac(BuildContext context, {Gorev? gorev, String? iletiId, String? ilkBaslik}) =>
      uyarlanirAc<bool>(context, (_) => GorevDuzenleyici(gorev: gorev, iletiId: iletiId, ilkBaslik: ilkBaslik), tamEkran: true);

  @override
  State<GorevDuzenleyici> createState() => _GorevDuzenleyiciState();
}

class _GorevDuzenleyiciState extends State<GorevDuzenleyici> {
  late final _baslik = TextEditingController(text: widget.gorev?.baslik ?? widget.ilkBaslik);
  late final _notlar = TextEditingController(text: widget.gorev?.notlar);
  late DateTime? _bitis = widget.gorev?.bitis;
  late String _oncelik = widget.gorev?.oncelik ?? 'normal';
  late String _durum = widget.gorev?.durum ?? 'todo';
  late GorevKisi? _atanan = widget.gorev?.atanan;
  List<GorevKisi> _kisiler = [];
  bool _kaydediyor = false;

  @override
  void initState() {
    super.initState();
    GorevApi.kisiler().then((l) {
      if (mounted) setState(() => _kisiler = l);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _baslik.dispose();
    _notlar.dispose();
    super.dispose();
  }

  Future<void> _tarih() async {
    final n = DateTime.now();
    final g = await showDatePicker(
      context: context,
      initialDate: _bitis ?? n,
      firstDate: DateTime(n.year - 1),
      lastDate: DateTime(n.year + 10),
      locale: const Locale('tr', 'TR'),
    );
    if (g == null || !mounted) return;
    final s = await showTimePicker(context: context, initialTime: _bitis != null ? TimeOfDay.fromDateTime(_bitis!) : const TimeOfDay(hour: 17, minute: 0));
    setState(() => _bitis = DateTime(g.year, g.month, g.day, s?.hour ?? 17, s?.minute ?? 0));
  }

  Future<void> _kisiSec() async {
    final ara = TextEditingController();
    final sec = await showModalBottomSheet<GorevKisi?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) {
          final q = ara.text.trim().toLowerCase();
          final l = _kisiler.where((k) => q.isEmpty || k.gorunen.toLowerCase().contains(q) || k.adres.toLowerCase().contains(q)).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(c).height * .7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: ara,
                      decoration: const InputDecoration(hintText: 'Kişi ara', prefixIcon: Icon(Simge.ara), isDense: true),
                      onChanged: (_) => yenile(() {}),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Simge.kisiYok),
                    title: const Text('Atanmamış'),
                    onTap: () => Navigator.pop(c, const GorevKisi(id: '')),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final k in l)
                          ListTile(
                            leading: Avatar(k.gorunen, boyut: 34, tohum: k.adres),
                            title: Text(k.gorunen),
                            subtitle: Text(k.adres),
                            trailing: _atanan?.id == k.id ? Icon(Simge.onay, color: c.r.vurgu) : null,
                            onTap: () => Navigator.pop(c, k),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    ara.dispose();
    if (sec != null) setState(() => _atanan = sec.id.isEmpty ? null : sec);
  }

  Future<void> _kaydet() async {
    if (_baslik.text.trim().isEmpty) {
      bildir('Başlık girin', tur: MesajTur.uyari);
      return;
    }
    setState(() => _kaydediyor = true);
    try {
      if (widget.gorev == null) {
        await GorevApi.olustur(
          baslik: _baslik.text,
          notlar: _notlar.text,
          bitis: _bitis,
          oncelik: _oncelik,
          durum: _durum,
          atananId: _atanan?.id,
          iletiId: widget.iletiId,
        );
      } else {
        await GorevApi.guncelle(
          widget.gorev!.id,
          baslik: _baslik.text,
          notlar: _notlar.text,
          bitis: _bitis,
          oncelik: _oncelik,
          durum: _durum,
          atananId: _atanan?.id,
        );
      }
      bildir(widget.gorev == null ? 'Görev oluşturuldu' : 'Görev güncellendi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      bildir('Kaydedilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
      if (mounted) setState(() => _kaydediyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.gorev == null ? 'Yeni görev' : 'Görevi düzenle'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _kaydediyor ? null : _kaydet, child: const Text('Kaydet')),
          ),
        ],
        bottom: _kaydediyor ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          TextField(
            key: const ValueKey('gorev-baslik'),
            controller: _baslik,
            autofocus: widget.gorev == null,
            maxLength: 300,
            style: gosterim(19, agirlik: FontWeight.w600),
            decoration: const InputDecoration(hintText: 'Ne yapılacak?', counterText: ''),
          ),
          if (widget.iletiId != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Simge.baglanti, size: 16, color: r.silik),
                  const SizedBox(width: 6),
                  Text('İletiye bağlı görev', style: TextStyle(color: r.silik, fontSize: 12.5)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _atanan == null ? const Icon(Simge.kisiEkle) : Avatar(_atanan!.gorunen, boyut: 32, tohum: _atanan!.adres),
                  title: Text(_atanan?.gorunen ?? 'Kişiye ata'),
                  subtitle: Text(_atanan?.adres ?? 'Atanmamış (yalnızca siz)'),
                  trailing: const Icon(Simge.ileri),
                  onTap: _kisiSec,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Simge.etkinlik),
                  title: Text(_bitis == null ? 'Bitiş tarihi ekle' : DateFormat('d MMMM y EEEE, HH:mm', 'tr_TR').format(_bitis!)),
                  trailing: _bitis == null
                      ? const Icon(Simge.ileri)
                      : IconButton(tooltip: 'Tarihi kaldır', icon: const Icon(Simge.kapat), onPressed: () => setState(() => _bitis = null)),
                  onTap: _tarih,
                ),
                const SizedBox(height: 8),
                Text(
                  'Öncelik',
                  style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [for (final e in gorevOncelikAdlari.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                  selected: {_oncelik},
                  onSelectionChanged: (v) => setState(() => _oncelik = v.first),
                ),
                const SizedBox(height: 12),
                Text(
                  'Durum',
                  style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [for (final e in gorevDurumAdlari.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                  selected: {_durum},
                  onSelectionChanged: (v) => setState(() => _durum = v.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notlar,
            minLines: 4,
            maxLines: 12,
            maxLength: 10000,
            decoration: const InputDecoration(labelText: 'Notlar', alignLabelWithHint: true),
          ),
        ],
      ),
    );
  }
}
