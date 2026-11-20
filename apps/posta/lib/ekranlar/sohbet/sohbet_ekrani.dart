import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../oturum.dart';
import '../../veri/sohbet_servisi.dart';
import 'kanallar.dart';
import 'kisi_secici.dart';
import 'ortak.dart';
import 'sohbet_odasi.dart';

enum SohbetSekmesi {
  tumu('Tümü'),
  kisiler('Kişiler'),
  gruplar('Gruplar'),
  kanallar('Kanallar');

  const SohbetSekmesi(this.ad);
  final String ad;

  bool uygun(SohbetOdasi o) => switch (this) {
    tumu => true,
    kisiler => o.birebir,
    gruplar => o.tur == 'group',
    kanallar => o.kanal,
  };
}

/// Telefonda bir odayı sayfa olarak açar.
Future<void> sohbetOdasiAc(BuildContext context, String odaId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SohbetOdasiEkrani(odaId: odaId)));

/// Kurum içi sohbet listesi: birebir, grup ve kanal sohbetleri; okunmamış sayıları, çevrimiçi durumu, arama.
/// [odaAc] verilirse (geniş ekran) oda yandaki bölmede açılır; yoksa sayfa olarak.
class SohbetEkrani extends StatefulWidget {
  const SohbetEkrani({super.key, this.odaAc, this.seciliOda});
  final ValueChanged<String>? odaAc;
  final String? seciliOda;
  @override
  State<SohbetEkrani> createState() => _SohbetEkraniState();
}

class _SohbetEkraniState extends State<SohbetEkrani> {
  SohbetSekmesi _sekme = SohbetSekmesi.tumu;
  final _ara = TextEditingController();
  bool _aramaAcik = false;

  /// Kişiler sekmesi: kurumdaki tüm iş arkadaşları (GET /chat/people) + en üstte siz.
  List<SohbetKisi>? _rehber;
  String? _rehberHata;
  bool _rehberYukleniyor = false;

