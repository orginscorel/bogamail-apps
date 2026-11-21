import 'dart:async';
import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../veri/arkaplan.dart';
import '../../ortak/izin.dart';
import '../../ortak/simgeler.dart';
import '../../veri/canli.dart';
import '../../veri/modeller.dart';
import '../../veri/sohbet_servisi.dart';
import '../../veri/yardimci.dart';
import 'ortak.dart';
import 'sohbet_ekleri.dart';

/// Bir sohbet odası: iletiler (eskiler yukarı kaydırınca yüklenir), yazma alanı, kendi iletisini silme, canlı güncelleme.
/// Canlı akış bağlı değilken 10 saniyede bir yoklanır.
class SohbetOdasiEkrani extends StatefulWidget {
  const SohbetOdasiEkrani({super.key, required this.odaId, this.sayfa = true, this.kapat});
  final String odaId;

  /// true: kendi AppBar'ı olan tam sayfa; false: geniş ekranın sağ bölmesi.
  final bool sayfa;
  final VoidCallback? kapat;

  @override
  State<SohbetOdasiEkrani> createState() => _SohbetOdasiEkraniState();
}

class _SohbetOdasiEkraniState extends State<SohbetOdasiEkrani> {
  final _metin = TextEditingController();
  final _odak = FocusNode();
  final _kaydirma = ScrollController();
  List<SohbetMesaji> _mesajlar = [];
  bool _yukleniyor = true;
  bool _eskiYukleniyor = false;
  bool _eskiBitti = false;
  bool _gonderiyor = false;

  /// Gönderilmeyi bekleyen ekler (yükleniyor ya da yüklendi).
  final _bekleyen = <_Yukleme>[];
  bool get _yukleniyor_ => _bekleyen.any((y) => y.ek == null && y.hata == null);
  List<String> get _hazirEkler => [for (final y in _bekleyen) ?y.ek?.id];
  bool get _gonderilebilir => !_gonderiyor && !_yukleniyor_ && (_metin.text.trim().isNotEmpty || _hazirEkler.isNotEmpty);
  String? _hata;
  StreamSubscription<CanliOlay>? _abone;
  Timer? _yoklama;

