import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../veri/takvim_servisi.dart';
import 'takvim_ekrani.dart';
import '../../ortak/uyarlanir.dart';

/// Etkinlik ayrıntısı: bilgiler, katılımcılar, düzenle / sil. Değişiklik olduysa true döner.
class EtkinlikAyrinti extends StatelessWidget {
  const EtkinlikAyrinti({super.key, required this.etkinlik, required this.takvimler});
  final Etkinlik etkinlik;
  final List<Takvim> takvimler;

  static Future<bool?> ac(BuildContext context, {required Etkinlik etkinlik, required List<Takvim> takvimler}) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => EtkinlikAyrinti(etkinlik: etkinlik, takvimler: takvimler),
  );

  Future<void> _sil(BuildContext context) async {
    final e = etkinlik;
    var bildirim = false;
    if (e.katilimcilar.isNotEmpty) {
      final s = await showDialog<int>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Etkinlik silinsin mi?'),
          content: Text(
            e.tekrar.isNotEmpty
                ? 'Tekrarlanan etkinliğin tüm örnekleri silinir. Katılımcılara iptal bildirimi gönderebilirsiniz.'
                : 'Katılımcılara iptal bildirimi gönderebilirsiniz.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
            TextButton(onPressed: () => Navigator.pop(c, 0), child: const Text('Yalnızca sil')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Marka.gul),
              onPressed: () => Navigator.pop(c, 1),
              child: const Text('Sil ve iptal gönder'),
            ),
          ],
        ),
      );
      if (s == null) return;
      bildirim = s == 1;
    } else if (!await onayla(
      context,
      'Etkinlik silinsin mi?',
      mesaj: e.tekrar.isNotEmpty ? 'Tekrarlanan etkinliğin tüm örnekleri silinir.' : null,
      evet: 'Sil',
      tehlikeli: true,
    )) {
      return;
    }
    final ok = await islem(() async {
      await TakvimApi.sil(e.id, bildir: bildirim);
      return true;
    }, tamam: 'Etkinlik silindi');
    if (ok == true && context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final e = etkinlik;
    final takvim = takvimler.where((t) => t.id == e.takvimId).firstOrNull;
    final renk = takvimRengi(e.renk, r.vurgu);
    Widget satir(IconData i, String t, {Widget? alt}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(i, size: 20, color: r.silik),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(t, style: TextStyle(color: r.metin, fontSize: 14.5)),
                ?alt,
              ],
            ),
          ),
        ],
      ),
    );
    final tarih = e.tumGun
        ? DateFormat('d MMMM y EEEE', 'tr_TR').format(e.baslangic)
        : DateFormat('d MMMM y EEEE', 'tr_TR').format(e.tekrarBaslangici ?? e.baslangic);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.baslik, style: gosterim(21, agirlik: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            satir(
              Simge.saat,
              tarih,
              alt: Text(etkinlikSaati(e), style: TextStyle(color: r.soluk)),
            ),
            if (e.tekrar.isNotEmpty) satir(Simge.tekrar, tekrarAdlari[e.tekrar] ?? e.tekrar),
            if (e.yer.isNotEmpty) satir(Simge.konum, e.yer),
            if (e.hatirlatma != null) satir(Simge.bildirim, hatirlatmaAdlari[e.hatirlatma] ?? '${e.hatirlatma} dakika önce'),
            if (takvim != null) satir(Simge.takvim, takvim.ad),
            if (e.aciklama.trim().isNotEmpty) satir(Simge.notlar, e.aciklama.trim()),
            if (e.katilimcilar.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Katılımcılar (${e.katilimcilar.length})',
                style: TextStyle(fontWeight: FontWeight.w600, color: r.soluk),
              ),
              for (final k in e.katilimcilar)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Avatar(k.gorunen, boyut: 32, tohum: k.eposta),
                  title: Text(k.gorunen),
                  subtitle: k.ad.isNotEmpty ? Text(k.eposta) : null,
                ),
            ],
            if (e.davetli)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Bu etkinlik bir toplantı davetinden eklendi.', style: TextStyle(color: r.silik, fontSize: 12.5)),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Marka.gul),
                    onPressed: () => _sil(context),
                    icon: const Icon(Simge.sil),
                    label: const Text('Sil'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final ok = await EtkinlikDuzenleyici.ac(context, takvimler: takvimler, etkinlik: e);
                      if (ok == true && context.mounted) Navigator.pop(context, true);
                    },
                    icon: const Icon(Simge.duzenle),
                    label: const Text('Düzenle'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Etkinlik oluştur / düzenle (tam sayfa). Kaydedildiyse true.
class EtkinlikDuzenleyici extends StatefulWidget {
  const EtkinlikDuzenleyici({super.key, required this.takvimler, this.etkinlik, this.baslangic});
  final List<Takvim> takvimler;
  final Etkinlik? etkinlik;
  final DateTime? baslangic;

  static Future<bool?> ac(BuildContext context, {required List<Takvim> takvimler, Etkinlik? etkinlik, DateTime? baslangic}) =>
      uyarlanirAc<bool>(context, (_) => EtkinlikDuzenleyici(takvimler: takvimler, etkinlik: etkinlik, baslangic: baslangic), tamEkran: true);

  @override
  State<EtkinlikDuzenleyici> createState() => _EtkinlikDuzenleyiciState();
}

class _EtkinlikDuzenleyiciState extends State<EtkinlikDuzenleyici> {
  late final _baslik = TextEditingController(text: widget.etkinlik?.baslik);
  late final _yer = TextEditingController(text: widget.etkinlik?.yer);
  late final _aciklama = TextEditingController(text: widget.etkinlik?.aciklama);
  final _katilimciEkle = TextEditingController();
  late DateTime _bas;
  late DateTime _son;
  late bool _tumGun;
  late String _tekrar;
  late int? _hatirlatma;
  late String _takvim;
  late List<Katilimci> _katilimcilar;
  bool _davetGonder = true;
  bool _kaydediyor = false;

  @override
  void initState() {
    super.initState();
    final e = widget.etkinlik;
    _bas = e?.baslangic ?? widget.baslangic ?? DateTime.now();
    _son = e?.bitis ?? _bas.add(const Duration(hours: 1));
    _tumGun = e?.tumGun ?? false;
    _tekrar = e?.tekrar ?? '';
    _hatirlatma = e == null ? 15 : e.hatirlatma;
    _takvim = e?.takvimId ?? (widget.takvimler.where((t) => t.varsayilan).firstOrNull?.id ?? widget.takvimler.firstOrNull?.id ?? '');
    _katilimcilar = [...?e?.katilimcilar];
    if (_tumGun && !_son.isAfter(_bas)) _son = _bas.add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _baslik.dispose();
    _yer.dispose();
    _aciklama.dispose();
    _katilimciEkle.dispose();
    super.dispose();
  }

  /// Tüm gün etkinliklerinde bitiş, son günün ertesi 00:00'dır (gösterimde son gün).
  DateTime get _gorunenSon => _tumGun ? _son.subtract(const Duration(days: 1)) : _son;

  Future<void> _tarihSec(bool baslangic) async {
    final ilk = baslangic ? _bas : _gorunenSon;
    final g = await showDatePicker(context: context, initialDate: ilk, firstDate: DateTime(2000), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
    if (g == null) return;
    setState(() {
      if (baslangic) {
        final fark = _son.difference(_bas);
        _bas = DateTime(g.year, g.month, g.day, _bas.hour, _bas.minute);
        _son = _bas.add(fark);
      } else {
        _son = _tumGun ? DateTime(g.year, g.month, g.day + 1) : DateTime(g.year, g.month, g.day, _son.hour, _son.minute);
        if (_son.isBefore(_bas)) _bas = _tumGun ? DateTime(g.year, g.month, g.day) : _son.subtract(const Duration(hours: 1));
      }
    });
  }

  Future<void> _saatSec(bool baslangic) async {
    final ilk = baslangic ? _bas : _son;
    final s = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(ilk));
    if (s == null) return;
    setState(() {
      if (baslangic) {
        final fark = _son.difference(_bas);
        _bas = DateTime(_bas.year, _bas.month, _bas.day, s.hour, s.minute);
        _son = _bas.add(fark);
      } else {
        _son = DateTime(_son.year, _son.month, _son.day, s.hour, s.minute);
        if (_son.isBefore(_bas)) _son = _son.add(const Duration(days: 1));
      }
    });
  }

  void _katilimciEkleyin() {
    final t = _katilimciEkle.text.trim();
    if (t.isEmpty) return;
    final m = RegExp(r'^\s*(?:"?([^"<]*)"?\s*)?<?([^\s<>@]+@[^\s<>@]+\.[^\s<>@]+)>?\s*$').firstMatch(t);
    if (m == null) {
      bildir('Geçersiz e-posta adresi', tur: MesajTur.uyari);
      return;
    }
    final eposta = m.group(2)!.toLowerCase();
    if (_katilimcilar.any((k) => k.eposta == eposta)) return;
    setState(() {
      _katilimcilar.add(Katilimci(ad: (m.group(1) ?? '').trim(), eposta: eposta));
      _katilimciEkle.clear();
    });
  }

  Future<void> _kaydet() async {
    if (_baslik.text.trim().isEmpty) {
      bildir('Başlık girin', tur: MesajTur.uyari);
      return;
    }
    if (_katilimciEkle.text.trim().isNotEmpty) _katilimciEkleyin();
    var bas = _bas;
    var son = _son;
    if (_tumGun) {
      bas = DateTime(bas.year, bas.month, bas.day);
      son = DateTime(son.year, son.month, son.day);
      if (!son.isAfter(bas)) son = bas.add(const Duration(days: 1));
    }
    if (son.isBefore(bas)) {
      bildir('Bitiş, başlangıçtan önce olamaz', tur: MesajTur.uyari);
      return;
    }
    final e = Etkinlik(
      id: widget.etkinlik?.id ?? '',
      takvimId: _takvim,
      baslik: _baslik.text,
      yer: _yer.text,
      aciklama: _aciklama.text,
      baslangic: bas,
      bitis: son,
      tumGun: _tumGun,
      tekrar: _tekrar,
      hatirlatma: _hatirlatma,
      katilimcilar: _katilimcilar,
    );
    setState(() => _kaydediyor = true);
    try {
      final s = await TakvimApi.kaydet(e, davetGonder: _davetGonder && _katilimcilar.isNotEmpty);
      if (s.davetHatasi.isNotEmpty) {
        bildir('Etkinlik kaydedildi, davet gönderilemedi', mesaj: s.davetHatasi, tur: MesajTur.uyari);
      } else {
        bildir(s.davetGonderildi ? 'Etkinlik kaydedildi, davetler gönderildi' : 'Etkinlik kaydedildi', tur: MesajTur.basari);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      bildir('Kaydedilemedi', mesaj: hataMetni(err), tur: MesajTur.hata);
      if (mounted) setState(() => _kaydediyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final tf = DateFormat('d MMM y, EEE', 'tr_TR');
    final sf = DateFormat('HH:mm');
    Widget zamanSatiri(String etiket, DateTime d, bool bas) => Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            etiket,
            style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: OutlinedButton(onPressed: () => _tarihSec(bas), child: Text(tf.format(d))),
        ),
        if (!_tumGun) ...[const SizedBox(width: 8), OutlinedButton(onPressed: () => _saatSec(bas), child: Text(sf.format(d)))],
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.etkinlik == null ? 'Yeni etkinlik' : 'Etkinliği düzenle'),
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
            key: const ValueKey('etkinlik-baslik'),
            controller: _baslik,
            autofocus: widget.etkinlik == null,
            maxLength: 300,
            style: gosterim(19, agirlik: FontWeight.w600),
            decoration: const InputDecoration(hintText: 'Başlık ekleyin', counterText: ''),
          ),
          const SizedBox(height: 12),
          Kutu(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tüm gün'),
                  value: _tumGun,
                  onChanged: (v) => setState(() {
                    _tumGun = v;
                    if (v) {
                      _bas = DateTime(_bas.year, _bas.month, _bas.day);
                      _son = DateTime(_son.year, _son.month, _son.day + 1);
                    } else {
                      _bas = DateTime(_bas.year, _bas.month, _bas.day, 9);
                      _son = _bas.add(const Duration(hours: 1));
                    }
                  }),
                ),
                zamanSatiri('Başlangıç', _bas, true),
                const SizedBox(height: 8),
                zamanSatiri('Bitiş', _gorunenSon, false),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _tekrar,
                  decoration: const InputDecoration(labelText: 'Tekrar', prefixIcon: Icon(Simge.tekrar)),
                  items: [for (final e in tekrarAdlari.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _tekrar = v ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: hatirlatmaAdlari.containsKey(_hatirlatma) ? _hatirlatma : null,
                  decoration: const InputDecoration(labelText: 'Hatırlatma', prefixIcon: Icon(Simge.bildirim)),
                  items: [for (final e in hatirlatmaAdlari.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _hatirlatma = v),
                ),
                if (widget.takvimler.length > 1) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: widget.takvimler.any((t) => t.id == _takvim) ? _takvim : null,
                    decoration: const InputDecoration(labelText: 'Takvim', prefixIcon: Icon(Simge.takvim)),
                    items: [
                      for (final t in widget.takvimler)
                        DropdownMenuItem(
                          value: t.id,
                          child: Row(
                            children: [
                              Icon(Simge.nokta, size: 12, color: takvimRengi(t.renk, r.vurgu)),
                              const SizedBox(width: 8),
                              Text(t.ad),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _takvim = v ?? _takvim),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Kutu(
            child: Column(
              children: [
                TextField(
                  controller: _yer,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Yer', prefixIcon: Icon(Simge.konum), counterText: ''),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _aciklama,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Açıklama', alignLabelWithHint: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Katılımcılar',
                  style: TextStyle(fontWeight: FontWeight.w600, color: r.soluk),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _katilimciEkle,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'ad@ornek.com',
                    prefixIcon: const Icon(Simge.kisiEkle),
                    suffixIcon: IconButton(tooltip: 'Ekle', icon: const Icon(Simge.ekle), onPressed: _katilimciEkleyin),
                  ),
                  onSubmitted: (_) => _katilimciEkleyin(),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in _katilimcilar)
                      InputChip(
                        avatar: Avatar(k.gorunen, boyut: 22, tohum: k.eposta),
                        label: Text(k.gorunen),
                        tooltip: k.eposta,
                        onDeleted: () => setState(() => _katilimcilar.remove(k)),
                      ),
                  ],
                ),
                if (_katilimcilar.isNotEmpty)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _davetGonder,
                    onChanged: (v) => setState(() => _davetGonder = v ?? true),
                    title: const Text('Katılımcılara davet e-postası gönder'),
                    subtitle: const Text('Takvim daveti (.ics) olarak gönderilir; yanıtlar takviminize işlenir.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
