import 'dart:async';
import 'dart:math';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';

import '../ortak/esitleme.dart';
import '../ortak/iskelet.dart';
import '../ortak/liste_filtresi.dart';
import '../ortak/secimler.dart';
import '../ortak/surukle.dart';
import '../veri/bildirim.dart';
import '../veri/durum.dart';
import '../veri/hesap_servisi.dart';
import '../veri/modeller.dart';
import '../veri/onbellek.dart';
import '../veri/onyukleme.dart';
import '../veri/posta_servisi.dart';
import '../veri/yardimci.dart';
import 'ileti_satiri.dart';

/// Aramanın sınırlandığı alan (sunucuda `in=`).
enum AramaAlani {
  hepsi('Tümü', null),
  kimden('Kimden', 'from'),
  kime('Kime', 'to'),
  konu('Konu', 'subject');

  const AramaAlani(this.ad, this.deger);
  final String ad;
  final String? deger;
}

/// Bir konumun (klasör / görünüm / etiket) ileti listesi: sayfalama, süzgeçler, arama, çoklu seçim, kaydırma eylemleri.
class IletiListesi extends StatefulWidget {
  const IletiListesi({
    super.key,
    required this.konum,
    required this.ac,
    this.seciliId,
    this.fab,
    this.kaldirildi,
    this.aramaSabit = false,
    this.klasorler,
    this.klasorRozeti = 0,
  });
  final Konum konum;
  final ValueChanged<IletiOzet> ac;
  final String? seciliId;
  final Widget? fab;

  /// Arama sekmesi: arama kutusu hep açık, sonuçlar tüm klasörlerden.
  final bool aramaSabit;

  /// Telefonda Posta sekmesi: başlığın solunda klasör değiştirici.
  final VoidCallback? klasorler;
  final int klasorRozeti;

  /// Listeden kaldırılan iletiler (okuyucu bölmesi kapanabilsin).
  final ValueChanged<Set<String>>? kaldirildi;

  @override
  State<IletiListesi> createState() => IletiListesiState();
}

class IletiListesiState extends State<IletiListesi> {
  final _kaydirma = ScrollController(keepScrollOffset: false);
  final _aramaMetni = TextEditingController();
  final _aramaOdak = FocusNode();
  List<IletiOzet> _ogeler = [];
  int _toplam = 0;
  bool _yukleniyor = true;
  bool _dahaYukleniyor = false;
  String? _hata;
  ListeFiltresi _filtre = ListeFiltresi.tumu;
  bool _aramaAcik = false;
  String _arama = '';
  bool _tumKlasorler = false;
  AramaAlani _alan = AramaAlani.hepsi;
  DateTimeRange? _tarih;
  final _secim = <String>{};
  int _istek = 0;
  List<KayitliArama> _kayitli = [];

  /// Sıralama oturum boyunca tüm listelerde korunur (web gibi).
  static Siralama _sonSiralama = Siralama.yeni;
  Siralama _siralama = _sonSiralama;

  int get _boyut => PostaDurum.ben.ayarlar?.sayfaBoyutu ?? 50;
  Klasor? get _klasor => widget.konum.tur == KonumTur.klasor ? PostaDurum.ben.klasor(widget.konum.id) : null;
  bool get _secimModu => _secim.isNotEmpty;

  /// Masaüstü (geniş pencere, fare): web gibi tıklama açar, Ctrl/Cmd+tıklama seçer, Shift+tıklama aralık seçer,
  /// başlıkta "Sayfadaki tümünü seç" kutusu ve kenar menüsüne sürükleme. Telefonda uzun basma seçimi korunur.
  bool get _masaustu => masaustuPlatformu && context.genis && widget.konum.tur != KonumTur.birlesik;

  /// Shift+tıklama aralığının başlangıcı (web anchor).
  String? _capa;

  /// Seçimi değiştirir; [aralik]: çapadan bu iletiye kadar olanları ekler (web toggle(id, shift)).
  void _secDegistir(String id, {bool aralik = false}) {
    setState(() {
      if (aralik && _capa != null) {
        final a = _ogeler.indexWhere((m) => m.id == _capa);
        final b = _ogeler.indexWhere((m) => m.id == id);
        if (a >= 0 && b >= 0) {
          for (var i = min(a, b); i <= max(a, b); i++) {
            _secim.add(_ogeler[i].id);
          }
          return;
        }
      }
      _secim.contains(id) ? _secim.remove(id) : _secim.add(id);
      _capa = id;
    });
  }

  bool get _hepsiSecili => _ogeler.isNotEmpty && _ogeler.every((m) => _secim.contains(m.id));

  void _hepsiniSecDegistir() => setState(() => _hepsiSecili ? _secim.clear() : _secim.addAll(_ogeler.map((m) => m.id)));

  /// Sürüklenen iletiler kenar menüsünde bir klasöre (taşı) ya da etikete (etiketle) bırakıldı.
  Future<void> _birak(List<String> idler, Konum hedef) async {
    final d = PostaDurum.ben;
    switch (hedef.tur) {
      case KonumTur.klasor:
        final k = d.klasor(hedef.id);
        if (k == null || k.id == _klasor?.id) return;
        await _toplu(idler, 'move', '${k.gorunenAd} klasörüne taşındı', klasorId: k.id);
      case KonumTur.etiket:
        final e = d.etiket(hedef.id);
        if (e == null) return;
        await _toplu(idler, 'label', '"${e.ad}" etiketi eklendi', etiketId: e.id, kaldir: false);
      case KonumTur.gorunum || KonumTur.birlesik:
        return;
    }
  }

