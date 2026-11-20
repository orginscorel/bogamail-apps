import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../veri/bildirim_izni.dart';
import '../oturum.dart';
import '../veri/bildirim.dart';
import '../veri/durum.dart';
import '../veri/html_temizle.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/tercihler.dart';
import '../veri/yardimci.dart';
import 'ayarlar/bolum.dart';
import 'ayarlar/bolumler.dart';
import 'hesap/araclar.dart';
import 'hesap/imza.dart';
import 'hesap/otomatik_yanit.dart';
import 'hesap/guvenlik.dart';
import 'hesap/posta_yonetimi.dart';
import 'hesap/profil.dart';
import 'hesap/suzgecler.dart';
import 'hesaplar.dart';

class AyarlarEkrani extends StatefulWidget {
  const AyarlarEkrani({super.key, this.kategori});

  /// Açılışta gösterilecek kategori (masaüstü sağ bölme; telefonda o bölümün sayfası açılır).
  final String? kategori;
  @override
  State<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends State<AyarlarEkrani> {
  PostaAyarlari? _a;
  String? _hata;
  final _ad = TextEditingController();
  final _tatilKonu = TextEditingController();
  final _tatilMetin = TextEditingController();
  bool _tatil = false;
  String? _tatilBas;
  String? _tatilBit;
  int _geriAl = 0;
  bool _kaydediliyor = false;
  bool _profilKirli = false;
  bool _tatilKirli = false;

  // bildirimler
  Map<String, dynamic>? _push;
  bool _izin = true;
  bool _arkaPlan = true;

  @override
  void initState() {
    super.initState();
    _yukle();
    _bildirimDurumu();
    for (final c in [_ad]) {
      c.addListener(() {
        if (!_profilKirli) setState(() => _profilKirli = true);
      });
    }
    for (final c in [_tatilKonu, _tatilMetin]) {
      c.addListener(() {
        if (!_tatilKirli) setState(() => _tatilKirli = true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_ad, _tatilKonu, _tatilMetin]) {
      c.dispose();
    }
    _degisim.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final a = await Posta.ayarlar();
      if (!mounted) return;
      PostaDurum.ben.ayarlar = a;
      setState(() {
        _a = a;
        _ad.text = a.gorunenAd;
        _tatil = a.tatilAcik;
        _tatilKonu.text = a.tatilKonu;
        _tatilMetin.text = a.tatilMetin;
        _tatilBas = a.tatilBaslangic;
        _tatilBit = a.tatilBitis;
        _geriAl = a.geriAlmaSaniye;
        _profilKirli = false;
        _tatilKirli = false;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _bildirimDurumu() async {
    if (Push.destekli) {
      try {
        final p = await Posta.pushBilgi();
        if (mounted) setState(() => _push = p);
      } catch (_) {}
    }
    if (Bildirim.android) {
      final i = await Bildirim.izinVar();
      final a = await Bildirim.arkaPlanAcik();
      if (mounted) {
        setState(() {
          _izin = i;
          _arkaPlan = a;
        });
      }
    }
  }

  Future<void> _kaydet(Map<String, dynamic> degisen, String tamam) async {
    setState(() => _kaydediliyor = true);
    try {
      await Posta.ayarKaydet(degisen);
      bildir(tamam, tur: MesajTur.basari);
      await _yukle();
      unawaited(Posta.kutuYenile());
    } catch (e) {
      bildir('Kaydedilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  Future<void> _profilKaydet() async {
    final a = _a!;
    final d = <String, dynamic>{};
    if (_ad.text.trim() != a.gorunenAd) d['display_name'] = _ad.text.trim();
    if (d.isEmpty) {
      setState(() => _profilKirli = false);
      return;
    }
    await _kaydet(d, 'Profil kaydedildi');
  }

  Future<void> _tatilKaydet() async {
    if (_tatil && _tatilMetin.text.trim().isEmpty) {
      bildir('Otomatik yanıt metnini yazın', tur: MesajTur.uyari);
      return;
    }
    await _kaydet({
      'vacation_enabled': _tatil,
      'vacation_subject': _tatilKonu.text.trim(),
      'vacation_body': _tatilMetin.text,
      'vacation_start': _tatilBas ?? '',
      'vacation_end': _tatilBit ?? '',
    }, _tatil ? 'Otomatik yanıt açıldı' : 'Otomatik yanıt kaydedildi');
  }

  Future<void> _tarihSec(bool baslangic) async {
    final simdi = DateTime.now();
    final mevcut = DateTime.tryParse((baslangic ? _tatilBas : _tatilBit) ?? '');
    final t = await showDatePicker(
      context: context,
      firstDate: DateTime(simdi.year - 1),
      lastDate: DateTime(simdi.year + 3),
      initialDate: mevcut ?? simdi,
      helpText: baslangic ? 'Başlangıç tarihi' : 'Bitiş tarihi',
    );
    if (t == null) return;
    final s = DateFormat('yyyy-MM-dd').format(t);
    setState(() {
      if (baslangic) {
        _tatilBas = s;
      } else {
        _tatilBit = s;
      }
      _tatilKirli = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        bottom: _kaydediliyor ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: _hata != null
          ? Durum.hata(_hata!, tekrar: _yukle)
          : _a == null
          ? const Durum.yukleniyor()
          : LayoutBuilder(
              builder: (_, k) => (_masaustuKipi = k.maxWidth >= masaustuGenisligi)
                  ? _masaustu()
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: _bolumler()),
                      ),
                    ),
            ),
    );
  }

  /// Bu genişlikten itibaren (masaüstü/tablet yatay) iki bölmeli düzen: solda kategoriler, sağda içerik.
  static const masaustuGenisligi = 820.0;

  late String _kategori = widget.kategori ?? 'hesaplar';
  bool _masaustuKipi = false;

  /// Tüm kategoriler: yerleşikler + lib/ekranlar/ayarlar/bolumler.dart'taki eklenenler (aynı id yerleşiğin yerine
  /// geçer), görünürlüğe göre süzülmüş ve sıralı.
  List<AyarBolumu> get _tumBolumler {
    final a = _a!;
    AyarBolumu y(String id, IconData ikon, String baslik, int sira, {bool Function(PostaAyarlari)? gorunur}) =>
        AyarBolumu(id: id, ikon: ikon, baslik: baslik, sira: sira, tamSayfa: true, gorunur: gorunur, olustur: (_) => _kategoriIcerigi(id));
    final yerlesik = [
      // Profil ve hesap
      y('profil', Simge.kimlik, 'Profil', 5),
      y('guvenlik', Simge.guvenli, 'Güvenlik', 70),
      y('cihazlar', Simge.cihazlar, 'Kayıtlı cihazlar ve oturumlar', 72),
      y('hesaplar', Simge.hesapYonet, 'Hesaplar', 74),
      y('depolama', Simge.sunucu, 'Depolama ve kota', 76),
      // Posta
      y('genel', Simge.ayarlarInce, 'Genel', 20),
      y('imza', Simge.imza, 'İmza', 40),
      y('suzgecler', Simge.suzgec, 'Süzgeçler', 80),
      y('otomatik', Simge.tatil, 'Otomatik yanıt', 90),
      y('kisiler', Simge.kisiler, 'Kişiler', 100),
      y('yonlendirme', Simge.yonlendir, 'Yönlendirme', 110, gorunur: (a) => a.ozellik('forwarding')),
      y('engelli', Simge.kalkan, 'Engellenen ve güvenli gönderenler', 112),
      y('posta', Simge.postaYonetimi, 'Posta araçları', 120),
      // Uygulama
      y('gorunum', Simge.palet, 'Görünüm', 30),
      y('bildirimler', Simge.bildirim, 'Bildirimler', 60),
      y('uygulama', Simge.guncelle, 'Güncelleme ve sürüm', 900),
      y('hakkinda', Simge.bilgi, 'Hakkında', 950),
    ];
    final ekIdler = ekAyarBolumleri.map((b) => b.id).toSet();
    final l = [...yerlesik.where((b) => !ekIdler.contains(b.id)), ...ekAyarBolumleri].where((b) => b.gorunur?.call(a) ?? true).toList();
    // Önce grup (Profil ve hesap, Posta, Uygulama), sonra sıra.
    l.sort((x, z) => x.etkinGrup.index != z.etkinGrup.index ? x.etkinGrup.index.compareTo(z.etkinGrup.index) : x.sira.compareTo(z.sira));
    return l;
  }

  /// Bölümün sayfası: tam sayfa olduğu gibi, gövde ise başlıklı okunabilir genişlikte bir sayfaya konur.
  Widget _bolumSayfasi(AyarBolumu b, BuildContext c, {required bool masaustu}) {
    if (b.tamSayfa) return b.olustur(c);
    final govde = b.olustur(c);
    if (!masaustu) {
      return Scaffold(
        appBar: AppBar(title: Text(b.baslik)),
        body: govde,
      );
    }
    return Scaffold(
      backgroundColor: context.r.zemin,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(b.baslik, style: gosterim(24, agirlik: FontWeight.w600)),
              ),
              Expanded(child: govde),
            ],
          ),
        ),
      ),
    );
  }

  Widget _masaustu() {
    final r = context.r;
    final l = _tumBolumler;
    if (!l.any((k) => k.id == _kategori)) _kategori = l.first.id;
    final secili = l.firstWhere((k) => k.id == _kategori);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 264,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
            children: [
              for (final (i, AyarBolumu(:id, :ikon, baslik: ad, :etkinGrup)) in l.indexed) ...[
                if (i == 0 || l[i - 1].etkinGrup != etkinGrup)
                  Padding(
                    key: ValueKey('ayar-grup-${etkinGrup.name}'),
                    padding: EdgeInsets.fromLTRB(12, i == 0 ? 8 : 18, 12, 6),
                    child: Text(
                      trBuyukHarf(etkinGrup.baslik),
                      style: TextStyle(color: r.silik, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .8),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Material(
                    color: _kategori == id ? r.vurguYumusak : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: ListTile(
                      key: ValueKey('ayar-kategori-$id'),
                      dense: true,
                      selected: _kategori == id,
                      selectedColor: r.vurgu,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      visualDensity: VisualDensity.compact,
                      leading: Icon(ikon, size: 20),
                      title: Text(ad, style: TextStyle(fontSize: 13.5, fontWeight: _kategori == id ? FontWeight.w600 : FontWeight.w400)),
                      onTap: () => setState(() => _kategori = id),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const SurumEtiketi(ortala: true),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: r.kenar),
        // Alt sayfalar (hesap/*, imza...) sağ bölmede açılır: bölmenin kendi gezgini vardır.
        Expanded(
          child: ClipRect(
            child: Navigator(
              key: ValueKey('ayar-bolme-$_kategori'),
              pages: [
                MaterialPage<void>(
                  key: ValueKey(_kategori),
                  child: Builder(builder: (c) => _bolumSayfasi(secili, c, masaustu: true)),
                ),
              ],
              onDidRemovePage: (_) {},
            ),
          ),
        ),
      ],
    );
  }

  /// Okunabilir genişlikte, kaydırılabilir içerik; geniş bölmede kartlar iki sütuna yayılır.
  Widget _icerik(String baslik, List<Widget> l) {
    // Bildirimler bölümünde izin kapalıysa uyarı bandı en üstte.
    if (_kategori == 'bildirimler') l = [const BildirimIzniBandi(kenar: EdgeInsets.only(bottom: 12)), ...l];
    if (!_masaustuKipi) {
      return Scaffold(
        appBar: AppBar(title: Text(baslik)),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: l),
      );
    }
    return Scaffold(
      backgroundColor: context.r.zemin,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              Text(baslik, style: gosterim(24, agirlik: FontWeight.w600)),
              const SizedBox(height: 8),
              ...l,
            ],
          ),
        ),
      ),
    );
  }

  /// İki kartı yan yana (yer yoksa alt alta) dizer.
  Widget _ikiSutun(Widget a, Widget b) => LayoutBuilder(
    builder: (_, k) => k.maxWidth < 680
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 12), b])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 16),
              Expanded(child: b),
            ],
          ),
  );

  /// Tam sayfa ekranlar sağ bölmeye okunabilir genişlikte yerleştirilir.
  Widget _sayfa(Widget w) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: w),
  );

  Widget _kategoriIcerigi(String id) {
    final a = _a!;
    final liste = _listeKartlari();
    return switch (id) {
      'hesaplar' => _icerik('Hesaplar', [
        const Baslik('Bu cihazdaki hesaplar'),
        const Kutu(padding: EdgeInsets.symmetric(vertical: 6), child: HesapSecici(gomulu: true)),
      ]),
      'depolama' => _icerik('Depolama ve kota', [const SizedBox(height: 8), _hesap()]),
      'cihazlar' => _sayfa(const KayitliCihazlarEkrani()),
      'engelli' => _sayfa(const GondericiListeleriEkrani()),
      'hakkinda' => _icerik('Hakkında', [const SizedBox(height: 8), _hakkindaKarti(), const SizedBox(height: 16), const SurumEtiketi(ortala: true)]),
      'genel' => _icerik('Genel', [const Baslik('Görünen ad'), _profilKarti(), const Baslik('Liste ve gönderim'), _ikiSutun(liste.first, liste.last)]),
      'gorunum' => _icerik('Görünüm', [const SizedBox(height: 8), _gorunumKarti()]),
      'imza' => _sayfa(const ImzaEkrani()),
      'profil' => _sayfa(const ImzaProfiliEkrani()),
      'bildirimler' => _icerik('Bildirimler', [const SizedBox(height: 8), _bildirimler()]),
      'guvenlik' => _icerik('Güvenlik', [
        AraclarBolumleri(ayarlar: a, bolumler: const {'guvenlik'}),
      ]),
      'suzgecler' => _sayfa(const SuzgeclerEkrani()),
      'otomatik' => _icerik('Otomatik yanıt', [
        const SizedBox(height: 8),
        _tatilBolumu(),
        if (a.ozellik('autoresponder')) ...[
          const SizedBox(height: 12),
          Kutu(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Builder(
              builder: (context) => ListTile(
                leading: const Icon(Simge.otomatik),
                title: const Text('Otomatik yanıt kuralları'),
                subtitle: const Text('Mesai dışı, belirli günler, iç/dış gönderen'),
                trailing: const Icon(Simge.ileri),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OtomatikYanitKurallariEkrani())),
              ),
            ),
          ),
        ],
      ]),
      'kisiler' => _sayfa(const KisilerEkrani()),
      'yonlendirme' => _sayfa(const YonlendirmeEkrani()),
      'posta' => _icerik('Posta yönetimi', [
        AraclarBolumleri(ayarlar: a, bolumler: const {'posta'}),
      ]),
      _ => _icerik('Uygulama ve güncelleme', [const SizedBox(height: 8), GuncellemeKarti(api: Uyg.api)]),
    };
  }

  Widget _bolumSatiri(AyarBolumu b) => ListTile(
    key: ValueKey('ayar-satir-${b.id}'),
    leading: Icon(b.ikon, size: 20, color: context.r.soluk),
    title: Text(b.baslik, style: const TextStyle(fontSize: 14)),
    subtitle: b.aciklama.isEmpty ? null : Text(b.aciklama, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
    trailing: Icon(Simge.ileri, size: 18, color: context.r.silik),
    visualDensity: VisualDensity.compact,
    onTap: () => _bolumAc(b),
  );

  /// Telefonda bölüm sayfası. Yerleşik sayfalar bu durumun alanlarını kullanır: değişince sayfa da yenilenir.
  Future<void> _bolumAc(AyarBolumu b) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => ListenableBuilder(listenable: _degisim, builder: (c, _) => _bolumSayfasi(b, c, masaustu: false)),
      ),
    );
    if (mounted) _yukle();
  }

  final _degisim = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _degisim.value++;
  }

  /// Telefon: üstte profil kartı (dokununca Profil), altında gruplanmış kategoriler (Profil ve hesap, Posta,
  /// Uygulama). Her kategori kendi sayfasında açılır; aynı ayar iki yerde görünmez.
  List<Widget> _bolumler() {
    final l = _tumBolumler;
    final profil = l.where((b) => b.id == 'profil').firstOrNull;
    return [
      const SizedBox(height: 8),
      _profilBasligi(profil),
      const BildirimIzniBandi(kenar: EdgeInsets.only(top: 4, bottom: 4)),
      for (final g in AyarGrubu.values)
        if (l.any((b) => b.etkinGrup == g && b.id != 'profil')) ...[
          Baslik(g.baslik, key: ValueKey('ayar-grup-${g.name}')),
          Kutu(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [for (final b in l.where((b) => b.etkinGrup == g && b.id != 'profil')) _bolumSatiri(b)]),
          ),
        ],
      const SizedBox(height: 16),
      const SurumEtiketi(ortala: true),
    ];
  }

  Widget _profilBasligi(AyarBolumu? profil) {
    final r = context.r;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: Uyg.kutu,
      builder: (_, _, _) => Kutu(
        padding: EdgeInsets.zero,
        child: InkWell(
          key: const ValueKey('profil-karti'),
          borderRadius: BorderRadius.circular(16),
          onTap: profil == null ? null : () => _bolumAc(profil),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Avatar(Uyg.ad.isEmpty ? Uyg.adres : Uyg.ad, boyut: 48, tohum: Uyg.adres),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Uyg.ad.isEmpty ? Uyg.adres : Uyg.ad,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: r.metin),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Uyg.adres,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: r.soluk, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Simge.ileri, size: 18, color: r.silik),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profilKarti() {
    return Kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ad,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Görünen ad', counterText: ''),
          ),
          const SizedBox(height: 12),
          _imzaSatiri(),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _profilKirli && !_kaydediliyor ? _profilKaydet : null, child: const Text('Kaydet')),
          ),
        ],
      ),
    );
  }

  Widget _imzaSatiri() {
    final r = context.r;
    final a = _a!;
    return ListTile(
      key: const ValueKey('imza-ac'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(Simge.imza, color: r.vurgu),
      title: const Text('İmza'),
      subtitle: Text(
        a.imzaKilitli
            ? 'Kurum şablonu (kilitli)'
            : (a.etkinImzaHtml.trim().isEmpty ? 'İmza yok · eklemek için dokunun' : htmlMetne(a.etkinImzaHtml).replaceAll(RegExp(r'\s+'), ' ').trim()),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Simge.ileri),
      onTap: () async {
        if (_masaustuKipi) return setState(() => _kategori = 'imza');
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ImzaEkrani()));
        _yukle();
      },
    );
  }

  Widget _gorunumKarti() {
    final r = context.r;
    return Kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tema',
            style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: temaKipi,
            builder: (_, k, _) => SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Simge.sistemTema)),
                ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Simge.acikTema)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Simge.koyuTema)),
              ],
              selected: {k},
              onSelectionChanged: (s) => Tercihler.temaAyarla(s.first),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: Tercihler.uzakGorseller,
            builder: (_, v, _) => SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: v,
              onChanged: Tercihler.uzakGorselAyarla,
              title: const Text('Uzak görselleri otomatik göster'),
              subtitle: const Text('Görseller sunucu üzerinden alınır; gönderen IP adresinizi görmez. Gereksiz ve uyarılı iletilerde yine sorulur.'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _listeKartlari() {
    final a = _a!;
    return [
      Kutu(
        child: Row(
          children: [
            const Expanded(child: Text('Sayfa başına ileti')),
            DropdownButton<int>(
              value: const [25, 50, 100, 200].contains(a.sayfaBoyutu) ? a.sayfaBoyutu : 50,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 25, child: Text('25')),
                DropdownMenuItem(value: 50, child: Text('50')),
                DropdownMenuItem(value: 100, child: Text('100')),
                DropdownMenuItem(value: 200, child: Text('200')),
              ],
              onChanged: _kaydediliyor ? null : (v) => _kaydet({'page_size': v ?? 50}, 'Sayfa boyutu kaydedildi'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Kutu(
        child: Row(
          children: [
            const Expanded(child: Text('Gönderimi geri alma süresi')),
            DropdownButton<int>(
              value: const [0, 5, 10, 20, 30].contains(_geriAl) ? _geriAl : 0,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Kapalı')),
                DropdownMenuItem(value: 5, child: Text('5 saniye')),
                DropdownMenuItem(value: 10, child: Text('10 saniye')),
                DropdownMenuItem(value: 20, child: Text('20 saniye')),
                DropdownMenuItem(value: 30, child: Text('30 saniye')),
              ],
              onChanged: _kaydediliyor ? null : (v) => _kaydet({'undo_send_seconds': v ?? 0}, 'Geri alma süresi kaydedildi'),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _hakkindaKarti() {
    final a = _a!;
    return Kutu(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Simge.sunucu),
            title: const Text('Sunucu'),
            subtitle: Text(Uyg.api.sunucu),
            onTap: () => kopyala(Uyg.api.sunucu, mesaj: 'Sunucu adresi kopyalandı'),
          ),
          if (a.sunucu.isNotEmpty) ListTile(leading: const Icon(Simge.kurulum), title: const Text('IMAP/SMTP sunucusu'), subtitle: Text(a.sunucu)),
        ],
      ),
    );
  }

  Widget _hesap() {
    final r = context.r;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: Uyg.kutu,
      builder: (_, k, _) {
        final kota = (k?['quota_bytes'] as num?)?.toInt() ?? 0;
        final kul = (k?['used_bytes'] as num?)?.toInt() ?? 0;
        final sinirsiz = sinirsizKota(kota);
        final oran = sinirsiz ? 0.0 : (kul / kota).clamp(0.0, 1.0);
        return Kutu(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(Uyg.ad.isEmpty ? Uyg.adres : Uyg.ad, boyut: 52, tohum: Uyg.adres),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Uyg.ad.isEmpty ? Uyg.adres : Uyg.ad, style: gosterim(17, agirlik: FontWeight.w600)),
                        Text(Uyg.adres, style: TextStyle(color: r.silik, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Depolama',
                    style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(sinirsiz ? '${boyutYaz(kul)} · Sınırsız' : '${boyutYaz(kul)} / ${boyutYaz(kota)}', style: TextStyle(color: r.silik, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: sinirsiz ? 0 : oran, minHeight: 8, backgroundColor: r.ic, color: oran >= .9 ? Marka.gul : r.birincil),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bildirimler() {
    final r = context.r;
    if (Push.destekli) {
      final p = _push;
      final acik = p?['available'] == true;
      final cihaz = (p?['devices'] as num?)?.toInt() ?? 0;
      return Kutu(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              p == null
                  ? 'Bildirim durumu alınıyor…'
                  : !acik
                  ? 'Uygulama bildirimleri bu sunucuda kapalı.'
                  : cihaz > 0
                  ? 'Bildirimler açık · $cihaz cihaz kayıtlı'
                  : 'Bu cihaz henüz kayıtlı değil.',
              style: TextStyle(color: r.soluk),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: !acik
                      ? null
                      : () async {
                          final ok = await Push.kaydet(Uyg.api, yol: Uyg.pushYolu, konu: Uyg.pushKonu);
                          bildir(
                            ok ? 'Bildirimler etkinleştirildi' : 'Bildirim izni verilmedi',
                            mesaj: ok ? null : 'Sistem Ayarları > Bildirimler bölümünden BogaMail\'e izin verin.',
                            tur: ok ? MesajTur.basari : MesajTur.uyari,
                          );
                          await _bildirimDurumu();
                        },
                  icon: const Icon(Simge.hatirlatma),
                  label: const Text('Bildirimleri etkinleştir'),
                ),
                OutlinedButton.icon(
                  onPressed: !acik || cihaz == 0 ? null : () => islem(Posta.pushTest, tamam: 'Test bildirimi gönderildi'),
                  icon: const Icon(Simge.gonder),
                  label: const Text('Test bildirimi gönder'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (Bildirim.android) {
      return Kutu(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_izin)
              ListTile(
                leading: const Icon(Simge.bildirimKapali, color: Marka.kehribar),
                title: const Text('Bildirim izni kapalı'),
                subtitle: const Text('Yeni e-postalardan haberdar olmak için izin verin.'),
                trailing: TextButton(
                  onPressed: () async {
                    await Bildirim.izinIste();
                    await _bildirimDurumu();
                  },
                  child: const Text('İzin ver'),
                ),
              ),
            SwitchListTile.adaptive(
              value: _arkaPlan,
              onChanged: (v) async {
                await Bildirim.arkaPlanAyarla(v);
                setState(() => _arkaPlan = v);
              },
              title: const Text('Arka planda yeni posta denetimi'),
              subtitle: const Text(
                'Uygulama kapalıyken Gelen Kutusu yaklaşık 15 dakikada bir denetlenir (Android en kısa bu aralığa izin verir; pil tasarrufu modunda gecikebilir).',
              ),
            ),
            ListTile(
              leading: const Icon(Simge.bildirimDolu),
              title: const Text('Test bildirimi göster'),
              onTap: () => Bildirim.goster(iletiId: '', baslik: 'BogaMail', metin: 'Bildirimler bu cihazda çalışıyor.'),
            ),
          ],
        ),
      );
    }
    if (Bildirim.windows) {
      return Kutu(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('BogaMail açıkken pencere arka plandaysa yeni e-postalar için Windows bildirimi gösterilir.', style: TextStyle(color: r.soluk)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => Bildirim.goster(iletiId: '', baslik: 'BogaMail', metin: 'Bildirimler bu bilgisayarda çalışıyor.'),
                icon: const Icon(Simge.bildirimDolu),
                label: const Text('Test bildirimi göster'),
              ),
            ),
          ],
        ),
      );
    }
    return Kutu(
      child: Text('Bu platformda bildirim desteklenmiyor.', style: TextStyle(color: r.soluk)),
    );
  }

  Widget _tatilBolumu() {
    final r = context.r;
    final izinli = _a!.ozellik('autoresponder');
    String tarih(String? s) {
      final t = DateTime.tryParse(s ?? '');
      return t == null ? 'Seçilmedi' : DateFormat('d MMMM y', 'tr_TR').format(t);
    }

    return Kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _tatil,
            onChanged: !izinli
                ? null
                : (v) => setState(() {
                    _tatil = v;
                    _tatilKirli = true;
                  }),
            title: const Text('Otomatik yanıt (izin/tatil)'),
            subtitle: Text(izinli ? 'Size yazan herkese bu yanıt gönderilir.' : 'Paketiniz otomatik yanıta izin vermiyor.'),
          ),
          if (izinli) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _tatilKonu,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Konu', hintText: 'Örn. İzindeyim', counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tatilMetin,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Yanıt metni', alignLabelWithHint: true),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _tarihSec(true),
                    icon: const Icon(Simge.etkinlik, size: 18),
                    label: Text('Başlangıç: ${tarih(_tatilBas)}', overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _tarihSec(false),
                    icon: const Icon(Simge.etkinlikOnay, size: 18),
                    label: Text('Bitiş: ${tarih(_tatilBit)}', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            if (_tatilBas != null || _tatilBit != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _tatilBas = null;
                    _tatilBit = null;
                    _tatilKirli = true;
                  }),
                  child: const Text('Tarihleri temizle'),
                ),
              ),
            Text('Tarih seçmezseniz otomatik yanıt siz kapatana kadar açık kalır.', style: TextStyle(color: r.silik, fontSize: 12.5)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _tatilKirli && !_kaydediliyor ? _tatilKaydet : null, child: const Text('Kaydet')),
            ),
          ],
        ],
      ),
    );
  }
}