  Future<void> _rehberYukle() async {
    if (_rehberYukleniyor) return;
    _rehberYukleniyor = true;
    try {
      final v = await Sohbet.kisiler();
      if (mounted) {
        setState(() {
          _rehber = v.kisiler;
          _rehberHata = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _rehberHata = e is ApiHata ? e.mesaj : 'Kişiler yüklenemedi.');
    } finally {
      _rehberYukleniyor = false;
    }
  }

  Future<void> _kisiyeYaz(SohbetKisi k) async {
    final benId = SohbetDurum.benId;
    for (final o in SohbetDurum.ben.odalar) {
      if (o.birebir && o.karsi(benId)?.id == k.id) return _ac(o.id);
    }
    try {
      final id = await Sohbet.odaOlustur([k.id]);
      await SohbetDurum.ben.yenile();
      if (mounted) _ac(id);
    } catch (e) {
      bildir(e is ApiHata ? e.mesaj : 'Sohbet açılamadı.', tur: MesajTur.hata);
    }
  }

  Widget _kisilerListesi() {
    final r = context.r;
    final q = _ara.text.trim().toLowerCase();
    if (_rehber == null) {
      if (_rehberHata != null) return Durum.hata(_rehberHata!, tekrar: _rehberYukle);
      if (!_rehberYukleniyor) _rehberYukle();
      return const Durum.yukleniyor();
    }
    bool uyar(SohbetKisi k) => q.isEmpty || '${k.gorunen} ${k.adres} ${k.unvan} ${k.departman}'.toLowerCase().contains(q);
    final ben = SohbetKisi(id: SohbetDurum.benId, adres: Uyg.adres, ad: Uyg.ad, cevrimici: 'online');
    final digerleri = _rehber!.where((k) => k.id != ben.id && uyar(k)).toList()
      ..sort((a, b) {
        int p(SohbetKisi k) => k.cevrimici == 'online' ? 0 : (k.cevrimici == 'away' ? 1 : 2);
        final c = p(a).compareTo(p(b));
        return c != 0 ? c : a.gorunen.toLowerCase().compareTo(b.gorunen.toLowerCase());
      });
    final beniGoster = uyar(ben);
    final okunmamis = <String, int>{};
    for (final o in SohbetDurum.ben.odalar.where((o) => o.birebir)) {
      final k = o.karsi(SohbetDurum.benId);
      if (k != null) okunmamis[k.id] = o.okunmamis;
    }
    Widget satir(SohbetKisi k, {bool benim = false}) {
      final v = varlikMetni(k);
      final alt = [if (k.unvan.isNotEmpty) k.unvan, if (k.departman.isNotEmpty) k.departman].join(' · ');
      final n = okunmamis[k.id] ?? 0;
      return ListTile(
        leading: VarlikAvatari(kisi: k, boyut: 42),
        title: Text(
          benim ? '${k.gorunen} (Siz)' : k.gorunen,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: n > 0 ? FontWeight.w800 : FontWeight.w600, color: r.metin),
        ),
        subtitle: Text(
          [if (alt.isNotEmpty) alt else k.adres, if (!benim && v.metin.isNotEmpty) v.metin].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: r.soluk, fontSize: 12.5),
        ),
        trailing: benim
            ? TextButton(onPressed: _durumum, child: const Text('Durumum'))
            : (n > 0 ? SayiHapi(n) : Icon(Icons.chat_bubble_outline_rounded, size: 20, color: r.silik)),
        onTap: benim ? _durumum : () => _kisiyeYaz(k),
      );
    }

    return RefreshIndicator(
      onRefresh: _rehberYukle,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (beniGoster) satir(ben, benim: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              'İŞ ARKADAŞLARI · ${digerleri.length}',
              style: TextStyle(color: r.silik, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .8),
            ),
          ),
          if (digerleri.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                q.isNotEmpty ? 'Aramanızla eşleşen kişi yok.' : 'Kurumunuzda sohbet kullanabilen başka kişi yok.',
                textAlign: TextAlign.center,
                style: TextStyle(color: r.soluk),
              ),
            ),
          for (final k in digerleri) satir(k),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    SohbetDurum.ben.addListener(_degisti);
    if (!SohbetDurum.ben.yuklendi) SohbetDurum.ben.yenile();
  }

  @override
  void dispose() {
    SohbetDurum.ben.removeListener(_degisti);
    _ara.dispose();
    super.dispose();
  }

  void _degisti() {
    if (mounted) setState(() {});
  }

  void _ac(String id) {
    if (widget.odaAc != null) {
      widget.odaAc!(id);
    } else {
      sohbetOdasiAc(context, id);
    }
  }

  Future<void> _yeni() async {
    final s = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Yeni sohbet', style: gosterim(17, agirlik: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Bir kişiyle'),
              subtitle: const Text('Birebir, yalnızca ikiniz'),
              onTap: () => Navigator.pop(c, 0),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Grup'),
              subtitle: const Text('Seçtiğiniz kişilerle özel grup'),
              onTap: () => Navigator.pop(c, 1),
            ),
            ListTile(
              leading: const Icon(Icons.tag_rounded),
              title: const Text('Kanallar'),
              subtitle: const Text('Kurumun açık kanallarına göz atın, katılın veya kanal oluşturun'),
              onTap: () => Navigator.pop(c, 2),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (s == null || !mounted) return;
    final id = s == 2 ? await KanallarEkrani.ac(context) : await KisiSecici.ac(context, coklu: s == 1);
    if (id != null && id.isNotEmpty && mounted) _ac(id);
  }

  Future<void> _durumum() async {
    SohbetProfili? p;
    try {
      p = await Sohbet.ben();
    } catch (e) {
      bildir('Durum alınamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
      return;
    }
    if (!mounted) return;
    var durum = p.durum;
    var goster = p.cevrimiciGoster;
    final metin = TextEditingController(text: p.durumMetni);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(c).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Durumum', style: gosterim(18, agirlik: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in sohbetDurumAdlari.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        avatar: Icon(_durumSimgesi(e.key), size: 16),
                        selected: durum == e.key,
                        onSelected: (_) => yenile(() => durum = e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: metin,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Durum notu', hintText: 'Örn. 15:00\'e kadar toplantıdayım'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: goster,
                  onChanged: (v) => yenile(() => goster = v),
                  title: const Text('Çevrimiçi olduğumu göster'),
                  subtitle: const Text('Kapatırsanız siz de başkalarının çevrimiçi durumunu göremezsiniz.'),
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
              ],
            ),
          ),
        ),
      ),
    );
    final not = metin.text.trim();
    metin.dispose();
    if (ok != true) return;
    await islem(
      () => Sohbet.benKaydet(cevrimiciGoster: goster, durum: durum, durumMetni: not),
      tamam: 'Durumunuz güncellendi',
    );
    await SohbetDurum.ben.yenile();
  }

  static IconData _durumSimgesi(String d) => switch (d) {
    'available' => Icons.check_circle_outline_rounded,
    'busy' => Icons.do_not_disturb_on_outlined,
    'meeting' => Icons.groups_outlined,
    'out' => Icons.directions_walk_rounded,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final d = SohbetDurum.ben;
    final r = context.r;
    final q = _ara.text.trim().toLowerCase();
    final benId = SohbetDurum.benId;
    final odalar = d.odalar.where((o) => _sekme.uygun(o) && (q.isEmpty || o.baslik(benId).toLowerCase().contains(q))).toList();
    Widget govde;
    if (d.kapali) {
      govde = Durum.bos(d.hata ?? 'Kurum içi mesajlaşma paketinizde kapalı.', ikon: Icons.speaker_notes_off_outlined);
    } else if (!d.yuklendi) {
      govde = const Durum.yukleniyor();
    } else if (d.hata != null && d.odalar.isEmpty) {
      govde = Durum.hata(d.hata!, tekrar: d.yenile);
    } else if (_sekme == SohbetSekmesi.kisiler) {
      govde = _kisilerListesi();
    } else {
      govde = RefreshIndicator(
        onRefresh: d.yenile,
        child: odalar.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 60),
                  Durum.bos(
                    q.isNotEmpty
                        ? 'Aramanızla eşleşen sohbet yok.'
                        : switch (_sekme) {
                            SohbetSekmesi.kisiler => 'Henüz birebir sohbetiniz yok.\nSağ alttaki düğmeyle bir iş arkadaşınıza yazın.',
                            SohbetSekmesi.gruplar => 'Henüz bir grubunuz yok.',
                            SohbetSekmesi.kanallar => 'Katıldığınız kanal yok.',
                            SohbetSekmesi.tumu => 'Henüz sohbet yok.',
                          },
                    ikon: Icons.forum_outlined,
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: odalar.length,
                separatorBuilder: (_, _) => Divider(height: 1, indent: 76, color: r.kenar.withValues(alpha: .6)),
                itemBuilder: (_, i) => _satir(odalar[i], benId),
              ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: _aramaAcik
            ? TextField(
                controller: _ara,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _sekme == SohbetSekmesi.kisiler ? 'Kişilerde ara' : 'Sohbetlerde ara',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                ),
                onChanged: (_) => setState(() {}),
              )
            : Row(
                children: [
                  const Text('Sohbet'),
                  if (d.okunmamis.value > 0) ...[const SizedBox(width: 8), SayiHapi(d.okunmamis.value)],
                ],
              ),
        actions: [
          IconButton(
            tooltip: _aramaAcik ? 'Aramayı kapat' : 'Sohbetlerde ara',
            icon: Icon(_aramaAcik ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _aramaAcik = !_aramaAcik;
              if (!_aramaAcik) _ara.clear();
            }),
          ),
          if (!d.kapali) ...[
            IconButton(
              tooltip: 'Kanallar',
              icon: const Icon(Icons.tag_rounded),
              onPressed: () async {
                final id = await KanallarEkrani.ac(context);
                if (id != null && mounted) _ac(id);
              },
            ),
            IconButton(tooltip: 'Durumum', icon: const Icon(Icons.emoji_people_rounded), onPressed: _durumum),
          ],
        ],
        bottom: d.kapali
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: SegmentedButton<SohbetSekmesi>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      for (final s in SohbetSekmesi.values)
                        ButtonSegment(
                          value: s,
                          label: Text(
                            () {
                              final n = d.odalar.where(s.uygun).fold(0, (t, o) => t + o.okunmamis);
                              return n > 0 && s != SohbetSekmesi.tumu ? '${s.ad} ($n)' : s.ad;
                            }(),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                          ),
                        ),
                    ],
                    selected: {_sekme},
                    onSelectionChanged: (v) => setState(() => _sekme = v.first),
                  ),
                ),
              ),
      ),
      floatingActionButton: d.kapali
          ? null
          : FloatingActionButton.extended(onPressed: _yeni, icon: const Icon(Icons.add_comment_rounded), label: const Text('Yeni sohbet')),
      body: govde,
    );
  }

  Widget _satir(SohbetOdasi o, String benId) {
    final r = context.r;
    final son = o.sonMesaj;
    final okunmamis = o.okunmamis > 0;
    String onizleme;
    if (son == null) {
      onizleme = o.kanal && o.aciklama.isNotEmpty ? o.aciklama : 'Henüz ileti yok';
    } else if (son.silindi) {
      onizleme = 'İleti geri çekildi';
    } else {
      final kim = son.benim ? 'Siz' : (o.birebir ? '' : son.gonderenAd.split(' ').first);
      onizleme = kim.isEmpty ? son.metin : '$kim: ${son.metin}';
    }
    final zaman = son?.tarih ?? o.sonTarih;
    final secili = widget.seciliOda == o.id;
    return Material(
      color: secili ? r.vurguYumusak : (okunmamis ? r.vurguYumusak.withValues(alpha: r.koyu ? .35 : .4) : r.kart),
      child: InkWell(
        onTap: () => _ac(o.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Row(
            children: [
              OdaSimgesi(oda: o),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.baslik(benId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: okunmamis ? FontWeight.w800 : FontWeight.w600, color: r.metin),
                          ),
                        ),
                        if (zaman != null)
                          Text(
                            _zaman(zaman),
                            style: TextStyle(fontSize: 12, color: okunmamis ? r.vurgu : r.silik, fontWeight: okunmamis ? FontWeight.w800 : FontWeight.w500),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            onizleme,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: okunmamis ? r.metin : r.silik,
                              fontWeight: okunmamis ? FontWeight.w600 : FontWeight.w400,
                              fontStyle: son?.silindi == true ? FontStyle.italic : null,
                            ),
                          ),
                        ),
                        if (okunmamis) ...[const SizedBox(width: 8), SayiHapi(o.okunmamis)],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _zaman(DateTime d) {
    final n = DateTime.now();
    if (d.year == n.year && d.month == n.month && d.day == n.day) return DateFormat('HH:mm').format(d);
    if (n.difference(d).inDays < 7) return DateFormat('EEE', 'tr_TR').format(d);
    return DateFormat('d.MM.yy').format(d);
  }
}