  IletiSurukleme? _surukleme(IletiOzet m) {
    if (!_masaustu) return null;
    final idler = _secim.contains(m.id) ? _ogeler.where((x) => _secim.contains(x.id)).map((x) => x.id).toList() : [m.id];
    return IletiSurukleme(idler, kaynak: widget.konum, birak: (h) => _birak(idler, h));
  }

  /// Arama sekmesinde henüz bir şey aranmadı: liste yerine ipuçları gösterilir.
  bool get _aramaBekliyor => widget.aramaSabit && _arama.isEmpty && _tarih == null;

  @override
  void initState() {
    super.initState();
    _kaydirma.addListener(_kaydi);
    PostaDurum.ben.surum.addListener(_canli);
    PostaDurum.ben.addListener(_durumDegisti);
    _yerelAbone = PostaDurum.ben.yerelDegisiklikler.listen(_yerelDegisti);
    if (widget.aramaSabit) {
      _aramaAcik = true;
      _tumKlasorler = true;
      _kayitlilariYukle();
    }
    _yukle();
  }

  @override
  void didUpdateWidget(IletiListesi oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.konum != widget.konum) {
      _secim.clear();
      _filtre = ListeFiltresi.tumu;
      if (_aramaAcik && widget.konum.tur != KonumTur.klasor) _tumKlasorler = true;
      _ogeler = [];
      _yukle();
    }
  }

  @override
  void dispose() {
    PostaDurum.ben.surum.removeListener(_canli);
    PostaDurum.ben.removeListener(_durumDegisti);
    _yerelAbone?.cancel();
    _onyuklemeGecikme?.cancel();
    _kaydirma.dispose();
    _aramaMetni.dispose();
    _aramaOdak.dispose();
    super.dispose();
  }

  /// Klasör sayıları değişti: başlıktaki okunmamış sayısı tazelenir.
  void _durumDegisti() {
    if (mounted) setState(() {});
  }

  void _canli() {
    if (!_yukleniyor && !_dahaYukleniyor && !_aramaBekliyor) _yukle(sessiz: true);
  }

  StreamSubscription<(String, Map<String, dynamic>)>? _yerelAbone;
  Timer? _onyuklemeGecikme;

  /// Uygulamanın kendi değişikliği (okundu, yıldız...): satır yerinde güncellenir, liste yeniden indirilmez.
  /// [id]'den [yon] kadar ötedeki ileti (J/K gezinmesi); yoksa null.
  IletiOzet? komsu(String id, int yon) {
    final i = _ogeler.indexWhere((m) => m.id == id);
    final j = i + yon;
    if (i < 0 || j < 0 || j >= _ogeler.length) return null;
    return _ogeler[j];
  }

  void _yerelDegisti((String, Map<String, dynamic>) d) {
    final m = _ogeler.where((m) => m.id == d.$1).firstOrNull;
    if (m == null || !mounted) return;
    setState(() {
      final v = d.$2;
      if (v['seen'] is bool) m.okundu = v['seen'] as bool;
      if (v['flagged'] is bool) m.yildizli = v['flagged'] as bool;
      if (v['important'] is bool) m.onemli = v['important'] as bool;
    });
  }

  void _kaydi() {
    // Sona yaklaşmadan sonraki sayfa istenir (kaydırma beklemeye düşmesin).
    if (_kaydirma.position.extentAfter < 1500 && !_dahaYukleniyor && !_yukleniyor && _ogeler.length < _toplam) _dahaFazla();
    // Kaydırma durunca görünen bölgedeki iletilerin gövdeleri önyüklenir (eski kuyruk düşer).
    _onyuklemeGecikme?.cancel();
    _onyuklemeGecikme = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || !_kaydirma.hasClients) return;
      Onyukleme.ben.iste(_ogeler, bas: (_kaydirma.offset / 76).floor());
    });
  }

  /// Önbelleğe alınan (süzgeçsiz, aramasız) görünümün anahtarı.
  String? get _onbellekAnahtari {
    if (_filtre.sunucuDegeri != null || _arama.trim().isNotEmpty || _tarih != null || widget.aramaSabit || _siralama != Siralama.yeni) return null;
    final k = widget.konum;
    return switch (k.tur) {
      KonumTur.klasor => Posta.listeAnahtari(klasorId: k.id),
      KonumTur.gorunum => Posta.listeAnahtari(gorunum: k.id),
      KonumTur.etiket => Posta.listeAnahtari(gorunum: 'label', etiketId: k.id),
      KonumTur.birlesik => null,
    };
  }

  static final _gun = DateFormat('yyyy-MM-dd');

  Future<Sayfa> _getir(int sayfa, int boyut) {
    final k = widget.konum;
    final arama = _arama.trim().isEmpty ? null : _arama.trim();
    final filtre = _filtre.sunucuDegeri;
    final bas = _tarih == null ? null : _gun.format(_tarih!.start);
    final bit = _tarih == null ? null : _gun.format(_tarih!.end);
    if ((arama != null || _tarih != null) && (_tumKlasorler || k.tur != KonumTur.klasor)) {
      return Posta.liste(
        gorunum: 'all',
        arama: arama,
        alan: _alan.deger,
        sayfa: sayfa,
        boyut: boyut,
        filtre: filtre,
        baslangic: bas,
        bitis: bit,
        siralama: _siralama,
      );
    }
    return switch (k.tur) {
      KonumTur.klasor => Posta.liste(
        klasorId: k.id,
        sayfa: sayfa,
        boyut: boyut,
        filtre: filtre,
        arama: arama,
        alan: _alan.deger,
        baslangic: bas,
        bitis: bit,
        siralama: _siralama,
      ),
      KonumTur.gorunum => Posta.liste(gorunum: k.id, sayfa: sayfa, boyut: boyut, filtre: filtre, siralama: _siralama),
      KonumTur.etiket => Posta.liste(gorunum: 'label', etiketId: k.id, sayfa: sayfa, boyut: boyut, filtre: filtre, siralama: _siralama),
      KonumTur.birlesik => Posta.liste(sayfa: sayfa, boyut: boyut, filtre: filtre, siralama: _siralama),
    };
  }

  /// İlk sayfayı (sessizde: o ana kadar yüklenen kadarını) yeniden alır.
  Future<void> _yukle({bool sessiz = false}) async {
    final no = ++_istek;
    if (_aramaBekliyor) {
      setState(() {
        _ogeler = [];
        _toplam = 0;
        _yukleniyor = false;
        _hata = null;
      });
      return;
    }
    if (!sessiz) {
      setState(() {
        _yukleniyor = true;
        _hata = null;
      });
      // Önce önbellek: liste anında görünür, ağ yanıtı gelince sessizce güncellenir.
      final a = _onbellekAnahtari;
      if (a != null) {
        final sw = Stopwatch()..start();
        final o = await Posta.listeOnbellek(a).catchError((_) => null);
        if (!mounted || no != _istek) return;
        if (o != null && _yukleniyor) {
          zamanLogu('liste (önbellek)', sw);
          setState(() {
            _ogeler = o.ogeler;
            _toplam = o.toplam;
            _yukleniyor = false;
          });
          sessiz = true;
        }
      }
    }
    final sw = Stopwatch()..start();
    try {
      final boyut = sessiz ? min(200, max(_ogeler.length, _boyut)) : _boyut;
      final s = await _getir(1, boyut);
      if (!mounted || no != _istek) return;
      zamanLogu('liste (ağ)', sw);
      setState(() {
        _ogeler = s.ogeler;
        _toplam = s.toplam;
        _yukleniyor = false;
        _hata = null;
        _secim.removeWhere((id) => !_ogeler.any((m) => m.id == id));
      });
      Onyukleme.ben.iste(_ogeler, bas: _kaydirma.hasClients ? (_kaydirma.offset / 76).floor() : 0);
      if (_klasor?.rol == 'inbox' && _ogeler.isNotEmpty) {
        unawaited(Bildirim.goruldu(_ogeler.map((m) => m.tarih).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a)));
      }
    } catch (e) {
      if (!mounted || no != _istek) return;
      setState(() {
        _yukleniyor = false;
        if (!sessiz || _ogeler.isEmpty) _hata = hataMetni(e);
      });
    }
  }

  Future<void> _dahaFazla() async {
    final no = _istek;
    setState(() => _dahaYukleniyor = true);
    try {
      final s = await _getir(_ogeler.length ~/ _boyut + 1, _boyut);
      if (!mounted || no != _istek) return;
      final var_ = _ogeler.map((m) => m.id).toSet();
      setState(() {
        _ogeler = [..._ogeler, ...s.ogeler.where((m) => !var_.contains(m.id))];
        _toplam = s.toplam;
      });
    } catch (e) {
      if (mounted) bildir('Daha fazla ileti yüklenemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _dahaYukleniyor = false);
    }
  }

  Future<void> yenile() async {
    PostaDurum.ben.sayilariYenile(listeler: false);
    await _yukle(sessiz: true);
  }

  void _filtreSec(ListeFiltresi f) {
    if (f == _filtre) return;
    HapticFeedback.selectionClick();
    setState(() {
      _filtre = f;
      _secim.clear();
    });
    _yukle();
  }

  // ---- eylemler ----

  void _cikar(Iterable<String> idler) {
    final s = idler.toSet();
    setState(() {
      _ogeler.removeWhere((m) => s.contains(m.id));
      _toplam = max(0, _toplam - s.length);
      _secim.removeAll(s);
    });
    widget.kaldirildi?.call(s);
  }

  /// Toplu eylem. [kaldir]: iletiler bu listeden çıkar.
  Future<void> _toplu(List<String> idler, String eylem, String tamam, {String? klasorId, String? etiketId, bool kaldir = true}) async {
    if (idler.isEmpty) return;
    final onceki = List<IletiOzet>.from(_ogeler);
    if (kaldir) _cikar(idler);
    try {
      await Posta.toplu(idler, eylem, klasorId: klasorId, etiketId: etiketId);
      if (!kaldir) {
        setState(() {
          for (final m in _ogeler.where((m) => idler.contains(m.id))) {
            switch (eylem) {
              case 'read':
                m.okundu = true;
              case 'unread':
                m.okundu = false;
              case 'flag':
                m.yildizli = true;
              case 'unflag':
                m.yildizli = false;
              case 'important':
                m.onemli = true;
              case 'unimportant':
                m.onemli = false;
              case 'label' when etiketId != null && !m.etiketler.contains(etiketId):
                m.etiketler = [...m.etiketler, etiketId];
            }
          }
          _secim.clear();
        });
      }
      bildir(tamam, tur: MesajTur.basari);
    } catch (e) {
      if (mounted && kaldir) setState(() => _ogeler = onceki);
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
    PostaDurum.ben.sayilariYenile(listeler: false);
  }

  bool get _copte => _klasor?.rol == 'trash';

  Future<void> _sil(List<String> idler) async {
    if (_copte &&
        !await onayla(
          context,
          '${idler.length == 1 ? 'İleti' : '${idler.length} ileti'} kalıcı olarak silinsin mi?',
          mesaj: 'Bu işlem geri alınamaz.',
          evet: 'Kalıcı sil',
          tehlikeli: true,
        )) {
      return;
    }
    await _toplu(idler, 'delete', _copte ? 'Kalıcı olarak silindi' : 'Çöp Kutusu\'na taşındı');
  }

  Future<void> _okunduDegistir(IletiOzet m) async {
    final yeni = !m.okundu;
    setState(() => m.okundu = yeni);
    try {
      await Posta.guncelle(m.id, {'seen': yeni});
      PostaDurum.ben.sayilariYenile(listeler: false);
    } catch (e) {
      if (mounted) setState(() => m.okundu = !yeni);
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _yildizDegistir(IletiOzet m) async {
    final yeni = !m.yildizli;
    setState(() => m.yildizli = yeni);
    try {
      await Posta.guncelle(m.id, {'flagged': yeni});
    } catch (e) {
      if (mounted) setState(() => m.yildizli = !yeni);
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _tasi(List<String> idler) async {
    final k = await klasorSec(context, haricId: _klasor?.id);
    if (k == null) return;
    await _toplu(idler, 'move', '${k.gorunenAd} klasörüne taşındı', klasorId: k.id);
  }

  Future<void> _klasorOkundu() async {
    final k = _klasor;
    try {
      final n = k != null ? await Posta.klasorOkundu(k.id) : await Posta.toplu(_ogeler.where((m) => !m.okundu).map((m) => m.id).toList(), 'read');
      bildir(n == 0 ? 'Okunmamış ileti yok' : '$n ileti okundu işaretlendi', tur: MesajTur.basari);
      PostaDurum.ben.sayilariYenile();
    } catch (e) {
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _hepsiOkundu() async {
    if (!await onayla(
      context,
      'Tüm klasörler okundu işaretlensin mi?',
      mesaj: 'Posta kutunuzdaki bütün okunmamış iletiler okundu olarak işaretlenir.',
      evet: 'Tümünü okundu yap',
    )) {
      return;
    }
    try {
      final n = await Posta.hepsiOkundu();
      bildir(n == 0 ? 'Okunmamış ileti yok' : '$n ileti okundu işaretlendi', tur: MesajTur.basari);
      PostaDurum.ben.sayilariYenile();
    } catch (e) {
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _bosalt() async {
    final k = _klasor;
    if (k == null) return;
    if (!await onayla(
      context,
      '${k.gorunenAd} boşaltılsın mı?',
      mesaj: 'Klasördeki tüm iletiler kalıcı olarak silinir. Bu işlem geri alınamaz.',
      evet: 'Boşalt',
      tehlikeli: true,
    )) {
      return;
    }
    try {
      final n = await Posta.klasorBosalt(k.id);
      _cikar(_ogeler.map((m) => m.id).toList());
      bildir('$n ileti kalıcı olarak silindi', tur: MesajTur.basari);
      PostaDurum.ben.sayilariYenile();
    } catch (e) {
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _etiketle(List<String> idler) async {
    final s = await etiketSec(context, const {});
    if (s == null || s.ekle.isEmpty || !mounted) return;
    for (final e in s.ekle) {
      await _toplu(idler, 'label', 'Etiket eklendi', etiketId: e, kaldir: false);
    }
  }

  // ---- arama ----

  void _aramaAc() {
    setState(() {
      _aramaAcik = true;
      _tumKlasorler = widget.konum.tur != KonumTur.klasor;
    });
    _aramaOdak.requestFocus();
  }

  void _aramaKapat() {
    final vardi = _arama.isNotEmpty || _tarih != null;
    setState(() {
      if (!widget.aramaSabit) _aramaAcik = false;
      _arama = '';
      _tarih = null;
      _alan = AramaAlani.hepsi;
      _aramaMetni.clear();
    });
    if (vardi || widget.aramaSabit) _yukle();
  }

  void _ara(String q) {
    setState(() => _arama = q.trim());
    _yukle();
  }

  Future<void> _kayitlilariYukle() async {
    try {
      final l = await Hesap.kayitliAramalar();
      if (mounted) setState(() => _kayitli = l);
    } catch (_) {}
  }

  Future<void> _aramayiKaydet() async {
    final q = _arama.trim();
    if (q.isEmpty) return;
    final ad = await metinSor(context, 'Aramayı kaydet', ilk: q, ipucu: 'Kayıt adı', tamam: 'Kaydet');
    if (ad == null || ad.trim().isEmpty) return;
    await islem(() => Hesap.aramaKaydet(ad, q), tamam: 'Arama kaydedildi');
    await _kayitlilariYukle();
  }

  void _kayitliAc(KayitliArama k) {
    _aramaMetni.text = k.sorgu;
    setState(() => _alan = AramaAlani.hepsi);
    _ara(k.sorgu);
  }

  Future<void> _tarihSec() async {
    final simdi = DateTime.now();
    final t = await showDateRangePicker(
      context: context,
      firstDate: DateTime(simdi.year - 20),
      lastDate: simdi,
      initialDateRange: _tarih,
      helpText: 'Tarih aralığı',
      saveText: 'Uygula',
    );
    if (t == null) return;
    setState(() => _tarih = t);
    _yukle();
  }

  Future<void> _islecYardimi() async {
    List<AramaIsleci> l;
    try {
      l = await Posta.aramaIslecleri();
    } catch (e) {
      bildir('Arama ipuçları alınamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
      return;
    }
    if (!mounted) return;
    final sec = await showModalBottomSheet<AramaIsleci>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text('Arama işleçleri', style: gosterim(17, agirlik: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Birleştirebilir, "tırnak" ile tam ifade arayabilir, -işleç ile hariç tutabilirsiniz.',
                  style: TextStyle(color: c.r.silik, fontSize: 12.5),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final i in l)
                      ListTile(
                        title: Text(i.ornek, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
                        subtitle: Text(i.ipucu),
                        onTap: () => Navigator.pop(c, i),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (sec == null) return;
    final t = _aramaMetni.text.trim();
    _aramaMetni.text = t.isEmpty ? sec.anahtar : '$t ${sec.anahtar}';
    _aramaMetni.selection = TextSelection.collapsed(offset: _aramaMetni.text.length);
    _aramaOdak.requestFocus();
  }

  // ---- arayüz ----

  int get _okunmamisSayisi {
    final d = PostaDurum.ben;
    return switch (widget.konum.tur) {
      KonumTur.klasor => _klasor?.okunmamis ?? 0,
      KonumTur.etiket => d.etiket(widget.konum.id)?.okunmamis ?? 0,
      KonumTur.gorunum => widget.konum.id == 'unread' ? _toplam : 0,
      KonumTur.birlesik => 0,
    };
  }

  /// Okunmamış süzgecinin anlamsız olduğu klasörler.
  bool get _filtreGizli =>
      widget.aramaSabit && _aramaBekliyor || const {'drafts', 'templates'}.contains(_klasor?.rol) || widget.konum == const Konum.gorunum('unread');

  PreferredSizeWidget _secimCubugu() {
    final secilen = _ogeler.where((m) => _secim.contains(m.id)).toList();
    final hepsi = secilen.length == _ogeler.length;
    return AppBar(
      backgroundColor: context.r.vurguYumusak,
      leading: IconButton(icon: const Icon(Simge.kapat), tooltip: 'Seçimi kaldır', onPressed: () => setState(_secim.clear)),
      title: Text('${_secim.length} ileti seçildi', style: gosterim(18, agirlik: FontWeight.w600)),
      actions: [
        TextButton.icon(
          onPressed: _hepsiniSecDegistir,
          icon: Icon(hepsi ? Simge.secimiKaldir : Simge.tumunuSec, size: 20),
          label: Text(hepsi ? 'Hiçbiri' : 'Tümünü seç'),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  /// Çoklu seçimde alttaki etiketli eylem çubuğu.
  Widget _secimEylemleri() {
    final r = context.r;
    final secilen = _ogeler.where((m) => _secim.contains(m.id)).toList();
    final hepsiOkundu = secilen.every((m) => m.okundu);
    final hepsiYildizli = secilen.every((m) => m.yildizli);
    final hepsiOnemli = secilen.every((m) => m.onemli);
    final idler = _secim.toList();
    final rol = _klasor?.rol;
    Widget dugme(IconData i, String t, VoidCallback f, {Color? renk}) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: f,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(i, size: 22, color: renk ?? r.metin),
              const SizedBox(height: 3),
              Text(
                t,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: renk ?? r.metin),
              ),
            ],
          ),
        ),
      ),
    );
    return Material(
      color: r.kart,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: r.kenar)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                dugme(
                  hepsiOkundu ? Simge.okunmadiYap : Simge.okunduYap,
                  hepsiOkundu ? 'Okunmadı' : 'Okundu',
                  () => _toplu(idler, hepsiOkundu ? 'unread' : 'read', hepsiOkundu ? 'Okunmadı işaretlendi' : 'Okundu işaretlendi', kaldir: false),
                ),
                if (rol != 'archive') dugme(Simge.arsiv, 'Arşivle', () => _toplu(idler, 'archive', 'Arşivlendi')),
                dugme(Simge.tasi, 'Taşı', () => _tasi(idler)),
                dugme(Simge.sil, _copte ? 'Kalıcı sil' : 'Sil', () => _sil(idler), renk: Marka.gul),
                Expanded(
                  child: PopupMenuButton<String>(
                    tooltip: 'Diğer işlemler',
                    onSelected: (v) => switch (v) {
                      'yildiz' => _toplu(idler, hepsiYildizli ? 'unflag' : 'flag', hepsiYildizli ? 'Yıldız kaldırıldı' : 'Yıldızlandı', kaldir: false),
                      'onemli' => _toplu(
                        idler,
                        hepsiOnemli ? 'unimportant' : 'important',
                        hepsiOnemli ? 'Önemli işareti kaldırıldı' : 'Önemli olarak işaretlendi',
                        kaldir: false,
                      ),
                      'etiket' => _etiketle(idler),
                      'spam' => _toplu(idler, 'spam', 'Gereksiz olarak işaretlendi'),
                      'spamDegil' => _toplu(idler, 'notspam', 'Gelen Kutusu\'na taşındı'),
                      _ => null,
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'yildiz',
                        child: ListTile(
                          leading: Icon(hepsiYildizli ? Simge.yildizDolu : Simge.yildiz),
                          title: Text(hepsiYildizli ? 'Yıldızı kaldır' : 'Yıldızla'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'onemli',
                        child: ListTile(leading: const Icon(Simge.onemli), title: Text(hepsiOnemli ? 'Önemli değil' : 'Önemli olarak işaretle')),
                      ),
                      const PopupMenuItem(
                        value: 'etiket',
                        child: ListTile(leading: Icon(Simge.etiket), title: Text('Etiket ekle…')),
                      ),
                      if (rol == 'junk')
                        const PopupMenuItem(
                          value: 'spamDegil',
                          child: ListTile(leading: Icon(Simge.begen), title: Text('Gereksiz değil')),
                        )
                      else
                        const PopupMenuItem(
                          value: 'spam',
                          child: ListTile(leading: Icon(Simge.bildir), title: Text('Gereksiz (spam)')),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Simge.dahaFazla, size: 22, color: r.metin),
                          const SizedBox(height: 3),
                          Text(
                            'Diğer',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: r.metin),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _aramaCubugu() {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: widget.aramaSabit ? null : IconButton(icon: const Icon(Simge.geri), tooltip: 'Aramayı kapat', onPressed: _aramaKapat),
      titleSpacing: widget.aramaSabit ? 16 : 0,
      title: TextField(
        controller: _aramaMetni,
        focusNode: _aramaOdak,
        textInputAction: TextInputAction.search,
        onSubmitted: _ara,
        decoration: InputDecoration(
          hintText: 'Postalarda ara (ad, adres, konu, metin)',
          isDense: true,
          prefixIcon: const Icon(Simge.ara, size: 20),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          suffixIcon: _aramaMetni.text.isEmpty && _arama.isEmpty
              ? null
              : IconButton(icon: const Icon(Simge.temizleX, size: 20), tooltip: 'Aramayı temizle', onPressed: _aramaKapat),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        if (_arama.isNotEmpty && _alan == AramaAlani.hepsi)
          IconButton(icon: const Icon(Simge.aramaKaydet), tooltip: 'Aramayı kaydet', onPressed: _aramayiKaydet),
        IconButton(icon: const Icon(Simge.aramaIslecleri), tooltip: 'Arama işleçleri', onPressed: _islecYardimi),
        const SizedBox(width: 4),
      ],
    );
  }

  PreferredSizeWidget _ustCubuk() {
    if (_secimModu) return _secimCubugu();
    if (_aramaAcik) return _aramaCubugu();
    final r = context.r;
    final durum = PostaDurum.ben;
    final k = _klasor;
    final okunmamis = _okunmamisSayisi;
    return AppBar(
      leading: widget.klasorler == null
          ? null
          : IconButton(
              key: const ValueKey('klasor-degistir'),
              tooltip: 'Klasörler ve etiketler',
              onPressed: widget.klasorler,
              icon: Badge(
                isLabelVisible: widget.klasorRozeti > 0,
                backgroundColor: r.vurgu,
                textColor: Colors.white,
                label: Text(widget.klasorRozeti > 999 ? '999+' : '${widget.klasorRozeti}'),
                child: const Icon(Simge.menu),
              ),
            ),
      titleSpacing: Navigator.of(context).canPop() || widget.klasorler != null ? 0 : 16,
      // Web: h-12 başlık — klasör adı (font-semibold) ve yanında toplam ileti sayısı (text-xs soluk).
      toolbarHeight: 48,
      shape: Border(bottom: BorderSide(color: r.kenar)),
      backgroundColor: r.kart,
      title: Row(
        children: [
          Flexible(
            child: Text(
              durum.baslik(widget.konum),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: r.metin),
            ),
          ),
          if (!_yukleniyor) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: okunmamis > 0 ? '${sayiYaz(okunmamis)} okunmamış' : '',
              child: Text(
                key: okunmamis > 0 ? const ValueKey('baslik-okunmamis') : null,
                sayiYaz(_toplam),
                style: TextStyle(fontSize: 12, color: r.silik, fontWeight: FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        ],
      ),
      actions: [
        // "Tüm hesaplar" kenar menüsünden / hesap menüsünden açılır (başlıkta ayrı simge yok).
        IconButton(icon: const Icon(Simge.ara), tooltip: 'Bu klasörde ara', onPressed: _aramaAc),
        PopupMenuButton<Siralama>(
          key: const ValueKey('sirala'),
          tooltip: 'Sırala',
          icon: Icon(Simge.sirala, color: _siralama == Siralama.yeni ? null : r.vurgu),
          onSelected: (v) {
            if (v == _siralama) return;
            setState(() => _siralama = _sonSiralama = v);
            _yukle();
          },
          itemBuilder: (_) => [
            const PopupMenuItem<Siralama>(enabled: false, height: 32, child: Text('Sıralama')),
            for (final v in Siralama.values) CheckedPopupMenuItem(value: v, checked: v == _siralama, child: Text(v.ad)),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: 'Liste seçenekleri',
          onSelected: (v) => switch (v) {
            'yenile' => _yukle(),
            'sec' => setState(() => _secim.addAll(_ogeler.map((m) => m.id))),
            'okundu' => _klasorOkundu(),
            'hepsi' => _hepsiOkundu(),
            'bosalt' => _bosalt(),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'yenile',
              child: ListTile(leading: Icon(Simge.yenile), title: Text('Yenile')),
            ),
            if (_ogeler.isNotEmpty)
              const PopupMenuItem(
                value: 'sec',
                child: ListTile(leading: Icon(Simge.kontrolListesi), title: Text('İleti seç')),
              ),
            const PopupMenuItem(
              value: 'okundu',
              child: ListTile(leading: Icon(Simge.hepsiOkundu), title: Text('Tümünü okundu işaretle')),
            ),
            const PopupMenuItem(
              value: 'hepsi',
              child: ListTile(leading: Icon(Simge.okunduYap), title: Text('Tüm klasörleri okundu işaretle')),
            ),
            if (k?.rol == 'trash' || k?.rol == 'junk')
              PopupMenuItem(
                value: 'bosalt',
                child: ListTile(
                  leading: const Icon(Simge.bosalt, color: Marka.gul),
                  title: Text('${k!.gorunenAd} boşalt'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Arama seçenekleri: kapsam (bu klasör / tüm klasörler), alan, tarih aralığı.
  Widget _aramaSecenekleri() {
    final r = context.r;
    final bicim = DateFormat('d MMM y', 'tr_TR');
    Widget cip(String t, bool secili, VoidCallback f, {IconData? ikon}) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(t),
        avatar: ikon == null ? null : Icon(ikon, size: 16),
        selected: secili,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selectedColor: r.vurgu,
        labelStyle: TextStyle(color: secili ? Colors.white : r.metin, fontWeight: FontWeight.w600, fontSize: 12.5),
        onSelected: (_) => f(),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (widget.konum.tur == KonumTur.klasor && !widget.aramaSabit) ...[
              cip('Bu klasörde', !_tumKlasorler, () {
                setState(() => _tumKlasorler = false);
                if (_arama.isNotEmpty) _yukle();
              }),
              cip('Tüm klasörlerde', _tumKlasorler, () {
                setState(() => _tumKlasorler = true);
                if (_arama.isNotEmpty) _yukle();
              }),
              Container(width: 1, height: 22, color: r.kenar, margin: const EdgeInsets.only(right: 6)),
            ],
            for (final a in AramaAlani.values)
              cip(a.ad, _alan == a, () {
                setState(() => _alan = a);
                if (_arama.isNotEmpty) _yukle();
              }),
            Container(width: 1, height: 22, color: r.kenar, margin: const EdgeInsets.only(right: 6)),
            cip(
              _tarih == null ? 'Tarih' : '${bicim.format(_tarih!.start)} – ${bicim.format(_tarih!.end)}',
              _tarih != null,
              _tarihSec,
              ikon: Simge.tarihAraligi,
            ),
            if (_tarih != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Tarihi kaldır',
                icon: const Icon(Simge.kapat, size: 18),
                onPressed: () {
                  setState(() => _tarih = null);
                  _yukle();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _ustAlan() {
    final r = context.r;
    final aramaVar = _arama.isNotEmpty || _tarih != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_aramaAcik) _aramaSecenekleri(),
        if (_masaustu && _ogeler.isNotEmpty)
          Container(
            height: 44,
            padding: const EdgeInsets.fromLTRB(2, 0, 8, 0),
            color: r.kart,
            child: Row(
              children: [
                Checkbox(
                  key: const ValueKey('hepsini-sec'),
                  value: _hepsiSecili ? true : (_secimModu ? null : false),
                  tristate: true,
                  semanticLabel: 'Sayfadaki tümünü seç',
                  onChanged: (_) => _hepsiniSecDegistir(),
                ),
                if (_secimModu)
                  Text(
                    '${_secim.length} seçili',
                    style: TextStyle(color: r.soluk, fontSize: 13, fontWeight: FontWeight.w600),
                  )
                else if (!_filtreGizli)
                  Expanded(
                    child: FiltreCubugu(
                      secili: _filtre,
                      degisti: _filtreSec,
                      sayilar: {if (!aramaVar && _okunmamisSayisi > 0) ListeFiltresi.okunmamis: _okunmamisSayisi},
                    ),
                  ),
              ],
            ),
          )
        else if (!_filtreGizli && !_secimModu)
          Container(
            height: 44,
            color: r.kart,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: FiltreCubugu(
              secili: _filtre,
              degisti: _filtreSec,
              sayilar: {if (!aramaVar && _okunmamisSayisi > 0) ListeFiltresi.okunmamis: _okunmamisSayisi},
            ),
          ),
        if (aramaVar && !_yukleniyor)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              _arama.isNotEmpty ? '"$_arama" için ${sayiYaz(_toplam)} sonuç' : '${sayiYaz(_toplam)} sonuç',
              style: TextStyle(color: r.silik, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        if (_filtre != ListeFiltresi.tumu && !_filtreGizli)
          FiltreBandi(filtre: _filtre, sonuc: _yukleniyor ? null : _toplam, temizle: () => _filtreSec(ListeFiltresi.tumu)),
        Divider(height: 1, color: r.kenar),
      ],
    );
  }

  String _bosMetin() {
    if (_arama.isNotEmpty || _tarih != null) return 'Aramanızla eşleşen ileti bulunamadı.\nFarklı sözcükler deneyin veya süzgeçleri kaldırın.';
    if (_filtre != ListeFiltresi.tumu) return _filtre.bosMetin;
    return switch (_klasor?.rol) {
      'inbox' => 'Gelen Kutunuz boş. Yeni postalar burada görünecek.',
      'drafts' => 'Kaydedilmiş taslak yok.',
      'sent' => 'Henüz gönderilmiş ileti yok.',
      'trash' => 'Çöp Kutusu boş.',
      'junk' => 'Gereksiz ileti yok.',
      'archive' => 'Arşiv boş.',
      'snoozed' => 'Ertelenmiş ileti yok.',
      'templates' => 'Kayıtlı şablon yok.',
      _ => widget.konum.tur == KonumTur.gorunum ? 'Bu görünümde ileti yok.' : 'Bu klasörde ileti yok.',
    };
  }

  IconData _bosSimge() {
    if (_arama.isNotEmpty || _tarih != null) return Simge.aramaYok;
    if (_filtre != ListeFiltresi.tumu) return _filtre.ikon;
    return switch (_klasor?.rol) {
      'inbox' => Simge.okunduYap,
      'trash' => Simge.sil,
      'drafts' => Simge.taslak,
      'sent' => Simge.gonder,
      _ => Simge.gelen,
    };
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (_aramaAcik && !widget.aramaSabit) const SingleActivator(LogicalKeyboardKey.escape): _aramaKapat,
        if (_secimModu) const SingleActivator(LogicalKeyboardKey.escape): () => setState(_secim.clear),
      },
      child: PopScope(
        canPop: !(_aramaAcik && !widget.aramaSabit) && !_secimModu,
        onPopInvokedWithResult: (cikti, _) {
          if (cikti) return;
          if (_secimModu) {
            setState(_secim.clear);
          } else if (_aramaAcik) {
            _aramaKapat();
          }
        },
        child: Scaffold(
          backgroundColor: context.r.kart,
          floatingActionButton: _secimModu ? null : widget.fab,
          appBar: _ustCubuk(),
          bottomNavigationBar: _secimModu ? _secimEylemleri() : null,
          body: Column(
            children: [
              // Telefonda (kenar menüsü kapalıyken) eşitleme sorunu liste başında görünür.
              if (!context.genis) const EsitlemeDurumu(serit: true),
              _ustAlan(),
              Expanded(child: _liste()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aramaIpuclari() {
    final r = context.r;
    Widget ipucu(String ornek, String aciklama) => ListTile(
      dense: true,
      leading: Icon(Simge.ipucu, color: r.vurgu, size: 20),
      title: Text(
        ornek,
        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
      ),
      subtitle: Text(aciklama),
      onTap: () {
        _aramaMetni.text = ornek;
        _ara(ornek);
      },
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 96),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: r.vurguYumusak, shape: BoxShape.circle),
            child: Icon(Simge.ara, size: 34, color: r.vurgu),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Tüm postalarınızda arayın',
          textAlign: TextAlign.center,
          style: gosterim(18, agirlik: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          'Gönderen, alıcı, konu veya ileti metninde geçen bir sözcük yazın.\nAlanı ve tarih aralığını yukarıdan seçebilirsiniz.',
          textAlign: TextAlign.center,
          style: TextStyle(color: r.soluk, fontSize: 13.5),
        ),
        if (_kayitli.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Baslik('Kayıtlı aramalar')),
          for (final k in _kayitli)
            ListTile(
              leading: Icon(Simge.yerImi, color: r.vurgu),
              title: Text(k.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(k.sorgu, style: const TextStyle(fontFamily: 'monospace')),
              onTap: () => _kayitliAc(k),
              trailing: IconButton(
                tooltip: 'Kaydı sil',
                icon: Icon(Simge.kapat, color: r.silik),
                onPressed: () async {
                  await islem(() => Hesap.kayitliAramaSil(k.id));
                  await _kayitlilariYukle();
                },
              ),
            ),
        ],
        const SizedBox(height: 16),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Baslik('Örnekler')),
        ipucu('has:attachment', 'Ek içeren iletiler'),
        ipucu('is:unread', 'Okunmamış iletiler'),
        ipucu('is:starred', 'Yıldızlı iletiler'),
        Center(
          child: TextButton.icon(onPressed: _islecYardimi, icon: const Icon(Simge.aramaIslecleri), label: const Text('Tüm arama işleçleri')),
        ),
      ],
    );
  }

  Widget _liste() {
    if (_aramaBekliyor) return _aramaIpuclari();
    if (_yukleniyor && _ogeler.isEmpty) return const ListeIskeleti();
    if (_hata != null && _ogeler.isEmpty) return Durum.hata(_hata!, tekrar: _yukle);
    if (_ogeler.isEmpty) {
      return RefreshIndicator(
        onRefresh: yenile,
        child: LayoutBuilder(
          builder: (c, k) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: k.maxHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: Durum.bos(_bosMetin(), ikon: _bosSimge())),
                  if (_filtre != ListeFiltresi.tumu)
                    OutlinedButton.icon(
                      onPressed: () => _filtreSec(ListeFiltresi.tumu),
                      icon: const Icon(Simge.suzgecYok, size: 18),
                      label: const Text('Tüm iletileri göster'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    // Tarih grupları (Bugün / Dün / Bu hafta …) satırların arasına başlık olarak girer.
    final girdiler = <Object>[];
    String? sonGrup;
    final simdi = DateTime.now();
    for (final m in _ogeler) {
      final g = m.tarih == null ? 'Tarihsiz' : tarihGrubu(m.tarih!, simdi);
      if (g != sonGrup) {
        girdiler.add(g);
        sonGrup = g;
      }
      girdiler.add(m);
    }
    final daha = _ogeler.length < _toplam;
    return RefreshIndicator(
      onRefresh: yenile,
      child: SlidableAutoCloseBehavior(
        child: ListView.builder(
          controller: _kaydirma,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: girdiler.length + (daha ? 1 : 0),
          itemBuilder: (c, i) {
            if (i >= girdiler.length) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator.adaptive()),
              );
            }
            final g = girdiler[i];
            if (g is String) {
              // Web: tarih grubu başlığı (text-xs font-semibold soluk, px-4 py-1.5, alt çizgi).
              return Container(
                decoration: BoxDecoration(
                  color: c.r.kart,
                  border: Border(bottom: BorderSide(color: c.r.kenar)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Semantics(
                  header: true,
                  child: Text(
                    g,
                    style: TextStyle(color: c.r.silik, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600),
                  ),
                ),
              );
            }
            final m = g as IletiOzet;
            return IletiSatiri(
              key: ValueKey(m.id),
              ileti: m,
              secili: _secim.contains(m.id),
              acik: widget.seciliId == m.id,
              secimModu: _secimModu,
              copte: _copte,
              arsivde: _klasor?.rol == 'archive',
              surukle: _surukleme(m),
              dokun: () {
                if (_masaustu) {
                  final k = HardwareKeyboard.instance;
                  if (k.isControlPressed || k.isMetaPressed) return _secDegistir(m.id);
                  if (k.isShiftPressed) return _secDegistir(m.id, aralik: true);
                }
                if (_secimModu && !_masaustu) {
                  _secDegistir(m.id);
                } else {
                  widget.ac(m);
                  if (!m.okundu && m.klasorRolu != 'drafts') setState(() => m.okundu = true);
                }
              },
              sec: () {
                HapticFeedback.selectionClick();
                _secDegistir(m.id, aralik: _masaustu && HardwareKeyboard.instance.isShiftPressed);
              },
              okundu: () => _okunduDegistir(m),
              yildiz: () => _yildizDegistir(m),
              arsivle: () => _toplu([m.id], 'archive', 'Arşivlendi'),
              sil: () => _sil([m.id]),
            );
          },
        ),
      ),
    );
  }
}
