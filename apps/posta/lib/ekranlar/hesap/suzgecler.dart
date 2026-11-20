import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/durum.dart';
import '../../veri/hesap_servisi.dart';
import 'ortak.dart';

const suzgecAlanlari = {
  'from': 'Kimden',
  'to': 'Kime',
  'cc': 'Bilgi (CC)',
  'recipient': 'Herhangi bir alıcı',
  'subject': 'Konu',
  'body': 'İleti metni',
  'size': 'Boyut (KB)',
};
const suzgecIslecleri = {
  'contains': 'içerir',
  'not_contains': 'içermez',
  'equals': 'eşittir',
  'starts': 'ile başlar',
  'ends': 'ile biter',
  'gt': 'büyüktür',
  'lt': 'küçüktür',
};
const suzgecEylemleri = {
  'move': 'Klasöre taşı',
  'label': 'Etiket ekle',
  'mark_read': 'Okundu işaretle',
  'flag': 'Yıldızla',
  'important': 'Önemli işaretle',
  'trash': 'Çöp Kutusu\'na taşı',
  'junk': 'Gereksiz\'e taşı',
};

/// Süzgecin okunabilir özeti: "Kimden içerir "fatura" → Klasöre taşı: Faturalar".
String suzgecOzeti(Suzgec s) {
  final d = PostaDurum.ben;
  final k = s.kosullar.map((x) => '${suzgecAlanlari[x.alan] ?? x.alan} ${suzgecIslecleri[x.islec] ?? x.islec} "${x.deger}"').join(s.hepsi ? ' ve ' : ' veya ');
  final e = s.eylemler
      .map((x) {
        final ad = suzgecEylemleri[x.tur] ?? x.tur;
        if (x.tur == 'move') return '$ad: ${d.klasor(x.deger)?.gorunenAd ?? '?'}';
        if (x.tur == 'label') return '$ad: ${d.etiket(x.deger)?.ad ?? '?'}';
        return ad;
      })
      .join(', ');
  return '${k.isEmpty ? 'Tüm iletiler' : k} → $e';
}

/// Süzgeci listede bir yukarı/aşağı taşır: sıra 10, 20, 30… olarak yeniden numaralanır ve yalnızca değişenler
/// kaydedilir (web FiltersSection.move ile aynı).
Future<void> suzgecTasi(List<Suzgec> l, int i, int yon) async {
  final j = i + yon;
  if (j < 0 || j >= l.length) return;
  final eski = {for (final s in l) s.id: s.sira};
  final sira = [...l];
  final x = sira[i];
  sira[i] = sira[j];
  sira[j] = x;
  final degisen = <Suzgec>[];
  for (var k = 0; k < sira.length; k++) {
    sira[k].sira = (k + 1) * 10;
    if (eski[sira[k].id] != sira[k].sira) degisen.add(sira[k]);
  }
  await Future.wait(degisen.map(Hesap.suzgecKaydet));
}

class SuzgeclerEkrani extends StatelessWidget {
  const SuzgeclerEkrani({super.key});

