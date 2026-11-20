import 'dart:async';
import 'dart:math';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../ortak/iskelet.dart';
import '../ortak/secimler.dart';
import '../veri/bildirim.dart';
import '../veri/durum.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/yardimci.dart';
import 'ileti_satiri.dart';

/// Bir konumun (klasör / görünüm / etiket) ileti listesi: sayfalama, arama, çoklu seçim, kaydırma eylemleri.
class IletiListesi extends StatefulWidget {
  const IletiListesi({super.key, required this.konum, required this.ac, this.seciliId, this.cekmece, this.fab, this.kaldirildi});
  final Konum konum;
  final ValueChanged<IletiOzet> ac;
  final String? seciliId;
  final Widget? cekmece;
  final Widget? fab;

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
  bool _okunmamis = false;
  bool _aramaAcik = false;
  String _arama = '';
  bool _tumKlasorler = false;
  final _secim = <String>{};
  int _istek = 0;

  int get _boyut => PostaDurum.ben.ayarlar?.sayfaBoyutu ?? 50;
  Klasor? get _klasor => widget.konum.tur == KonumTur.klasor ? PostaDurum.ben.klasor(widget.konum.id) : null;
  bool get _secimModu => _secim.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _kaydirma.addListener(_kaydi);
    PostaDurum.ben.surum.addListener(_canli);
    _yukle();
  }

  @override
  void didUpdateWidget(IletiListesi oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.konum != widget.konum) {
      _secim.clear();
      _okunmamis = false;
      if (_aramaAcik && widget.konum.tur != KonumTur.klasor) _tumKlasorler = true;
      _ogeler = [];
      _yukle();
    }
  }

  @override
  void dispose() {
    PostaDurum.ben.surum.removeListener(_canli);
    _kaydirma.dispose();
    _aramaMetni.dispose();
    _aramaOdak.dispose();
    super.dispose();
  }

  void _canli() {
    if (!_yukleniyor && !_dahaYukleniyor) _yukle(sessiz: true);
  }

  void _kaydi() {
    if (_kaydirma.position.extentAfter < 600 && !_dahaYukleniyor && !_yukleniyor && _ogeler.length < _toplam) _dahaFazla();
  }

  Future<Sayfa> _getir(int sayfa, int boyut) {
    final k = widget.konum;
    final arama = _arama.trim().isEmpty ? null : _arama.trim();
    if (arama != null && (_tumKlasorler || k.tur != KonumTur.klasor)) {
      return Posta.liste(gorunum: 'all', arama: arama, sayfa: sayfa, boyut: boyut, okunmamis: _okunmamis);
    }
    return switch (k.tur) {
      KonumTur.klasor => Posta.liste(klasorId: k.id, sayfa: sayfa, boyut: boyut, okunmamis: _okunmamis, arama: arama),
      KonumTur.gorunum => Posta.liste(gorunum: k.id, sayfa: sayfa, boyut: boyut, okunmamis: _okunmamis),
      KonumTur.etiket => Posta.liste(etiketId: k.id, sayfa: sayfa, boyut: boyut, okunmamis: _okunmamis),
    };
  }

  /// İlk sayfayı (sessizde: o ana kadar yüklenen kadarını) yeniden alır.
  Future<void> _yukle({bool sessiz = false}) async {
    final no = ++_istek;
    if (!sessiz) {
      setState(() {
        _yukleniyor = true;
        _hata = null;
      });
    }
    try {
      final boyut = sessiz ? min(200, max(_ogeler.length, _boyut)) : _boyut;
      final s = await _getir(1, boyut);
      if (!mounted || no != _istek) return;
      setState(() {
        _ogeler = s.ogeler;
        _toplam = s.toplam;
        _yukleniyor = false;
        _hata = null;
        _secim.removeWhere((id) => !_ogeler.any((m) => m.id == id));
      });
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
  Future<void> _toplu(List<String> idler, String eylem, String tamam, {String? klasorId, bool kaldir = true}) async {
    if (idler.isEmpty) return;
    final onceki = List<IletiOzet>.from(_ogeler);
    if (kaldir) _cikar(idler);
    try {
      await Posta.toplu(idler, eylem, klasorId: klasorId);
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

  // ---- arama ----

  void _aramaAc() {
    setState(() {
      _aramaAcik = true;
      _tumKlasorler = widget.konum.tur != KonumTur.klasor;
    });
    _aramaOdak.requestFocus();
  }

  void _aramaKapat() {
    final vardi = _arama.isNotEmpty;
    setState(() {
      _aramaAcik = false;
      _arama = '';
      _aramaMetni.clear();
    });
    if (vardi) _yukle();
  }

  void _ara(String q) {
    setState(() => _arama = q.trim());
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
                child: Text('Arama işleçleri', style: gosterim(17, agirlik: FontWeight.w700)),
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

  PreferredSizeWidget _ustCubuk() {
    final r = context.r;
    final durum = PostaDurum.ben;
    final menu = widget.cekmece != null && !_aramaAcik && !_secimModu
        ? Builder(
            builder: (c) => IconButton(icon: const Icon(Icons.menu_rounded), tooltip: 'Klasörler', onPressed: () => Scaffold.of(c).openDrawer()),
          )
        : null;
    if (_secimModu) {
      final secilen = _ogeler.where((m) => _secim.contains(m.id)).toList();
      final hepsiOkundu = secilen.every((m) => m.okundu);
      final hepsiYildizli = secilen.every((m) => m.yildizli);
      final idler = _secim.toList();
      return AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Seçimi kaldır', onPressed: () => setState(_secim.clear)),
        title: Text('${_secim.length} seçili'),
        actions: [
          IconButton(
            icon: Icon(hepsiOkundu ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined),
            tooltip: hepsiOkundu ? 'Okunmadı yap' : 'Okundu yap',
            onPressed: () => _toplu(idler, hepsiOkundu ? 'unread' : 'read', hepsiOkundu ? 'Okunmadı işaretlendi' : 'Okundu işaretlendi', kaldir: false),
          ),
          if (_klasor?.rol != 'archive')
            IconButton(icon: const Icon(Icons.archive_outlined), tooltip: 'Arşivle', onPressed: () => _toplu(idler, 'archive', 'Arşivlendi')),
          IconButton(icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Sil', onPressed: () => _sil(idler)),
          PopupMenuButton<String>(
            tooltip: 'Diğer işlemler',
            onSelected: (v) => switch (v) {
              'tasi' => _tasi(idler),
              'yildiz' => _toplu(idler, hepsiYildizli ? 'unflag' : 'flag', hepsiYildizli ? 'Yıldız kaldırıldı' : 'Yıldızlandı', kaldir: false),
              'spam' => _toplu(idler, 'spam', 'Gereksiz olarak işaretlendi'),
              'spamDegil' => _toplu(idler, 'notspam', 'Gelen Kutusu\'na taşındı'),
              _ => setState(() => _secim.addAll(_ogeler.map((m) => m.id))),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'hepsi',
                child: ListTile(leading: Icon(Icons.select_all_rounded), title: Text('Tümünü seç')),
              ),
              const PopupMenuItem(
                value: 'tasi',
                child: ListTile(leading: Icon(Icons.drive_file_move_outline), title: Text('Taşı…')),
              ),
              PopupMenuItem(
                value: 'yildiz',
                child: ListTile(leading: const Icon(Icons.star_border_rounded), title: Text(hepsiYildizli ? 'Yıldızı kaldır' : 'Yıldızla')),
              ),
              if (_klasor?.rol == 'junk')
                const PopupMenuItem(
                  value: 'spamDegil',
                  child: ListTile(leading: Icon(Icons.thumb_up_alt_outlined), title: Text('Gereksiz değil')),
                )
              else
                const PopupMenuItem(
                  value: 'spam',
                  child: ListTile(leading: Icon(Icons.report_outlined), title: Text('Gereksiz (spam)')),
                ),
            ],
          ),
        ],
      );
    }
    if (_aramaAcik) {
      return AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Aramayı kapat', onPressed: _aramaKapat),
        titleSpacing: 0,
        title: TextField(
          controller: _aramaMetni,
          focusNode: _aramaOdak,
          textInputAction: TextInputAction.search,
          onSubmitted: _ara,
          decoration: InputDecoration(
            hintText: 'Postalarda ara',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            suffixIcon: _aramaMetni.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.clear_rounded, size: 20), tooltip: 'Temizle', onPressed: () => setState(_aramaMetni.clear)),
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.manage_search_rounded), tooltip: 'Arama işleçleri', onPressed: _islecYardimi),
          IconButton(icon: const Icon(Icons.search_rounded), tooltip: 'Ara', onPressed: () => _ara(_aramaMetni.text)),
        ],
      );
    }
    final k = _klasor;
    final okunmamis = k?.okunmamis ?? durum.etiket(widget.konum.id)?.okunmamis ?? 0;
    return AppBar(
      leading: menu,
      automaticallyImplyLeading: false,
      titleSpacing: menu == null ? 16 : 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(durum.baslik(widget.konum), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (!_yukleniyor)
            Text(
              okunmamis > 0 ? '${sayiYaz(okunmamis)} okunmamış · ${sayiYaz(_toplam)} ileti' : '${sayiYaz(_toplam)} ileti',
              style: TextStyle(fontSize: 12, color: r.silik, fontWeight: FontWeight.w500),
            ),
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.search_rounded), tooltip: 'Ara', onPressed: _aramaAc),
        PopupMenuButton<String>(
          tooltip: 'Liste seçenekleri',
          onSelected: (v) => switch (v) {
            'yenile' => _yukle(),
            'okundu' => _klasorOkundu(),
            'hepsi' => _hepsiOkundu(),
            'bosalt' => _bosalt(),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'yenile',
              child: ListTile(leading: Icon(Icons.refresh_rounded), title: Text('Yenile')),
            ),
            const PopupMenuItem(
              value: 'okundu',
              child: ListTile(leading: Icon(Icons.done_all_rounded), title: Text('Tümünü okundu işaretle')),
            ),
            const PopupMenuItem(
              value: 'hepsi',
              child: ListTile(leading: Icon(Icons.mark_email_read_outlined), title: Text('Tüm klasörleri okundu işaretle')),
            ),
            if (k?.rol == 'trash' || k?.rol == 'junk')
              PopupMenuItem(
                value: 'bosalt',
                child: ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Marka.gul),
                  title: Text('${k!.gorunenAd} boşalt'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _filtreler() {
    final r = context.r;
    final ara = _aramaAcik && widget.konum.tur == KonumTur.klasor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: const Text('Okunmamış'),
              selected: _okunmamis,
              visualDensity: VisualDensity.compact,
              onSelected: (v) {
                setState(() => _okunmamis = v);
                _yukle();
              },
            ),
            if (ara) ...[
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Tüm klasörlerde'),
                selected: _tumKlasorler,
                visualDensity: VisualDensity.compact,
                onSelected: (v) {
                  setState(() => _tumKlasorler = v);
                  if (_arama.isNotEmpty) _yukle();
                },
              ),
            ],
            if (_arama.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text('"$_arama" için ${sayiYaz(_toplam)} sonuç', style: TextStyle(color: r.silik, fontSize: 12.5)),
            ],
          ],
        ),
      ),
    );
  }

  String _bosMetin() {
    if (_arama.isNotEmpty) return 'Aramanızla eşleşen ileti bulunamadı.';
    if (_okunmamis) return 'Okunmamış ileti yok.';
    return switch (_klasor?.rol) {
      'inbox' => 'Gelen Kutunuz boş. Yeni postalar burada görünecek.',
      'drafts' => 'Kaydedilmiş taslak yok.',
      'sent' => 'Henüz gönderilmiş ileti yok.',
      'trash' => 'Çöp Kutusu boş.',
      'junk' => 'Gereksiz ileti yok.',
      'archive' => 'Arşiv boş.',
      'snoozed' => 'Ertelenmiş ileti yok.',
      _ => widget.konum.tur == KonumTur.gorunum ? 'Bu görünümde ileti yok.' : 'Bu klasörde ileti yok.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (_aramaAcik) const SingleActivator(LogicalKeyboardKey.escape): _aramaKapat,
        if (_secimModu) const SingleActivator(LogicalKeyboardKey.escape): () => setState(_secim.clear),
      },
      child: PopScope(
        canPop: !_aramaAcik && !_secimModu,
        onPopInvokedWithResult: (cikti, _) {
          if (cikti) return;
          if (_secimModu) {
            setState(_secim.clear);
          } else if (_aramaAcik) {
            _aramaKapat();
          }
        },
        child: Scaffold(
          drawer: widget.cekmece,
          floatingActionButton: _secimModu ? null : widget.fab,
          appBar: _ustCubuk(),
          body: Column(
            children: [
              _filtreler(),
              Expanded(child: _liste()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liste() {
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
              child: Durum.bos(_bosMetin(), ikon: _arama.isNotEmpty ? Icons.search_off_rounded : Icons.inbox_rounded),
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
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Semantics(
                  header: true,
                  child: Text(
                    g,
                    style: TextStyle(color: c.r.silik, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .4),
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
              dokun: () {
                if (_secimModu) {
                  setState(() => _secim.contains(m.id) ? _secim.remove(m.id) : _secim.add(m.id));
                } else {
                  widget.ac(m);
                  if (!m.okundu && m.klasorRolu != 'drafts') setState(() => m.okundu = true);
                }
              },
              sec: () {
                HapticFeedback.selectionClick();
                setState(() => _secim.contains(m.id) ? _secim.remove(m.id) : _secim.add(m.id));
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