  SohbetOdasi? get _oda {
    for (final o in SohbetDurum.ben.odalar) {
      if (o.id == widget.odaId) return o;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    SohbetDurum.ben.acikOda = widget.odaId;
    Arkaplan.durum(onPlanda: true, acikOda: widget.odaId);
    SohbetDurum.ben.addListener(_durum);
    _abone = SohbetDurum.ben.olaylar.listen(_canli);
    _kaydirma.addListener(_kaydi);
    _yoklama = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!Canli.ben.bagli.value) _yeniler();
    });
    _yukle();
  }

  @override
  void didUpdateWidget(SohbetOdasiEkrani eski) {
    super.didUpdateWidget(eski);
    if (eski.odaId != widget.odaId) {
      SohbetDurum.ben.acikOda = widget.odaId;
      Arkaplan.durum(onPlanda: true, acikOda: widget.odaId);
      _mesajlar = [];
      _eskiBitti = false;
      _yukle();
    }
  }

  @override
  void dispose() {
    if (SohbetDurum.ben.acikOda == widget.odaId) {
      SohbetDurum.ben.acikOda = null;
      Arkaplan.durum(onPlanda: true, acikOda: null);
    }
    SohbetDurum.ben.removeListener(_durum);
    _abone?.cancel();
    _yoklama?.cancel();
    for (final y in _bekleyen) {
      y.iptal.cancel();
    }
    _metin.dispose();
    _odak.dispose();
    _kaydirma.dispose();
    super.dispose();
  }

  void _durum() {
    if (mounted) setState(() {});
  }

  void _kaydi() {
    // Liste ters çizildiğinden (en yeni altta) "sonraki" kısım eski iletilerdir.
    if (_kaydirma.position.extentAfter < 300 && !_eskiYukleniyor && !_eskiBitti && _mesajlar.isNotEmpty) _eskiler();
  }

  Future<void> _yukle() async {
    final oda = widget.odaId;
    // Önce yerel: son iletiler önbellekten hemen çizilir, ağ yanıtı gelince yerine konur.
    final h = Sohbet.mesajlarHemen(oda);
    setState(() {
      _hata = null;
      if (h != null) _mesajlar = h;
      _yukleniyor = h == null;
    });
    if (h == null) {
      final o = await Sohbet.mesajlarOnbellek(oda).catchError((_) => null);
      if (!mounted || oda != widget.odaId) return;
      if (o != null && _yukleniyor) {
        setState(() {
          _mesajlar = o;
          _yukleniyor = false;
        });
      }
    }
    try {
      final l = await Sohbet.mesajlar(oda);
      if (!mounted || oda != widget.odaId) return;
      setState(() {
        _mesajlar = l;
        _eskiBitti = l.length < 100;
        _yukleniyor = false;
      });
      unawaited(SohbetDurum.ben.okunduIsaretle(oda));
    } catch (e) {
      if (mounted && oda == widget.odaId) {
        setState(() {
          if (_mesajlar.isEmpty || !(e is ApiHata && e.baglantiYok)) _hata = hataMetni(e);
          _yukleniyor = false;
        });
      }
    }
  }

  Future<void> _eskiler() async {
    setState(() => _eskiYukleniyor = true);
    try {
      final l = await Sohbet.mesajlar(widget.odaId, once: _mesajlar.first.id);
      if (!mounted) return;
      setState(() {
        _mesajlar = [...l, ..._mesajlar];
        _eskiBitti = l.length < 100;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _eskiYukleniyor = false);
    }
  }

  /// Son iletiden yenileri alır.
  Future<void> _yeniler() async {
    if (_yukleniyor) return;
    try {
      final son = _mesajlar.isEmpty ? null : _mesajlar.last.id;
      final l = await Sohbet.mesajlar(widget.odaId, sonra: son);
      if (!mounted || l.isEmpty) return;
      final var_ = _mesajlar.map((m) => m.id).toSet();
      setState(() => _mesajlar = [..._mesajlar, ...l.where((m) => !var_.contains(m.id))]);
      unawaited(SohbetDurum.ben.okunduIsaretle(widget.odaId));
    } catch (_) {}
  }

  /// Silinen iletiler için yüklü aralığı yeniden alır.
  Future<void> _tazele() async {
    try {
      final l = await Sohbet.mesajlar(widget.odaId, sonra: _mesajlar.isEmpty ? null : _mesajlar.first.id - 1);
      if (!mounted) return;
      final yeni = {for (final m in l) m.id: m};
      setState(() => _mesajlar = [for (final m in _mesajlar) yeni[m.id] ?? m, ...l.where((m) => _mesajlar.isEmpty || m.id > _mesajlar.last.id)]);
    } catch (_) {}
  }

  void _canli(CanliOlay o) {
    if ('${o.veri['room_id'] ?? ''}' != widget.odaId) return;
    if (o.tur == 'chat_message') _yeniler();
    if (o.tur == 'chat_update' || o.tur == 'chat_reaction') _tazele();
  }

  Future<void> _gonder() async {
    final t = _metin.text.trim();
    if (!_gonderilebilir) return;
    if (t.characters.length > 4000) {
      bildir('İleti çok uzun', mesaj: 'En fazla 4000 karakter yazabilirsiniz.', tur: MesajTur.uyari);
      return;
    }
    final ekler = _hazirEkler;
    setState(() => _gonderiyor = true);
    try {
      final m = await Sohbet.gonder(widget.odaId, t, ekler: ekler);
      if (!mounted) return;
      _metin.clear();
      setState(() {
        _bekleyen.removeWhere((y) => y.ek != null || y.hata != null);
        if (!_mesajlar.any((x) => x.id == m.id)) _mesajlar = [..._mesajlar, m];
      });
      if (_kaydirma.hasClients) _kaydirma.jumpTo(0);
      SohbetDurum.ben.yenile();
    } catch (e) {
      bildir('İleti gönderilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _gonderiyor = false);
      _odak.requestFocus();
    }
  }

  // ---- ekler ----

  Future<void> _ekMenusu() async {
    final mobil = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final s = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Simge.ek), title: const Text('Dosya'), onTap: () => Navigator.pop(c, 'dosya')),
            ListTile(leading: const Icon(Simge.galeri), title: const Text('Galeri'), onTap: () => Navigator.pop(c, 'galeri')),
            if (mobil) ...[
              ListTile(leading: const Icon(Simge.kamera), title: const Text('Kamerayla fotoğraf çek'), onTap: () => Navigator.pop(c, 'foto')),
              ListTile(leading: const Icon(Simge.video), title: const Text('Kamerayla video çek'), onTap: () => Navigator.pop(c, 'video')),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text('Dosya başına en çok 25 MB, iletide en çok 10 ek.', style: TextStyle(color: c.r.silik, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
    if (s == null || !mounted) return;
    final secilen = <({String ad, Future<Uint8List> Function() oku, int boyut})>[];
    try {
      if (s == 'dosya') {
        final l = await FilePicker.pickFiles(dialogTitle: 'Dosya ekle');
        for (final f in l) {
          secilen.add((ad: f.name, oku: f.readAsBytes, boyut: f.lengthSync() ?? await f.length() ?? 0));
        }
      } else {
        final p = ImagePicker();
        final l = switch (s) {
          'foto' => [?await p.pickImage(source: ImageSource.camera, imageQuality: 82, maxWidth: 2560, maxHeight: 2560)],
          'video' => [?await p.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 3))],
          _ => await p.pickMultipleMedia(imageQuality: 82, maxWidth: 2560, maxHeight: 2560),
        };
        for (final f in l) {
          secilen.add((ad: f.name, oku: f.readAsBytes, boyut: await f.length()));
        }
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code.contains('access_denied') || e.code.contains('permission')) {
        await izinReddedildi(context, kamera: s == 'foto' || s == 'video');
      } else {
        bildir('Dosya alınamadı', mesaj: e.message, tur: MesajTur.hata);
      }
      return;
    } catch (_) {
      bildir('Dosya alınamadı', tur: MesajTur.hata);
      return;
    }
    for (final f in secilen) {
      _ekYuklemeyeBasla(f.ad, f.boyut, f.oku);
    }
  }

  /// Bir dosyayı hemen yüklemeye başlar (ilerleme şeritte gösterilir).
  void _ekYuklemeyeBasla(String ad, int boyut, Future<Uint8List> Function() oku) {
    if (_bekleyen.length >= 10) {
      bildir('En fazla 10 ek', mesaj: '"$ad" eklenmedi.', tur: MesajTur.uyari);
      return;
    }
    final y = _Yukleme(ad, boyut);
    if (boyut > Sohbet.azamiEk) {
      y.hata = 'Dosya 25 MB sınırını aşıyor.';
      setState(() => _bekleyen.add(y));
      return;
    }
    setState(() => _bekleyen.add(y));
    () async {
      try {
        final veri = await oku();
        final ek = await Sohbet.ekYukle(
          widget.odaId,
          ad,
          veri,
          iptal: y.iptal,
          ilerleme: (a, t) {
            if (mounted && t > 0) setState(() => y.ilerleme = a / t);
          },
        );
        if (mounted) setState(() => y.ek = ek);
      } on ApiHata catch (e) {
        if (e.kod == 'iptal') return;
        if (mounted) setState(() => y.hata = e.mesaj);
      } catch (e) {
        if (mounted) setState(() => y.hata = hataMetni(e));
      }
    }();
  }

  Widget _ekSeridi() {
    final r = context.r;
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        itemCount: _bekleyen.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final y = _bekleyen[i];
          final hata = y.hata != null;
          return Tooltip(
            message: y.hata ?? y.ad,
            child: Container(
              key: ValueKey('bekleyen-$i'),
              width: 200,
              padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
              decoration: BoxDecoration(
                color: hata ? Marka.gul.withValues(alpha: .08) : r.ic,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: hata ? Marka.gul.withValues(alpha: .4) : r.kenar),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: y.ek == null && !hata
                        ? CircularProgressIndicator(strokeWidth: 2.5, value: y.ilerleme == 0 ? null : y.ilerleme)
                        : Icon(hata ? Simge.hata : ekSimgesi(icerikTuru(y.ad), y.ad), color: hata ? Marka.gul : r.vurgu),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          y.ad,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          hata ? y.hata! : (y.ek == null ? '%${((y.ilerleme) * 100).round()} yükleniyor' : boyutYaz(y.boyut)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: hata ? Marka.gul : r.silik),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kaldır',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Simge.kapat, size: 16, color: r.silik),
                    onPressed: () => setState(() {
                      y.iptal.cancel();
                      _bekleyen.remove(y);
                    }),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- tepkiler ----

  Future<void> _tepki(SohbetMesaji m, String emoji) async {
    try {
      final l = await Sohbet.tepki(widget.odaId, m.id, emoji);
      if (mounted) setState(() => m.tepkiler = l);
    } catch (e) {
      bildir('Tepki verilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _tepkiEkle(SohbetMesaji m) async {
    final e = await tepkiSec(context);
    if (e != null) await _tepki(m, e);
  }

  Future<void> _sil(SohbetMesaji m) async {
    if (!await onayla(context, 'İleti geri çekilsin mi?', mesaj: 'İleti herkes için "silindi" olarak görünür.', evet: 'Geri çek', tehlikeli: true)) return;
    try {
      await Sohbet.mesajSil(widget.odaId, m.id);
      await _tazele();
    } catch (e) {
      bildir('İleti silinemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  void _iletiMenusu(SohbetMesaji m) {
    if (m.silindi) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in sikTepkiler.take(6))
                    InkWell(
                      key: ValueKey('hizli-tepki-$e'),
                      customBorder: const CircleBorder(),
                      onTap: () {
                        Navigator.pop(c);
                        _tepki(m, e);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                  IconButton.filledTonal(
                    tooltip: 'Diğer tepkiler',
                    icon: const Icon(Simge.tepkiEkle),
                    onPressed: () {
                      Navigator.pop(c);
                      _tepkiEkle(m);
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            if (m.metin.isNotEmpty)
              ListTile(
                leading: const Icon(Simge.kopyala),
                title: const Text('Kopyala'),
                onTap: () {
                  Navigator.pop(c);
                  kopyala(m.metin, mesaj: 'İleti kopyalandı');
                },
              ),
            if (m.benim)
              ListTile(
                leading: const Icon(Simge.sil, color: Marka.gul),
                title: const Text('Geri çek (herkesten sil)', style: TextStyle(color: Marka.gul)),
                onTap: () {
                  Navigator.pop(c);
                  _sil(m);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _bilgi(SohbetOdasi oda) {
    final benId = SohbetDurum.benId;
    showModalBottomSheet<void>(
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
                child: Text(oda.baslik(benId), style: gosterim(18, agirlik: FontWeight.w600)),
              ),
              if (oda.aciklama.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(oda.aciklama, style: TextStyle(color: c.r.soluk)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  '${oda.uyeSayisi} üye',
                  style: TextStyle(color: c.r.silik, fontWeight: FontWeight.w600),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in oda.uyeler)
                      ListTile(
                        leading: VarlikAvatari(kisi: u),
                        title: Text(u.id == benId ? '${u.gorunen} (siz)' : u.gorunen),
                        subtitle: Text(
                          [
                            if (u.durum.isNotEmpty) sohbetDurumAdlari[u.durum] ?? u.durum,
                            if (u.durumMetni.isNotEmpty) u.durumMetni,
                            if (varlikMetni(u).metin.isNotEmpty) varlikMetni(u).metin,
                            if (u.altBilgi.isNotEmpty) u.altBilgi,
                          ].join(' · '),
                          maxLines: 2,
                        ),
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

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final oda = _oda;
    final benId = SohbetDurum.benId;
    final baslik = oda?.baslik(benId) ?? 'Sohbet';
    String alt = '';
    if (oda != null) {
      if (oda.birebir) {
        final k = oda.karsi(benId);
        if (k != null) {
          alt = [
            if (k.durum.isNotEmpty) sohbetDurumAdlari[k.durum] ?? '',
            if (k.durumMetni.isNotEmpty) k.durumMetni,
            varlikMetni(k).metin,
          ].where((s) => s.isNotEmpty).join(' · ');
        }
      } else {
        alt = '${oda.uyeSayisi} üye';
      }
    }
    final ust = Row(
      children: [
        if (oda != null) OdaSimgesi(oda: oda, boyut: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                baslik,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: gosterim(17, agirlik: FontWeight.w600),
              ),
              if (alt.isNotEmpty)
                Text(
                  alt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: r.silik, fontWeight: FontWeight.w500),
                ),
            ],
          ),
        ),
      ],
    );
    final eylemler = [if (oda != null) IconButton(tooltip: 'Üyeler ve bilgi', icon: const Icon(Simge.bilgi), onPressed: () => _bilgi(oda))];
    final govde = Column(
      children: [
        Expanded(child: _liste()),
        _yazmaAlani(),
      ],
    );
    if (widget.sayfa) {
      return Scaffold(
        backgroundColor: r.zemin,
        appBar: AppBar(titleSpacing: 0, title: ust, actions: eylemler),
        body: SafeArea(top: false, child: govde),
      );
    }
    return Material(
      color: r.zemin,
      child: Column(
        children: [
          Container(
            height: 60,
            color: r.kart,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: ust),
                ...eylemler,
                if (widget.kapat != null) IconButton(tooltip: 'Kapat', icon: const Icon(Simge.kapat), onPressed: widget.kapat),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: govde),
        ],
      ),
    );
  }

  Widget _liste() {
    if (_yukleniyor && _mesajlar.isEmpty) return const Durum.yukleniyor();
    if (_hata != null && _mesajlar.isEmpty) return Durum.hata(_hata!, tekrar: _yukle);
    if (_mesajlar.isEmpty) {
      return const Durum.bos('Henüz ileti yok. İlk iletiyi siz yazın!', ikon: Simge.mesaj);
    }
    final ters = _mesajlar.reversed.toList();
    final grup = _oda != null && !_oda!.birebir;
    return ListView.builder(
      controller: _kaydirma,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: ters.length + (_eskiBitti ? 0 : 1),
      itemBuilder: (c, i) {
        if (i >= ters.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final m = ters[i];
        final onceki = i + 1 < ters.length ? ters[i + 1] : null; // zamanca önceki
        final yeniGun = onceki == null || !_ayniGun(onceki.tarih, m.tarih);
        final ayniKisi =
            !yeniGun && onceki.gonderenId == m.gonderenId && m.tarih != null && onceki.tarih != null && m.tarih!.difference(onceki.tarih!).inMinutes < 5;
        return Column(
          children: [
            if (yeniGun) _gunAyraci(m.tarih),
            MesajBalonu(
              mesaj: m,
              adGoster: grup && !m.benim && !ayniKisi,
              sikisik: ayniKisi,
              uzunBas: () => _iletiMenusu(m),
              tepki: (e) => _tepki(m, e),
              tepkiEkle: () => _tepkiEkle(m),
            ),
          ],
        );
      },
    );
  }

  static bool _ayniGun(DateTime? a, DateTime? b) => a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _gunAyraci(DateTime? d) {
    final r = context.r;
    final n = DateTime.now();
    final metin = d == null
        ? ''
        : _ayniGun(d, n)
        ? 'Bugün'
        : _ayniGun(d, n.subtract(const Duration(days: 1)))
        ? 'Dün'
        : DateFormat('d MMMM y, EEEE', 'tr_TR').format(d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(20)),
          child: Text(
            metin,
            style: TextStyle(fontSize: 11.5, color: r.soluk, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _yazmaAlani() {
    final r = context.r;
    final oda = _oda;
    return Container(
      decoration: BoxDecoration(
        color: r.kart,
        border: Border(top: BorderSide(color: r.kenar)),
      ),
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_bekleyen.isNotEmpty) _ekSeridi(),
            const SizedBox(height: 8),
            CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.enter): _gonder},
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    key: const ValueKey('sohbet-ek'),
                    tooltip: 'Ek ekle',
                    onPressed: _gonderiyor ? null : _ekMenusu,
                    icon: Icon(Simge.ekleDaire, color: r.soluk),
                    style: IconButton.styleFrom(minimumSize: const Size(44, 46)),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('sohbet-yaz'),
                      controller: _metin,
                      focusNode: _odak,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: oda?.kanal == true ? 'Kanala yazın (@ad ile birinden bahsedin)' : 'İleti yazın',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    key: const ValueKey('sohbet-gonder'),
                    tooltip: 'Gönder (Enter)',
                    style: IconButton.styleFrom(backgroundColor: r.vurgu, foregroundColor: Colors.white, minimumSize: const Size(46, 46)),
                    onPressed: _gonderilebilir ? _gonder : null,
                    icon: _gonderiyor
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Simge.gonder, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Yukleme {
  _Yukleme(this.ad, this.boyut);
  final String ad;
  final int boyut;
  final iptal = CancelToken();
  double ilerleme = 0;
  SohbetEki? ek;
  String? hata;
}

/// Sohbet balonu: kendi iletileri sağda vurgu renginde, diğerleri solda kart renginde. @bahsetmeler vurgulanır.
class MesajBalonu extends StatelessWidget {
  const MesajBalonu({super.key, required this.mesaj, this.adGoster = false, this.sikisik = false, this.uzunBas, this.tepki, this.tepkiEkle});
  final SohbetMesaji mesaj;
  final bool adGoster;
  final bool sikisik;
  final VoidCallback? uzunBas;
  final ValueChanged<String>? tepki;
  final VoidCallback? tepkiEkle;

  static final _bahsetme = RegExp(r'(^|[\s(])(@[\p{L}\p{N}._%+-]+(?:@[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)+)?)', unicode: true);

  List<InlineSpan> _parcalar(String metin, TextStyle vurgu) {
    final out = <InlineSpan>[];
    var son = 0;
    for (final m in _bahsetme.allMatches(metin)) {
      final bas = m.start + m.group(1)!.length;
      if (bas > son) out.add(TextSpan(text: metin.substring(son, bas)));
      out.add(TextSpan(text: m.group(2), style: vurgu));
      son = m.end;
    }
    if (son < metin.length) out.add(TextSpan(text: metin.substring(son)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ben = mesaj.benim;
    final renk = ben ? r.vurgu : r.kart;
    final yazi = ben ? Colors.white : r.metin;
    final saat = mesaj.tarih == null ? '' : DateFormat('HH:mm').format(mesaj.tarih!);
    return Padding(
      padding: EdgeInsets.only(top: sikisik ? 2 : 8),
      child: Row(
        mainAxisAlignment: ben ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (ben && tepkiEkle != null && !mesaj.silindi) _HizliTepki(ekle: tepkiEkle!),
          Flexible(
            child: Column(
              crossAxisAlignment: ben ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: GestureDetector(
                    onLongPress: uzunBas,
                    onSecondaryTap: uzunBas,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      decoration: BoxDecoration(
                        color: mesaj.silindi ? r.ic : renk,
                        border: ben || mesaj.silindi ? null : Border.all(color: r.kenar),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(ben ? 18 : 6),
                          bottomRight: Radius.circular(ben ? 6 : 18),
                        ),
                        boxShadow: ben || mesaj.silindi ? null : r.hafifGolge,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (adGoster)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                mesaj.gonderenAd,
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Avatar.renkFor(mesaj.gonderenId ?? mesaj.gonderenAd)),
                              ),
                            ),
                          if (!mesaj.silindi && mesaj.ekler.isNotEmpty) SohbetEkleri(ekler: mesaj.ekler, benim: ben),
                          if (mesaj.silindi)
                            Text(
                              'Bu ileti geri çekildi',
                              style: TextStyle(fontStyle: FontStyle.italic, color: r.silik, fontSize: 14),
                            )
                          else if (mesaj.metin.isNotEmpty)
                            SelectableText.rich(
                              TextSpan(
                                style: TextStyle(color: yazi, fontSize: 15, height: 1.35),
                                children: _parcalar(
                                  mesaj.metin,
                                  TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: ben ? Colors.white : r.vurgu,
                                    backgroundColor: ben ? Colors.white24 : r.vurguYumusak,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 2),
                          Align(
                            alignment: Alignment.bottomRight,
                            widthFactor: 1,
                            child: Text(
                              '$saat${mesaj.duzenlendi != null ? ' · düzenlendi' : ''}',
                              style: TextStyle(fontSize: 10.5, color: ben && !mesaj.silindi ? Colors.white70 : r.silik),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (mesaj.tepkiler.isNotEmpty && tepki != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TepkiHaplari(tepkiler: mesaj.tepkiler, degistir: tepki!, ekle: tepkiEkle),
                  ),
              ],
            ),
          ),
          if (!ben && tepkiEkle != null && !mesaj.silindi) _HizliTepki(ekle: tepkiEkle!),
        ],
      ),
    );
  }
}

/// Masaüstünde fareyle üzerine gelince görünen "tepki ekle" düğmesi (dokunmatikte uzun basma menüsü).
class _HizliTepki extends StatelessWidget {
  const _HizliTepki({required this.ekle});
  final VoidCallback ekle;
  @override
  Widget build(BuildContext context) {
    final masaustu = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (!masaustu) return const SizedBox.shrink();
    return _UzerindeGorunur(
      child: IconButton(
        tooltip: 'Tepki ekle',
        visualDensity: VisualDensity.compact,
        icon: Icon(Simge.tepkiEkle, size: 18, color: context.r.silik),
        onPressed: ekle,
      ),
    );
  }
}

class _UzerindeGorunur extends StatefulWidget {
  const _UzerindeGorunur({required this.child});
  final Widget child;
  @override
  State<_UzerindeGorunur> createState() => _UzerindeGorunurState();
}

class _UzerindeGorunurState extends State<_UzerindeGorunur> {
  bool _ustunde = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _ustunde = true),
    onExit: (_) => setState(() => _ustunde = false),
    child: AnimatedOpacity(opacity: _ustunde ? 1 : .25, duration: const Duration(milliseconds: 120), child: widget.child),
  );
}