  Future<void> _duzenle(BuildContext context, Suzgec? s, Future<void> Function() yenile) async {
    final kaydedildi = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SuzgecDuzenleyici(suzgec: s)));
    if (kaydedildi == true) await yenile();
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<List<Suzgec>>(
    baslik: 'Süzgeçler (kurallar)',
    altBaslik: 'Gelen iletiler sırayla bu kurallardan geçer; koşulları sağlayanlara eylemler uygulanır.',
    yukle: Hesap.suzgecler,
    fab: (context, yenile) =>
        FloatingActionButton.extended(onPressed: () => _duzenle(context, null, yenile), icon: const Icon(Icons.add_rounded), label: const Text('Süzgeç ekle')),
    govde: (context, l, yenile) {
      if (l.isEmpty) {
        return [const BosKart('Henüz süzgeç yok. Örneğin belirli bir göndericinin iletilerini bir klasöre taşıyabilirsiniz.', ikon: Icons.filter_alt_outlined)];
      }
      final r = context.r;
      return [
        KartListe(
          children: [
            for (final (i, s) in l.indexed)
              ListTile(
                key: ValueKey('suzgec-${s.id}'),
                onTap: () => _duzenle(context, s, yenile),
                leading: Switch.adaptive(
                  value: s.acik,
                  onChanged: (v) async {
                    s.acik = v;
                    await islem(() => Hesap.suzgecKaydet(s), tamam: v ? 'Süzgeç açıldı' : 'Süzgeç kapatıldı');
                    await yenile();
                  },
                ),
                title: Text(
                  s.ad.isEmpty ? 'Adsız süzgeç' : s.ad,
                  style: TextStyle(fontWeight: FontWeight.w600, color: s.acik ? r.metin : r.silik),
                ),
                subtitle: Text(suzgecOzeti(s), maxLines: 3, overflow: TextOverflow.ellipsis),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Seçenekler',
                  onSelected: (v) async {
                    if (v == 'yukari' || v == 'asagi') {
                      await islem(() => suzgecTasi(l, i, v == 'yukari' ? -1 : 1));
                      await yenile();
                    } else if (v == 'calistir') {
                      final n = await islem(() => Hesap.suzgecCalistir(s.id));
                      if (n != null) bildir('${n.eslesen} ileti eşleşti', mesaj: '${n.taranan} ileti tarandı', tur: MesajTur.basari);
                      PostaDurum.ben.sayilariYenile();
                    } else if (v == 'sil') {
                      if (!await onayla(context, 'Süzgeç silinsin mi?', evet: 'Sil', tehlikeli: true)) return;
                      await islem(() => Hesap.suzgecSil(s.id), tamam: 'Süzgeç silindi');
                      await yenile();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'yukari',
                      enabled: i > 0,
                      child: const ListTile(leading: Icon(Icons.arrow_upward_rounded), title: Text('Yukarı taşı')),
                    ),
                    PopupMenuItem(
                      value: 'asagi',
                      enabled: i < l.length - 1,
                      child: const ListTile(leading: Icon(Icons.arrow_downward_rounded), title: Text('Aşağı taşı')),
                    ),
                    const PopupMenuItem(
                      value: 'calistir',
                      child: ListTile(leading: Icon(Icons.play_arrow_rounded), title: Text('Gelen Kutusu\'na şimdi uygula')),
                    ),
                    const PopupMenuItem(
                      value: 'sil',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded, color: Marka.gul),
                        title: Text('Sil'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ];
    },
  );
}

/// Süzgeç oluşturma / düzenleme sayfası.
class SuzgecDuzenleyici extends StatefulWidget {
  const SuzgecDuzenleyici({super.key, this.suzgec});
  final Suzgec? suzgec;
  @override
  State<SuzgecDuzenleyici> createState() => _SuzgecDuzenleyiciState();
}

class _SuzgecDuzenleyiciState extends State<SuzgecDuzenleyici> {
  late final Suzgec _s = widget.suzgec == null ? Suzgec(kosullar: [SuzgecKosulu()], eylemler: [SuzgecEylemi()]) : Suzgec.json(widget.suzgec!.json());
  late final _ad = TextEditingController(text: _s.ad);
  bool _mesgul = false;

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    _s.ad = _ad.text.trim();
    if (_s.ad.isEmpty) return bildir('Süzgece bir ad verin', tur: MesajTur.uyari);
    if (_s.kosullar.any((k) => k.deger.trim().isEmpty)) return bildir('Koşul değerlerini doldurun', tur: MesajTur.uyari);
    if (_s.eylemler.isEmpty) return bildir('En az bir eylem ekleyin', tur: MesajTur.uyari);
    if (_s.eylemler.any((e) => e.degerli && e.deger.isEmpty)) return bildir('Taşınacak klasörü / eklenecek etiketi seçin', tur: MesajTur.uyari);
    setState(() => _mesgul = true);
    final ok = await islem(() async {
      await Hesap.suzgecKaydet(_s);
      return true;
    }, tamam: 'Süzgeç kaydedildi');
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (ok == true) Navigator.pop(context, true);
  }

  Widget _secim<T>(T deger, Map<T, String> ogeler, ValueChanged<T> degisti) => DropdownButtonFormField<T>(
    initialValue: ogeler.containsKey(deger) ? deger : null,
    isExpanded: true,
    isDense: true,
    items: [
      for (final e in ogeler.entries)
        DropdownMenuItem(
          value: e.key,
          child: Text(e.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (v) {
      if (v != null) setState(() => degisti(v));
    },
  );

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final d = PostaDurum.ben;
    final klasorler = {for (final k in d.klasorler.where((k) => k.rol != 'drafts' && k.rol != 'sent' && k.rol != 'templates')) k.id: k.gorunenAd};
    final etiketler = {for (final e in d.etiketler) e.id: e.ad};
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.suzgec == null ? 'Yeni süzgeç' : 'Süzgeci düzenle'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              TextField(
                controller: _ad,
                decoration: const InputDecoration(labelText: 'Süzgeç adı'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _s.acik,
                onChanged: (v) => setState(() => _s.acik = v),
                title: const Text('Etkin'),
              ),
              Baslik(
                'Koşullar',
                sag: TextButton.icon(
                  onPressed: () => setState(() => _s.kosullar.add(SuzgecKosulu())),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Koşul ekle'),
                ),
              ),
              if (_s.kosullar.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Tümü sağlanmalı')),
                      ButtonSegment(value: false, label: Text('Herhangi biri yeter')),
                    ],
                    selected: {_s.hepsi},
                    onSelectionChanged: (v) => setState(() => _s.hepsi = v.first),
                  ),
                ),
              if (_s.kosullar.isEmpty) Text('Koşul yoksa süzgeç tüm gelen iletilere uygulanır.', style: TextStyle(color: r.silik)),
              for (final k in _s.kosullar)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Kutu(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _secim(k.alan, suzgecAlanlari, (v) {
                                      k.alan = v;
                                      final boyut = k.islec == 'gt' || k.islec == 'lt';
                                      if (v == 'size' && !boyut) k.islec = 'gt';
                                      if (v != 'size' && boyut) k.islec = 'contains';
                                    }),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _secim(
                                      k.islec,
                                      k.alan == 'size'
                                          ? {for (final e in suzgecIslecleri.entries.where((e) => e.key == 'gt' || e.key == 'lt')) e.key: e.value}
                                          : {for (final e in suzgecIslecleri.entries.where((e) => e.key != 'gt' && e.key != 'lt')) e.key: e.value},
                                      (v) => k.islec = v,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                initialValue: k.deger,
                                keyboardType: k.alan == 'size' ? TextInputType.number : TextInputType.text,
                                decoration: InputDecoration(hintText: k.alan == 'size' ? 'Örn. 1024' : 'Değer', isDense: true),
                                onChanged: (v) => k.deger = v,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Koşulu kaldır',
                          icon: Icon(Icons.close_rounded, color: r.silik),
                          onPressed: () => setState(() => _s.kosullar.remove(k)),
                        ),
                      ],
                    ),
                  ),
                ),
              Baslik(
                'Eylemler',
                sag: TextButton.icon(
                  onPressed: () => setState(() => _s.eylemler.add(SuzgecEylemi(tur: 'mark_read'))),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Eylem ekle'),
                ),
              ),
              for (final e in _s.eylemler)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Kutu(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: _secim(e.tur, suzgecEylemleri, (v) {
                            e.tur = v;
                            e.deger = '';
                          }),
                        ),
                        if (e.degerli) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: (e.tur == 'move' ? klasorler : etiketler).isEmpty
                                ? Text(e.tur == 'move' ? 'Klasör yok' : 'Etiket yok', style: TextStyle(color: r.silik))
                                : _secim(e.deger, e.tur == 'move' ? klasorler : etiketler, (v) => e.deger = v),
                          ),
                        ],
                        IconButton(
                          tooltip: 'Eylemi kaldır',
                          icon: Icon(Icons.close_rounded, color: r.silik),
                          onPressed: () => setState(() => _s.eylemler.remove(e)),
                        ),
                      ],
                    ),
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _s.dur,
                onChanged: (v) => setState(() => _s.dur = v ?? false),
                title: const Text('Bu süzgeç uygulanınca sonraki süzgeçleri işleme'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
